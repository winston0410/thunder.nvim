-- TODO Use vim.pos to improve code quality https://github.com/neovim/neovim/issues/25509
local M = {}
local THUNDER_NS = vim.api.nvim_create_namespace('thunder')
local _unused_labels = ''

---@class Thunder.Config
local default_opts = {
  labels = 'qwertyuiop[asdfghjkl;zxcvbnm,.',
  label = {
    before = true,
    after = false,
    uppercase = true,
    style = 'inline',
  },
  highlight = {
    priority = 5000,
  }
}

---@type Thunder.Config
M.options = {}

local function is_search()
  local t = vim.fn.getcmdtype()
  return t == '/' or t == '?'
end

---@return string An unused label from the label pool
local function get_next_label()
  local next = _unused_labels:sub(1, 1)
  _unused_labels = _unused_labels:sub(2)
  return next
end

M.setup = function(opts)
  M.options = vim.tbl_deep_extend('force', {}, default_opts, opts or {})
  _unused_labels = M.options.labels

  local links = {
    FlashBackdrop = 'Comment',
    FlashMatch = 'Search',
    FlashCurrent = 'IncSearch',
    FlashLabel = 'Substitute',
    FlashPrompt = 'MsgArea',
    FlashPromptIcon = 'Special',
    FlashCursor = 'Cursor',
  }
  for hl_group, link in pairs(links) do
    vim.api.nvim_set_hl(0, hl_group, { link = link, default = true })
  end

  local group = vim.api.nvim_create_augroup('thunder', { clear = true })
  vim.api.nvim_create_autocmd('CmdlineChanged', {
    group = group,
    callback = function()
      if not is_search() then
        return
      end
      -- M.reset()
      -- M.update()
    end,
  })

  vim.api.nvim_create_autocmd('CmdlineLeave', {
    group = group,
    callback = function()
      if vim.v.event.abort then
        return
      end
      if not is_search() then
        return
      end
      M.update()
        vim.on_key(function (key)
            print("key found", key)
        end)
    end,
  })
  vim.api.nvim_create_autocmd('CmdlineEnter', {
    group = group,
    callback = function()
      if not is_search() then
        return
      end
      M.reset()
    end,
  })
end

---@param pattern string
local function get_all_matches(pattern)
  local win = vim.api.nvim_get_current_win()
  local view = vim.api.nvim_win_call(win, vim.fn.winsaveview)
  -- start searching
  vim.api.nvim_win_set_cursor(win, { 1, 0 })
  local results = {}
  local next = vim.fn.searchpos(pattern, 'cW')
  while not (next[1] == 0 and next[2] == 0) do
    table.insert(results, next)
    next = vim.fn.searchpos(pattern, 'W')
  end
  vim.api.nvim_win_call(win, function()
    vim.fn.winrestview(view)
  end)
  local info = vim.fn.getwininfo(win)[1]
  local visible_result = vim
    .iter(results)
    :filter(function(item)
      return item[1] >= info.topline and item[1] <= info.botline
    end)
    :totable()
  return visible_result
end

M.update = function()
  local pattern = vim.fn.getcmdline()
  -- REF https://github.com/folke/flash.nvim/blob/fcea7ff883235d9024dc41e638f164a450c14ca2/lua/flash/plugins/search.lua#L51
  if pattern:sub(1, 1) == vim.fn.getcmdtype() then
    pattern = vim.fn.getreg('/') .. pattern:sub(2)
  end
  local matches = get_all_matches(pattern)
  for _, match in ipairs(matches) do
    local label = get_next_label()
    if label == '' then
      break
    end
    local row = match[1] - 1
    local col = match[2] - 1
    vim.api.nvim_buf_set_extmark(0, THUNDER_NS, row, col, {
      priority = M.options.highlight.priority,
      virt_text = { { label, 'FlashLabel' } },
      virt_text_pos = M.options.label.style,
      end_col = col - 1,
      strict = false,
    })
  end
end

M.reset = function()
  vim.api.nvim_buf_clear_namespace(0, THUNDER_NS, 0, -1)
  _unused_labels = M.options.labels
end

return M
