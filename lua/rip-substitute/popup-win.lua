local M = {}
local u = require("rip-substitute.utils")
--------------------------------------------------------------------------------

---@nodiscard
---@return string[]
local function getPopupLines()
	local state = require("rip-substitute.state").state
	return vim.api.nvim_buf_get_lines(state.popupBufNr, 0, -1, true)
end

---Adds `Search` and `Replace` as labels to the popup window, if there is enough
---space in the popup window, i.e., the current content will not overlap with it.
---@param popupWidth number
local function setPopupLabelsIfEnoughSpace(popupWidth)
	local hide = require("rip-substitute.config").config.popupWin.hideSearchReplaceLabels
	if hide then return end

	local state = require("rip-substitute.state").state
	local ns = vim.api.nvim_create_namespace("rip-substitute.labels")
	vim.api.nvim_buf_clear_namespace(state.popupBufNr, ns, 0, -1)

	local popupLines = getPopupLines()
	local labels = { " Search", "Replace" }
	for i = 1, 2 do
		local contentOverlapsLabel = #popupLines[i] >= (popupWidth - #labels[i])
		if not contentOverlapsLabel then
			vim.api.nvim_buf_set_extmark(state.popupBufNr, ns, i - 1, 0, {
				virt_text = { { labels[i], "DiagnosticVirtualTextInfo" } },
				virt_text_pos = "right_align",
			})
		end
	end
end

local function ensureOnly2LinesInPopup()
	local state = require("rip-substitute.state").state
	local lines = getPopupLines()
	if #lines == 2 then return end
	if #lines == 1 then
		lines[2] = ""
	elseif #lines > 2 then
		if lines[1] == "" then table.remove(lines, 1) end
		if lines[3] and lines[2] == "" then table.remove(lines, 2) end
	end
	vim.api.nvim_buf_set_lines(state.popupBufNr, 0, -1, true, { lines[1], lines[2] })
	vim.cmd.normal { "zb", bang = true } -- enforce scroll position
end

