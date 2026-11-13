-- lua/practice.lua
-- changed from original: this file is lines 72 to 642 of the earlier ~/.config/nvim/init.lua, copied as is
-- apart from the lines marked like this one. It is the Python practice setup: Viz panel,
-- run_python, :Test, and the debugger with its memory picture and step history.
local M = {}

-- Viz panel: shows the newest picture, from lc.draw() (~/.cache/lc/viz-*.png) or the
-- debugger's memory picture (this Neovim's own folder, viz.own), using kitty's graphics protocol. While debugging it sits in the debugger's right column;
-- otherwise it opens as its own right split (q closes it).
local viz = { dir = vim.fn.expand('~/.cache/lc'), hint = ' draw(x) from lc shows a picture here', id = 0 }
-- This Neovim's own folder for debugger memory pictures and step history, so two Neovims
-- debugging at once don't show or delete each other's pictures. Removed on exit.
viz.own = viz.dir .. '/nvim-' .. vim.fn.getpid()
-- Debugger step history (F7/F8); its functions are defined with the debugger setup below.
local history = { dir = viz.own .. '/history', steps = {} } -- history.at: shown step, nil = live
local in_kitty = vim.env.KITTY_WINDOW_ID ~= nil and #vim.api.nvim_list_uis() > 0 -- not headless

function viz.buffer()
  if not (viz.buf and vim.api.nvim_buf_is_valid(viz.buf)) then
    viz.buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(viz.buf, 'Viz')
    vim.bo[viz.buf].filetype = 'lcviz'
    vim.api.nvim_buf_set_lines(viz.buf, 0, -1, false, { viz.hint })
    vim.keymap.set('n', 'q', '<cmd>close<cr>', { buffer = viz.buf, desc = 'Close Viz panel' })
  end
  return viz.buf
end

-- Terminal cell size in pixels, to fit the picture without stretching it.
local ffi = require('ffi')
pcall(ffi.cdef, 'struct lc_winsize { unsigned short row, col, xpixel, ypixel; }; int ioctl(int, unsigned long, ...);')
local function cell_size()
  local ws = ffi.new('struct lc_winsize')
  -- changed from original: TIOCGWINSZ differs on macOS; 0x5413 is Linux-only.
  local tiocgwinsz = vim.uv.os_uname().sysname == 'Darwin' and 0x40087468 or 0x5413
  if ffi.C.ioctl(1, tiocgwinsz, ws) == 0 and ws.xpixel > 0 then -- TIOCGWINSZ
    return ws.xpixel / ws.col, ws.ypixel / ws.row
  end
  return 9, 18
end

