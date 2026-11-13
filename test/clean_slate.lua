-- test/clean_slate.lua
-- Run by `test/check.sh --clean-slate` with an empty XDG_DATA_HOME, as on a new machine:
-- plugins install from the lockfile at startup, then :InstallTools installs every tool.
-- Prints PASS or the failures; exits 1 on failure.

local failures = {}

local plugins = #vim.pack.get()
if plugins ~= 7 then table.insert(failures, 'plugins installed: ' .. plugins .. ' of 7') end

vim.cmd('InstallTools')
local registry = require('mason-registry')
local names = { 'clangd', 'gopls', 'vtsls', 'codelldb', 'delve', 'basedpyright', 'ruff' }
local function all_installed()
  for _, name in ipairs(names) do
    local ok, pkg = pcall(registry.get_package, name) -- errors until the registry loads
    if not ok or pkg:is_installing() or not pkg:is_installed() then return false end
  end
  return true
end
if not vim.wait(600000, all_installed, 1000) then
  table.insert(failures, 'tools not installed within 600 s')
end
for _, bin in ipairs({ 'clangd', 'gopls', 'vtsls', 'codelldb', 'dlv', 'basedpyright-langserver', 'ruff' }) do
  local path = vim.fn.stdpath('data') .. '/mason/bin/' .. bin
  if vim.fn.executable(path) ~= 1 then table.insert(failures, 'missing ' .. path) end
end

local messages = vim.fn.execute('messages')
if messages:find('E%d+:') or messages:find('Error') then table.insert(failures, 'messages: ' .. messages) end

io.write(#failures == 0 and 'PASS clean_slate\n' or ('FAIL clean_slate: ' .. table.concat(failures, '; ') .. '\n'))
vim.cmd(#failures > 0 and 'cquit 1' or 'qall!')
