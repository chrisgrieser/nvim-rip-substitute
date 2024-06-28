local M = {}
local rg = require("rip-substitute.rg-operations")
local utils = require("rip-substitute.utils")


---@return string
---@return string
local function getSearchAndReplaceValuesFromPopup()
	local config = require("rip-substitute.config").config
	local state = require("rip-substitute.state").state

	local toSearch, toReplace = unpack(vim.api.nvim_buf_get_lines(
		state.popupBufNr, 0, -1, false))
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
	vim.print("[GETTING MATCHES] for ", toSearch, " ", toReplace)
	if not toSearch then return end
	local code, matched = rg.runRipgrep {
		"--line-number",
		"--column",
		"--vimgrep",
		"--no-filename",
		toSearch,
	}
	if code ~= 0 then
		return nil, "could not get rg matches"
	end
	if #matched == 0 then
		return {}, nil
	end


	---@type RipSubstituteMatch[]
	local matches = utils.map(matched,
		---@param line string
		---@param i integer
		function(line, i)
			vim.print(line)
			local  rowStr, colStr, text = line:match("^(%d+):(%d+):(.*)")
			---@type RipSubstituteMatch
			local match = {
				row = tonumber(rowStr) - 1,
				col = tonumber(colStr) - 1,
				matchedText = text,
				replacementText = ""
			}
			return match
		end
	)

	if toReplace and toReplace ~= "" then
		for i, match in ipairs(matches) do
			local replaced
			code, replaced = rg.runRipgrep {
				"--line-number",
				"--column",
				"--vimgrep",
				"--no-filename",
				toReplace,
			}
			if code ~= 0 then
				return nil, "could not get rg replacements"
			end
			if #matched ~= #replaced then
				return nil, "#matched ~= #replaced"
			end
			if not replaced[i] then
				return nil, "could not get replacement for " .. match.matchedText
			end
			match.replacementText = replaced[i]
		end
	end
	vim.print(matches)
	return matches
end


---@param matches RipSubstituteMatch[]
---@return RipSubstituteMatch | nil, string |nil
function M.get_closest_match_after_cursor(matches)
	local state = require("rip-substitute.state").state
    local cursor_row, cursor_col =
        unpack(vim.api.nvim_win_get_cursor(state.popupWinNr))
    local closestMatch = nil -- Store the closest match found after cursor

    -- First, try to find a match after the cursor position
    for _, match in ipairs(matches) do
        local on_line_after = match.start.row > cursor_row
        local on_same_line = match.start.row == cursor_row
        local cursor_on_match = on_same_line
            and match.start.col <= cursor_col
            and match.finish.col >= cursor_col
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
            local on_line_before = match.finish.row < cursor_row
            local on_same_line_before = match.finish.row == cursor_row
                and match.finish.col < cursor_col

            if on_line_before or on_same_line_before then
                closestMatch = match
                -- No break here; keep updating closestMatch to the last match before cursor
            end
        end
    end

    return closestMatch
end


return M
