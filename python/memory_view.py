# ~/.config/nvim/python/memory_view.py
"""Draws a paused program's memory, Python Tutor style, for Neovim's Viz panel.

Neovim's debugger calls render() inside the paused program after every step.
The picture shows each frame on the call stack and everything reachable from
it: lists, dicts, sets, tuples, your own classes (including __slots__ ones),
cycles and shared references. Classes, functions and modules are left out, and
so are frames from the standard library and installed packages. When the debugger
stops on an error, the frames the error already left are drawn from its traceback.
"""

import builtins
import os
import sys
import sysconfig
import time
import types
from pathlib import Path

_FIRST_IMPORT = "memory_graph" not in sys.modules
import memory_graph as mg
from memory_graph import utils

if _FIRST_IMPORT:
    # memory_graph adds itself as the builtin `mg`; keep the program's names clean.
    vars(builtins).pop("mg", None)

# ponytail: depth caps tried in turn until the picture fits _MAX_LINES graphviz
# lines, so every step stays under ~0.5s: a 300-node list shows ~10 nodes then
# ✂, a 255-node tree its top levels. Raise them to see more, at slower steps.
_DEPTHS = (12, 8, 6)
_MAX_LINES = 300

_DEBUGGER_DIR = f"{os.sep}debugpy{os.sep}"
_STDLIB = frozenset(getattr(sys, "stdlib_module_names", ())) | {"builtins"}
# Standard library and installed packages: like the debugger's "just my code", their
# frames (threading's _bootstrap, asyncio's event loop, ...) are left out of the picture.
_PATHS = sysconfig.get_paths()
_LIBRARY_DIRS = tuple(
    {
        os.path.join(_PATHS[k], "")
        for k in ("stdlib", "platstdlib", "purelib", "platlib")
    }
)


def _slot_names(cls):
    """Returns the __slots__ field names of a user class, or [] for stdlib types."""
    if cls.__module__.split(".")[0] in _STDLIB:
        return []  # e.g. pathlib.Path uses slots, but its text form reads better.
    names = []
    for klass in cls.__mro__:
        slots = vars(klass).get("__slots__", ())
        names += [slots] if isinstance(slots, str) else list(slots)
    return [n for n in names if n not in ("__dict__", "__weakref__")]


def _has_fields(value):
    return hasattr(value, "__dict__") or bool(_slot_names(type(value)))


def _fields(value):
    fields = dict(getattr(value, "__dict__", {}))
    for name in _slot_names(type(value)):
        if hasattr(value, name):
            fields[name] = getattr(value, name)
    return fields


# memory_graph only reads __dict__; teach it about __slots__ too.
utils.has_dict_attributes = _has_fields
utils.get_dict_attributes = _fields


def _is_data(name, value):
    """Returns whether a variable is program data rather than code or a type hint."""
    module = type(value).__module__
    return not (
        name.startswith("__")
        or isinstance(value, (type, types.ModuleType))
        or utils.is_not_state(value)
        or module == "typing"  # List, Optional, ...
        # Functions wrapped by @cache/@lru_cache, partial(), itemgetter(), ... Your
        # own classes with __call__ still count as data.
        or (callable(value) and module.split(".")[0] in _STDLIB)
    )


def _kind(frame):
    """Returns "debugger" (debugpy, runpy), "library" (stdlib, packages) or "program"."""
    name = frame.f_code.co_filename
    # runpy's file is "<frozen runpy>" on 3.11+ unless frozen modules are off.
    if _DEBUGGER_DIR in name or frame.f_globals.get("__name__") == "runpy":
        return "debugger"
    # "<frozen importlib._bootstrap>" frames sit between yours while an import runs.
    if name.startswith(_LIBRARY_DIRS) or name.startswith("<frozen "):
        return "library"
    return "program"


def _program_frames(frame):
    """Returns the paused program's frames, outermost first.

    Walks outward from `frame`, skips everything above the debugger (this module
    and the evaluated expression), then keeps your code's frames until the debugger
    or runpy code that started the program. Library frames in between are skipped.
    """
    frames, seen_debugger = [], False
    while frame:
        kind = _kind(frame)
        if kind == "debugger" and frames:
            break
        seen_debugger = seen_debugger or kind == "debugger"
        if seen_debugger and kind == "program":
            frames.append(frame)
        frame = frame.f_back
    return frames[::-1]


def _exception_frames(tb):
    """Returns the program frames in a traceback, outermost first.

    When the debugger stops on an uncaught exception, the frames the error came
    through have already left the stack (all of them before Python 3.12), but the
    traceback still holds them, variables included.
    """
    frames = []
    while tb:
        if _kind(tb.tb_frame) == "program":
            frames.append(tb.tb_frame)
        tb = tb.tb_next
    return frames


def _call_stack(frames):
    return mg.call_stack(
        {
            f"{level}: {frame.f_code.co_name}": {
                name: value
                for name, value in frame.f_locals.items()
                if _is_data(name, value)
            }
            for level, frame in enumerate(frames)
        }
    )


