local M = {}
local u = require("rip-substitute.utils")
--------------------------------------------------------------------------------

---@param args string[]
---@return vim.SystemCompleted
local function runRipgrep(args)
	local config = require("rip-substitute.config").config
	local state = require("rip-substitute.state").state

	local rgCmd = vim.list_extend({ "rg", "--no-config" }, args)
	if config.regexOptions.pcre2 then table.insert(rgCmd, "--pcre2") end
	vim.list_extend(rgCmd, { "--", state.targetFile })
	return vim.system(rgCmd):wait()
end

---@return string
---@return string
local function getSearchAndReplace()
	local config = require("rip-substitute.config").config
	local state = require("rip-substitute.state").state

	local toSearch, toReplace = unpack(vim.api.nvim_buf_get_lines(state.popupBufNr, 0, -1, false))
	if config.regexOptions.autoBraceSimpleCaptureGroups then
		toReplace = toReplace:gsub("%$(%d+)", "${%1}")
	end
	return toSearch, toReplace
end

--------------------------------------------------------------------------------

function M.executeSubstitution()
	local state = require("rip-substitute.state").state
	local config = require("rip-substitute.config").config
	local toSearch, toReplace = getSearchAndReplace()

	-- notify on count
	if config.notificationOnSuccess then
		local rgCount = runRipgrep { toSearch, "--count-matches" }
		if rgCount.code == 0 then
			local count = tonumber(vim.trim(rgCount.stdout))
			local pluralS = count == 1 and "" or "s"
			u.notify(("Replaced %s occurrence%s."):format(count, pluralS))
		end
	end

	-- substitute
	local rgResult = runRipgrep { toSearch, "--replace=" .. toReplace, "--line-number" }
	if rgResult.code ~= 0 then
		u.notify(rgResult.stderr, "error")
		return
	end

	-- UPDATE LINES
	-- only update individual lines as opposed to whole buffer, as this
	-- preserves folds and marks
	local replacements = vim.split(vim.trim(rgResult.stdout), "\n")
	for _, repl in pairs(replacements) do
		local lineStr, newLine = repl:match("^(%d+):(.*)")
		local lnum = assert(tonumber(lineStr))
		vim.api.nvim_buf_set_lines(state.targetBuf, lnum - 1, lnum, false, { newLine })
	end
end

--------------------------------------------------------------------------------

---@param rgArgs string[]
---@return Iter { lnum: number, col: number, text: string }
local function rgResultsIter(rgArgs)
	local rgResult = runRipgrep(rgArgs)
	if rgResult.code ~= 0 then return vim.iter({}) end -- empty iter on error
	local rgLines = vim.split(vim.trim(rgResult.stdout), "\n")

	local state = require("rip-substitute.state").state
	local viewportStart = vim.fn.line("w0", state.targetWin)
	local viewportEnd = vim.fn.line("w$", state.targetWin)

	return vim.iter(rgLines)
		:filter(function(line) -- PERF only in viewport
			local lnum = tonumber(line:match("^(%d+):"))
			return (lnum >= viewportStart) and (lnum <= viewportEnd)
		end)
		:map(function(line)
			local lnumStr, colStr, text = line:match("^(%d+):(%d+):(.*)")
			return {
				lnum = tonumber(lnumStr) - 1,
				col = tonumber(colStr) - 1,
				text = text,
			}
		end)
end

function M.incrementalPreview()
	local state = require("rip-substitute.state").state
	vim.api.nvim_buf_clear_namespace(state.targetBuf, state.incPreviewNs, 0, -1)
	local toSearch, toReplace = getSearchAndReplace()
	if toSearch == "" then return end

	-- HIGHLIGHT SEARCH MATCHES
	local rgArgs = { toSearch, "--line-number", "--column", "--only-matching" }
	local searchMatchEndCols = {}
	rgResultsIter(rgArgs):each(function(result)
		local endCol = result.col + #result.text
		vim.api.nvim_buf_add_highlight(
			state.targetBuf,
			state.incPreviewNs,
			toReplace == "" and "IncSearch" or "LspInlayHint",
			result.lnum,
			result.col,
			endCol
		)
		-- INFO saving the end columns to correctly position the replacements.
		-- For single files, `rg` gives us results sorted by line & column, so
		-- that we can simply collect them in a list.
		table.insert(searchMatchEndCols, endCol)
	end)

	-- INSERT REPLACEMENTS AS VIRTUAL TEXT
	if toReplace == "" then return end

	vim.list_extend(rgArgs, { "--replace=" .. toReplace })
	rgResultsIter(rgArgs):each(function(result)
		local virtText = { result.text, "IncSearch" }
		local endCol = table.remove(searchMatchEndCols, 1)
		vim.api.nvim_buf_set_extmark(
			state.targetBuf,
			state.incPreviewNs,
			result.lnum,
			endCol,
			{ virt_text = { virtText }, virt_text_pos = "inline" }
		)
	end)
end

--------------------------------------------------------------------------------
return M
