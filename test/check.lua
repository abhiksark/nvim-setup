-- test/check.lua
-- Headless checks for this config. Run through test/check.sh, which also checks the
-- startup budget. Prints PASS/FAIL per case; exits 1 if any case failed.
-- Sample files go in Neovim's own temp folder, never in a real repo.

local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')
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

local function case(name, fn)
  vim.cmd('silent! only | silent! %bwipeout!')
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
  vim.cmd('silent! only | silent! %bwipeout!')
  sample(spaced .. 'err/a.c', 'int main(void) { return 1 }\n')
  local out = run_output(path, 60000)
  assert(out:find('error', 1, true), out)
  assert(not out:find('old-output', 1, true), 'ran the old binary: ' .. out)
end)

case('same_name', function()
  local x = sample('x/main.c', '#include <stdio.h>\nint main(void) { puts("from-x"); }\n')
  local y = sample('y/main.c', '#include <stdio.h>\nint main(void) { puts("from-y"); }\n')
  for _, step in ipairs({ { x, 'from-x' }, { y, 'from-y' }, { x, 'from-x' } }) do
    vim.cmd('silent! only | silent! %bwipeout!')
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

-- Errors raised in callbacks outside a case's pcall land in :messages.
case('messages_clean', function()
  local messages = vim.fn.execute('messages')
  assert(not messages:find('E%d+:') and not messages:find('Error'), messages)
end)

vim.cmd(failed > 0 and 'cquit 1' or 'qall!')
