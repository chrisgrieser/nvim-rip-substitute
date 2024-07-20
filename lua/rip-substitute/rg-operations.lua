local M = {}
local config = require("rip-substitute.config").config
local u = require("rip-substitute.utils")
--------------------------------------------------------------------------------

---@return string
---@return string
local function getSearchAndReplaceValuesFromPopup()
	local state = require("rip-substitute.state").state

	local toSearch, toReplace = unpack(vim.api.nvim_buf_get_lines(state.popupBufNr, 0, -1, false))
	if config.regexOptions.autoBraceSimpleCaptureGroups then
		toReplace = toReplace:gsub("%$(%d+)", "${%1}")
	end
	return toSearch, toReplace
end

---@param line string formatted as `lnum:col:text`
---@return { lnum: number, col: number, text: string }
local function parseRgResult(line)
	local lnumStr, colStr, text = line:match("^(%d+):(%d+):(.*)")
	return { lnum = tonumber(lnumStr) - 1, col = tonumber(colStr) - 1, text = text }
end

--------------------------------------------------------------------------------

---@param rgArgs string[]
---@return number exitCode
---@return string[] stdoutOrStderr
function M.runRipgrep(rgArgs)
	local state = require("rip-substitute.state").state

	-- args
	local args = vim.deepcopy(rgArgs) -- copy, since list_extend modifies the *passed* original
	table.insert(args, 1, "rg")
	vim.list_extend(args, {
		config.regexOptions.pcre2 and "--pcre2" or "--no-pcre2",
		"--" .. config.regexOptions.casing,
		"--no-config",
		"--",
		state.targetFile,
	})

	-- results
	local result = vim.system(args):wait()
	local text = result.code == 0 and result.stdout or result.stderr
	return result.code, vim.split(vim.trim(text or ""), "\n")
end

---@return string
---@return string
function M.getSearchAndReplaceValuesFromPopup()
	local state = require("rip-substitute.state").state

	local toSearch, toReplace = unpack(vim.api.nvim_buf_get_lines(state.popupBufNr, 0, -1, false))
	if config.regexOptions.autoBraceSimpleCaptureGroups then
		-- CAVEAT will not work if user has 10 capture groups (which should almost never happen though)
		toReplace = toReplace:gsub("%$(%d)", "${%1}")
	end
	return toSearch, toReplace
end

function M.substitute()
	local state = require("rip-substitute.state").state
	local match = state.selectedMatch
	if not match then return end
	local line = vim.api.nvim_buf_get_lines(state.targetBuf, match.row, match.row + 1, false)[1]
	local start = match.col
	local _end = match.col + #match.matchedText

	local newLine = line:sub(1, start) .. match.replacementText .. line:sub(_end + 1)

	vim.api.nvim_buf_set_lines(state.targetBuf, match.row, match.row + 1, false, { newLine })
end

function M.substituteAll()
	local state = require("rip-substitute.state").state
	local toSearch, toReplace = M.getSearchAndReplaceValuesFromPopup()

	local code, results = M.runRipgrep { toSearch, "--replace=" .. toReplace, "--line-number" }
	if code ~= 0 then
		local errorMsg = vim.trim(table.concat(results, "\n"))
		u.notify(errorMsg, "error")
		return
	end

	-- INFO Only update individual lines as opposed to whole buffer, as this
	-- preserves folds and marks. We could also use `nvim_buf_set_text` to update
	-- only sections inside specific lines, however that requires a lot of manual
	-- calculation when dealing with multiple matches in a line, and will only be
	-- more complicated when features like `--multiline` support are added later
	-- on. As the benefit of preserving marks *inside* a changed line is not that
	-- great, we'll stick to the simpler approach.
	local replacedLines = 0
	for _, repl in pairs(results) do
		local lineStr, newLine = repl:match("^(%d+):(.*)")
		local lnum = assert(tonumber(lineStr), "rg parsing error")
		if not state.range or (lnum >= state.range.start and lnum <= state.range.end_) then
			vim.api.nvim_buf_set_lines(state.targetBuf, lnum - 1, lnum, false, { newLine })
			replacedLines = replacedLines + 1
		end
	end

	-- notify
	if require("rip-substitute.config").config.notificationOnSuccess then
		local count = state.matchCount
		local s1 = count == 1 and "" or "s"
		local msg = ("Replaced %d occurrence%s"):format(count, s1)
		if replacedLines ~= count then
			local s2 = replacedLines == 1 and "" or "s"
			msg = msg .. (" in %d line%s"):format(replacedLines, s2)
		end
		u.notify(msg .. ".")
	end
