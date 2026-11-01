--- Core keyword matching and replacement for switch.nvim.
---
--- This module is deliberately free of buffer/window logic so it can be used
--- and tested independently.
local M = {}

local function is_word_char(char)
  return char ~= "" and char:match("^[%w_]$") ~= nil
end

---@param keywords string[]
---@return string
local function next_keyword(keywords, index)
  return keywords[(index % #keywords) + 1]
end

---Preserve the casing style of `source` when replacing it with `replacement`.
---@param source string
---@param replacement string
---@return string
local function match_case(source, replacement)
  local has_upper = source:find("%u") ~= nil
  local has_lower = source:find("%l") ~= nil

  if has_upper and not has_lower then
    return replacement:upper()
  end

  if source:sub(1, 1):match("%u") then
    return replacement:sub(1, 1):upper() .. replacement:sub(2):lower()
  end

  return replacement:lower()
end

---@param line string
---@param start_byte integer
---@param end_byte integer
---@param candidate table
---@return boolean
local function has_valid_boundaries(line, start_byte, end_byte, candidate)
  if candidate.starts_with_word_char then
    local previous = start_byte > 1 and line:sub(start_byte - 1, start_byte - 1) or ""
    if is_word_char(previous) then
      return false
    end
  end

  if candidate.ends_with_word_char then
    local following = line:sub(end_byte + 1, end_byte + 1)
    if is_word_char(following) then
      return false
    end
  end

  return true
end

---@param line string
---@param position integer 1-based byte position
---@param candidate table
---@return boolean
local function matches_at(line, position, candidate)
  local end_byte = position + candidate.length - 1
  if end_byte > #line then
    return false
  end

  local segment = line:sub(position, end_byte)
  if candidate.lowercase then
    segment = segment:lower()
  end

  if segment ~= candidate.match then
    return false
  end

  return has_valid_boundaries(line, position, end_byte, candidate)
end

---Build the matcher list. Longer keywords come first so that overlapping
---keywords (for example "is not" and "is") match the most specific one.
---@param groups string[][]
---@param ignore_case boolean
---@return table[]
local function build_candidates(groups, ignore_case)
  local candidates = {}

  for group_index, group in ipairs(groups) do
    for keyword_index, keyword in ipairs(group) do
      candidates[#candidates + 1] = {
        group = group_index,
        index = keyword_index,
        match = ignore_case and keyword:lower() or keyword,
        lowercase = ignore_case,
        length = #keyword,
        starts_with_word_char = is_word_char(keyword:sub(1, 1)),
        ends_with_word_char = is_word_char(keyword:sub(-1)),
      }
    end
  end

  table.sort(candidates, function(a, b)
    if a.length ~= b.length then
      return a.length > b.length
    end
    if a.group ~= b.group then
      return a.group < b.group
    end
    return a.index < b.index
  end)

  return candidates
end

---Replace every configured keyword in a single line.
---
---All matches are discovered against the original line, so replacements are
---never re-processed. For example, `true false` with the group
---`{ "true", "false" }` becomes `false true`, not `false false`.
---
---@param line string
---@param groups string[][]
---@param opts? { ignore_case?: boolean, preserve_case?: boolean, only_covering_col?: integer }
---@return string line, integer replacements
function M.replace_line(line, groups, opts)
  opts = opts or {}
  local candidates = build_candidates(groups, opts.ignore_case == true)
  local only_covering_col = opts.only_covering_col
  local pieces = {}
  local position = 1
  local replacements = 0

  while position <= #line do
    local candidate
    for _, item in ipairs(candidates) do
      if matches_at(line, position, item) then
        candidate = item
        break
      end
    end

    if candidate then
      local end_byte = position + candidate.length - 1
      local is_target = only_covering_col == nil or (only_covering_col >= position and only_covering_col <= end_byte)

      if is_target then
        local replacement = next_keyword(groups[candidate.group], candidate.index)
        if opts.ignore_case and opts.preserve_case then
          replacement = match_case(line:sub(position, end_byte), replacement)
        end
        pieces[#pieces + 1] = replacement
        replacements = replacements + 1
      else
        pieces[#pieces + 1] = line:sub(position, end_byte)
      end

      position = end_byte + 1
    else
      pieces[#pieces + 1] = line:sub(position, position)
      position = position + 1
    end
  end

  return table.concat(pieces), replacements
end

---Replace every configured keyword in a list of lines.
---@param lines string[]
---@param groups string[][]
---@param opts? { ignore_case?: boolean, preserve_case?: boolean }
---@return string[] lines, integer replacements
function M.replace(lines, groups, opts)
  local result = {}
  local replacements = 0

  for index, line in ipairs(lines) do
    local replaced, count = M.replace_line(line, groups, opts)
    result[index] = replaced
    replacements = replacements + count
  end

  return result, replacements
end

return M
