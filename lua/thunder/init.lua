local M = {}
local THUNDER_NS = vim.api.nvim_create_namespace('thunder')
local ESC_KEY = vim.api.nvim_replace_termcodes("<esc>", true, true, true)
local unused_labels = ''
local label_pos = {}

---@class Thunder.Config
local default_opts = {
  labels = 'qwertyuiop[asdfghjkl;zxcvbnm,.',
  label = {
    before = true,
    after = false,
    uppercase = true,
    style = 'overlay',
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
  local next = unused_labels:sub(1, 1)
  unused_labels = unused_labels:sub(2)
  return next
end

M.setup = function(opts)
  M.options = vim.tbl_deep_extend('force', {}, default_opts, opts or {})
  unused_labels = M.options.labels

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
  local win = vim.api.nvim_get_current_win()
  local pattern = vim.fn.getcmdline()
  -- REF https://github.com/folke/flash.nvim/blob/fcea7ff883235d9024dc41e638f164a450c14ca2/lua/flash/plugins/search.lua#L51
  if pattern:sub(1, 1) == vim.fn.getcmdtype() then
    pattern = vim.fn.getreg('/') .. pattern:sub(2)
  end
  local matches = get_all_matches(pattern)
  if #matches == 1 then
      return
  end
  for _, match in ipairs(matches) do
    local label = get_next_label()
    if label == '' then
      break
    end
    local pos = vim.pos(match[1] - 1, match[2] - 1)

    label_pos[label] = pos:to_cursor()
    local extmark_pos = pos:to_extmark()
    vim.api.nvim_buf_set_extmark(0, THUNDER_NS, extmark_pos[1], extmark_pos[2], {
      priority = M.options.highlight.priority,
      virt_text = { { label, 'FlashLabel' } },
      virt_text_pos = M.options.label.style,
      strict = true
    })
  end
  vim.cmd.redraw()
  local ok, ret = pcall(vim.fn.getcharstr)
  if not ok or ret == ESC_KEY then
      vim.api.nvim_buf_clear_namespace(0, THUNDER_NS, 0, -1)
      return
  end
  local cursor_pos = label_pos[ret]
  vim.api.nvim_buf_clear_namespace(0, THUNDER_NS, 0, -1)
  if cursor_pos == nil then
      return
  end
  -- NOTE run cursor setting in next event loop, as the cursor setting for search result will happen in this loop, and we cannot stop it
  vim.schedule(function()
      vim.api.nvim_win_set_cursor(win, cursor_pos)
  end)
end

M.reset = function()
  unused_labels = M.options.labels
  label_pos = {}
end

return M