end

--------------------------------------------------------------------------------
--- RANGE: FILTER MATCHES
--- PERF For single files, `rg` gives us results sorted by lines, so we can
--- `slice` instead of `filter` to improve performance.
---@param matches RipSubstituteMatch
---@param range CmdRange
local function getMatchesInRange(matches, range)
	local rangeStartIdx, rangeEndIdx
	for i, match in ipairs(matches) do
		local inRange = match.row >= range.start and match.row <= range.end_
		if rangeStartIdx == nil and inRange then rangeStartIdx = i end
		if rangeStartIdx and match.row > range.end_ then
			rangeEndIdx = i - 1
			break
		end
	end
	if rangeStartIdx == nil then return end -- no matches in range
	return vim.list_slice(matches, rangeStartIdx, rangeEndIdx)
end

---@param matches RipSubstituteMatch
---@param viewStartLnum number
---@param viewEndLnum number
---@return number|nil, number | nil
local function getViewportRange(matches, viewStartLnum, viewEndLnum)
	-- VIEWPORT: FILTER MATCHES
	local viewStartIdx, viewEndIdx
	for i, match in ipairs(matches) do
		if not viewStartIdx and match.row >= viewStartLnum and match.row <= viewEndLnum then
			viewStartIdx = i
		end
		if viewStartIdx and match.row > viewEndLnum then
			viewEndIdx = i - 1
			break
		end
	end
end

---@param match RipSubstituteMatch
---@param selected boolean
---@param targetBuf number
---@param incPreviewNs number
function M.highlightReplacement(match, selected, targetBuf, incPreviewNs)
	local hl_group = selected and config.incrementalPreview.hlGroups.currentMatch
		or config.incrementalPreview.hlGroups.replacement
	local ok, err = pcall(
		function()
			vim.api.nvim_buf_set_extmark(targetBuf, incPreviewNs, match.row, match.col, {
				virt_text = {
					{
						match.replacementText,
						hl_group,
					},
				},
				virt_text_pos = "inline",
				hl_mode = "replace",
				strict = false,
				conceal = match.matchedText,
				end_col = match.col + #match.matchedText,
				end_row = match.row,
			})
		end
	)
end

--TODO: apparently some highlights that we want to keep get removed anyway-> todo comments
--
---@param match RipSubstituteMatch
---@param selected boolean
---@param targetBuf number
---@param incPreviewNs number
---@param matchEndCol number
function M.highlightMatch(match, selected, targetBuf, incPreviewNs, matchEndCol)
	local hlGroup = selected and config.incrementalPreview.hlGroups.currentMatch
		or config.incrementalPreview.hlGroups.match
	vim.api.nvim_buf_add_highlight(
		targetBuf,
		incPreviewNs,
		hlGroup,
		match.row,
		match.col,
		matchEndCol
	)
end

---Creates an increments preview of search matches & replacements in the
---viewport, and returns the total number of matches. (The total count is derived
---from this function to avoid re-running `rg` just for the count.)
---@param viewStartLnum number
---@param viewEndLnum number
function M.incrementalPreviewAndMatchCount(viewStartLnum, viewEndLnum)
	local state = require("rip-substitute.state").state
	state.matchCount = 0
	vim.api.nvim_buf_clear_namespace(state.targetBuf, state.incPreviewNs, 0, -1)

	local matches = state.matches
	if not matches or #matches == 0 then return end
	if state.range then matches = getMatchesInRange(matches, state.range) end
	if not matches or #matches == 0 then return end

	state.matchCount = #matches

	local viewStartIdx, viewEndIdx = getViewportRange(matches, viewStartLnum, viewEndLnum)
	if not viewStartIdx or not viewEndIdx then return end

	-- SEARCH: HIGHLIGHT MATCHES
	-- hide when there is a replacement value
	local matchEndcolsInViewport = {}
	vim.iter(matches):slice(viewStartIdx, viewEndIdx):each(function(match)
		if match.replacementText == "" then
			M.highlightMatch(
				match,
				state.selectedMatch == match,
				state.targetBuf,
				state.incPreviewNs,
				match.col + #match.matchedText
			)
		else
			M.highlightReplacement(
				match,
				state.selectedMatch == match,
				state.targetBuf,
				state.incPreviewNs
			)
		end
	end)
end

--------------------------------------------------------------------------------
return M
