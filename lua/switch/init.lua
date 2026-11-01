---switch.nvim - cycle through groups of keywords in Neovim.
local M = {}

local core = require("switch.core")

---@class SwitchConfig
---@field keywords string[][] Groups of keywords. Each group is cycled independently.
---@field keymap string|false Key that performs the switch. Set to false to disable.
---@field scope "line"|"buffer"|"cursor" Where to look for keywords.
---@field ignore_case boolean Match keywords case-insensitively.
---@field preserve_case boolean Keep the matched text's casing when ignore_case is on.
---@field notify boolean Show a message when nothing was replaced.
---@field command boolean Create the `:Switch` user command.

---@type SwitchConfig
local defaults = {
  keywords = {},
  keymap = "<leader>sw",
  scope = "line",
  ignore_case = false,
  preserve_case = false,
  notify = false,
  command = true,
}

---@type SwitchConfig
local config = vim.deepcopy(defaults)

local created_keymap
local created_command = false
local has_setup = false

local scopes = {
  line = true,
  buffer = true,
  cursor = true,
}

---@param keywords any
local function validate_keywords(keywords)
  if type(keywords) ~= "table" then
    error("switch.nvim: `keywords` must be an array of keyword groups (string[][])")
  end

  local seen = {}
  for group_index, group in ipairs(keywords) do
    if type(group) ~= "table" then
      error(("switch.nvim: keyword group #%d must be an array of strings"):format(group_index))
    end
    if #group == 0 then
      error(("switch.nvim: keyword group #%d must not be empty"):format(group_index))
    end

    for keyword_index, keyword in ipairs(group) do
      if type(keyword) ~= "string" then
        error(("switch.nvim: keyword #%d in group #%d must be a string"):format(keyword_index, group_index))
      end
      if keyword == "" then
        error(("switch.nvim: keyword #%d in group #%d must not be empty"):format(keyword_index, group_index))
      end
      if seen[keyword] then
        error(("switch.nvim: duplicate keyword %q (already in group #%d)"):format(keyword, seen[keyword]))
      end
      seen[keyword] = group_index
    end
  end
end

---@param scope string
---@return "line"|"buffer"|"cursor"
local function validate_scope(scope)
  if not scopes[scope] then
    error(('switch.nvim: `scope` must be "line", "buffer" or "cursor", got %q'):format(tostring(scope)))
  end
  return scope
end

---@param opts table
local function validate_options(opts)
  validate_keywords(opts.keywords)

  if opts.keymap ~= false and type(opts.keymap) ~= "string" then
    error("switch.nvim: `keymap` must be a string or false")
  end

  validate_scope(opts.scope)

  for _, option in ipairs({ "ignore_case", "preserve_case", "notify", "command" }) do
    if type(opts[option]) ~= "boolean" then
      error(("switch.nvim: `%s` must be a boolean"):format(option))
    end
  end
end

---@param count integer
---@param groups string[][]
local function notify_if_enabled(count, groups)
  if count > 0 or not config.notify then
    return
  end

  if #groups == 0 then
    vim.notify("switch.nvim: no keywords configured", vim.log.levels.INFO)
  else
    vim.notify("switch.nvim: no keyword found", vim.log.levels.INFO)
  end
end

---@param lines string[]
---@param row integer 0-based row
---@param opts table
---@return integer replacements
local function replace_lines(lines, row, opts)
  local new_lines, replacements = core.replace(lines, opts.keywords, opts)
  if replacements > 0 then
    vim.api.nvim_buf_set_lines(0, row, row + #lines, false, new_lines)
  end
  return replacements
end

---@param value any
---@param fallback any
---@return any
local function with_default(value, fallback)
  if value == nil then
    return fallback
  end
  return value
end

---Switch the keywords in the current scope.
---
---This is the public API used by the mapping and the `:Switch` command. It can
---also be called manually, for example:
---
---```lua
---require("switch").switch({ scope = "buffer" })
---```
---
---@param opts? { scope?: "line"|"buffer"|"cursor", keywords?: string[][], ignore_case?: boolean, preserve_case?: boolean }
---@return integer replacements
function M.switch(opts)
  opts = opts or {}

  local groups = opts.keywords or config.keywords
  validate_keywords(groups)

  local scope = validate_scope(opts.scope or config.scope)
  local replace_opts = {
    keywords = groups,
    ignore_case = with_default(opts.ignore_case, config.ignore_case),
    preserve_case = with_default(opts.preserve_case, config.preserve_case),
  }

  local replacements = 0

  if scope == "buffer" then
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    replacements = replace_lines(lines, 0, replace_opts)
  elseif scope == "line" then
    local row = vim.api.nvim_win_get_cursor(0)[1] - 1
    replacements = replace_lines({ vim.api.nvim_buf_get_lines(0, row, row + 1, false)[1] }, row, replace_opts)
  else -- cursor
    local cursor = vim.api.nvim_win_get_cursor(0)
    local row = cursor[1] - 1
    local line = vim.api.nvim_buf_get_lines(0, row, row + 1, false)[1]

    -- `nvim_win_get_cursor` uses a 0-based column. The core matcher expects a
    -- 1-based byte column.
    replace_opts.only_covering_col = cursor[2] + 1
    replacements = replace_lines({ line }, row, replace_opts)
  end

  if replacements > 0 then
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = vim.api.nvim_buf_get_lines(0, cursor[1] - 1, cursor[1], false)[1] or ""
    vim.api.nvim_win_set_cursor(0, { cursor[1], math.min(cursor[2], math.max(#line - 1, 0)) })
  else
    notify_if_enabled(replacements, groups)
  end

  return replacements
end

---Return a copy of the current configuration.
---@return SwitchConfig
function M.get_config()
  return vim.deepcopy(config)
end

---Set up switch.nvim. Safe to call more than once.
---@param opts? SwitchConfig
---@return table
function M.setup(opts)
  opts = opts or {}

  local merged = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts)
  validate_options(merged)
  config = merged
  has_setup = true

  if created_keymap then
    pcall(vim.keymap.del, "n", created_keymap)
    created_keymap = nil
  end

  if config.keymap then
    vim.keymap.set("n", config.keymap, function()
      M.switch()
    end, { desc = "Switch keyword", silent = true })
    created_keymap = config.keymap
  end

  if created_command then
    pcall(vim.api.nvim_del_user_command, "Switch")
    created_command = false
  end

  if config.command then
    vim.api.nvim_create_user_command("Switch", function(args)
      M.switch({ scope = args.args ~= "" and args.args or config.scope })
    end, {
      nargs = "?",
      desc = "Switch configured keywords",
      complete = function()
        return { "line", "buffer", "cursor" }
      end,
    })
    created_command = true
  end

  return M
end

---Whether setup has been called at least once.
---@return boolean
function M.is_setup()
  return has_setup
end

return M
