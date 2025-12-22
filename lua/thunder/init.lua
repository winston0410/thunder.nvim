local M = {}
local THUNDER_NS = vim.api.nvim_create_namespace('thunder')
local ESC_KEY = vim.api.nvim_replace_termcodes('<esc>', true, true, true)
local THUNDER_JUMP_POST_EVENT = 'ThunderJumpPost'
local available_labels = {}

---@class Thunder.Config
local default_opts = {
  label = {
    chars = 'qwertyuiop[asdfghjkl;zxcvbnm,.',
    style = 'overlay',
    uppercase = true,
  },
  highlight = {
    base_priority = 5000,
    label = 'FlashLabel',
  },
  jump = {
    jumplist = true,
    open_fold = true,
  },
  prompt = {
    enabled = true,
    message = '🔦 Pick a target or press <ESC> to end the jump:',
  },
}

---@type Thunder.Config
M.options = {}

---@return string[]
local function generate_unused_labels()
  local uppercase_chars = {}
  if M.options.label.uppercase then
    uppercase_chars = vim.split(M.options.label.chars:upper(), '')
  end
  local result =
    vim.list.unique(vim.list_extend(vim.split(M.options.label.chars, ''), uppercase_chars))
  return result
end

---@return string The input from the user
local function get_user_input()
  vim.cmd.redraw()
  local ok, ret = pcall(vim.fn.getcharstr)
  if not ok or ret == ESC_KEY then
    return ""
  end
  return ret
end

---@param win integer
---@param cursor_pos vim.Pos
local function jump(win, cursor_pos)
    -- NOTE run cursor setting in next event loop, as the cursor setting for search result will happen in this loop, and we cannot stop it
    vim.schedule(function()
    if M.options.jump.jumplist then
      vim.cmd('normal! m`')
    end
    vim.api.nvim_win_set_cursor(win, cursor_pos)
    vim.api.nvim_exec_autocmds('User', {
      pattern = THUNDER_JUMP_POST_EVENT,
    })
    end)
end
---@param current integer current item index
---@param total integer total item in the match
---@return integer
local function get_label_idx(current, total)
    local result = current % total
    if result == 0 then
        result = current
    end
    return result
end
M.setup = function(opts)
  M.options = vim.tbl_deep_extend('force', {}, default_opts, opts or {})

  local links = {
    [M.options.highlight.label] = 'Substitute',
  }
  for hl_group, link in pairs(links) do
    vim.api.nvim_set_hl(0, hl_group, { link = link, default = true })
  end
  available_labels = generate_unused_labels()
end

---@param win integer
---@param pattern string
local function get_all_matches(win, pattern)
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

M.search = function()
  local label_pos = {}
  local win = vim.api.nvim_get_current_win()
  local pattern = vim.fn.getcmdline()
  -- REF https://github.com/folke/flash.nvim/blob/fcea7ff883235d9024dc41e638f164a450c14ca2/lua/flash/plugins/search.lua#L51
  if pattern:sub(1, 1) == vim.fn.getcmdtype() then
    pattern = vim.fn.getreg('/') .. pattern:sub(2)
  end
  local matches = get_all_matches(win, pattern)
  if #matches == 1 then
    return
  end
  
  for i, match in ipairs(matches) do
    local label_idx = get_label_idx( i, #matches)
    local label = available_labels[label_idx]
    if label == '' then
      break
    end
    local pos = vim.pos(match[1] - 1, match[2] - 1)

    label_pos[label] = pos:to_cursor()
    local extmark_pos = pos:to_extmark()
    vim.api.nvim_buf_set_extmark(0, THUNDER_NS, extmark_pos[1], extmark_pos[2], {
      priority = M.options.highlight.base_priority,
      virt_text = { { label, M.options.highlight.label } },
      virt_text_pos = M.options.label.style,
      strict = true,
    })
  end
  if M.options.prompt.enabled then
    vim.api.nvim_echo({ { M.options.prompt.message } }, false, {})
  end
  local ret = get_user_input()
  vim.api.nvim_buf_clear_namespace(0, THUNDER_NS, 0, -1)
  local cursor_pos = label_pos[ret]
  if cursor_pos == nil then
    return
  end
  jump(win, cursor_pos)
end

return M
