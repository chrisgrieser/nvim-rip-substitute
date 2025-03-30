local M = {}
local u = require("rip-substitute.utils")
--------------------------------------------------------------------------------

---@param rgArgs string[]
---@return number exitCode
---@return string[] stdoutOrStderr
local function runRipgrep(rgArgs)
	local argOrderValid = rgArgs[#rgArgs - 1] == "--"
	assert(argOrderValid, "Last 2 args must be `--` & searchValue for proper parsing.") -- see #26

	local config = require("rip-substitute.config").config
	local targetBufCache = require("rip-substitute.state").targetBufCache
	local state = require("rip-substitute.state").state

	local args = {
		"rg",
		"--no-config",
		config.regexOptions.pcre2 and "--pcre2" or "--no-pcre2",
		state.useFixedStrings and "--fixed-strings" or "--no-fixed-strings",
		state.useIgnoreCase and "--ignore-case" or "--case-sensitive",
		"--no-crlf", -- see #17
	}
	vim.list_extend(args, rgArgs)
	if config.debug then u.notify("ARGS\n" .. table.concat(args, " "), "debug") end

	-- INFO reading from stdin instead of the file to deal with unsaved changes
	-- (see #8) and to be able to handle non-file buffers
	local result = vim.system(args, { stdin = targetBufCache }):wait()
	if config.debug then u.notify("RESULT\n" .. result.stdout, "debug") end

	local text = result.code == 0 and result.stdout or result.stderr
	return result.code, vim.split(vim.trim(text or ""), "\n")
end

---@return string
---@return string
function M.getSearchAndReplaceValuesFromPopup()
	local config = require("rip-substitute.config").config
	local state = require("rip-substitute.state").state

	local toSearch, toReplace = unpack(vim.api.nvim_buf_get_lines(state.popupBufNr, 0, -1, false))
	if config.regexOptions.autoBraceSimpleCaptureGroups then
		-- CAVEAT will not work if user has 10 capture groups (which should almost never happen though)
		toReplace = toReplace:gsub("%$(%d)", "${%1}")
	end
	return toSearch, toReplace
end

---@param line string formatted as `lnum:col:text`
---@return { lnum: number, col: number, text: string }
local function parseRgResult(line)
	local lnumStr, colStr, text = line:match("^(%d+):(%d+):(.*)")

	-- GUARD empty line with empty search string, see #38
	if not lnumStr then
		lnumStr = line:match("%d")
		colStr = "1"
		text = ""
	end

	return { lnum = tonumber(lnumStr) - 1, col = tonumber(colStr) - 1, text = text }
end

--------------------------------------------------------------------------------

function M.executeSubstitution()
	local state = require("rip-substitute.state").state
	local toSearch, toReplace = M.getSearchAndReplaceValuesFromPopup()

	local code, results = runRipgrep { "--replace=" .. toReplace, "--line-number", "--", toSearch }
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
	if require("rip-substitute.config").config.notification.onSuccess then
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

---Creates an incremental preview of search matches & replacements in the
---viewport, and returns the total number of matches. Searches are hidden via
---`conceal` (requires `conceallevel` >= 2), and replacements are inserted as
---inline virtual text. The total count is derived from this function to avoid
---re-running `rg` just for the count.
function M.incrementalPreviewAndMatchCount()
	local viewStartLnum, viewEndLnum = u.getViewport()
	local state = require("rip-substitute.state").state
	local ns = vim.api.nvim_create_namespace("rip-substitute.incPreview")
	local hlGroup = require("rip-substitute.config").config.incrementalPreview.matchHlGroup
	local toSearch, toReplace = M.getSearchAndReplaceValuesFromPopup()

	-- CLEAR PREVIOUS PREVIEW
	state.matchCount = 0
	vim.api.nvim_buf_clear_namespace(state.targetBuf, ns, 0, -1)

	-- GUARD INVALID SEARCH/REPLACE STRINGS
	if toSearch == "" then return end
	if toSearch:find("\\[nr]") and toReplace:find("\\[nr]") then
		-- see #28 or https://github.com/chrisgrieser/nvim-rip-substitute/issues/28#issuecomment-2503761241
		u.notify("Search and replace strings cannot contain newlines.", "error")
		return
	end

	-- DETERMINE MATCHES
	local rgArgs = { "--line-number", "--column", "--only-matching", "--", toSearch }
	local code, searchMatches = runRipgrep(rgArgs)
	if code ~= 0 then return end

	-- RANGE: FILTER MATCHES
	-- PERF For single files, `rg` gives us results sorted by line number
	-- already, so we can `slice` instead of `filter` to improve performance.
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
		if rangeStartIdx == nil then return end -- no matches in range
		searchMatches = vim.list_slice(searchMatches, rangeStartIdx, rangeEndIdx)
	end

	state.matchCount = #searchMatches

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
	if not viewStartIdx then return end -- no matches in viewport
	if not viewEndIdx then viewEndIdx = #searchMatches end -- viewport is at end of file

	-- SEARCH: HIGHLIGHT MATCHES
	-- hide when there is a replacement value
	local matchEndcolsInViewport = {}
	vim.iter(searchMatches):slice(viewStartIdx, viewEndIdx):map(parseRgResult):each(function(match)
		local matchEndCol = match.col + #match.text
		if toReplace == "" then
			if vim.hl.range then
				vim.hl.range(
					state.targetBuf,
					ns,
					hlGroup,
					{ match.lnum, match.col },
					{ match.lnum, matchEndCol }
				)
			else
				---@diagnostic disable-next-line: deprecated --- keep for backwards compatibility
				vim.api.nvim_buf_add_highlight(
					state.targetBuf,
					ns,
					hlGroup,
					match.lnum,
					match.col,
					matchEndCol
				)
			end
		else
			-- INFO requires `conceallevel` >= 2
			vim.api.nvim_buf_set_extmark(state.targetBuf, ns, match.lnum, match.col, {
				conceal = "",
				end_col = matchEndCol,
				end_row = match.lnum,
			})

			-- INFO saving the end columns to correctly position the replacements.
			-- For single files, `rg` gives us results sorted by line & column, so
			-- that we can simply collect them in a list.
			table.insert(matchEndcolsInViewport, matchEndCol)
		end
	end)

	-- REPLACE: INSERT AS VIRTUAL TEXT
	if toReplace == "" then return end

	table.insert(rgArgs, 1, "--replace=" .. toReplace) -- prepend, so `-- searchValue` is still at the end
	local code2, replacements = runRipgrep(rgArgs)
	if code2 ~= 0 then return #searchMatches end

	if state.range then replacements = vim.list_slice(replacements, rangeStartIdx, rangeEndIdx) end

	vim.iter(replacements):slice(viewStartIdx, viewEndIdx):map(parseRgResult):each(function(repl)
		local matchEndCol = table.remove(matchEndcolsInViewport, 1)
		local virtText = { repl.text, hlGroup }
		vim.api.nvim_buf_set_extmark(state.targetBuf, ns, repl.lnum, matchEndCol, {
			virt_text = { virtText },
			virt_text_pos = "inline",
		})
	end)
end

--------------------------------------------------------------------------------
return M
