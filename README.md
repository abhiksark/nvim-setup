<!-- README.md -->
# nvim-setup

A Neovim configuration that provides the everyday features of VS Code in any project: a
file tree, a file finder, project search, git change marks, an error list, and running
and debugging the current file. It supports Python, Rust, C, C++, Go, JavaScript and
TypeScript, and starts in about 25 ms.

The screen shows only code by default. The file tree, finder, error list and run output
open when needed and close with one key.

## Install

The config needs Neovim 0.12 or later. Plugins are pinned in `nvim-pack-lock.json` and
install on first launch. `install.sh` installs the language servers and debug adapters for
the languages you pick (see [Picking languages](#picking-languages)).

### Linux (Debian or Ubuntu)

```sh
# Neovim 0.12+: download a release from https://github.com/neovim/neovim/releases
sudo apt install git curl unzip ripgrep fd-find graphviz build-essential
mkdir -p ~/.local/bin && ln -s "$(command -v fdfind)" ~/.local/bin/fd   # Debian names fd "fdfind"

curl --proto '=https' -sSf https://sh.rustup.rs | sh
# Go: https://go.dev/dl
# Node 22.18 or later, for example with nvm: nvm install 22

python3 -m pip install debugpy
python3 -m pip install --target ~/.local/share/nvim/memory-graph memory_graph graphviz

git clone https://github.com/abhiksark/nvim-setup ~/.config/nvim
~/.config/nvim/install.sh    # pick languages; installs plugins, servers and debuggers
```

On Ubuntu 24.04 and later, pip refuses to install into the system Python
("externally-managed-environment"). For the `debugpy` line, add
`--user --break-system-packages`. The `--target` line is not affected.

### Mac

```sh
xcode-select --install                              # C and C++ compilers
brew install neovim git ripgrep fd graphviz go node python

curl --proto '=https' -sSf https://sh.rustup.rs | sh

python3 -m pip install debugpy
python3 -m pip install --target ~/.local/share/nvim/memory-graph memory_graph graphviz

git clone https://github.com/abhiksark/nvim-setup ~/.config/nvim
~/.config/nvim/install.sh    # pick languages; installs plugins, servers and debuggers
```

Homebrew's Python refuses `pip install` into itself in the same way. For the `debugpy`
line, add `--user --break-system-packages`.

### Picking languages

`install.sh` sets up only the languages you pick, for example Python alone on a server. It
never uses sudo, and it does not install the languages themselves, so the lines above are
needed only for the languages you use.

```sh
./install.sh               # checklist: arrows move, Space ticks, a ticks all, Enter installs
./install.sh python go     # no checklist; "all" picks every language
```

| Pick | Needs on the machine | Installs |
|---|---|---|
| `python` | `python3` with its `venv` module | basedpyright, ruff |
| `go` | `go` | gopls, delve |
| `c` | a C compiler, `unzip`, `curl` or `wget` | clangd, codelldb |
| `js` | `node`, `npm` | vtsls |
| `rust` | `rustup`, `unzip`, `curl` or `wget` | rust-analyzer (through rustup), codelldb |

A pick whose prerequisites are missing is skipped, with a line saying what is missing. The
script reports each tool it installs, then notes optional extras that are missing
(debugpy, the memory picture, ripgrep). It exits with status 1 if anything was skipped or
failed, so other setup scripts can call it.

Inside Neovim, `:InstallTools python go` installs the same tools, and `:InstallTools` alone
installs them for every language.

### Terminal

The config is built for [kitty](https://sw.kovidgoyal.net/kitty/). The Python memory
picture needs kitty, and kitty ships the icon font the file tree uses.

If icons show up as Chinese characters, another installed font is claiming the icon code
points. Add this line to `kitty.conf` so kitty uses its built-in icon font for them:

```
symbol_map U+E000-U+F8FF,U+F0000-U+FFFFF Symbols Nerd Font Mono
```

In other terminals, icons fall back to plain text. To use icons there, install a
[Nerd Font](https://www.nerdfonts.com/) and set `vim.g.nerd_font = true` at the top of
`init.lua`.

## Keys

The leader key is Space. Pressing Space, `g`, `[` or `]` and waiting shows what can come
next.

| Key | Action |
|---|---|
| Ctrl+P, Space f f | Find a file by name |
| Space f r | Recent files |
| Space b | Open files |
| Space / | Search text in the project |
| Ctrl+B, Space e | Show or hide the file tree |
| Space x x | Error list |
| Space c f | Format the file |
| F5, Space r | Run the current file |
| F6 | Start debugging, or continue to the next breakpoint |
| F9 | Set or clear a breakpoint |
| F10 | Step over |
| F11 | Step into |
| F4 | Stop debugging and close the panels |
| F7, F8 | Earlier and later steps of the memory picture (Python) |
| `gd` | Go to definition |
| Tab | Accept the completion suggestion, or the first one if none is picked |
| `q` | Close the run output or a panel |

Neovim's built-in language keys also work:

| Key | Action |
|---|---|
| `K` | Show documentation |
| `grr` | References |
| `grn` | Rename |
| `gra` | Code actions |
| `gri` | Implementation |
| `gO` | Symbols in the file |
| Ctrl+O, Ctrl+I | Jump back and forward, for example after `gd` |
| Ctrl+], Ctrl+T | Go to definition, and back |
| `[d`, `]d` | Previous and next error |
| `[h`, `]h` | Previous and next git change |

Ctrl+B replaces Vim's page-up; Ctrl+U still scrolls up.

### Switching files, splits and tabs

There is no tab bar. Opened files stay open in the background.

| Key | Action |
|---|---|
| Space b | List the open files and pick one |
| `]b`, `[b` | Next and previous open file |
| Ctrl+^ | The file you were in just before |
| Ctrl+W then `h`, `j`, `k`, `l` | Move to the split on the left, below, above or right |
| Ctrl+W then `w` | Move to the next split, for example from the file tree to the code |
| `gt`, `gT` | Next and previous tab (the finder's Ctrl+T opens a file in a new tab) |

### In the file tree

| Key | Action |
|---|---|
| Enter, `l` | Open a file, or expand a folder |
| `h` | Collapse a folder |
| Backspace | Go up one folder |
| `a` | Add a file in the folder under the cursor. End the name with `/` for a folder. |
| `d` | Delete |
| `r` | Rename |
| `c` | Copy |
| `m` | Move |
| `y`, `p` | Copy to the clipboard, then paste |
| `o` | Open with the system's default app |
| `u` | Refresh the tree |
| `H`, `I` | Show or hide hidden and git-ignored files |
| `Z` | Collapse every folder |
| `]g`, `[g` | Next and previous file with git changes |
| `]e`, `[e` | Next and previous file with errors |
| Ctrl+B, `q` | Close the tree |
| `?` | Show every key |

### In the finder, project search and error list

| Key | Action |
|---|---|
| Ctrl+J, Ctrl+K | Move down and up |
| Enter | Open the item |
| Ctrl+V, Ctrl+S | Open in a side-by-side or stacked split |
| Ctrl+T | Open in a new tab |
| Tab | Mark several items |
| Ctrl+Q | Send the items to the quickfix list |
| Alt+H, Alt+I | Show or hide hidden and git-ignored files |
| Esc | Close (press it twice while typing) |
| `?` | Show every key |

### In the debugger panels

| Key | Action |
|---|---|
| Enter | Expand or collapse a variable or watch |
| `e` | Edit a variable's value or a watch expression |
| `i` | In the watches panel, type an expression and press Enter to watch it |
| `d` | Remove a watch |

## Plugins

Plugins load with Neovim's built-in `vim.pack`, with no other plugin manager.

| Plugin | Why it is here |
|---|---|
| [snacks.nvim](https://github.com/folke/snacks.nvim) | File tree, file finder, project search and error list. Only its `explorer` and `picker` modules are on. |
| [mini.nvim](https://github.com/nvim-mini/mini.nvim) | Bracket pairs, git change marks, branch name, status line, icons and key hints. |
| [mason.nvim](https://github.com/mason-org/mason.nvim) | Installs language servers and debug adapters on each machine. |
| [nvim-dap](https://github.com/mfussenegger/nvim-dap) | The debugger. |
| [nvim-dap-ui](https://github.com/rcarriga/nvim-dap-ui) | The debugger's variables, stack and console panels. |
| [nvim-dap-python](https://github.com/mfussenegger/nvim-dap-python) | Python debugging through debugpy. |
| [nvim-nio](https://github.com/nvim-neotest/nvim-nio) | Required by nvim-dap-ui. |

There is no completion plugin and no treesitter. Completion uses Neovim's built-in LSP
completion, and highlighting uses Vim's syntax files plus the language servers.

## Languages

| Language | Language server | F5 runs | Format on save | Error list covers | Debugger |
|---|---|---|---|---|---|
| Python | basedpyright, ruff | `python3 <file>` | yes (ruff) | open files | debugpy |
| Rust | rust-analyzer | `cargo run` in a Cargo project, otherwise `rustc -g` | yes (rustfmt) | whole project | codelldb |
| C | clangd | `cc -g -O0 -Wall` | no | open files | codelldb |
| C++ | clangd | `c++ -std=c++20 -g -O0 -Wall` | no | open files | codelldb |
| Go | gopls | `go run .` in a module, otherwise `go run <file>` | yes (gofmt) | whole project | delve |
| JavaScript | vtsls | `node <file>` | no | open files | none |
| TypeScript | vtsls | `node <file>` | no | open files | none |

Notes:

- Compiled binaries go to `~/.cache/nvim-run/`, never next to the source file.
- In a Cargo package with several binaries, F5 and F6 use the binary whose main file is
  open (for example `src/bin/two.rs`), and otherwise the package's first binary.
- The error list shows errors from every folder, not only the one Neovim started in.
- C, C++, JavaScript and TypeScript have no single standard style, so they are not
  formatted on save. Space c f formats them on demand.
- F5 compiles one C or C++ file. Projects with several source files are not built.
- clangd needs `compile_commands.json` to understand a project with several files. CMake
  writes one with `-DCMAKE_EXPORT_COMPILE_COMMANDS=ON`, and
  [bear](https://github.com/rizsotto/Bear) generates one for Make. Single files work
  without it.
- Node runs TypeScript by removing the types, which needs Node 22.18 or later. It rejects
  `enum`, `namespace` and constructor parameter properties.
- F5 does not run TSX files, which need a bundler.
- A Rust file outside any Cargo project uses rust-analyzer's single-file mode, which
  covers the `.rs` files in its folder. A `.rs` file added to that folder later needs
  `:lsp restart`.
- Mason installs the newest delve, which may not officially support an older Go. The
  config skips delve's Go version check. If Go debugging misbehaves, update Go.
- If Neovim is closed while `:InstallTools` is running, a tool can be left half installed.
  Run `:MasonUninstall <name>`, then `:InstallTools` again.

## Python practice tools

`lua/practice.lua` holds a setup for practicing algorithms in Python:

- F5 runs the file.
- `:Test` adds a test block for a LeetCode-style `class Solution`. The test imports helpers
  from `lc.py`, which lives in the practice repo.
- While debugging, a side panel draws a picture of the program's memory at every stop, and
  F7 and F8 move through earlier stops.

The memory picture needs kitty, graphviz and the `memory-graph` install line above.

## Adding a language

1. In `init.lua`, add a `vim.lsp.config('<name>', { cmd, filetypes, root_markers })` block
   and add the name to `vim.lsp.enable`.
2. Add the language and its Mason package names to `tools` in `init.lua`. Add the same
   language name to `names` and `labels` in `install.sh`, and its prerequisites to
   `missing_for`. Then run `./install.sh <language>`.
3. To run files with F5, add a line for the filetype to `runner_for`.
4. To format on save, add the server name to `format_on_save`.

## Tests

```sh
test/check.sh                 # startup budget, then headless checks for every feature
test/check.sh --clean-slate   # install everything into an empty folder (needs network)
CHECK_ONLY=rust nvim --headless -c 'luafile test/check.lua'   # only matching checks
```

The checks write sample files to a temporary folder and never touch real projects.
