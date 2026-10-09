-- Account completion in bank_workflow.py's TSV drafts only.
local header = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ''
if not header:match('^action\tdate\tdescription\tamount\tcurrency\tbank_account\tcounter_account\t') then return end

local columns = {}
local index = 0
for name in (header .. '\t'):gmatch('(.-)\t') do
  index = index + 1
  columns[name] = index
end

local accounts
local function load_accounts()
  if accounts then return accounts end
  accounts = {}
  local binary = vim.fn.exepath('hledger')
  if binary == '' and vim.fn.executable('/opt/homebrew/bin/hledger') == 1 then binary = '/opt/homebrew/bin/hledger' end
  if binary == '' then return accounts end
  local cmd = { binary }
  local journal = vim.g.bank_import_ledger or vim.env.LEDGER_FILE
  if not journal or journal == '' then
    local candidate = vim.fn.expand('~/Ledger/main_2025.ledger')
    if vim.fn.filereadable(candidate) == 1 then journal = candidate end
  end
  if journal and journal ~= '' then vim.list_extend(cmd, { '-f', vim.fn.expand(journal) }) end
  table.insert(cmd, 'accounts')
  local result = vim.system(cmd, { text = true }):wait()
  if result.code ~= 0 then
    vim.notify('hledger accounts: ' .. vim.trim(result.stderr or ''), vim.log.levels.WARN)
    return accounts
  end
  for name in (result.stdout or ''):gmatch('[^\r\n]+') do
    name = vim.trim(name)
    if name ~= '' then table.insert(accounts, name) end
  end
  return accounts
end

function _G.BankDraftComplete(findstart, base)
  local line = vim.api.nvim_get_current_line()
  local column = vim.api.nvim_win_get_cursor(0)[2]
  local prefix = line:sub(1, column)
  local field = 1
  for _ in prefix:gmatch('\t') do field = field + 1 end
  if field ~= columns.bank_account and field ~= columns.counter_account then
    return findstart == 1 and -1 or {}
  end
  if findstart == 1 then
    local last_tab = prefix:match('.*()\t')
    return last_tab or 0 -- zero-based byte index of first character in the field
  end
  local matches = {}
  for _, name in ipairs(load_accounts()) do
    if name:sub(1, #base):lower() == base:lower() then table.insert(matches, name) end
  end
  return matches
end

vim.bo.omnifunc = 'v:lua.BankDraftComplete'
vim.keymap.set('i', '<C-Space>', '<C-x><C-o>', { buffer = 0, desc = 'Suggest hledger accounts' })
