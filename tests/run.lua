package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local core = require("switch.core")
local switch = require("switch")

local failures = 0
local tests = 0

local function fail(name, message)
  failures = failures + 1
  print(("not ok %d - %s"):format(tests, name))
  print("  " .. message)
end

local function ok(name, condition, message)
  tests = tests + 1
  if condition then
    print(("ok %d - %s"):format(tests, name))
  else
    fail(name, message or "assertion failed")
  end
end

local function eq(name, actual, expected)
  ok(name, vim.deep_equal(actual, expected), ("expected %s, got %s"):format(vim.inspect(expected), vim.inspect(actual)))
end

local function replace(name, line, groups, expected, opts, expected_count)
  local result, count = core.replace_line(line, groups, opts)
  eq(name, result, expected)
  if expected_count ~= nil then
    eq(name .. " (count)", count, expected_count)
  end
end

replace("cycles last keyword back to the first", "true false", { { "true", "false" } }, "false true", nil, 2)
replace("cycles a single last keyword", "false", { { "true", "false" } }, "true", nil, 1)
replace("does not match inside a word", "untrue true", { { "true", "false" } }, "untrue false", nil, 1)
replace("replaces multiple independent groups", "yes on", {
  { "yes", "no" },
  { "on", "off" },
}, "no off", nil, 2)
replace("prefers the longest keyword", "is not is", {
  { "is", "was" },
  { "is not", "was not" },
}, "was not was", nil, 2)
replace("handles symbols", "i++", { { "++", "--" } }, "i--", nil, 1)
replace("handles keywords containing spaces", "foo bar", { { "foo bar", "baz" } }, "baz", nil, 1)
replace("does not reprocess replacements", "x", { { "x", "y" } }, "y", nil, 1)
replace("only replaces the keyword under the cursor", "true false", { { "true", "false" } }, "false false", {
  only_covering_col = 1,
}, 1)
replace("only replaces the keyword under a later cursor column", "true false", { { "true", "false" } }, "true true", {
  only_covering_col = 6,
}, 1)
replace("ignores case", "True TRUE true", { { "true", "false" } }, "false false false", {
  ignore_case = true,
}, 3)
replace("preserves case", "True TRUE true", { { "true", "false" } }, "False FALSE false", {
  ignore_case = true,
  preserve_case = true,
}, 3)
replace("leaves unknown words alone", "hello world", { { "true", "false" } }, "hello world", nil, 0)

local lines, count = core.replace({ "yes off", "no on" }, {
  { "yes", "no" },
  { "on", "off" },
})
eq("replaces across lines", lines, { "no on", "yes off" })
eq("counts replacements across lines", count, 4)

-- Integration: setup + buffer mutation through the public API.
switch.setup({
  keywords = {
    { "left", "right" },
    { "up", "down" },
  },
  keymap = false,
  command = false,
  notify = false,
})

vim.api.nvim_buf_set_lines(0, 0, -1, false, { "left up", "right down" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })

local switched = switch.switch({ scope = "line" })
eq("switches the current line through the public API", vim.api.nvim_buf_get_lines(0, 0, -1, false), {
  "right down",
  "right down",
})
eq("returns the replacement count", switched, 2)

vim.api.nvim_buf_set_lines(0, 0, -1, false, { "left up", "right down" })
local buffer_switched = switch.switch({ scope = "buffer" })
eq("switches the whole buffer", vim.api.nvim_buf_get_lines(0, 0, -1, false), {
  "right down",
  "left up",
})
eq("returns the buffer replacement count", buffer_switched, 4)

-- Cursor scope must not touch another keyword on the same line.
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "left left" })
vim.api.nvim_win_set_cursor(0, { 1, 5 })
switch.switch({ scope = "cursor" })
eq("cursor scope only replaces the keyword under the cursor", vim.api.nvim_buf_get_lines(0, 0, -1, false), {
  "left right",
})

-- Configuration validation.
local valid, err = pcall(switch.setup, { keywords = { { "a", "" } }, keymap = false })
ok("rejects empty keywords", not valid, tostring(err))
valid = pcall(switch.setup, { keywords = { { "a", "b" }, { "b", "c" } }, keymap = false })
ok("rejects duplicate keywords across groups", not valid, "expected duplicate keyword error")

-- Per-call options can override the configured booleans, including with false.
switch.setup({
  keywords = { { "yes", "no" } },
  ignore_case = true,
  keymap = false,
  command = false,
})
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "Yes yes" })
switch.switch({ scope = "line", ignore_case = false })
eq("per-call ignore_case=false overrides the config", vim.api.nvim_buf_get_lines(0, 0, -1, false), { "Yes no" })

-- Keymap and command creation.
switch.setup({
  keywords = { { "a", "b" } },
  keymap = "<Plug>(switch-test)",
  command = true,
})
eq("creates the keymap", vim.fn.maparg("<Plug>(switch-test)", "n") ~= "", true)
eq("creates the :Switch command", vim.fn.exists(":Switch"), 2)
switch.setup({
  keywords = { { "a", "b" } },
  keymap = false,
  command = false,
})
eq("removes the keymap when disabled", vim.fn.maparg("<Plug>(switch-test)", "n"), "")
eq("removes the :Switch command when disabled", vim.fn.exists(":Switch"), 0)

if failures > 0 then
  print(("\n%d of %d tests failed"):format(failures, tests))
  vim.cmd("cq")
end

print(("\nall %d tests passed"):format(tests))