local function closePopupWin()
	local state = require("rip-substitute.state").state

	-- empty cache (relevant for larger buffers)
	require("rip-substitute.state").targetBufCache = ""

	-- history: save last popup content for next run
	local lastPopupContent = state.popupPresentContent or getPopupLines()
	state.popupPresentContent = nil
	local isDuplicate = vim.deep_equal(state.popupHistory[#state.popupHistory], lastPopupContent)
	local empty = vim.trim(lastPopupContent[1]) == "" and vim.trim(lastPopupContent[2]) == ""
	if not isDuplicate and not empty then table.insert(state.popupHistory, lastPopupContent) end

	-- close popup win and buffer
	if vim.api.nvim_win_is_valid(state.popupWinNr) then
		vim.api.nvim_win_close(state.popupWinNr, true)
	end
	if vim.api.nvim_buf_is_valid(state.popupBufNr) then
		vim.api.nvim_buf_delete(state.popupBufNr, { force = true })
	end
	local ns = vim.api.nvim_create_namespace("rip-substitute.incPreview")
	vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)
end

local function confirmSubstitution()
	local state = require("rip-substitute.state").state

	-- block confirmation if no matches
	-- (matchcount is also set to `0` when search or replace string is invalid)
	if state.matchCount == 0 then return end

	require("rip-substitute.rg-operations").executeSubstitution()
	closePopupWin()
	vim.cmd.stopinsert()
end

local function updateMatchCount()
	local state = require("rip-substitute.state").state
	local config = require("rip-substitute.config").config
	local matchHlGroup = config.popupWin.matchCountHlGroup
	local noMatchHlGroup = config.popupWin.noMatchHlGroup

	local currentFooter = vim.api.nvim_win_get_config(state.popupWinNr).footer
	local keymapHint = currentFooter[#currentFooter]

	local plural = state.matchCount == 1 and "" or "es"
	local matchText = (" %d match%s "):format(state.matchCount, plural)
	local matchHighlight = state.matchCount > 0 and matchHlGroup or noMatchHlGroup

	vim.api.nvim_win_set_config(state.popupWinNr, {
		footer = {
			{ matchText, matchHighlight },
			keymapHint,
		},
	})
end

local function autoCaptureGroups()
	-- GUARD
	local state = require("rip-substitute.state").state
	local cursorInSearchLine = vim.api.nvim_win_get_cursor(state.popupWinNr)[1] == 1
	local featureEnabled = require("rip-substitute.config").config.editingBehavior.autoCaptureGroups
	if not featureEnabled or not cursorInSearchLine or state.useFixedStrings then return end

	local toSearch, toReplace = unpack(getPopupLines())
	local _, closeParenCount = toSearch:gsub("[^\\]%)", "")
	local _, openParenCount1 = toSearch:gsub("^%([^)]", "")
	local _, openParenCount2 = toSearch:gsub("[^\\]%([^)]", "")
	local openParenCount = openParenCount1 + openParenCount2
	local countOfBalancedParens = math.min(openParenCount, closeParenCount)

	local captureCount = 0
	for n = 1, countOfBalancedParens do
		local hasGroupN = toReplace:match("%$" .. n) or toReplace:match("%{" .. n .. "}")
		if not hasGroupN then break end
		captureCount = n
	end

	if captureCount < countOfBalancedParens then
		local newReplaceLine = toReplace .. "$" .. (captureCount + 1)
		vim.api.nvim_buf_set_lines(state.popupBufNr, 1, 2, false, { newReplaceLine })
	end
end

---@param minWidth integer
local function adaptivePopupWidth(minWidth)
	local state = require("rip-substitute.state").state
	local currentOpts = vim.api.nvim_win_get_config(state.popupWinNr)
	local searchLine, replaceLine = unpack(getPopupLines())
	local longestLine = math.max(#searchLine, #replaceLine)
	local newWidth = math.max(longestLine + 2, minWidth) -- + 2 for win borders
	local diff = newWidth - currentOpts.width
	if diff ~= 0 then vim.api.nvim_win_set_config(state.popupWinNr, { width = newWidth }) end
	setPopupLabelsIfEnoughSpace(newWidth)
end

---Adds two dummy-windows with `blend` to achieve a backdrop-like effect before
---and after the range.
---@param popupZindex integer
local function rangeBackdrop(popupZindex)
	local opts = require("rip-substitute.config").config.incrementalPreview.rangeBackdrop
	local state = require("rip-substitute.state").state
	if not opts.enabled or not state.range then return end

	-- pause folds for the duration of the substitution, since they mess up the
	-- calculation of the size of the cover windows
	vim.wo[state.targetWin].foldenable = false
	vim.api.nvim_create_autocmd("BufLeave", {
		once = true,
		buffer = state.popupBufNr,
		callback = function() vim.wo[state.targetWin].foldenable = true end,
	})

	local viewStart, viewEnd = u.getViewport()
	local rangeStart, rangeEnd = state.range.start, state.range.end_
	local offset = viewStart
	local cover = { {}, {} }

	cover[1].start = viewStart
	cover[1].relStart = cover[1].start - offset
	cover[1].height = rangeStart - viewStart

	cover[2].start = rangeEnd + 1
	cover[2].relStart = cover[2].start - offset
	cover[2].height = viewEnd - rangeEnd

	for i = 1, 2 do
		local height = cover[i].height
		local relStart = cover[i].relStart
		-- if height is negative, the range starts/ends before/after the
		-- viewport, so we do not need that half of the cover
		if height > 0 then
			local buf = vim.api.nvim_create_buf(false, true)
			local win = vim.api.nvim_open_win(buf, false, {
				relative = "win",
				win = state.targetWin,
				row = relStart,
				col = 0,
				focusable = false,
				width = vim.api.nvim_win_get_width(state.targetWin),
				height = height,
				style = "minimal",
				zindex = popupZindex - 1, -- so the popup stays on top
			})
			vim.api.nvim_set_hl(0, "RipSubBackdrop", { bg = "#000000", default = true })
			vim.wo[win].winhighlight = "Normal:RipSubBackdrop"
			vim.wo[win].winblend = opts.blend
			vim.bo[buf].buftype = "nofile"

			-- remove range cover when done
			vim.api.nvim_create_autocmd("BufLeave", {
				once = true,
				buffer = state.popupBufNr,
				callback = function()
					if win and vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
					if buf and vim.api.nvim_buf_is_valid(buf) then
						vim.api.nvim_buf_delete(buf, { force = true })
					end
				end,
			})
		end
	end
end

local function setPopupTitle()
	local state = require("rip-substitute.state").state
	local config = require("rip-substitute.config").config

	local title
	if state.useIgnoreCase or state.useFixedStrings then
		title = ""
		title = state.useFixedStrings and title .. " --fixed-strings" or title
		title = state.useIgnoreCase and title .. " --ignore-case" or title
		title = vim.trim(title)
	elseif state.range then
		title = "Range: " .. state.range.start
		if state.range.start ~= state.range.end_ then title = title .. " – " .. state.range.end_ end
	else
		title = config.popupWin.title
	end

	if title ~= "" then title = " " .. title .. " " end
	vim.api.nvim_win_set_config(state.popupWinNr, { title = title })
end

local function createKeymaps()
	local keymaps = require("rip-substitute.config").config.keymaps
	local state = require("rip-substitute.state").state
	local opts = { buffer = state.popupBufNr, nowait = true }

	-- confirm & abort
	vim.keymap.set({ "n", "x" }, keymaps.abort, closePopupWin, opts)
	vim.keymap.set({ "n", "x" }, keymaps.confirm, confirmSubstitution, opts)
	vim.keymap.set("i", keymaps.insertModeConfirm, confirmSubstitution, opts)

	-- regex101
	vim.keymap.set(
		{ "n", "x" },
		keymaps.openAtRegex101,
		function() require("rip-substitute.open-at-regex101").request() end,
		opts
	)

	-- history keymaps
	state.historyPosition = #state.popupHistory + 1
	vim.keymap.set({ "n", "x" }, keymaps.prevSubst, function()
		if state.historyPosition < 2 then return end
		if state.historyPosition == #state.popupHistory + 1 then
			state.popupPresentContent = vim.api.nvim_buf_get_lines(state.popupBufNr, 0, -1, true)
		end
		state.historyPosition = state.historyPosition - 1
		local content = state.popupHistory[state.historyPosition]
		vim.api.nvim_buf_set_lines(state.popupBufNr, 0, -1, false, content)
	end, opts)
	vim.keymap.set({ "n", "x" }, keymaps.nextSubst, function()
		if state.historyPosition == #state.popupHistory + 1 then return end -- already at present
		state.historyPosition = state.historyPosition + 1
		local content = state.historyPosition == #state.popupHistory + 1 and state.popupPresentContent
			or state.popupHistory[state.historyPosition]
		vim.api.nvim_buf_set_lines(state.popupBufNr, 0, -1, false, content)
	end, opts)

	-- toggle fixed strings
	vim.keymap.set({ "n", "x" }, keymaps.toggleFixedStrings, function()
		state.useFixedStrings = not state.useFixedStrings
		require("rip-substitute.rg-operations").incrementalPreviewAndMatchCount()
		updateMatchCount()
		setPopupTitle()
	end, opts)

	-- toggle case sensitive
	vim.keymap.set({ "n", "x" }, keymaps.toggleIgnoreCase, function()
		state.useIgnoreCase = not state.useIgnoreCase
		require("rip-substitute.rg-operations").incrementalPreviewAndMatchCount()
		updateMatchCount()
		setPopupTitle()
	end, opts)
end

-- 1. display base keymaps on first run, and advanced keymaps on subsequent runs
-- 2. shorten them as much as possible, to keep the popup width small
---@return string
---@nodiscard
local function initialKeymapHints()
	local m = require("rip-substitute.config").config.keymaps
	local state = require("rip-substitute.state").state

	local keymapHint = ("%s confirm  %s abort"):format(m.confirm, m.abort)
	if #state.popupHistory > 0 then
		keymapHint = #state.popupHistory % 2 == 0
				and ("%s fixed  %s case"):format(m.toggleFixedStrings, m.toggleIgnoreCase)
			or ("%s/%s history  %s regex101"):format(m.prevSubst, m.nextSubst, m.openAtRegex101)
	end
	keymapHint = keymapHint -- using only utf symbols, so they work w/o nerd fonts
		:gsub("<[Cc][Rr]>", "↩")
		:gsub("<[dD]own>", "↓")
		:gsub("<[Uu]p>", "↑")
		:gsub("<[Rr]ight>", "→")
		:gsub("<[Ll]eft>", "←")
		:gsub("<[Tt]ab>", "↹ ")
		:gsub("<[Ss]pace>", "⎵")
		:gsub("<[Bb][Ss]>", "⌫")
		:gsub("<[Cc]%-(.)>", function(char) return "⌃" .. char:upper() end)
		:gsub("<[Mm]%-(.)>", function(char) return "⌥" .. char:upper() end)
		:gsub("<[Dd]%-(.)>", function(char) return "⌘" .. char:upper() end) -- D-key -> macOS cmd key
		:gsub(" (%a) ", " %1: ") -- add colon for single letters, so it's clear it's a keymap
		:gsub("^(%a) ", "%1: ")
	return keymapHint
end

-- temporarily set conceal, so the incremental preview hides characters correctly
local function temporarilySetConceal()
	local state = require("rip-substitute.state").state
	local previousConceal = vim.wo[state.targetWin].conceallevel
	if previousConceal < 2 then
		vim.wo[state.targetWin].conceallevel = 2
		vim.api.nvim_create_autocmd("BufLeave", {
			once = true,
			buffer = state.popupBufNr,
			callback = function() vim.wo[state.targetWin].conceallevel = previousConceal end,
		})
	end
end

--------------------------------------------------------------------------------

function M.openSubstitutionPopup()
	local state = require("rip-substitute.state").state
	local config = require("rip-substitute.config").config

	-- CREATE BUFFER
	state.popupBufNr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(state.popupBufNr, 0, -1, false, state.prefill)
	vim.api.nvim_buf_set_name(state.popupBufNr, config.popupWin.title)
	pcall(vim.treesitter.start, state.popupBufNr, "regex")
	vim.bo[state.popupBufNr].filetype = "rip-substitute"

	-- FOOTER & WIDTH
	local keymapHint = initialKeymapHints()
	-- 11 for "234 matches" + 4 for border & padding of footer
	local minWidth = vim.api.nvim_strwidth(keymapHint) + 11 + 4

	-- CREATE WINDOW
	local popupZindex = 49 -- below nvim-notify (50), above scrollbars (satellite uses 40)
	state.popupWinNr = vim.api.nvim_open_win(state.popupBufNr, true, {
		relative = "win",
		anchor = config.popupWin.position == "top" and "NE" or "SE",
		row = config.popupWin.position == "top" and 0 or vim.api.nvim_win_get_height(0),
		col = vim.api.nvim_win_get_width(0),
		width = minWidth,
		height = 2,

		style = "minimal",
		border = config.popupWin.border,
		zindex = popupZindex,
		footer = {
			{ " " .. keymapHint .. " ", "FloatBorder" },
		},
	})
	local win = state.popupWinNr
	vim.wo[win].list = true
	vim.wo[win].listchars = "multispace:·,trail:·,lead:·,tab:▸▸,precedes:…,extends:…"
	vim.wo[win].signcolumn = "no"
	vim.wo[win].scrolloff = 0
	vim.wo[win].sidescrolloff = 0 -- no need for scrolloff, since window is dynamically resized
	vim.wo[win].winfixbuf = true

	-- CURSOR PLACEMENT
	if config.prefill.startInReplaceLineIfPrefill and state.prefill[1] ~= "" then
		vim.api.nvim_win_set_cursor(state.popupWinNr, { 2, 0 })
	end
	vim.cmd.startinsert { bang = true }

	-- WINDOW LOOK AND BEHAVIOR
	createKeymaps()
	setPopupTitle()
	setPopupLabelsIfEnoughSpace(minWidth)
	rangeBackdrop(popupZindex)
	temporarilySetConceal()

	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		buffer = state.popupBufNr,
		group = vim.api.nvim_create_augroup("rip-substitute-popup-changes", {}),
		callback = function()
			ensureOnly2LinesInPopup()
			autoCaptureGroups()
			adaptivePopupWidth(minWidth)

			require("rip-substitute.rg-operations").incrementalPreviewAndMatchCount()
			updateMatchCount()
		end,
	})

	-- INFO this autocmd needs to come at the end, since autocmds of the same
	-- type are triggered in order of their definition, and this autocmd running
	-- before other `BufLeave` autocmds prevents their execution for some reason
	-- not entirely clear to me.
	vim.api.nvim_create_autocmd("BufLeave", {
		once = true,
		buffer = state.popupBufNr,
		group = vim.api.nvim_create_augroup("rip-substitute-popup-leave", {}),
		-- close the popup on leaving buffer, ensures there is not leftover
		-- buffer when user closes popup in a different way, such as `:close`.
		callback = closePopupWin,
	})
end

--------------------------------------------------------------------------------
return M
