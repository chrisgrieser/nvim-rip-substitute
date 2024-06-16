local M = {}
local u = require("rip-substitute.utils")
--------------------------------------------------------------------------------

---@param args string[]
---@return number exitCode
---@return string[] stdoutOrStderr
local function runRipgrep(args)
	local config = require("rip-substitute.config").config
	local state = require("rip-substitute.state").state

	local rgCmd = vim.list_extend({ "rg", "--no-config" }, args)
	if config.regexOptions.pcre2 then table.insert(rgCmd, "--pcre2") end
	vim.list_extend(rgCmd, { "--", state.targetFile })
	local result = vim.system(rgCmd):wait()

	local text = result.code == 0 and result.stdout or result.stderr
	return result.code, vim.split(vim.trim(text or ""), "\n")
end

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

---@param line string formatted as `lnum:col:text`
---@return { lnum: number, col: number, text: string }
local function parseRgResult(line)
	local lnumStr, colStr, text = line:match("^(%d+):(%d+):(.*)")
	return { lnum = tonumber(lnumStr) - 1, col = tonumber(colStr) - 1, text = text }
end

--------------------------------------------------------------------------------

function M.executeSubstitution()
	local state = require("rip-substitute.state").state
	local toSearch, toReplace = getSearchAndReplaceValuesFromPopup()

	local code, results = runRipgrep { toSearch, "--replace=" .. toReplace, "--line-number" }
	if code ~= 0 then
		u.notify(table.concat(results, "\n"), "error")
		return
	end

	-- only update individual lines as opposed to whole buffer, as this
	-- preserves folds and marks
	local replacementCount = 0
	for _, repl in pairs(results) do
		local lineStr, newLine = repl:match("^(%d+):(.*)")
		local lnum = assert(tonumber(lineStr), "rg parsing error")
		if not state.range or (lnum >= state.range.start and lnum <= state.range.end_) then
			vim.api.nvim_buf_set_lines(state.targetBuf, lnum - 1, lnum, false, { newLine })
			replacementCount = replacementCount + 1
		end
	end

	-- notify
	if require("rip-substitute.config").config.notificationOnSuccess then
		local pluralS = replacementCount == 1 and "" or "s"
		u.notify(("%d occurrence%s replaced"):format(replacementCount, pluralS))
	end
end

--------------------------------------------------------------------------------

---Creates an increments preview of search matches & replacements in the
---viewport, and returns the total number of matches. (The total count is derived
---from this function to avoid re-running `rg` just for the count.)
---@param viewStartLnum number
---@param viewEndLnum number
---@return number? -- total number of matches (including outside viewport)
function M.incrementalPreviewAndMatchCount(viewStartLnum, viewEndLnum)
	local state = require("rip-substitute.state").state
	local opts = require("rip-substitute.config").config.incrementalPreview
	local hl = opts.hlGroups
	vim.api.nvim_buf_clear_namespace(state.targetBuf, state.incPreviewNs, 0, -1)

	local toSearch, toReplace = getSearchAndReplaceValuesFromPopup()
	if toSearch == "" then return end

	-- DETERMINE MATCHES
	local rgArgs = { toSearch, "--line-number", "--column", "--only-matching" }
	local code, searchMatches = runRipgrep(rgArgs)
	if code ~= 0 then return end

	-- RANGE: FILTER MATCHES
	-- PERF For single files, `rg` gives us results sorted by lines, so we can
	-- slice instead of filter to improve performance.
	local rangeStartIdx, rangeEndIdx
	if state.range then
		for i = 1, #searchMatches do
			local lnum = tonumber(searchMatches[i]:match("^(%d+):"))
			local inRange = lnum >= state.range.start and lnum <= state.range.end_
			if rangeStartIdx == nil and inRange then rangeStartIdx = i end
			if rangeStartIdx and lnum > state.range.end_ then
				rangeEndIdx = i - 1
				break
			end
		end
		searchMatches = vim.list_slice(searchMatches, rangeStartIdx, rangeEndIdx)
	end

	-- VIEWPORT: FILTER MATCHES
	local viewStartIdx, viewEndIdx
	for i = 1, #searchMatches do
		local lnum = tonumber(searchMatches[i]:match("^(%d+):"))
		if not viewStartIdx and lnum >= viewStartLnum and lnum <= viewEndLnum then
			viewStartIdx = i
		end
		if viewStartIdx and lnum > viewEndLnum then
			viewEndIdx = i - 1
			break
		end
	end
	if not viewStartIdx then return #searchMatches end -- no matches in viewport
	if not viewEndIdx then viewEndIdx = #searchMatches end

	-- HIGHLIGHT SEARCH MATCHES
	local matchEndcolsInViewport = {}
	vim.iter(searchMatches):slice(viewStartIdx, viewEndIdx):map(parseRgResult):each(function(match)
		local matchEndCol = match.col + #match.text
		vim.api.nvim_buf_add_highlight(
			state.targetBuf,
			state.incPreviewNs,
			toReplace == "" and hl.activeSearch or hl.inactiveSearch,
			match.lnum,
			match.col,
			matchEndCol
		)
		-- INFO saving the end columns to correctly position the replacements.
		-- For single files, `rg` gives us results sorted by line & column, so
		-- that we can simply collect them in a list.
		if toReplace ~= "" then table.insert(matchEndcolsInViewport, matchEndCol) end
	end)

	-- INSERT REPLACEMENTS AS VIRTUAL TEXT
	if toReplace == "" then return #searchMatches end

	table.insert(rgArgs, "--replace=" .. toReplace)
	local code2, replacements = runRipgrep(rgArgs)
	if code2 ~= 0 then return #searchMatches end

	if state.range then replacements = vim.list_slice(replacements, rangeStartIdx, rangeEndIdx) end

	vim.iter(replacements):slice(viewStartIdx, viewEndIdx):map(parseRgResult):each(function(repl)
		local matchEndCol = table.remove(matchEndcolsInViewport, 1)
		local virtText = { repl.text, hl.replacement }
		vim.api.nvim_buf_set_extmark(
			state.targetBuf,
			state.incPreviewNs,
			repl.lnum,
			matchEndCol,
			{ virt_text = { virtText }, virt_text_pos = "inline", strict = false }
		)
	end)

	return #searchMatches
end

--------------------------------------------------------------------------------
return M
