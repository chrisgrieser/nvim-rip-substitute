local M = {}
local u = require("rip-substitute.utils")
--------------------------------------------------------------------------------

---@param toSearch string
---@param toReplace string
---@return { lnum: number, startCol: number, endCol: number, replacement: string }[]?
---@return string? errmsg
local function runRipgrep(toSearch, toReplace)
	local config = require("rip-substitute.config").config
	local targetBufCache = require("rip-substitute.state").targetBufCache
	local state = require("rip-substitute.state").state

	local args = {
		"rg",
		"--no-config",
		"--json",
		"--replace=" .. toReplace,
		config.regexOptions.pcre2 and "--pcre2" or "--no-pcre2",
		state.useFixedStrings and "--fixed-strings" or "--no-fixed-strings",
		state.useIgnoreCase and "--ignore-case" or "--case-sensitive",
		"--no-crlf", -- see #17
		"--",
		toSearch, -- last for escaping, see #26
	}
	if config.debug then u.notify("ARGS\n" .. table.concat(args, " "), "debug") end

	-- reading from stdin instead of the file to deal with unsaved changes and to
	-- be able to handle non-file buffers (see #8)
	local result = vim.system(args, { stdin = targetBufCache }):wait()
	if config.debug then u.notify("RESULT\n" .. result.stdout, "debug") end

	if result.code ~= 0 then
		local errmsg = result.stderr or "Unknown error"
		return nil, errmsg
	end

	-- PARSE MATCHES
	local lines = vim.split(vim.trim(result.stdout or ""), "\n")
	local matches = vim.iter(lines):fold({}, function(acc, jsonLine)
		local o = vim.json.decode(jsonLine)
		if o.type ~= "match" then return acc end -- `start`, `end`, and `summary` jsons
		for _, submatch in ipairs(o.data.submatches) do
			table.insert(acc, {
				lnum = o.data.line_number - 1,
				startCol = submatch.start,
				endCol = submatch["end"],
				replacement = submatch.replacement.text,
			})
		end
		return acc
	end)

	return matches, nil
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

--------------------------------------------------------------------------------

function M.executeSubstitution()
	local state = require("rip-substitute.state").state
	local config = require("rip-substitute.config").config
	local toSearch, toReplace = M.getSearchAndReplaceValuesFromPopup()

	local matches, errmsg = runRipgrep(toSearch, toReplace)
	if errmsg then
		u.notify(errmsg, "error")
		return
	end

	-- Update individual lines as opposed to whole buffer, as this preserves
	-- folds, marks, and exmarks (see #45).
	vim.iter(matches):rev():each(function(m) -- reverse due to shifting
		if state.range and (m.lnum < state.range.start or m.lnum > state.range.end_) then return end
		vim.api.nvim_buf_set_text(
			state.targetBuf,
			m.lnum,
			m.startCol,
			m.lnum,
			m.endCol,
			{ m.replacement }
		)
	end)

	-- notify
	if config.notification.onSuccess then
		local s1 = state.matchCount == 1 and "" or "s"
		local msg = ("Replaced %d occurrence%s."):format(state.matchCount, s1)
		u.notify(msg)
	end
end

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
		u.notify("Newlines in search or replace strings are not supported yet.", "warn")
		return
	end

	-- RUN RIPGREP
	local matches, errmsg = runRipgrep(toSearch, toReplace)
	if not matches or errmsg then return end

	-- REMOVE MATCHES OUTSIDE RANGE
	-- PERF For single files, `rg` gives us results sorted by line number
	-- already, so we can `slice` instead of `filter` to improve performance.
	local rangeStartIdx, rangeEndIdx
	if state.range then
		for i = 1, #matches do
			local lnum = matches[i].lnum + 1 -- this one isn't off-by-one
			local inRange = lnum >= state.range.start and lnum <= state.range.end_
			if rangeStartIdx == nil and inRange then rangeStartIdx = i end
			if rangeStartIdx and lnum > state.range.end_ then
				rangeEndIdx = i - 1
				break
			end
		end
		if rangeStartIdx == nil then return end -- no matches in range
		matches = vim.list_slice(matches, rangeStartIdx, rangeEndIdx)
	end
	state.matchCount = #matches

	-- REMOVE MATCHES OUTSIDE VIEWPORT
	local viewStartIdx, viewEndIdx
	for i = 1, #matches do
		local lnum = matches[i].lnum + 1 -- this one isn't off-by-one
		if not viewStartIdx and lnum >= viewStartLnum and lnum <= viewEndLnum then
			viewStartIdx = i
		end
		if viewStartIdx and lnum > viewEndLnum then
			viewEndIdx = i - 1
			break
		end
	end
	if not viewStartIdx then return end -- no matches in viewport
	if not viewEndIdx then viewEndIdx = #matches end -- viewport is at end of file
	matches = vim.list_slice(matches, viewStartIdx, viewEndIdx)

	-- ADD DECORATIONS
	vim.iter(matches):each(function(match)
		-- ONLY SEARCH -> HIGHLIGHT MATCHES
		if toReplace == "" then
			-- stylua: ignore
			if vim.hl.range then
				vim.hl.range(state.targetBuf, ns, hlGroup, { match.lnum, match.startCol }, { match.lnum, match.endCol })
			else
				---@diagnostic disable-next-line: deprecated --- keep for backwards compatibility
				vim.api.nvim_buf_add_highlight(state.targetBuf, ns, hlGroup, match.lnum, match.startCol, match.endCol)
			end
			return
		end

		-- SEARCH & REPLACE -> HIDE SEARCH, INSERT REPLACE AS VIRTUAL TEXT
		vim.api.nvim_buf_set_extmark(state.targetBuf, ns, match.lnum, match.startCol, {
			conceal = "", -- INFO requires `conceallevel` >= 2
			end_col = match.endCol,
			end_row = match.lnum,
		})

		vim.api.nvim_buf_set_extmark(state.targetBuf, ns, match.lnum, match.endCol, {
			virt_text = {
				{ match.replacement, hlGroup },
			},
			virt_text_pos = "inline",
		})
	end)
end

--------------------------------------------------------------------------------
return M
