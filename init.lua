-- init.lua
-- Global Neovim config: VS Code's everyday features in any project, without the weight.
-- The Python practice tools (Viz panel, :Test, debugger memory picture) are in
-- lua/practice.lua. Design: docs/superpowers/specs/2026-11-13-nvim-ide-design.md.

vim.g.mapleader = ' '

vim.o.number = true
vim.o.relativenumber = true
vim.o.signcolumn = 'yes'
vim.o.clipboard = 'unnamedplus'
vim.o.ignorecase = true
vim.o.smartcase = true
vim.o.undofile = true
vim.o.completeopt = 'menuone,noselect,popup'
-- ponytail: indent widths come from each language's bundled ftplugin.

vim.diagnostic.config({ virtual_text = true, severity_sort = true })

-- Every plugin in one add, so a fresh machine installs them all from the lockfile with
-- no prompt. practice.lua's own add of the debugger plugins then does nothing.
vim.pack.add({
  'https://github.com/folke/snacks.nvim',
  'https://github.com/nvim-mini/mini.nvim',
  'https://github.com/mason-org/mason.nvim',
  'https://github.com/mfussenegger/nvim-dap',
  'https://github.com/mfussenegger/nvim-dap-python',
  'https://github.com/nvim-neotest/nvim-nio',
  'https://github.com/rcarriga/nvim-dap-ui',
}, { confirm = false })

-- Auto-close brackets and quotes; typing the closer steps over it.
require('mini.pairs').setup()
-- A third `"` after `""` is inserted as-is, so `"""` docstrings leave no stray quote.
vim.keymap.set('i', '"', function()
  local line, col = vim.api.nvim_get_current_line(), vim.fn.col('.')
  if line:sub(col - 2, col - 1) == '""' and line:sub(col, col) ~= '"' then return '"' end
  return MiniPairs.closeopen('""', '^[^\\]')
end, { expr = true, replace_keycodes = false, desc = 'Pair quotes, allow """' })

-- Mason installs servers and debug adapters per machine and puts its bin first on PATH.
require('mason').setup()
-- rust-analyzer is not here: rustup's component matches the installed toolchain.
local tools = { 'clangd', 'gopls', 'vtsls', 'codelldb', 'delve', 'basedpyright', 'ruff' }
vim.api.nvim_create_user_command('InstallTools', function()
  local registry = require('mason-registry')
  registry.refresh(function()
    for _, name in ipairs(tools) do
      local pkg = registry.get_package(name)
      if not pkg:is_installed() then
        vim.notify('Installing ' .. name)
        pkg:install()
      end
    end
  end)
end, { desc = 'Install missing language servers and debug adapters' })

-- Language servers. Each block: how to start it, which files, how to find the project root.
vim.lsp.config('basedpyright', {
  cmd = { 'basedpyright-langserver', '--stdio' },
  filetypes = { 'python' },
  root_markers = { 'pyproject.toml', 'setup.py', '.git' },
  settings = { basedpyright = { analysis = { typeCheckingMode = 'standard' } } },
})
vim.lsp.config('ruff', {
  cmd = { 'ruff', 'server' },
  filetypes = { 'python' },
  root_markers = { 'pyproject.toml', 'ruff.toml', '.git' },
  -- Match basedpyright (utf-16 only) so both servers agree on column positions.
  capabilities = { general = { positionEncodings = { 'utf-16' } } },
})
vim.lsp.config('rust_analyzer', {
  cmd = { 'rust-analyzer' },
  filetypes = { 'rust' },
  root_markers = { 'Cargo.toml', '.git' },
})
vim.lsp.config('clangd', {
  cmd = { 'clangd' },
  filetypes = { 'c', 'cpp' },
  root_markers = { 'compile_commands.json', '.clangd', '.git' },
})
vim.lsp.config('gopls', {
  cmd = { 'gopls' },
  filetypes = { 'go', 'gomod' },
  root_markers = { 'go.mod', '.git' },
})
vim.lsp.config('vtsls', {
  cmd = { 'vtsls', '--stdio' },
  filetypes = { 'javascript', 'javascriptreact', 'typescript', 'typescriptreact' },
  root_markers = { 'tsconfig.json', 'package.json', '.git' },
})
vim.lsp.enable({ 'basedpyright', 'ruff', 'rust_analyzer', 'clangd', 'gopls', 'vtsls' })

-- Servers whose formatter runs on save: languages with one standard style. C, C++, JS and
-- TS have none, so saving would reformat other people's code; Space c f formats on demand.
local format_on_save = { ruff = true, rust_analyzer = true, gopls = true }

vim.api.nvim_create_autocmd('LspAttach', {
  callback = function(args)
    local client = assert(vim.lsp.get_client_by_id(args.data.client_id))

    if client:supports_method('textDocument/completion') then
      -- Servers trigger on '.' and the like, so add identifier chars to pop up while
      -- typing. One client serves every buffer, so extend only on first attach.
      local chars = client.server_capabilities.completionProvider.triggerCharacters or {}
      if not vim.tbl_contains(chars, 'a') then
        for c in ('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_'):gmatch('.') do
          table.insert(chars, c)
        end
      end
      client.server_capabilities.completionProvider.triggerCharacters = chars
      vim.lsp.completion.enable(true, client.id, args.buf, { autotrigger = true })
    end

    if format_on_save[client.name] then
      vim.api.nvim_create_autocmd('BufWritePre', {
        buffer = args.buf,
        callback = function() vim.lsp.buf.format({ bufnr = args.buf, id = client.id }) end,
      })
    end
  end,
})

vim.keymap.set('n', 'gd', vim.lsp.buf.definition, { desc = 'Go to definition' })
vim.keymap.set('n', '<leader>cf', function() vim.lsp.buf.format() end, { desc = 'Format file' })

local practice = require('practice')
local dap = require('dap')

-- F5: run the current file in the bottom panel.
local function run_file()
  if vim.b.python_run then vim.cmd.wincmd('p') end -- pressed from the run panel
  local ft = vim.bo.filetype
  if ft == 'python' then return practice.run_python() end
  vim.notify('F5: no runner for ' .. ft)
end

-- F6: start debugging the current file, or continue a paused session.
local function debug_file()
  if dap.session() then return dap.continue() end -- from any window, panels included
  local ft = vim.bo.filetype
  if ft == 'python' then return practice.debug_python() end
  vim.notify('F6: no debugger for ' .. ft)
end

vim.keymap.set('n', '<leader>r', run_file, { desc = 'Run current file' })
-- F5 also works from Insert mode (where <Space>r would just type " r") and from a
-- selected :Test placeholder.
vim.keymap.set({ 'n', 'i', 's' }, '<F5>', run_file, { desc = 'Run current file' })
vim.keymap.set({ 'n', 'i', 't' }, '<F6>', debug_file, { desc = 'Debug: start / continue' })
