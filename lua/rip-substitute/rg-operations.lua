local M = {}
local u = require("rip-substitute.utils")
--------------------------------------------------------------------------------

---@class RipSubstitute.RipgrepMatch
---@field lnum number
---@field startCol number
---@field endCol number
---@field replacement string

---@param toSearch string
---@param toReplace string for `--replace`
---@param glob? string for `--glob`, if not provided runs on current buffer from stdin
---@return table<string, RipSubstitute.RipgrepMatch[]>?
---@return string? errmsg
local function runRipgrep(toSearch, toReplace, glob)
	local config = require("rip-substitute.config").config
	local state = require("rip-substitute.state").state

	local args = {
		"rg",
		"--no-config",
		"--json", -- outputs as json-lines
		"--replace=" .. toReplace,
		config.regexOptions.pcre2 and "--pcre2" or "--no-pcre2",
		state.useFixedStrings and "--fixed-strings" or "--no-fixed-strings",
		state.useIgnoreCase and "--ignore-case" or "--case-sensitive",
		"--no-crlf", -- see #17
		"--",
		toSearch, -- last for escaping, see #26
	}

	local stdin
	if not glob then
		-- reading from stdin instead of the file to deal with unsaved changes and to
		-- be able to handle non-file buffers (see #8)
		stdin = require("rip-substitute.state").targetBufCache
	else
		-- using `--glob=*` results in ignoring gitignored files and even includes
		-- files in `.git` itself; thus we skip the `--glob` arg then to just use
		-- the default behavior
		local globMatchesAll = glob == "*" or glob == "**/*"
		if not globMatchesAll then
			-- insert not at the end, since `--` and searchterm must come last
			table.insert(args, #args - 2, "--glob=" .. glob)
			table.insert(args, #args - 2, "--glob=!.git") -- just extra safety net
		end
	end
	if config.debug then u.notify("ARGS\n" .. table.concat(args, " "), "debug") end

	-- RUN
	local result = vim.system(args, { stdin = stdin }):wait()
	if config.debug then u.notify("RESULT\n" .. result.stdout, "debug") end
	if result.code ~= 0 then
		local errmsg = result.stderr or "Unknown error"
		return nil, errmsg
	end

	-- PARSE MATCHES
	local jsonLines = vim.split(vim.trim(result.stdout or ""), "\n")
	local matches = vim.iter(jsonLines):fold({}, function(acc, jsonLine)
		local o = vim.json.decode(jsonLine)
		if o.type ~= "match" then return acc end -- `start`, `end`, and `summary` jsons
		local relPath = o.data.path.text
		acc[relPath] = acc[relPath] or {}
		for _, submatch in ipairs(o.data.submatches) do
			table.insert(acc[relPath], {
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

---@param successCallback function
function M.substituteInBuffer(successCallback)
	local state = require("rip-substitute.state").state
	local config = require("rip-substitute.config").config
	local toSearch, toReplace = M.getSearchAndReplaceValuesFromPopup()

	local matches, errmsg = runRipgrep(toSearch, toReplace)
	if not matches then
		u.notify(errmsg or "Unknown error", "error")
		return
	end
	local matchesInBuf = vim.tbl_values(matches)[1] --[=[@as RipSubstitute.RipgrepMatch[]]=]

	vim.iter(matchesInBuf):rev():each(function(m) -- reverse due to shifting
		local outsideRange = state.range
			and (m.lnum + 1 < state.range.start or m.lnum + 1 > state.range.end_) -- range not off-by-one
		if outsideRange then return end

		-- Update individual sections as opposed to whole buffer, as this preserves
		-- folds, marks, and exmarks (see #45).
		vim.api.nvim_buf_set_text(
			state.targetBuf,
			m.lnum,
			m.startCol,
			m.lnum,
			m.endCol,
			{ m.replacement }
		)
	end)
	successCallback()

	-- notify
	if config.notification.onSuccess then
		local s = #matchesInBuf == 1 and "" or "s"
		local msg = ("Replaced %d occurrence%s in the buffer."):format(state.matchCount, s)
		u.notify(msg)
	end
end

---@param successCallback function
function M.substituteInCwd(successCallback)
	local state = require("rip-substitute.state").state
	if vim.bo[state.targetBuf].buftype ~= "" then
		u.notify("Cannot substitute in the whole cwd from a special buffer.", "warn")
		return
	elseif state.range then
		u.notify("Cannot substitute in the whole cwd when using a range.", "warn")
		return
	end

	local filename = vim.fs.basename(vim.api.nvim_buf_get_name(state.targetBuf))
	local ext = filename:match("%.%w+$") or ""
	local defaultGlob = "**/*" .. ext
	local prompt = "Substitute in cwd with --glob= "

	vim.ui.input({ prompt = prompt, default = defaultGlob }, function(input)
		if not input or input == "" then return end

		-- RUN
		local glob = input
		local toSearch, toReplace = M.getSearchAndReplaceValuesFromPopup()
		local matches, errmsg = runRipgrep(toSearch, toReplace, glob)
		if not matches then
			u.notify(errmsg or "Unknown error", "error")
			return
		end

		-- REPLACE IN ALL FILES
		local cwd = assert(vim.uv.cwd(), "Could not determine cwd.")
		local updateCount = 0
		for relpath, matchesInFile in pairs(matches) do
			local edits = vim
				.iter(matchesInFile)
				:rev() -- reverse due to shifting
				:map(function(match) ---@cast match RipSubstitute.RipgrepMatch
					local textEdit = { ---@type lsp.TextEdit
						newText = match.replacement,
						range = {
							start = { line = match.lnum, character = match.startCol },
							["end"] = { line = match.lnum, character = match.endCol },
						},
					}
					return textEdit
				end)
				:totable()

			local textDocumentEdits = { ---@type lsp.TextDocumentEdit
				textDocument = { uri = vim.uri_from_fname(cwd .. "/" .. relpath) },
				edits = edits,
			}

			-- LSP-API is the easiest method for replacing in non-open documents
			vim.lsp.util.apply_text_document_edit(textDocumentEdits, nil, vim.o.encoding)

			updateCount = updateCount + #matchesInFile
		end
		vim.cmd("silent! wall") -- save all changes
		successCallback()

		-- NOTIFY
		local config = require("rip-substitute.config").config
		if config.notification.onSuccess then
			local files = vim.tbl_keys(matches)
			local s1 = updateCount == 1 and "" or "s"
			local s2 = #files == 1 and "" or "s"
			local msg = ("Replaced %d occurrence%s in %d file%s."):format(updateCount, s1, #files, s2)
				.. "\n* "
				.. table.concat(files, "\n* ")
			u.notify(msg)
		end
	end)
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
	local matchesInBuf = vim.tbl_values(matches)[1] --[=[@as RipSubstitute.RipgrepMatch[]]=]

	-- REMOVE MATCHES OUTSIDE RANGE
	-- PERF For single files, `rg` gives us results sorted by line number
	-- already, so we can `slice` instead of `filter` to improve performance.
	local rangeStartIdx, rangeEndIdx
	if state.range then
		for i = 1, #matchesInBuf do
			local lnum = matchesInBuf[i].lnum + 1 -- this one isn't off-by-one
			local inRange = lnum >= state.range.start and lnum <= state.range.end_
			if rangeStartIdx == nil and inRange then rangeStartIdx = i end
			if rangeStartIdx and lnum > state.range.end_ then
				rangeEndIdx = i - 1
				break
			end
		end
		if rangeStartIdx == nil then return end -- no matches in range
		matchesInBuf = vim.list_slice(matchesInBuf, rangeStartIdx, rangeEndIdx)
	end
	state.matchCount = #matchesInBuf

	-- REMOVE MATCHES OUTSIDE VIEWPORT
	local viewStartIdx, viewEndIdx
	for i = 1, #matchesInBuf do
		local lnum = matchesInBuf[i].lnum + 1 -- this one isn't off-by-one
		if not viewStartIdx and lnum >= viewStartLnum and lnum <= viewEndLnum then
			viewStartIdx = i
		end
		if viewStartIdx and lnum > viewEndLnum then
			viewEndIdx = i - 1
			break
		end
	end
	if not viewStartIdx then return end -- no matches in viewport
	if not viewEndIdx then viewEndIdx = #matchesInBuf end -- viewport is at end of file
	matchesInBuf = vim.list_slice(matchesInBuf, viewStartIdx, viewEndIdx)

	-- ADD DECORATIONS
	vim.iter(matchesInBuf):each(function(match)
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