def render(out_dir, dark=False):
    """Draws the paused program's memory into out_dir as viz-<time>.png.

    Args:
        out_dir: The folder Neovim's Viz panel watches.
        dark: Colors for a dark terminal background (Neovim's 'background').

    Returns:
        A short summary such as "drew 2 frames: 0: <module>, 1: solve".
    """
    mg.set_colors(dark=dark, transparent=True)
    caller = sys._getframe(1)
    frames = _program_frames(caller)
    # Stopped on an error, the debugger gives the evaluated expression __exception__ =
    # (type, value, traceback): add the frames the error has already left.
    error = None
    for scope in (caller, caller.f_back):  # the evaluated expression, or a lambda in it
        if scope and error is None:
            error = scope.f_locals.get(
                "__exception__", scope.f_globals.get("__exception__")
            )
    if isinstance(error, tuple) and len(error) == 3 and error[2] is not None:
        frames += [f for f in _exception_frames(error[2]) if f not in frames]
    stack = _call_stack(frames)
    # memory_graph reads everything recursively, two levels per linked node, before
    # it applies the depth cap: a 1000-node list needs more than the default 1000.
    limit = sys.getrecursionlimit()
    sys.setrecursionlimit(max(limit, 10_000))
    try:
        for depth in _DEPTHS:
            mg.config.max_graph_depth = depth
            graph = mg.create_graph(stack)
            if len(graph.body) <= _MAX_LINES:
                break
    except RecursionError:
        raise RuntimeError("too deep to draw: a chain of about 5000+ objects") from None
    finally:
        sys.setrecursionlimit(limit)
    graph.attr(dpi="144")
    png = graph.pipe(format="png")
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    # A new file name per picture: the Viz panel shows the newest viz-*.png.
    path = out / f"viz-{time.time_ns()}.png"
    tmp = path.with_suffix(".tmp")
    tmp.write_bytes(png)
    tmp.replace(path)
    for old in out.glob("viz-*.png"):
        if old != path:
            old.unlink(missing_ok=True)
    return f"drew {len(stack)} frames: {', '.join(stack)}"


if __name__ == "__main__":
    import functools
    import tempfile
    import typing

    class Slotted:
        __slots__ = ("a", "b")

        def __init__(self):
            self.a = [1]

    assert _fields(Slotted()) == {"a": [1]}  # unset slots are skipped
    assert _slot_names(Path) == []
    assert not _is_data("Optional", typing.Optional) and not _is_data(
        "Slotted", Slotted
    )
    assert _is_data("x", [1]) and _is_data("s", Slotted())

    class Counter:
        def __call__(self):
            return 1

    assert not _is_data("fib", functools.lru_cache(abs))
    assert _is_data("counter", Counter())
    assert "mg" not in vars(builtins)

    # Pretend to be debugpy: frames from a file under .../debugpy/ sit between
    # the program (below) and the evaluated render() call (above).
    fake = {}
    exec(  # noqa: S102 - builds a stand-in for debugpy's code
        compile("def suspend(f): return f()", f"{os.sep}debugpy{os.sep}x.py", "exec"),
        fake,
    )

    def solve(nums):
        seen = {nums[0]}  # noqa: F841 - drawn from the frame's locals
        return fake["suspend"](lambda: _program_frames(sys._getframe(0)))

    names = [f.f_code.co_name for f in solve([3, 1])]
    assert names == ["<module>", "solve"], names

    # A standard-library frame between two of yours (like threading's) is left out.
    lib = {}
    exec(  # noqa: S102 - builds a stand-in for library code
        compile(
            "def call(f): return f()", os.path.join(_PATHS["stdlib"], "x.py"), "exec"
        ),
        lib,
    )
    names = [f.f_code.co_name for f in lib["call"](functools.partial(solve, [3, 1]))]
    assert names == ["<module>", "solve"], names

    # Stopped on an error: the frames it already left come from its traceback.
    def failing(n):
        return 10 // n

    try:
        failing(0)
    except ZeroDivisionError as err:
        error = (ZeroDivisionError, err, err.__traceback__)
    names = [f.f_code.co_name for f in _exception_frames(error[2])]
    assert names == ["<module>", "failing"], names

    class Node:
        def __init__(self, left=None, right=None):
            self.left, self.right = left, right

    def full_tree(levels):
        return Node(full_tree(levels - 1), full_tree(levels - 1)) if levels else None

    with tempfile.TemporaryDirectory() as tmp_dir:
        fake["suspend"](lambda: render(tmp_dir))
        pngs = list(Path(tmp_dir).glob("viz-*.png"))
        assert len(pngs) == 1 and pngs[0].read_bytes()[:4] == b"\x89PNG", pngs
        light_text = mg.config.foreground_color
        fake["suspend"](lambda: render(tmp_dir, dark=True))
        assert mg.config.foreground_color != light_text, "dark=True picks dark colors"

        # Evaluated like the debugger does at an exception stop, with __exception__ in scope.
        scope = {"__exception__": error, "render": render, "out": tmp_dir}
        summary = fake["suspend"](lambda: eval("(lambda: render(out))()", scope))
        assert summary == "drew 2 frames: 0: <module>, 1: failing", (
            summary
        )  # <module>, and failing() which already exited

        big = full_tree(8)  # 255 nodes: too big at the first depth cap
        start = time.perf_counter()
        fake["suspend"](lambda: render(tmp_dir))
        assert mg.config.max_graph_depth < _DEPTHS[0]
        assert time.perf_counter() - start < 1, "a big tree should draw fast"

        big = None
        for _ in range(6000):  # a chain too deep for memory_graph's recursive reader
            big = Node(big)
        try:
            fake["suspend"](lambda: render(tmp_dir))
            raise AssertionError("expected RuntimeError")
        except RuntimeError as err:
            assert "too deep" in str(err)
        assert sys.getrecursionlimit() == 1000
    print("ok")
