local M = {}
local rg = require("rip-substitute.rg-operations")
local utils = require("rip-substitute.utils")

---@return string
---@return string
local function getSearchAndReplaceValuesFromPopup()
	local config = require("rip-substitute.config").config
	local state = require("rip-substitute.state").state

	local toSearch, toReplace = unpack(vim.api.nvim_buf_get_lines(state.popupBufNr, 0, -1, false))
	if config.regexOptions.autoBraceSimpleCaptureGroups then
		toReplace = toReplace:gsub("%$(%d+)", "${%1}")
	end
	return toSearch, toReplace
end

---@class RipSubstituteMatch
---@field row number
---@field col number
---@field matchedText string
---@field replacementText string

---@return RipSubstituteMatch[]|nil,string|nil
function M.getMatches()
	local toSearch, toReplace = getSearchAndReplaceValuesFromPopup()
	if not toSearch then return end
	local code, matched = rg.runRipgrep {
		"--line-number",
		"--column",
		"--vimgrep",
		"--no-filename",
		"--only-matching",
		toSearch,
	}
	if code ~= 0 then return nil, "[1]could not get rg matches" end
	if #matched == 0 then return {}, nil end

	---@type RipSubstituteMatch[]
	local matches = utils.map(
		matched,
		---@param line string
		---@param i integer
		function(line, i)
			local rowStr, colStr, text = line:match("^(%d+):(%d+):(.*)")
			---@type RipSubstituteMatch
			local match = {
				row = tonumber(rowStr) - 1,
				col = tonumber(colStr) - 1,
				matchedText = text,
				replacementText = "",
			}
			return match
		end
	)


	if toReplace and toReplace ~= "" then
		for i, match in ipairs(matches) do
			local rgArgs = {
				"--line-number",
				"--column",
				"--vimgrep",
				"--no-filename",
				"--only-matching",
				"--replace=" .. toReplace,
				toSearch,
			}
			local replaced
			code, replaced = rg.runRipgrep(rgArgs)
			if code ~= 0 then
				return nil, "[3]could not get rg replacements"
			end
			if #matched ~= #replaced then return nil, "#matched ~= #replaced" end
			if not replaced[i] then
				return nil, "[4]could not get replacement for " .. match.matchedText
			end

			local line = replaced[i]
			local rowStr, colStr, replacementText = line:match("^(%d+):(%d+):(.*)")
			---@type RipSubstituteMatch
			match.replacementText = replacementText
		end
	end
	return matches
end

---@param matches RipSubstituteMatch[]
---@return RipSubstituteMatch | nil, string |nil
function M.getClosestMatchAfterCursor(matches)
	if #matches == 0 then return nil end
	local state = require("rip-substitute.state").state
	local cursor_row, cursor_col = unpack(vim.api.nvim_win_get_cursor(state.targetWin))
	local closestMatch = nil -- Store the closest match found after cursor

	cursor_row = cursor_row - 1
	-- First, try to find a match after the cursor position
	for _, match in ipairs(matches) do
		local on_line_after = match.row > cursor_row
		local on_same_line = match.row == cursor_row
		local cursor_on_match = on_same_line and match.col <= cursor_col and match.col >= cursor_col
		local on_same_line_after = not cursor_on_match and on_same_line and match.col > cursor_col

		if on_line_after or cursor_on_match or on_same_line_after then
			closestMatch = match
			break -- Stop the loop if a match is found
		end
	end

	-- If no match is found after cursor, search from the beginning of the file to the cursor
	if not closestMatch then
		for _, match in ipairs(matches) do
			local on_line_before = match.row < cursor_row
			local on_same_line_before = match.row == cursor_row and match.col < cursor_col

			if on_line_before or on_same_line_before then
				closestMatch = match
				-- No break here; keep updating closestMatch to the last match before cursor
			end
		end
	end

	return closestMatch
end

---@param replacing boolean
---@param newSelectedMatchIndex number
local function updateSelectedMatchHighlight(replacing, newSelectedMatchIndex)
	local state = require("rip-substitute.state").state
	vim.api.nvim_buf_clear_namespace(
		state.targetBuf,
		state.incPreviewNs,
		state.selectedMatch.row,
		state.selectedMatch.row + 1
	)
	if replacing then
		rg.highlightReplacement(state.selectedMatch, false, state.targetBuf, state.incPreviewNs)
	else
		rg.highlightMatch(
			state.selectedMatch,
			false,
			state.targetBuf,
			state.incPreviewNs,
			state.selectedMatch.col + #state.selectedMatch.matchedText
		)
	end
	state.selectedMatch = state.matches[newSelectedMatchIndex]
	--TODO: this will probably clear too many highlights
	vim.api.nvim_buf_clear_namespace(
		state.targetBuf,
		state.incPreviewNs,
		state.selectedMatch.row,
		state.selectedMatch.row + 1
	)
	if replacing then
		rg.highlightReplacement(state.selectedMatch, false, state.targetBuf, state.incPreviewNs)
	else
		rg.highlightMatch(
			state.selectedMatch,
			true,
			state.targetBuf,
			state.incPreviewNs,
			state.selectedMatch.col + #state.selectedMatch.matchedText
		)
	end
end

function M.selectPrevMatch()
	local state = require("rip-substitute.state").state
	local selectedMatch = state.selectedMatch
	if not selectedMatch then return end
	local currentMatchIndex = utils.index_of(
		state.matches,
		function(m) return m == selectedMatch end
	)
	local prevIndex = -1
	if currentMatchIndex == 1 then
		prevIndex = #state.matches
	else
		prevIndex = currentMatchIndex - 1
	end
	local replacing = selectedMatch.replacementText ~= ""
	updateSelectedMatchHighlight(replacing, prevIndex)
	M.centerViewportOnMatch(state.selectedMatch)
end

function M.selectNextMatch()
	local state = require("rip-substitute.state").state
	local selectedMatch = state.selectedMatch
	if not selectedMatch then return end
	local replacing = selectedMatch.replacementText ~= ""
	local currentMatchIndex = utils.index_of(
		state.matches,
		function(m) return m == selectedMatch end
	)
	local nextIndex = -1
	if currentMatchIndex == #state.matches then
		nextIndex = 1
	else
		nextIndex = currentMatchIndex + 1
	end
	updateSelectedMatchHighlight(replacing, nextIndex)
	M.centerViewportOnMatch(state.selectedMatch)
end

---@param match RipSubstituteMatch
function M.centerViewportOnMatch(match)
	local state = require("rip-substitute.state").state
	local padding = 5
	local row, col = match.row + 1, match.col
	local topLine, botLine = utils.getViewport()
	if row < (topLine + padding) or row > (botLine - padding) then
		vim.api.nvim_win_call(
			state.targetWin,
			function() vim.api.nvim_win_set_cursor(state.targetWin, { row, col }) end
		)
		vim.api.nvim_win_call(state.targetWin, function() vim.api.nvim_command("normal zz") end)
	end
end

return M
