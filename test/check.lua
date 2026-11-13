-- test/check.lua
-- Headless checks for this config. Run through test/check.sh, which also checks the
-- startup budget. Prints PASS/FAIL per case; exits 1 if any case failed.
-- Sample files go in Neovim's own temp folder, never in a real repo.

local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')
vim.cmd.cd(root) -- pickers and the tree read the working folder
local failed = 0

local noticed = {}
vim.notify = function(msg) table.insert(noticed, tostring(msg)) end

-- Everything passed to vim.notify since the last call.
local function notices()
  local out = noticed
  noticed = {}
  return out
end

-- Write `text` to `rel` under this run's temp folder; return the absolute path.
local function sample(rel, text)
  local path = root .. '/' .. rel
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  local f = assert(io.open(path, 'w'))
  f:write(text)
  f:close()
  return path
end

local function edit(path) vim.cmd.edit(vim.fn.fnameescape(path)) end

-- Edit `path` and wait up to `ms` for the language server `client` to attach.
local function attached(path, client, ms)
  edit(path)
  local buf = vim.api.nvim_get_current_buf()
  return vim.wait(ms, function() return #vim.lsp.get_clients({ bufnr = buf, name = client }) > 0 end, 50)
end

-- Call the Lua callback of a mapping, as pressing the key would.
local function press(key, mode)
  local map = vim.fn.maparg(key, mode or 'n', false, true)
  assert(map.callback, 'no Lua mapping for ' .. key)
  map.callback()
end

local function run_windows()
  local wins = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.b[vim.api.nvim_win_get_buf(win)].python_run then table.insert(wins, win) end
  end
  return wins
end

-- Wait for the run panel's job to finish; return the panel's text.
local function panel_text(ms)
  local win = assert(run_windows()[1], 'no run window')
  local buf = vim.api.nvim_win_get_buf(win)
  local job = vim.b[buf].terminal_job_id
  vim.wait(ms, function() return vim.fn.jobwait({ job }, 0)[1] ~= -1 end, 50)
  vim.wait(300) -- let the terminal draw the last lines
  return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
end

-- Edit `path`, press F5, and return the run panel's text once the program exits.
local function run_output(path, ms)
  edit(path)
  press('<F5>')
  vim.cmd.stopinsert()
  return panel_text(ms)
end

-- Back to one window, and wipe file and terminal buffers. The debugger panels keep their
-- own (nofile) buffers, which dap-ui expects to reuse.
local function reset()
  for _, picker in ipairs(Snacks.picker.get({ tab = false })) do picker:close() end
  vim.wait(100) -- picker windows close on the next loop turn
  vim.cmd('silent! only | silent! enew!')
  local current = vim.api.nvim_get_current_buf()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local bt = vim.bo[buf].buftype
    if buf ~= current and (bt == '' or bt == 'terminal') then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
end

-- CHECK_ONLY=<Lua pattern> runs only the matching cases, for quick iteration.
local function case(name, fn)
  if vim.env.CHECK_ONLY and not name:match(vim.env.CHECK_ONLY) then return end
  reset()
  notices()
  local ok, err = pcall(fn)
  if ok then
    io.write('PASS ', name, '\n')
  else
    failed = failed + 1
    io.write('FAIL ', name, ': ', tostring(err), '\n')
  end
end

case('python_lsp', function()
  local path = sample('py/a.py', 'print(1)\n')
  assert(attached(path, 'basedpyright', 20000), 'basedpyright did not attach')
  assert(attached(path, 'ruff', 20000), 'ruff did not attach')
end)

case('python_run', function()
  local out = run_output(sample('py/b.py', 'print("hi py")\n'), 30000)
  assert(out:find('hi py', 1, true), out)
end)

case('practice_api', function()
  assert(type(require('practice').is_panel) == 'function', 'practice.is_panel missing')
  assert(vim.fn.exists(':Test') == 2, ':Test missing')
  assert(vim.fn.maparg('<F7>', 'n') ~= '', 'F7 unmapped')
end)

case('quote_pairs', function()
  vim.api.nvim_feedkeys('i"""', 'xt', false)
  local line = vim.api.nvim_get_current_line()
  assert(line == '"""', 'line is ' .. line)
end)

case('key_modes', function()
  local want = { ['<leader>r'] = { 'n' }, ['<F5>'] = { 'n', 'i', 's' }, ['<F6>'] = { 'n', 'i', 't' } }
  for key, modes in pairs(want) do
    for _, mode in ipairs(modes) do
      assert(vim.fn.maparg(key, mode) ~= '', key .. ' unmapped in mode ' .. mode)
    end
  end
end)

case('rerun_from_output', function()
  local path = sample('py/c.py', 'print("again")\n')
  run_output(path, 30000)
  vim.api.nvim_set_current_win(run_windows()[1])
  press('<F5>')
  vim.cmd.stopinsert()
  local out = panel_text(30000)
  assert(out:find('again', 1, true), out)
  assert(#run_windows() == 1, #run_windows() .. ' run windows')
  local said = notices()
  assert(#said == 0, table.concat(said, '; '))
end)

-- A machine without a server (a fresh Mac before :InstallTools) opens files quietly.
case('missing_server_quiet', function()
  local mason_bin = vim.fn.stdpath('data') .. '/mason/bin'
  local path = vim.env.PATH
  vim.env.PATH = table.concat(vim.tbl_filter(function(dir) return dir ~= mason_bin end,
    vim.split(path, ':', { plain = true })), ':')
  local ok, err = pcall(function()
    edit(sample('quiet/a.go', 'package main\n'))
    vim.wait(1000)
    local said = notices()
    assert(#said == 0, table.concat(said, '; '))
  end)
  vim.env.PATH = path
  assert(ok, err)
end)

local servers = {
  { 'rust', 'rs/main.rs', 'fn main() {}\n', 'rust_analyzer' },
  { 'c', 'c/a.c', 'int main(void) { return 0; }\n', 'clangd' },
  { 'cpp', 'cpp/a.cpp', 'int main() { return 0; }\n', 'clangd' },
  { 'go', 'go/main.go', 'package main\n\nfunc main() {}\n', 'gopls' },
  { 'js', 'js/a.js', 'console.log(1);\n', 'vtsls' },
  { 'ts', 'ts/a.ts', 'const n: number = 1;\n', 'vtsls' },
  { 'tsx', 'tsx/a.tsx', 'export const A = () => <div />;\n', 'vtsls' },
}
sample('go/go.mod', 'module example.com/check\n\ngo 1.21\n')
for _, s in ipairs(servers) do
  case('lsp_' .. s[1], function()
    assert(attached(sample(s[2], s[3]), s[4], 30000), s[4] .. ' did not attach')
  end)
end

-- A Rust file outside any Cargo project (LeetCode style) still gets language features,
-- without an error popup about the missing workspace.
case('rust_single_file', function()
  local path = sample('rs single/a.rs', 'fn add(a: i32) -> i32 { a + 1 }\nfn main() {\n    println!("{}", add(1));\n}\n')
  assert(attached(path, 'rust_analyzer', 30000), 'rust_analyzer did not attach')
  local buf = vim.api.nvim_get_current_buf()
  local params = { textDocument = { uri = vim.uri_from_bufnr(buf) }, position = { line = 2, character = 20 } }
  local text = ''
  for _ = 1, 15 do -- the server indexes first; ask again until it answers
    for _, r in pairs(vim.lsp.buf_request_sync(buf, 'textDocument/hover', params, 2000) or {}) do
      if r.result then text = r.result.contents.value or '' end
    end
    if text:find('fn add', 1, true) then break end
    vim.wait(1000)
  end
  assert(text:find('fn add', 1, true), 'no hover: ' .. text)
  local said = table.concat(notices(), '; ')
  assert(not said:find('workspace', 1, true), said)
end)

-- Write `lines` to a buffer of `path` once `client` is attached; return the saved text.
local function saved(path, client, lines)
  assert(attached(path, client, 30000), client .. ' did not attach')
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.cmd('silent write')
  return table.concat(vim.fn.readfile(path), '\n') .. '\n'
end

case('format_go', function()
  local text = 'package main\nfunc  main(){}\n'
  local want = vim.system({ 'gofmt' }, { stdin = text }):wait().stdout
  local got = saved(sample('go/fmt.go', ''), 'gopls', vim.split(text, '\n', { trimempty = true }))
  assert(got == want, vim.inspect(got))
end)

case('no_format_c', function()
  local got = saved(sample('c/fmt.c', ''), 'clangd', { 'int main(){return 0;}' })
  assert(got == 'int main(){return 0;}\n', vim.inspect(got))
end)

case('format_key', function()
  assert(vim.fn.maparg('<leader>cf', 'n') ~= '', 'Space c f unmapped')
end)

-- Type `keys` (with <...> key names) into an empty buffer; return the line.
local function typed(keys)
  vim.cmd.enew()
  vim.api.nvim_feedkeys(vim.keycode(keys), 'xt', false)
  return vim.api.nvim_get_current_line()
end
local show_menu = "<Cmd>lua vim.fn.complete(1, { 'alpha', 'beta' })<CR>"

-- Tab accepts a completion suggestion: the first when none is picked, as in VS Code.
case('tab_accepts_first_suggestion', function()
  local line = typed('i' .. show_menu .. '<Tab><Esc>')
  assert(line == 'alpha', vim.inspect(line))
end)

case('tab_accepts_picked_suggestion', function()
  local line = typed('i' .. show_menu .. '<C-n><C-n><Tab><Esc>')
  assert(line == 'beta', vim.inspect(line))
end)

-- With no menu, Tab still jumps to the next snippet field (:Test needs it) or inserts a tab.
case('tab_jumps_snippet_field', function()
  local line = typed("i<Cmd>lua vim.snippet.expand('$1-$2')<CR>x<Tab>y<Esc>")
  assert(line == 'x-y', vim.inspect(line))
end)

case('tab_inserts_tab', function()
  local line = typed('i<Tab>x<Esc>')
  assert(line == '\tx', vim.inspect(line))
end)

-- F5 in every language, from folders with spaces in their names.
local programs = {
  { 'c', 'c/a.c', '#include <stdio.h>\nint main(void) { puts("hi c"); return 0; }\n' },
  { 'cpp', 'cpp/a.cpp', '#include <iostream>\nint main() { std::cout << "hi cpp\\n"; }\n' },
  { 'rust_file', 'rs/a.rs', 'fn main() { println!("hi rust_file"); }\n' },
  { 'go', 'go/main.go', 'package main\n\nimport "fmt"\n\nfunc main() { fmt.Println("hi go") }\n' },
  { 'js', 'js/a.js', 'console.log("hi js");\n' },
  { 'ts', 'ts/a.ts', 'const who: string = "ts";\nconsole.log(`hi ${who}`);\n' },
}
local spaced = 'dir with space/'
sample(spaced .. 'go/go.mod', 'module example.com/hi\n\ngo 1.21\n')
for _, p in ipairs(programs) do
  case('run_' .. p[1], function()
    local out = run_output(sample(spaced .. p[2], p[3]), 60000)
    assert(out:find('hi ' .. p[1], 1, true), out)
  end)
end

case('run_rust_cargo', function()
  sample(spaced .. 'cargo/Cargo.toml', '[package]\nname = "hi"\nversion = "0.1.0"\nedition = "2021"\n')
  local out = run_output(sample(spaced .. 'cargo/src/main.rs', 'fn main() { println!("hi cargo"); }\n'), 120000)
  assert(out:find('hi cargo', 1, true), out)
end)

case('run_tsx', function()
  edit(sample(spaced .. 'tsx/a.tsx', 'export const A = () => <div />;\n'))
  press('<F5>')
  assert(vim.tbl_contains(notices(), 'TSX needs a bundler; F5 does not run it'), 'no TSX message')
  assert(#run_windows() == 0, 'a run panel opened')
end)

case('run_no_file', function()
  vim.cmd.enew()
  press('<F5>')
  assert(table.concat(notices(), '\n'):find('open a code file', 1, true), 'no message')
end)

case('compile_error', function()
  local path = sample(spaced .. 'err/a.c', '#include <stdio.h>\nint main(void) { puts("old-output"); }\n')
  assert(run_output(path, 60000):find('old-output', 1, true), 'first run failed')
  reset()
  sample(spaced .. 'err/a.c', 'int main(void) { return 1 }\n')
  local out = run_output(path, 60000)
  assert(out:find('error', 1, true), out)
  assert(not out:find('old-output', 1, true), 'ran the old binary: ' .. out)
end)

case('same_name', function()
  local x = sample('x/main.c', '#include <stdio.h>\nint main(void) { puts("from-x"); }\n')
  local y = sample('y/main.c', '#include <stdio.h>\nint main(void) { puts("from-y"); }\n')
  for _, step in ipairs({ { x, 'from-x' }, { y, 'from-y' }, { x, 'from-x' } }) do
    reset()
    local out = run_output(step[1], 60000)
    assert(out:find(step[2], 1, true), out)
  end
end)

case('rerun_replaces', function()
  edit(sample('py/wait.py', 'input("name? ")\n'))
  press('<F5>')
  vim.cmd.stopinsert()
  press('<F5>')
  vim.cmd.stopinsert()
  assert(#run_windows() == 1, #run_windows() .. ' run windows')
end)

case('no_binary_beside_source', function()
  local path = sample('alone/a.c', '#include <stdio.h>\nint main(void) { puts("alone"); }\n')
  assert(run_output(path, 60000):find('alone', 1, true), 'run failed')
  local names = vim.fn.readdir(vim.fs.dirname(path))
  assert(#names == 1 and names[1] == 'a.c', vim.inspect(names))
end)

-- Tree, finder, search, error list, git marks, status line.
case('keys_exist', function()
  for _, key in ipairs({ '<C-p>', '<leader>ff', '<leader>fr', '<leader>/', '<C-b>', '<leader>e', '<leader>xx' }) do
    assert(vim.fn.maparg(key, 'n', false, true).callback, key .. ' has no Lua callback')
  end
end)

case('open_files_list', function()
  edit(sample('bufs/a.py', 'x = 1\n'))
  edit(sample('bufs/b.py', 'y = 2\n'))
  press('<leader>b')
  assert(vim.wait(5000, function() return #Snacks.picker.get({ source = 'buffers' }) > 0 end, 50),
    'Space b did not open the list of open files')
end)

local function tree_windows()
  return vim.tbl_filter(function(win)
    return vim.bo[vim.api.nvim_win_get_buf(win)].filetype:match('^snacks_') ~= nil
  end, vim.api.nvim_list_wins())
end

local function open_tree()
  press('<C-b>')
  assert(vim.wait(5000, function() return #tree_windows() > 0 end, 50), 'tree did not open')
end

case('tree_toggle', function()
  edit(sample('tree/a.py', 'x = 1\n'))
  open_tree()
  press('<C-b>')
  assert(vim.wait(5000, function() return #tree_windows() == 0 end, 50), 'tree did not close')
end)

case('tree_is_panel', function()
  edit(sample('tree/a.py', 'x = 1\n'))
  open_tree()
  for _, win in ipairs(tree_windows()) do
    assert(require('practice').is_panel(win), 'tree window is not a panel')
  end
end)

case('tree_stays_open', function()
  edit(sample('tree/a.py', 'x = 1\n'))
  local code = vim.api.nvim_get_current_win()
  open_tree()
  vim.api.nvim_set_current_win(code)
  edit(sample('tree/b.py', 'y = 2\n'))
  vim.wait(300)
  assert(#tree_windows() > 0, 'tree closed')
end)

case('statusline_set', function()
  assert(vim.o.statusline:find('MiniStatusline', 1, true), vim.o.statusline)
end)

case('diff_signs', function()
  local path = sample('repo/a.txt', 'one\ntwo\n')
  local git = { 'git', '-C', vim.fs.dirname(path), '-c', 'user.name=t', '-c', 'user.email=t@t' }
  for _, args in ipairs({ { 'init', '-q' }, { 'add', 'a.txt' }, { 'commit', '-qm', 'init' } }) do
    assert(vim.system(vim.list_extend(vim.deepcopy(git), args)):wait().code == 0, 'git ' .. args[1])
  end
  edit(path)
  vim.api.nvim_buf_set_lines(0, 1, 2, false, { 'changed' })
  local hunks = function() return #((MiniDiff.get_buf_data(0) or {}).hunks or {}) end
  assert(vim.wait(3000, function() return hunks() == 1 end, 50), 'hunks: ' .. hunks())
end)

case('quiet_start', function()
  local out = vim.system({ 'nvim', '--headless', '-c',
    'lua io.write(#vim.api.nvim_list_wins(), "|", vim.fn.execute("messages"))', '+qa' }):wait().stdout
  assert(out == '1|', vim.inspect(out))
end)

-- Debugger: breakpoints stop in every compiled language, from folders with spaces.
local dap = require('dap')

-- Set breakpoints on `lines` of `path`, press F6, and wait for the first stop.
local function debug_until_stop(path, lines, ms)
  edit(path)
  for _, line in ipairs(lines) do
    vim.api.nvim_win_set_cursor(0, { line, 0 })
    dap.set_breakpoint()
  end
  press('<F6>')
  -- Fail fast when F6 starts no session (a message or a build-error panel instead).
  local refused = function()
    return #vim.tbl_filter(function(m) return m:find('^F6') ~= nil end, noticed) > 0
  end
  vim.wait(ms, function() return dap.session() ~= nil or refused() or #run_windows() > 0 end, 100)
  assert(dap.session(), 'no session; notices: ' .. table.concat(notices(), '; '))
  assert(vim.wait(ms, function() return dap.session() and dap.session().current_frame ~= nil end, 100),
    'no stop; notices: ' .. table.concat(notices(), '; '))
  return dap.session()
end

local function stop_debug()
  require('dap.breakpoints').clear()
  if dap.session() then dap.terminate() end
  vim.wait(5000, function() return dap.session() == nil end, 100)
  require('dapui').close()
end

-- Run fn, then stop the debugger whether fn passed or not.
local function debugging(fn)
  return function()
    local ok, err = pcall(fn)
    stop_debug()
    assert(ok, err)
  end
end

local debuggees = {
  cpp = { spaced .. 'dbg/a.cpp', '#include <cstdio>\nint main() {\n  int a = 1;\n  int b = a + 1;\n  std::printf("%d\\n", b);\n}\n', 3 },
  rust = { spaced .. 'dbg/a.rs', 'fn main() {\n    let a = 1;\n    let b = a + 1;\n    println!("{}", b);\n}\n', 3 },
  -- Go is saved through gofmt, so the sample is already in gofmt layout.
  go = { spaced .. 'dbg/go/main.go', 'package main\n\nfunc main() {\n\ta := 1\n\tprintln(a + 1)\n}\n', 4 },
}
sample(spaced .. 'dbg/go/go.mod', 'module example.com/dbg\n\ngo 1.21\n')
for _, lang in ipairs({ 'cpp', 'rust', 'go' }) do
  local d = debuggees[lang]
  case('debug_' .. lang, debugging(function()
    local s = debug_until_stop(sample(d[1], d[2]), { d[3] }, 120000)
    assert(s.current_frame.line == d[3], 'stopped at line ' .. s.current_frame.line)
  end))
end

case('debug_no_memory_warning', debugging(function()
  local d = debuggees.cpp
  debug_until_stop(sample(d[1], d[2]), { d[3] }, 120000)
  vim.wait(2000)
  local said = table.concat(notices(), '; ')
  assert(not said:find('Memory picture', 1, true), said)
end))

case('continue_from_panel', debugging(function()
  local d = debuggees.cpp
  local s = debug_until_stop(sample(d[1], d[2]), { 3, 4 }, 120000)
  local panel = vim.tbl_filter(function(win)
    return vim.bo[vim.api.nvim_win_get_buf(win)].filetype:match('^dap') ~= nil
  end, vim.api.nvim_list_wins())[1]
  assert(panel, 'no debugger panel open')
  vim.api.nvim_set_current_win(panel)
  press('<F6>')
  assert(vim.wait(30000, function() return s.current_frame and s.current_frame.line == 4 end, 100),
    'did not continue to line 4')
  local said = table.concat(notices(), '; ')
  assert(not said:find('open a code file', 1, true), said)
end))

case('debug_build_error', debugging(function()
  edit(sample(spaced .. 'dbg/bad.c', 'int main(void) { return 1 }\n'))
  press('<F6>')
  vim.cmd.stopinsert()
  local out = panel_text(60000)
  assert(out:find('error', 1, true), out)
  assert(dap.session() == nil, 'a debug session started')
end))

case('debug_python_still', debugging(function()
  local path = sample('py/dbg.py', 'a = 1\nb = a + 1\nc = b + 1\nprint(c)\n')
  local s = debug_until_stop(path, { 3 }, 120000)
  assert(s.current_frame.line == 3, 'stopped at line ' .. s.current_frame.line)
end))

-- Fixes from the whole-branch review.

-- Format on save keeps working, without warnings, after the server restarts.
case('format_after_restart', function()
  local path = sample('go/restart.go', 'package main\n')
  assert(attached(path, 'gopls', 30000), 'gopls did not attach')
  local buf = vim.api.nvim_get_current_buf()
  local old = vim.lsp.get_clients({ bufnr = buf, name = 'gopls' })[1].id
  vim.cmd('lsp restart gopls')
  assert(vim.wait(30000, function()
    local c = vim.lsp.get_clients({ bufnr = buf, name = 'gopls' })[1]
    return c ~= nil and c.id ~= old and c.initialized
  end, 100), 'gopls did not come back')
  notices()
  local text = 'package main\nfunc  main(){}\n'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, '\n', { trimempty = true }))
  vim.cmd('silent write')
  local want = vim.system({ 'gofmt' }, { stdin = text }):wait().stdout
  assert(table.concat(vim.fn.readfile(path), '\n') .. '\n' == want, 'not formatted')
  local said = table.concat(notices(), '; ')
  assert(said == '', said)
end)

-- A missing runtime or compiler gives one message, and no panel or Lua error.
case('missing_runtime', function()
  local js = sample('js/norun.js', 'console.log(1);\n')
  local c = sample('c/nocc.c', 'int main(void) { return 0; }\n')
  local path = vim.env.PATH
  local ok, err = pcall(function()
    edit(js)
    vim.env.PATH = '/nonexistent'
    press('<F5>')
    assert(#run_windows() == 0, 'a run panel opened')
    assert(table.concat(notices(), '\n'):find('F5: node not found on PATH', 1, true), 'no F5 message')
    edit(c)
    press('<F6>')
    assert(table.concat(notices(), '\n'):find('F6: cc not found on PATH', 1, true), 'no F6 message')
  end)
  vim.env.PATH = path
  assert(ok, err)
end)

-- The error list lists errors from every folder, opens with the cursor in the list, and
-- q closes it.
case('error_list', function()
  sample('elist/sub/keep.txt', '')
  local bad = sample('elist/other/bad.py', 'x: int = "s"\n')
  vim.cmd.cd(root .. '/elist/sub')
  local ok, err = pcall(function()
    assert(attached(bad, 'basedpyright', 20000), 'basedpyright did not attach')
    assert(vim.wait(20000, function() return #vim.diagnostic.get(0) > 0 end, 100), 'no diagnostics')
    press('<leader>xx')
    local picker
    assert(vim.wait(5000, function()
      picker = Snacks.picker.get({ source = 'diagnostics' })[1]
      return picker ~= nil and #picker:items() > 0
    end, 50), 'error list is empty')
    assert(vim.bo.filetype == 'snacks_picker_list' and vim.fn.mode() == 'n',
      'focus is in ' .. vim.bo.filetype .. ' mode ' .. vim.fn.mode())
    vim.api.nvim_feedkeys('q', 'xt', false)
    assert(vim.wait(2000, function() return #tree_windows() == 0 end, 50), 'q did not close it')
  end)
  vim.cmd.cd(root)
  assert(ok, err)
end)

-- Cargo: F5 and F6 use the binary whose main file is open; a library says so.
local function cargo_toml(name)
  return ('[package]\nname = "%s"\nversion = "0.1.0"\nedition = "2021"\n'):format(name)
end
local function multi_crate()
  sample(spaced .. 'multi/Cargo.toml', cargo_toml('multi'))
  sample(spaced .. 'multi/src/main.rs', 'fn main() {\n    println!("hi main");\n}\n')
  return sample(spaced .. 'multi/src/bin/two.rs', 'fn main() {\n    let a = 1;\n    println!("hi two {}", a);\n}\n')
end

case('cargo_second_binary', function()
  local out = run_output(multi_crate(), 120000)
  assert(out:find('hi two', 1, true), out)
end)

case('cargo_second_binary_debug', debugging(function()
  local two = multi_crate()
  local s = debug_until_stop(two, { 3 }, 120000)
  local frame = s.current_frame
  assert(frame.line == 3 and vim.uv.fs_realpath(frame.source.path) == vim.uv.fs_realpath(two),
    ('stopped at %s:%d'):format(frame.source.path, frame.line))
end))

case('cargo_library_only', function()
  sample(spaced .. 'lib/Cargo.toml', cargo_toml('onlylib'))
  edit(sample(spaced .. 'lib/src/lib.rs', 'pub fn f() -> i32 {\n    1\n}\n'))
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  dap.set_breakpoint()
  press('<F6>')
  require('dap.breakpoints').clear()
  local said = table.concat(notices(), '\n')
  assert(said:find('F6: no binary target in this Cargo package', 1, true), 'said: ' .. said)
end)

-- F6 right after F5, with the cursor still in the run panel, debugs the file.
case('debug_from_run_panel', debugging(function()
  local d = debuggees.cpp
  local path = sample(d[1], d[2])
  run_output(path, 60000)
  vim.api.nvim_set_current_win(run_windows()[1])
  vim.cmd('wincmd p')
  vim.api.nvim_win_set_cursor(0, { d[3], 0 })
  dap.set_breakpoint()
  vim.api.nvim_set_current_win(run_windows()[1])
  press('<F6>')
  assert(vim.wait(120000, function() return dap.session() and dap.session().current_frame ~= nil end, 100),
    'no stop; notices: ' .. table.concat(notices(), '; '))
end))

-- :InstallTools says what it did.
case('install_tools_reports', function()
  vim.cmd('InstallTools')
  assert(vim.wait(60000, function()
    return table.concat(noticed, '\n'):find('InstallTools: all tools are installed', 1, true) ~= nil
  end, 200), 'said: ' .. table.concat(noticed, '; '))
end)

-- :InstallTools and install.sh install the tools for the languages you pick. These cases
-- expect the Python and Go tools to be installed already, so nothing is downloaded.
local install_sh = vim.fn.stdpath('config') .. '/install.sh'

case('install_tools_unknown', function()
  vim.cmd('InstallTools nosuch')
  local said = table.concat(notices(), '\n')
  assert(said:find('nosuch', 1, true) and said:find('python', 1, true), said)
end)

case('install_tools_one_language', function()
  vim.cmd('InstallTools python')
  local said = ''
  vim.wait(30000, function()
    said = said .. table.concat(notices(), '\n')
    return said:find('all tools are installed', 1, true) ~= nil
  end, 100)
  assert(said:find('basedpyright', 1, true) and said:find('ruff', 1, true), said)
  assert(not said:find('gopls', 1, true), 'checked other languages: ' .. said)
end)

-- The ! (script) form exits Neovim, so it must do nothing of the kind with a UI attached:
-- typed by hand it would throw away unsaved edits.
case('install_tools_bang_keeps_ui_open', function()
  local chan = vim.fn.jobstart({ 'nvim', '--embed' }, { rpc = true })
  vim.rpcrequest(chan, 'nvim_ui_attach', 80, 24, {})
  pcall(vim.rpcrequest, chan, 'nvim_command', 'InstallTools! python')
  local running = vim.fn.jobwait({ chan }, 3000)[1] == -1
  vim.fn.jobstop(chan)
  assert(running, 'Neovim exited')
end)

-- Run install.sh with `args`; return its exit code and combined output.
local function run_install(args, opts)
  local r = vim.system(vim.list_extend({ install_sh }, args), opts or {}):wait(120000)
  return r.code, (r.stdout or '') .. (r.stderr or '')
end

case('install_sh_bad_name', function()
  local code, out = run_install({ 'nosuch' })
  assert(code == 2, 'exit ' .. code .. ': ' .. out)
  assert(out:find('python', 1, true) and out:find('rust', 1, true), out)
end)

case('install_sh_needs_terminal', function()
  local code, out = run_install({})
  assert(code == 2, 'exit ' .. code .. ': ' .. out)
  assert(out:find('Usage', 1, true), out)
end)

case('install_sh_python', function()
  local code, out = run_install({ 'python' })
  assert(code == 0, 'exit ' .. code .. ': ' .. out)
  assert(out:find('all tools are installed (basedpyright, ruff)', 1, true), out)
end)

case('install_sh_missing_prereq', function()
  -- A PATH with bash and nvim only: Go is missing, so the Go pick is skipped.
  local bin = root .. '/nogo-bin'
  vim.fn.mkdir(bin, 'p')
  for _, tool in ipairs({ 'bash', 'nvim' }) do vim.uv.fs_symlink(vim.fn.exepath(tool), bin .. '/' .. tool) end
  local code, out = run_install({ 'go' }, { env = { PATH = bin } })
  assert(code == 1, 'exit ' .. code .. ': ' .. out)
  assert(out:find('go not found', 1, true), out)
  assert(not out:find('InstallTools', 1, true), 'tried to install anyway: ' .. out)
end)

-- Drive the checklist in a real terminal (script(1)) by typing `keys`.
local function menu(keys)
  local r = vim.system({ 'script', '-qec', vim.fn.shellescape(install_sh), '/dev/null' },
    { stdin = keys }):wait(120000)
  return r.code, r.stdout or ''
end

case('install_sh_menu', function()
  local code, out = menu('\027[B \n') -- down to Go, tick it, Enter
  assert(code == 0, 'exit ' .. code .. ': ' .. out)
  assert(out:find('all tools are installed (gopls, delve)', 1, true), out)
end)

case('install_sh_menu_quit', function()
  local code, out = menu('q')
  assert(code == 0, 'exit ' .. code .. ': ' .. out)
  assert(not out:find('InstallTools', 1, true), 'installed something: ' .. out)
end)

-- Errors raised in callbacks outside a case's pcall land in :messages.
case('messages_clean', function()
  local messages = vim.fn.execute('messages')
  assert(not messages:find('E%d+:') and not messages:find('Error'), messages)
end)

vim.cmd(failed > 0 and 'cquit 1' or 'qall!')
