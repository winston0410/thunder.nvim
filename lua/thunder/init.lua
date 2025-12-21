local M = {}
local THUNDER_NS = vim.api.nvim_create_namespace("thunder")

---@class Thunder.Config
local default_opts = {
    labels = "qwertyuiop[asdfghjkl;zxcvbnm,.",
    label = {
        before = true,
        after = false,
        uppercase = true,
    },
}

local function is_search()
    local t = vim.fn.getcmdtype()
    return t == "/" or t == "?"
end

M.setup = function(opts)
    M.options = vim.tbl_deep_extend("force", {}, default_opts, opts or {})

    local group = vim.api.nvim_create_augroup("thunder", { clear = true })
    vim.api.nvim_create_autocmd("CmdlineChanged", {
        group = group,
        callback = function()
            if not is_search() then
                return
            end
            M.update()
        end,
    })

    vim.api.nvim_create_autocmd("CmdlineLeave", {
        group = group,
        callback = function()
            if vim.v.event.abort then
                return
            end
            if not is_search() then
                return
            end
            print("completed search")
        end,
    })
    vim.api.nvim_create_autocmd("CmdlineEnter", {
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
    local results = {}
    local next = vim.fn.searchpos(pattern, "cW")
    while not (next[1] == 0 and next[2] == 0) do
        table.insert(results, next)
        next = vim.fn.searchpos(pattern, "W")
    end
    local win = vim.api.nvim_get_current_win()
    local info = vim.fn.getwininfo(win)[1]
    local visible_result = vim.iter(results):filter(function (item)
        return item[1] >= info.topline and item[1] <= info.botline
    end):totable()
    return visible_result
end

M.update = function()
    local pattern = vim.fn.getcmdline()
    -- when doing // or ??, get the pattern from the search register
    -- See :h search-commands
    if pattern:sub(1, 1) == vim.fn.getcmdtype() then
        pattern = vim.fn.getreg("/") .. pattern:sub(2)
    end
    local matches = get_all_matches(pattern)
    print("matches", vim.inspect(matches))
end

M.reset = function()
    vim.api.nvim_buf_clear_namespace(0, THUNDER_NS, 0, -1)
end

return M