-- The picture is drawn with kitty's Unicode placeholders: the Viz buffer holds U+10EEEE
-- characters whose color is the image id and whose combining marks give each cell's
-- row and column. Neovim redraws them like any text, so the picture survives running
-- programs, splits and resizes. Marks: kitty's rowcolumn-diacritics.txt, in order.
local MARKS = {}
for hex in ([[
0305 030D 030E 0310 0312 033D 033E 033F 0346 034A 034B 034C 0350 0351 0352 0357 035B 0363 0364
0365 0366 0367 0368 0369 036A 036B 036C 036D 036E 036F 0483 0484 0485 0486 0487 0592 0593 0594
0595 0597 0598 0599 059C 059D 059E 059F 05A0 05A1 05A8 05A9 05AB 05AC 05AF 05C4 0610 0611 0612
0613 0614 0615 0616 0617 0657 0658 0659 065A 065B 065D 065E 06D6 06D7 06D8 06D9 06DA 06DB 06DC
06DF 06E0 06E1 06E2 06E4 06E7 06E8 06EB 06EC 0730 0732 0733 0735 0736 073A 073D 073F 0740 0741
0743 0745 0747 0749 074A 07EB 07EC 07ED 07EE 07EF 07F0 07F1 07F3 0816 0817 0818 0819 081B 081C
081D 081E 081F 0820 0821 0822 0823 0825 0826 0827 0829 082A 082B 082C 082D 0951 0953 0954 0F82
0F83 0F86 0F87 135D 135E 135F 17DD 193A 1A17 1A75 1A76 1A77 1A78 1A79 1A7A 1A7B 1A7C 1B6B 1B6D
1B6E 1B6F 1B70 1B71 1B72 1B73 1CD0 1CD1 1CD2 1CDA 1CDB 1CE0 1DC0 1DC1 1DC3 1DC4 1DC5 1DC6 1DC7
1DC8 1DC9 1DCB 1DCC 1DD1 1DD2 1DD3 1DD4 1DD5 1DD6 1DD7 1DD8 1DD9 1DDA 1DDB 1DDC 1DDD 1DDE 1DDF
1DE0 1DE1 1DE2 1DE3 1DE4 1DE5 1DE6 1DFE 20D0 20D1 20D4 20D5 20D6 20D7 20DB 20DC 20E1 20E7 20E9
20F0 2CEF 2CF0 2CF1 2DE0 2DE1 2DE2 2DE3 2DE4 2DE5 2DE6 2DE7 2DE8 2DE9 2DEA 2DEB 2DEC 2DED 2DEE
2DEF 2DF0 2DF1 2DF2 2DF3 2DF4 2DF5 2DF6 2DF7 2DF8 2DF9 2DFA 2DFB 2DFC 2DFD 2DFE 2DFF A66F A67C
A67D A6F0 A6F1 A8E0 A8E1 A8E2 A8E3 A8E4 A8E5 A8E6 A8E7 A8E8 A8E9 A8EA A8EB A8EC A8ED A8EE A8EF
A8F0 A8F1 AAB0 AAB2 AAB3 AAB7 AAB8 AABE AABF AAC1 FE20 FE21 FE22 FE23 FE24 FE25 FE26 10A0F 10A38
1D185 1D186 1D187 1D188 1D189 1D1AA 1D1AB 1D1AC 1D1AD 1D242 1D243 1D244]]):gmatch('%x+') do
  MARKS[#MARKS + 1] = vim.fn.nr2char(tonumber(hex, 16))
end
local PLACEHOLDER = vim.fn.nr2char(0x10EEEE)
local ns = vim.api.nvim_create_namespace('lcviz')

-- Kitty graphics commands go through nvim_ui_send, in order with Neovim's own output.
local function kitty(control, payload)
  return '\027_G' .. control .. (payload and ';' .. payload or '') .. '\027\\'
end

-- Free the current picture in kitty.
function viz.hide()
  if viz.shown then vim.api.nvim_ui_send(kitty('a=d,d=I,i=' .. viz.id .. ',q=2')) end
  viz.shown = false
end

-- Forget the last picture; runs before each F5 run and debug session.
function viz.reset()
  for _, dir in ipairs({ viz.dir, viz.own }) do
    for _, file in ipairs(vim.fn.glob(dir .. '/viz-*.png', false, true)) do os.remove(file) end
  end
  viz.hide()
  viz.path, viz.pin = nil, nil
  for _, win in ipairs(vim.fn.win_findbuf(viz.buffer())) do vim.wo[win].winbar = '' end
  vim.api.nvim_buf_clear_namespace(viz.buffer(), ns, 0, -1)
  vim.api.nvim_buf_set_lines(viz.buf, 0, -1, false, { viz.hint })
end

-- Show the newest picture, or the pinned one (viz.pin = { path, label }, set while
-- looking at an earlier debugger step), opening a right split if no window shows the panel.
function viz.show()
  local files = vim.fn.glob(viz.dir .. '/viz-*.png', false, true) -- draw() pictures
  vim.list_extend(files, vim.fn.glob(viz.own .. '/viz-*.png', false, true)) -- memory pictures
  -- Names carry a nanosecond timestamp, so the last is newest.
  table.sort(files, function(a, b) return vim.fs.basename(a) < vim.fs.basename(b) end)
  local path = viz.pin and viz.pin.path or files[#files]
  if not in_kitty or not path then return end
  local win = vim.fn.bufwinid(viz.buffer())
  if win == -1 then
    if path == viz.path then return end -- panel was closed; reopen only for a new picture
    local width = math.floor(vim.o.columns * 0.4)
    win = vim.api.nvim_open_win(viz.buf, false, { split = 'right', win = -1, width = width })
    vim.w[win].lcviz_split = true
  end
  for option, value in pairs({ number = false, relativenumber = false, signcolumn = 'no', wrap = false }) do
    vim.wo[win][option] = value
  end
  local label = viz.pin and viz.pin.label or ''
  if vim.wo[win].winbar ~= label then vim.wo[win].winbar = label end -- before sizing: it takes a row
  local file = io.open(path, 'rb')
  if not file then return end
  local png = file:read('*a')
  file:close()
  -- PNG width and height are big-endian integers at bytes 17 and 21.
  local function u32(i)
    local a, b, c, d = png:byte(i, i + 3)
    return ((a * 256 + b) * 256 + c) * 256 + d
  end
  local cell_w, cell_h = cell_size()
  local cols = math.min(vim.api.nvim_win_get_width(win), #MARKS)
  local rows = math.min(vim.api.nvim_win_get_height(win), #MARKS)
  -- Shrink to fit the window, but never enlarge past the picture's own size.
  local scale = math.min(1, cols * cell_w / u32(17), rows * cell_h / u32(21))
  cols = math.max(1, math.floor(u32(17) * scale / cell_w + 0.5))
  rows = math.max(1, math.floor(u32(21) * scale / cell_h + 0.5))

  viz.hide()
  viz.id = viz.id % 0xFFFFFF + 1 -- a fresh 24-bit id: it is stored in a text color
  local data = vim.base64.encode(png)
  local chunks = math.ceil(#data / 4096)
  local out = {}
  for i = 1, chunks do
    local control = i == 1 and ('a=T,f=100,t=d,i=%d,U=1,c=%d,r=%d,q=0,'):format(viz.id, cols, rows) or ''
    out[i] = kitty(control .. 'm=' .. (i < chunks and 1 or 0), data:sub((i - 1) * 4096 + 1, i * 4096))
  end
  vim.api.nvim_ui_send(table.concat(out))
  viz.shown, viz.path = true, path

  viz.size = { cols = cols, rows = rows }
  vim.api.nvim_buf_clear_namespace(viz.buf, ns, 0, -1)
  vim.api.nvim_buf_set_lines(viz.buf, 0, -1, false, {})
end

-- Write the placeholder text for picture `id` (explicit row and column marks on every
-- cell: Neovim may compress runs of identical characters, which would break kitty's
-- left-to-right inference).
local function write_placeholders(id)
  if id ~= viz.id or not viz.buf or not vim.api.nvim_buf_is_valid(viz.buf) then return end
  local lines = {}
  for r = 1, viz.size.rows do
    local cells = {}
    for c = 1, viz.size.cols do
      cells[c] = PLACEHOLDER .. MARKS[r] .. MARKS[c]
    end
    lines[r] = table.concat(cells)
  end
  vim.api.nvim_set_hl(0, 'LcVizImage', { fg = ('#%06x'):format(id) })
  vim.api.nvim_buf_clear_namespace(viz.buf, ns, 0, -1)
  vim.api.nvim_buf_set_lines(viz.buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_extmark(viz.buf, ns, 0, 0, { end_row = #lines - 1, end_col = #lines[#lines], hl_group = 'LcVizImage' })
end

-- Kitty answers "i=<id>;OK" once it has received the picture; then write the text. In
-- testing, cells written right after the OK sometimes stayed blank until they were
-- written again, so blank the text and write it once more a moment later. In a test kitty
-- (software rendering), one rewrite at 200ms left 19 of 120 large pictures blank; adding a
-- second at 1s left 6 of 120. Ctrl-L (:redraw!) fixes any that remain.
vim.api.nvim_create_autocmd('TermResponse', {
  callback = function(ev)
    local id = tonumber((ev.data.sequence or ''):match('^\027_Gi=(%d+);OK'))
    if not id then return end
    write_placeholders(id)
    for _, delay in ipairs({ 200, 1000 }) do
      vim.defer_fn(function()
        if id ~= viz.id then return end
        vim.api.nvim_buf_set_lines(viz.buf, 0, -1, false, {})
        vim.cmd.redraw()
        write_placeholders(id)
      end, delay)
    end
  end,
})

-- Coalesce triggers (a new picture file, window resizes) into one render once the
-- window layout has settled.
viz.timer = vim.uv.new_timer()
function viz.schedule()
  viz.timer:stop()
  viz.timer:start(50, 0, vim.schedule_wrap(viz.show))
end

for _, dir in ipairs(vim.fn.glob(viz.dir .. '/nvim-*', false, true)) do
  local pid = tonumber(dir:match('nvim%-(%d+)$'))
  if pid and not vim.uv.kill(pid, 0) then vim.fn.delete(dir, 'rf') end -- left by a Neovim that crashed
end
viz.watchers = {}
for _, dir in ipairs({ viz.dir, viz.own }) do
  pcall(vim.fn.mkdir, dir, 'p') -- a read-only ~/.cache must not stop the rest of this config
  local watcher = vim.uv.new_fs_event()
  watcher:start(dir, {}, function(_, name)
    if name and name:match('^viz%-%d+%.png$') then viz.schedule() end
  end)
  table.insert(viz.watchers, watcher)
end
vim.api.nvim_create_autocmd({ 'VimResized', 'WinResized' }, {
  callback = function()
    if viz.path then viz.schedule() end
  end,
})
vim.api.nvim_create_autocmd('VimLeavePre', {
  callback = function()
    viz.hide()
    vim.fn.delete(viz.own, 'rf')
  end,
})

-- Save, then run the current file in a split (type into it for input(); q closes it).
-- Each run replaces the previous run's window.
local function run_python()
  if vim.b.python_run then vim.cmd.wincmd('p') end -- pressed from the output window
  local file = vim.fn.expand('%:p')
  vim.cmd.write()
  history.show(nil) -- leave any earlier-step view (F7) and its line mark
  viz.reset()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.b[vim.api.nvim_win_get_buf(win)].python_run then vim.api.nvim_win_close(win, true) end
  end
  vim.cmd('botright 12new')
  vim.b.python_run = true
  vim.bo.bufhidden = 'wipe'
  vim.fn.jobstart({ 'python3', file }, { term = true })
  vim.keymap.set('n', 'q', '<cmd>close<cr>', { buffer = true, desc = 'Close run output' })
  vim.cmd.startinsert()
end
-- changed from original: Space r and F5 are mapped in init.lua, which runs any language.
M.run_python = run_python

-- :Test appends a PASS/FAIL test block for the `class Solution` method in this file.
-- Node inputs and outputs use the helpers in python/lc.py (linked, tree, to_list, to_levels).
local function add_tests()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local text = table.concat(lines, '\n')
  for i, line in ipairs(lines) do
    if line:match('^if __name__ == ') then
      vim.api.nvim_win_set_cursor(0, { i, 0 })
      return vim.notify('This file already has a test block.', vim.log.levels.WARN)
    end
  end

  -- First public method of `class Solution`; types come from annotations or from
  -- old-style docstrings (":type head: ListNode", ":rtype: ListNode").
  local method, def_line, ret, params, types
  local in_solution = false
  for i, line in ipairs(lines) do
    in_solution = in_solution or line:match('^class Solution') ~= nil
    local name, args, rest = line:match('^%s+def%s+(%a[%w_]*)%s*%((.*)%)(.-):%s*$')
    if in_solution and name then
      method, def_line, ret, params, types = name, line, rest:match('%->%s*(.-)%s*$') or '', {}, {}
      local depth, cur = 0, ''
      for ch in (args .. ','):gmatch('.') do
        if ch == ',' and depth == 0 then
          local pname, ann = vim.trim(cur):match('^([%w_]+)%s*:?%s*([^=]*)')
          if pname and pname ~= 'self' then
            params[#params + 1], types[pname] = pname, vim.trim(ann)
          end
          cur = ''
        else
          depth = depth + (ch:match('[%[(]') and 1 or ch:match('[%])]') and -1 or 0)
          cur = cur .. ch
        end
      end
      for j = i + 1, math.min(i + 12, #lines) do
        local pname, ptype = lines[j]:match(':type%s+([%w_]+):%s*(.-)%s*$')
        if pname then types[pname] = ptype end
        ret = lines[j]:match(':rtype:%s*(.-)%s*$') or ret
      end
      break
    end
  end
  if not method then
    return vim.notify('No `class Solution` method found in this file.', vim.log.levels.ERROR)
  end

  -- Imports: lc helpers for node inputs/outputs, and names that annotations need at runtime.
  local function missing(module, name)
    return not text:find('from ' .. module .. ' import[^\n]*%f[%w_]' .. name .. '%f[^%w_]')
  end
  local wanted = { typing = {}, lc = {} }
  local function want(module, name)
    if missing(module, name) and not vim.tbl_contains(wanted[module], name) then
      table.insert(wanted[module], name)
    end
  end
  for node, build, convert in ('ListNode linked to_list TreeNode tree to_levels'):gmatch('(%S+) (%S+) (%S+)') do
    for _, pname in ipairs(params) do
      if types[pname]:find(node) then want('lc', build) end
    end
    if ret:find(node) then want('lc', convert) end
    if def_line:find(node) and not text:find('class ' .. node) then want('lc', node) end
  end
  for _, name in ipairs({ 'Optional', 'List', 'Dict', 'Set', 'Tuple' }) do
    if def_line:find('%f[%w]' .. name .. '%[') then want('typing', name) end
  end
  -- Lay imports out the way ruff's isort rules expect: sorted names (classes first),
  -- typing merged into an existing line, lc in its own section.
  local function joined(names)
    table.sort(names, function(a, b)
      local ca, cb = a:match('^%u') ~= nil, b:match('^%u') ~= nil
      if ca ~= cb then return ca end
      return a:lower() < b:lower()
    end)
    return table.concat(names, ', ')
  end
  local at = 0 -- last top-level import line, else the leading URL comment
  for i, line in ipairs(lines) do
    if line:match('^import ') or line:match('^from ') then
      at = i
    elseif not (line:match('^%s*$') or line:match('^#')) then
      break
    end
  end
  local new = {}
  if #wanted.typing > 0 then
    local row, existing = nil, nil
    for i = 1, at do
      existing = lines[i]:match('^from typing import (.+)$')
      if existing then row = i break end
    end
    if row then
      local names = vim.split(existing, '%s*,%s*')
      vim.list_extend(names, wanted.typing)
      vim.api.nvim_buf_set_lines(0, row - 1, row, false, { 'from typing import ' .. joined(names) })
    else
      new[#new + 1] = 'from typing import ' .. joined(wanted.typing)
    end
  end
  if #wanted.lc > 0 then
    if #new > 0 or at > 0 and lines[at]:match('^[fi]') then new[#new + 1] = '' end
    new[#new + 1] = 'from lc import ' .. joined(wanted.lc)
  end
  if #new > 0 then
    if at == 0 and (lines[1] or ''):match('^#') then at = 1 end
    if at > 0 and not lines[at]:match('^[fi]') then table.insert(new, 1, '') end
    if lines[at + 1] and not lines[at + 1]:match('^%s*$') then new[#new + 1] = '' end
    vim.api.nvim_buf_set_lines(0, at, at, false, new)
  end

  -- Test block as a snippet: <Tab> jumps between placeholders. Brackets and quotes are
  -- pre-filled, so you type only the contents: 2, 7, 11 rather than [2, 7, 11].
  local function wrap(t, slot)
    if t:find('ListNode') then return 'linked([' .. slot .. '])' end
    if t:find('TreeNode') then return 'tree([' .. slot .. '])' end
    if t:match('^[Ll]ist') then return '[' .. slot .. ']' end
    if t == 'str' then return '"' .. slot .. '"' end
    return slot
  end
  local fields = {}
  for i, pname in ipairs(params) do
    fields[i] = wrap(types[pname], ('${%d:%s}'):format(i, pname))
  end
  local expected = ('${%d:expected}'):format(#params + 1)
  local convert = ret:find('ListNode') and 'to_list' or ret:find('TreeNode') and 'to_levels'
  fields[#fields + 1] = convert and '[' .. expected .. ']' or wrap(ret, expected)
  local call = ('Solution().%s(*args)'):format(method)
  local body = table.concat({
    'if __name__ == "__main__":',
    '    cases: list[tuple] = [',
    '        # (' .. table.concat(vim.list_extend(vim.list_slice(params), { 'expected' }), ', ') .. ')',
    '        (' .. table.concat(fields, ', ') .. (#fields == 1 and ',' or '') .. '),$0',
    '    ]',
    '    for *args, want in cases:',
    '        shown = repr(args)[1:-1]',
    '        got = ' .. (convert and convert .. '(' .. call .. ')' or call),
    '        mark = "PASS" if got == want else "FAIL"',
    '        print(f"{mark}  {shown} => {got!r}  (expected {want!r})")',
  }, '\n')
  local last = vim.api.nvim_buf_line_count(0)
  vim.api.nvim_buf_set_lines(0, last, last, false, { '', '', '' })
  vim.api.nvim_win_set_cursor(0, { last + 3, 0 })
  vim.snippet.expand(body)
end
vim.api.nvim_create_user_command('Test', add_tests, { desc = 'Add a test block for class Solution' })

-- Debugger: variables panel on the right, program output at the bottom.
vim.pack.add({
  'https://github.com/mfussenegger/nvim-dap',
  'https://github.com/mfussenegger/nvim-dap-python',
  'https://github.com/nvim-neotest/nvim-nio',
  'https://github.com/rcarriga/nvim-dap-ui',
})
local dap, dapui = require('dap'), require('dapui')
require('dap-python').setup('python3') -- miniconda's python3 ships debugpy
-- Python lives on a slow external drive; allow debugpy more than the default 4s to start.
local python_adapter = dap.adapters.python
dap.adapters.python = function(cb, config)
  python_adapter(function(adapter)
    adapter.options = vim.tbl_extend('force', adapter.options or {}, { initialize_timeout_sec = 15 })
    cb(adapter)
  end, config)
end
dapui.setup({
  wrap = true, -- long values like a graph's adjacency dict wrap instead of being cut off
  layouts = {
    {
      -- dap-ui stacks these bottom-up: shown top to bottom as variables, picture, watches.
      elements = {
        { id = 'watches', size = 0.15 },
        { id = 'viz', size = 0.6 },
        { id = 'scopes', size = 0.25 },
      },
      position = 'right',
      size = 0.4, -- 40% of the screen width
    },
    { elements = { 'console' }, position = 'bottom', size = 12 },
  },
})
dapui.register_element('viz', { render = function() end, buffer = viz.buffer, allow_without_session = true })
-- Panels open on start and stay open after the program ends so output stays visible.
dap.listeners.before.launch.dapui = function() dapui.open() end
-- In top-level code Locals and Globals hold the same variables; list them once.
dap.listeners.before.scopes['hide-module-globals'] = function(session, _, response, request)
  local frame = session.current_frame
  if response and frame and frame.id == request.frameId and frame.name == '<module>' then
    response.scopes = vim.tbl_filter(function(s) return s.name ~= 'Globals' end, response.scopes)
  end
end

-- Debugger panels, the Viz panel and F5 run output, as opposed to code windows.
local function is_panel(win)
  local buf = vim.api.nvim_win_get_buf(win)
  local ft = vim.bo[buf].filetype
  -- changed from original: the snacks file tree and error list count as panels too.
  return ft:match('^dap') ~= nil or ft == 'lcviz' or vim.b[buf].python_run == true
    or ft:match('^snacks_') ~= nil
end
M.is_panel = is_panel -- changed from original: exported for init.lua.

-- Step history: each stop's memory picture is kept with its file and line, so F7/F8 can
-- show earlier steps. The program itself can't go back (debugpy has no step-back); F10
-- carries on live. Cleared when a new debug session starts.
-- ponytail: every step kept (~80 KB each) until the next F6; cap it if runs get long.
-- (The `history` table itself is declared next to `viz`, so F5 can leave the past view.)
local past_ns = vim.api.nvim_create_namespace('lcpast')
vim.api.nvim_set_hl(0, 'LcPastLine', { default = true, link = 'Visual' })
pcall(vim.fn.mkdir, history.dir, 'p')

-- Called once a stop's picture is drawn: keep a copy of it (the newest in this Neovim's folder).
function history.add(frame)
  local files = vim.fn.glob(viz.own .. '/viz-*.png', false, true)
  table.sort(files)
  local copy = ('%s/step-%d.png'):format(history.dir, #history.steps + 1)
  if files[#files] and vim.uv.fs_copyfile(files[#files], copy) then
    table.insert(history.steps, { png = copy, file = frame.source and frame.source.path, line = frame.line })
  end
end

-- Show step `at` (its picture, and its line marked in the code), or nil for live.
function history.show(at)
  local step = at and history.steps[at]
  local was_pinned = viz.pin ~= nil
  history.at = step and at or nil
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do vim.api.nvim_buf_clear_namespace(buf, past_ns, 0, -1) end
  viz.pin = step and { path = step.png, label = (' step %d/%d · past · F7 ◀ F8 ▶ · F10 resumes'):format(at, #history.steps) }
  if step or was_pinned then viz.schedule() end
  if not (step and step.file) then return end
  local buf = vim.fn.bufadd(step.file)
  vim.fn.bufload(buf)
  local win = vim.fn.bufwinid(buf)
  if win == -1 then -- e.g. the step was in a file you stepped into; show it in a code window
    win = vim.iter(vim.api.nvim_tabpage_list_wins(0)):find(function(w)
      return not is_panel(w) and vim.api.nvim_win_get_config(w).relative == ''
    end) or vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)
  end
  local line = math.min(step.line, vim.api.nvim_buf_line_count(buf)) -- the file may have been edited since
  vim.api.nvim_buf_set_extmark(buf, past_ns, line - 1, 0,
    { sign_text = '◀', sign_hl_group = 'LcPastLine', line_hl_group = 'LcPastLine' })
  vim.api.nvim_win_set_cursor(win, { line, 0 })
end

function history.move(delta)
  local count = #history.steps
  if count == 0 then return vim.notify('No steps yet: start with F6 and step with F10') end
  local at = (history.at or count) + delta -- the live view is the newest step
  if at < 1 then return vim.notify('This is the first step') end
  if at > count then return vim.notify('This is the latest step') end
  history.show(at < count and at or nil)
end

function history.reset()
  history.show(nil)
  for _, file in ipairs(vim.fn.glob(history.dir .. '/step-*.png', false, true)) do os.remove(file) end
  history.steps = {}
end

-- Python Tutor style picture of the paused program's memory, redrawn at every stop.
-- memory_view.py and memory_graph live outside any project, so the paused program
-- gets them on sys.path for the call: it works in any folder, venv or conda env.
local memory_paths = { vim.fn.stdpath('config') .. '/python', vim.fn.stdpath('data') .. '/memory-graph' }
-- Built per stop: the colors follow 'background', which Neovim reads from the terminal theme.
local function memory_expr()
  return ("(lambda s: ([s.path.append(p) for p in %s if p not in s.path],"
    .. " __import__('memory_view').render(%s, dark=%s))[1])(__import__('sys'))")
    :format(vim.json.encode(memory_paths), vim.json.encode(viz.own), vim.o.background == 'dark' and 'True' or 'False')
end
dap.listeners.after.event_stopped['memory-view'] = function(session, body)
  -- changed from original: the picture reads Python objects; skip other languages' sessions.
  if session.config.type ~= 'python' then return end
  if history.at then history.show(nil) end -- a real step: back to live
  for _, watch in ipairs(dapui.elements.watches.get()) do
    if watch.expression:find('draw(', 1, true) then return end -- a draw() watch owns the panel
  end
  local stop = (session.memory_view_stop or 0) + 1
  session.memory_view_stop = stop
  -- A fast F10 resumes the program before a reply arrives; ignore replies for old stops.
  local function current() return session.memory_view_stop == stop and session.stopped_thread_id ~= nil end
  session:request('stackTrace', { threadId = body.threadId, levels = 1 }, function(err, response)
    local frame = not err and current() and response.stackFrames[1]
    if not frame then return end
    session:request('evaluate', { expression = memory_expr(), frameId = frame.id, context = 'repl' }, function(e)
      if not e then return history.add(frame) end
      if not current() or session.memory_view_warned then return end
      session.memory_view_warned = true -- once per run, not on every step
      local reason = (e.message or vim.inspect(e)):match('([^\n]+)\n*$') -- a traceback's last line
      vim.notify('Memory picture failed: ' .. reason, vim.log.levels.WARN)
    end)
  end)
end

local function debug_start_or_continue()
  if dap.session() then return dap.continue() end
  vim.cmd('stopinsert | write')
  history.reset()
  viz.reset()
  for _, win in ipairs(vim.fn.win_findbuf(viz.buffer())) do -- the debugger column has its own
    if vim.w[win].lcviz_split then vim.api.nvim_win_close(win, true) end
  end
  dap.run({
    type = 'python',
    request = 'launch',
    name = 'Debug file',
    program = vim.fn.expand('%:p'),
    console = 'integratedTerminal',
    -- With no breakpoints set, pause on the first line instead of running straight through.
    stopOnEntry = next(require('dap.breakpoints').get()) == nil,
    -- Show only your own variables, not Python internals (__name__, methods, ...).
    variablePresentation = { special = 'hide', ['function'] = 'hide', class = 'hide' },
  })
end

-- changed from original: F6 is mapped in init.lua, which debugs any language.
M.debug_python = debug_start_or_continue
local modes = { 'n', 'i', 't' }
vim.keymap.set({ 'n', 'i' }, '<F9>', dap.toggle_breakpoint, { desc = 'Debug: toggle breakpoint' })
vim.keymap.set(modes, '<F10>', dap.step_over, { desc = 'Debug: next line' })
vim.keymap.set(modes, '<F11>', dap.step_into, { desc = 'Debug: step into function' })
vim.keymap.set(modes, '<F7>', function() history.move(-1) end, { desc = 'Debug: show the previous step' })
vim.keymap.set(modes, '<F8>', function() history.move(1) end, { desc = 'Debug: show the next step' })
vim.keymap.set(modes, '<F4>', function()
  dap.terminate()
  dapui.close()
end, { desc = 'Debug: stop and close panels' })

-- :q in the last code window also closes the debugger panels and run output, so one
-- :q quits Neovim instead of one :q per panel.
vim.api.nvim_create_autocmd('QuitPre', {
  callback = function()
    local current = vim.api.nvim_get_current_win()
    if is_panel(current) then return end
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local floating = vim.api.nvim_win_get_config(win).relative ~= ''
      if win ~= current and not floating and not is_panel(win) then return end
    end
    if dap.session() then dap.terminate() end
    dapui.close()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if win ~= current and is_panel(win) then pcall(vim.api.nvim_win_close, win, true) end
    end
  end,
})

-- changed from original: module return.
return M
