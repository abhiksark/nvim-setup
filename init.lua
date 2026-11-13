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

-- File tree and pickers: only these two snacks modules are on. Inside the tree, snacks
-- maps Ctrl+B to scrolling; map it to close so Ctrl+B toggles from anywhere.
require('snacks').setup({
  explorer = { enabled = true },
  picker = {
    enabled = true,
    sources = {
      explorer = {
        win = {
          list = { keys = { ['<c-b>'] = 'close' } },
          input = { keys = { ['<c-b>'] = { 'close', mode = { 'n', 'i' } } } },
        },
      },
    },
  },
})

-- Ctrl+B and Space e show or hide the tree as a left column.
local function toggle_tree()
  local tree = Snacks.picker.get({ source = 'explorer' })[1]
  if tree then tree:close() else Snacks.explorer() end
end

vim.keymap.set('n', '<C-p>', function() Snacks.picker.files() end, { desc = 'Find file' })
vim.keymap.set('n', '<leader>ff', function() Snacks.picker.files() end, { desc = 'Find file' })
vim.keymap.set('n', '<leader>fr', function() Snacks.picker.recent() end, { desc = 'Recent files' })
vim.keymap.set('n', '<leader>/', function() Snacks.picker.grep() end, { desc = 'Search in project' })
vim.keymap.set('n', '<C-b>', toggle_tree, { desc = 'Toggle file tree' })
vim.keymap.set('n', '<leader>e', toggle_tree, { desc = 'Toggle file tree' })
vim.keymap.set('n', '<leader>xx', function()
  Snacks.picker.diagnostics({ layout = { preset = 'ivy_split' } })
end, { desc = 'Error list' })

-- Icons need a Nerd Font; kitty has its symbols built in. Elsewhere, plain ASCII unless
-- vim.g.nerd_font = true is set before this file runs.
if vim.g.nerd_font == nil then vim.g.nerd_font = vim.env.KITTY_WINDOW_ID ~= nil end
require('mini.icons').setup({ style = vim.g.nerd_font and 'glyph' or 'ascii' })
-- Git changes as bars in the sign column (the default colors line numbers instead).
require('mini.diff').setup({ view = { style = 'sign', signs = { add = '▎', change = '▎', delete = '▁' } } })
require('mini.git').setup() -- branch name for the status line
require('mini.statusline').setup()

-- Hints for what can follow Space, g, [ and ].
local clue = require('mini.clue')
clue.setup({
  triggers = {
    { mode = 'n', keys = '<Leader>' },
    { mode = 'x', keys = '<Leader>' },
    { mode = 'n', keys = 'g' },
    { mode = 'x', keys = 'g' },
    { mode = 'n', keys = '[' },
    { mode = 'n', keys = ']' },
  },
  clues = {
    { mode = 'n', keys = '<Leader>f', desc = '+find' },
    { mode = 'n', keys = '<Leader>c', desc = '+code' },
    { mode = 'n', keys = '<Leader>x', desc = '+errors' },
    clue.gen_clues.g(),
  },
})

local practice = require('practice')
local dap = require('dap')

-- Run `cmd` in the bottom panel, the way practice.run_python does: each run replaces the
-- last, you can type into it for input, and q closes it. The shared python_run flag lets
-- both kinds of run replace each other and count as panels.
local function run_in_panel(cmd, cwd)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.b[vim.api.nvim_win_get_buf(win)].python_run then vim.api.nvim_win_close(win, true) end
  end
  vim.cmd('botright 12new')
  vim.b.python_run = true
  vim.bo.bufhidden = 'wipe'
  vim.fn.jobstart(cmd, { term = true, cwd = cwd })
  vim.keymap.set('n', 'q', '<cmd>close<cr>', { buffer = true, desc = 'Close run output' })
  vim.cmd.startinsert()
end

-- Compiled binaries live here, one per source file (named by a hash of its full path), so
-- two main.c files in different folders never share one and none land beside the source.
local run_cache = vim.fn.expand('~/.cache/nvim-run')
local compilers = {
  c = { 'cc', '-g', '-O0', '-Wall' },
  cpp = { 'c++', '-std=c++20', '-g', '-O0', '-Wall' },
  rust = { 'rustc', '-g' },
}

-- The compiler command for a single C, C++ or Rust file, and the binary it writes.
local function compile_argv(path, ft)
  local bin = ('%s/%s-%s'):format(run_cache, vim.fn.fnamemodify(path, ':t:r'), vim.fn.sha256(path):sub(1, 8))
  return vim.list_extend(vim.deepcopy(compilers[ft]), { path, '-o', bin }), bin
end

-- The command and folder that run `path`, or nil and the reason it can't be run.
local function runner_for(path, ft)
  local dir = vim.fs.dirname(path)
  if ft == 'rust' and vim.fs.root(path, 'Cargo.toml') then
    return { 'cargo', 'run' }, vim.fs.root(path, 'Cargo.toml')
  end
  if compilers[ft] then
    local argv, bin = compile_argv(path, ft)
    local compile = table.concat(vim.tbl_map(vim.fn.shellescape, argv), ' ')
    -- Delete the last binary first, so a failed compile can't run it.
    local script = ('mkdir -p %s && rm -f %s && %s && exec %s'):format(
      vim.fn.shellescape(run_cache), vim.fn.shellescape(bin), compile, vim.fn.shellescape(bin))
    return { 'sh', '-c', script }, dir
  end
  if ft == 'go' then return { 'go', 'run', vim.fs.root(path, 'go.mod') and '.' or path }, dir end
  if ft == 'javascript' or ft == 'typescript' then return { 'node', path }, dir end
  if ft == 'typescriptreact' then return nil, 'TSX needs a bundler; F5 does not run it' end
  return nil, 'F5: no runner for ' .. ft
end

-- A file that F5 and F6 can act on: not a panel, the tree or a scratch buffer.
local function in_code_file()
  return not practice.is_panel(vim.api.nvim_get_current_win()) and vim.bo.buftype == ''
    and vim.api.nvim_buf_get_name(0) ~= ''
end

-- F5: run the current file in the bottom panel.
local function run_file()
  if vim.b.python_run then vim.cmd.wincmd('p') end -- pressed from the run panel
  if not in_code_file() then return vim.notify('F5: open a code file first') end
  local ft = vim.bo.filetype
  if ft == 'python' then return practice.run_python() end
  local cmd, cwd = runner_for(vim.api.nvim_buf_get_name(0), ft)
  if not cmd then return vim.notify(cwd) end
  vim.cmd('stopinsert | silent write')
  run_in_panel(cmd, cwd)
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
