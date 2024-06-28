local utils = require("rip-substitute.utils")
--TODO: seems like these are globals in sandr
--probably need to integrate into state
Matches = {}
CurrentMatch = nil
local M = {}

---@class RipSubstitute.Position
---@field row number
---@field col number

--- i would use vim.Range, but it's weird because end is a keyword
--- and therefore can't be used like match.end
---@class RipSubstituteRange
---@field start RipSubstitute.Position
---@field end_ RipSubstitute.Position

---@param line string
---@param row number
---@param search_term string
---@return RipSubstituteRange[]
local function getMatchesOfLine(line, row, search_term)
	local config = require("rip-substitute.config").config
	local matches = {}
	local ignoreCase = config.regexOptions.casing == "ignore-case"
	local line_to_search = ignoreCase and string.lower(line) or line
	local term_to_search = search_term
	term_to_search = ignoreCase and string.lower(term_to_search) or term_to_search

	local start_pos = 1
	while true do
		local start, finish
		if config.regex then
			-- Escape parentheses and replace "?" with "\=" for zero or one occurrences in Vim regex
			term_to_search = term_to_search
				:gsub([[\]], [[\\]]) -- This ensures that \w in the input becomes \\w in the Lua string, which vim.regex interprets as \w
				:gsub("%(", "\\(") -- Replace "(" with "\("
				:gsub("%)", "\\)") -- Replace ")" with "\)"
				:gsub("%?", "\\=") -- Replace "?" with "\=" (zero or one occurrence in Vim regex)
				:gsub("\\([%a])", "%%%1") -- Escape special characters
				:gsub("\\%%", "\\") -- Handle escaped percentages
			local success, regex = pcall(vim.regex, term_to_search)
			if not success or not regex then return {} end
			local substring = line_to_search:sub(start_pos)
			local match_start, match_end = regex:match_str(substring)
			if match_start then
				start = start_pos + match_start - 1
				finish = start_pos + match_end - 1
			end
		else
			start, finish = line_to_search:find(term_to_search, start_pos, not config.regex)
		end
		if not start then break end

		local match = {
			start = { col = start - 1, row = row },
			finish = { col = finish, row = row },
		}
		table.insert(matches, match)
		start_pos = finish + 1
	end

	return matches
end

---@param bufnr number
---@param searchTerm string
---@return RipSubstituteRange[] | nil
function M.getMatches(bufnr, searchTerm)
	if not searchTerm or searchTerm == "" then return {} end
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	return utils.flatMap(
		lines,
		function(line, i) local matchesOfLine = getMatchesOfLine(line, i, searchTerm) end
	)
end

---@param matches RipSubstituteRange[]
---@return RipSubstituteRange | nil
function M.get_closest_match_after_cursor(matches)
	local state = require("rip-substitute.state").state
	local cursor_row, cursor_col = unpack(vim.api.nvim_win_get_cursor(state.targetWin))
	local closestMatch = nil -- Store the closest match found after cursor

	-- First, try to find a match after the cursor position
	for _, match in ipairs(matches) do
		local on_line_after = match.start.row > cursor_row
		local on_same_line = match.start.row == cursor_row
		local cursor_on_match = on_same_line
			and match.start.col <= cursor_col
			and match.end_.col >= cursor_col
		local on_same_line_after = not cursor_on_match
			and on_same_line
			and match.start.col > cursor_col

		if on_line_after or cursor_on_match or on_same_line_after then
			closestMatch = match
			break -- Stop the loop if a match is found
		end
	end

	-- If no match is found after cursor, search from the beginning of the file to the cursor
	if not closestMatch then
		for _, match in ipairs(matches) do
			local on_line_before = match.end_.row < cursor_row
			local on_same_line_before = match.end_.row == cursor_row
				and match.end_.col < cursor_col

			if on_line_before or on_same_line_before then
				closestMatch = match
				-- No break here; keep updating closestMatch to the last match before cursor
			end
		end
	end

	return closestMatch
end

--- @param match1 RipSubstituteRange
--- @param match2 RipSubstituteRange
function M.equals(match1, match2)
	return match1.start.col == match2.start.col
		and match1.start.row == match2.start.row
		and match1.end_.col == match2.end_.col
		and match1.end_.row == match2.end_.row
end

---@param current_match RipSubstituteRange
---@param matches RipSubstituteRange[]
function M.get_next_match(current_match, matches)
	if current_match == nil then
		error("must provide value for current_match")
		return
	end

	local current_index = utils.index_of(
		matches,
		function(match) return M.equals(match, current_match) end
	)
	if current_index == nil then
		error("couldn't locate match in list of matches")
		return
	end
	return current_index + 1 > #matches and matches[1] or matches[current_index + 1]
end

---@param currentMatch RipSubstituteRange
---@param matches RipSubstituteRange[]
function M.getPrevMatch(currentMatch, matches)
	if currentMatch == nil then
		error("must provide value for current_match")
		return
	end
	local current_index = utils.index_of(
		matches,
		function(match) return M.equals(match, currentMatch) end
	)
	if current_index == nil then
		error("couldn't locate match in list of matches")
		return
	end
	return current_index - 1 < 1 and matches[#matches] or matches[current_index - 1]
end

---@param match RipSubstituteRange
function M.centerViewportOnMatch(match)
	local top_line = vim.fn.line("w0") -- Get the top line of the current window
	local bot_line = vim.fn.line("w$") -- Get the bottom line of the current window
	local match_line = match.start.row

	-- Check if the match is outside the current viewport
	if match_line < top_line or match_line > bot_line then
		-- Center the viewport on the match
		vim.api.nvim_win_set_cursor(0, { match_line, 0 }) -- Set cursor to the line of the match
		vim.cmd("normal zz") -- Center the window view on the cursor line
	end
end

return M
