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
    uppercase = false,
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
  if M.options.prompt.enabled then
    -- https://github.com/nvim-mini/mini.jump2d/blob/7a089cb719adb7c2faa2a859038d69d58fcbee84/lua/mini/jump2d.lua#L1105C59-L1105C72
    vim.cmd([[echo '' | redraw]])
    vim.api.nvim_echo({ { M.options.prompt.message } }, false, {})
  end
  local ok, ret = pcall(vim.fn.getcharstr)
  if not ok or ret == ESC_KEY then
    return ''
  end
  vim.cmd([[echo '' | redraw]])
  return ret
end

---@param win integer
---@param cursor_pos vim.Pos
local function jump(win, cursor_pos)
  if M.options.jump.jumplist then
    vim.cmd('normal! m`')
  end
  vim.api.nvim_win_set_cursor(win, cursor_pos:to_cursor())
  vim.api.nvim_exec_autocmds('User', {
    pattern = THUNDER_JUMP_POST_EVENT,
  })
end
---@param current integer current item index
---@param total integer total label count
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

---@param label string Label for the extmark
---@param pos vim.Pos Position for the extmark
local function set_label(label, pos)
      local extmark_pos = pos:to_extmark()
      vim.api.nvim_buf_set_extmark(0, THUNDER_NS, extmark_pos[1], extmark_pos[2], {
        priority = M.options.highlight.base_priority,
        virt_text = { { label, M.options.highlight.label } },
        virt_text_pos = M.options.label.style,
        strict = true,
      })
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

  -- NOTE run all the labelling in the next event loop, so the highlight and cursor position of search can be placed correctly
  vim.schedule(function()
    for i, match in ipairs(matches) do
      local label_idx = get_label_idx(i, #available_labels)
      local round = math.ceil(i / #available_labels)
      local label = available_labels[label_idx]
      local pos = vim.pos(match[1] - 1, match[2] - 1)

      if label_pos[label] == nil then
        label_pos[label] = pos
      else
        local adjusted_label = available_labels[round]
        local current_value = label_pos[label]
        -- check if the current is pos or not
        if getmetatable(current_value) == vim.pos then
          local first_label = available_labels[1]
          label_pos[label] = {
            [first_label] = current_value,
          }
        end
        label_pos[label][adjusted_label] = pos
      end
      set_label(label, pos)
    end
    local target_dict = label_pos

    while true do
        local ret = get_user_input()
        vim.api.nvim_buf_clear_namespace(0, THUNDER_NS, 0, -1)
        local value = target_dict[ret]
        if value == nil then
            return
        end
        if getmetatable(value) == vim.pos then
            jump(win, value)
            return
        end
        for label, pos in pairs(value) do
          set_label(label,pos)
        end
        target_dict = value
    end
  end)
end

return M
