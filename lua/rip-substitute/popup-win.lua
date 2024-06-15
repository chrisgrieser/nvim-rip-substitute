local M = {}
local u = require("rip-substitute.utils")
--------------------------------------------------------------------------------

---@return string[]
local function getPopupLines()
	local state = require("rip-substitute.state").state
	return vim.api.nvim_buf_get_lines(state.popupBufNr, 0, -1, true)
end

---Adds `Search` and `Replace` as labels to the popup window, if there is enough
---space in the popup window, i.e., the current content will not overlap with it.
---@param popupWidth number
local function setPopupLabelsIfEnoughSpace(popupWidth)
	local config = require("rip-substitute.config").config
	if config.popupWin.hideSearchReplaceLabels then return end
	local state = require("rip-substitute.state").state
	vim.api.nvim_buf_clear_namespace(state.popupBufNr, state.labelNs, 0, -1)

	local popupLines = getPopupLines()
	local labels = { " Search", "Replace" }
	for i = 1, 2 do
		local contentOverlapsLabel = #popupLines[i] >= (popupWidth - #labels[i])
		if not contentOverlapsLabel then
			vim.api.nvim_buf_set_extmark(state.popupBufNr, state.labelNs, i - 1, 0, {
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

	-- save last popup content for next run
	local lastPopupContent = state.popupPresentContent or getPopupLines()
	state.popupPresentContent = nil
	local isDuplicate = vim.deep_equal(state.popupHistory[#state.popupHistory], lastPopupContent)
	if not isDuplicate then table.insert(state.popupHistory, lastPopupContent) end

	-- close popup win and buffer
	if vim.api.nvim_win_is_valid(state.popupWinNr) then
		vim.api.nvim_win_close(state.popupWinNr, true)
	end
	if vim.api.nvim_buf_is_valid(state.popupBufNr) then
		vim.api.nvim_buf_delete(state.popupBufNr, { force = true })
	end
	vim.api.nvim_buf_clear_namespace(0, state.incPreviewNs, 0, -1)
end

---@param numOfMatches number
local function updateMatchCount(numOfMatches)
	local config = require("rip-substitute.config").config
	local state = require("rip-substitute.state").state
	local currentFooter = vim.deepcopy(vim.api.nvim_win_get_config(state.popupWinNr).footer)
	local keymapHint = table.remove(currentFooter)
	local updatedFooter = { keymapHint }

	if numOfMatches > 0 then
		local plural = numOfMatches == 1 and "" or "es"
		local matchText = (" %s match%s "):format(numOfMatches, plural)
		local hlGroup = config.popupWin.matchCountHlGroup
		local matchSegment = numOfMatches > 0 and { matchText, hlGroup } or nil
		table.insert(updatedFooter, 1, matchSegment)
	end

	vim.api.nvim_win_set_config(state.popupWinNr, { footer = updatedFooter })
end

local function autoCaptureGroups()
	local state = require("rip-substitute.state").state
	local toSearch, toReplace = unpack(getPopupLines())

	local _, openParenCount = toSearch:gsub("%)", "")
	local _, closeParenCount = toSearch:gsub("%([^?)]", "")
	local balancedCount = math.min(openParenCount, closeParenCount)

	local captureCount = 0
	for n = 1, balancedCount do
		local hasGroupN = toReplace:match("%$" .. n) or toReplace:match("%{" .. n .. "}")
		if not hasGroupN then break end
		captureCount = n
	end

	if captureCount < balancedCount then
		local newReplaceLine = toReplace .. "$" .. (captureCount + 1)
		vim.api.nvim_buf_set_lines(state.popupBufNr, 1, 2, false, { newReplaceLine })
	end
end

---@param minWidth integer
---@return integer newWidth
local function adaptivePopupWidth(minWidth)
	local state = require("rip-substitute.state").state
	local currentOpts = vim.api.nvim_win_get_config(state.popupWinNr)
	local lineLength = #vim.api.nvim_get_current_line() + 2 -- +2 for the border
	local newWidth = math.max(lineLength, minWidth)
	local diff = newWidth - currentOpts.width
	if diff ~= 0 then
		vim.api.nvim_win_set_config(state.popupWinNr, {
			win = state.targetWin,
			relative = currentOpts.relative,
			row = currentOpts.row,
			col = currentOpts.col - diff,
			width = newWidth,
		})
	end
	return newWidth
end

---Adds two dummy-windows with `blend` to achieve a backdrop-like effect before
---and after the range.
---@param popupZindex integer
local function setupViewOfRange(popupZindex)
	local conf = require("rip-substitute.config").config.incrementalPreview.rangeBackdrop
	local state = require("rip-substitute.state").state
	if not conf.enabled or not state.range then return end

	local blend = conf.blend
	local buf, win, height, row = {}, {}, {}, {}

	local viewStart, viewEnd = u.getViewport()
	local relViewStart = 0
	local relViewEnd = viewEnd - viewStart
	local relRangeStart = state.range.start - viewStart
	local relRangeEnd = state.range.end_ - viewStart
	row[1] = relViewStart
	height[1] = relRangeStart + 1
	row[2] = relRangeEnd + 2
	height[2] = relViewEnd - relRangeEnd + 1

	for i = 1, 2 do
		-- if height is negative or zero, the range starts/ends before/after the
		-- viewport, so we do not need that half of the cover
		if height[i] > 1 then
			buf[i] = vim.api.nvim_create_buf(false, true)
			win[i] = vim.api.nvim_open_win(buf[i], false, {
				relative = "editor",
				row = row[i],
				col = 0,
				focusable = false,
				width = vim.api.nvim_win_get_width(state.targetWin),
				height = height[i],
				style = "minimal",
				zindex = popupZindex - 1, -- so the popup stays on top
			})
			vim.api.nvim_set_hl(0, "RipSubBackdrop", { bg = "#000000", default = true })
			vim.wo[win[i]].winhighlight = "Normal:RipSubBackdrop"
			vim.wo[win[i]].winblend = blend
			vim.bo[buf[i]].buftype = "nofile"
		end
	end

	-- remove range covers when done
	vim.api.nvim_create_autocmd("BufLeave", {
		once = true,
		buffer = state.popupBufNr,
		callback = function()
			for i = 1, 2 do
				if win[i] and vim.api.nvim_win_is_valid(win[i]) then
					vim.api.nvim_win_close(win[i], true)
				end
				if buf[i] and vim.api.nvim_buf_is_valid(buf[i]) then
					vim.api.nvim_buf_delete(buf[i], { force = true })
				end
			end
		end,
	})
end

--------------------------------------------------------------------------------

---@param prefill string
function M.openSubstitutionPopup(prefill)
	local rg = require("rip-substitute.rg-operations")
	local state = require("rip-substitute.state").state
	local config = require("rip-substitute.config").config

	-- CREATE BUFFER
	state.popupBufNr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(state.popupBufNr, 0, -1, false, { prefill, "" })
	vim.api.nvim_buf_set_name(state.popupBufNr, "rip-substitute")
	pcall(vim.treesitter.start, state.popupBufNr, "regex")
	vim.api.nvim_set_option_value("filetype", "rip-substitute", { buf = state.popupBufNr })

	-- FOOTER & WIDTH
	local maps = config.keymaps
	local suffix = #state.popupHistory == 0 and ("%s Abort"):format(maps.abort)
		or ("%s/%s Prev/Next"):format(maps.prevSubst, maps.nextSubst)
	local keymapHint = maps.confirm .. " Confirm  " .. suffix
	keymapHint = keymapHint -- using only utf symbols, so they work w/o nerd fonts
		:gsub("<[Cc][Rr]>", "↩")
		:gsub("<[dD]own>", "↓")
		:gsub("<[Uu]p>", "↑")
		:gsub("<[Rr]ight>", "→")
		:gsub("<[Ll]eft>", "←")
		:gsub("<[Tt]ab>", "⭾ ")
		:gsub("<[Ss]pace>", "⎵")
		:gsub("<[Bb][Ss]>", "⌫")
	-- 11 for "234 matches" + 4 for border & footer padding
	local minWidth = vim.api.nvim_strwidth(keymapHint) + 11 + 4

	local title = state.range and ("Range: L%d – L%d"):format(state.range.start, state.range.end_)
		or " rip-substitute"

	-- CREATE WINDOW
	local offsetScrollbar = 2
	local offsetStatuslines = 3
	local popupZindex = 2 -- below nvim-notify
	state.popupWinNr = vim.api.nvim_open_win(state.popupBufNr, true, {
		-- window at bottom right
		relative = "win",
		row = vim.api.nvim_win_get_height(0) - 1 - offsetStatuslines,
		col = vim.api.nvim_win_get_width(0) - 1 - minWidth - offsetScrollbar,
		width = minWidth,
		height = 2,

		style = "minimal",
		border = config.popupWin.border,
		title = " " .. title .. " ",
		zindex = popupZindex,
		footer = {
			{ " " .. keymapHint .. " ", "FloatBorder" },
		},
	})
	local winOpts = {
		list = true,
		listchars = "multispace:·,trail:·,lead:·,tab:▸▸,precedes:…,extends:…",
		signcolumn = "no",
		sidescrolloff = 0, -- no need, since we dynamically resize the window
		scrolloff = 0,
		winfixbuf = true,
	}
	for opt, value in pairs(winOpts) do
		vim.api.nvim_set_option_value(opt, value, { win = state.popupWinNr })
	end
	vim.cmd.startinsert { bang = true }

	-- LABELS, MATCH-HIGHLIGHTS, AND STATIC WINDOW
	local viewStartLn, viewEndLn = u.getViewport()
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		buffer = state.popupBufNr,
		group = vim.api.nvim_create_augroup("rip-substitute-popup-changes", {}),
		callback = function()
			ensureOnly2LinesInPopup()
			local count = rg.incrementalPreviewAndMatchCount(viewStartLn, viewEndLn) or 0
			updateMatchCount(count)
			if config.editingBehavior.autoCaptureGroups then autoCaptureGroups() end
			local newWidth = adaptivePopupWidth(minWidth)
			setPopupLabelsIfEnoughSpace(newWidth) -- should be last
		end,
	})
	setPopupLabelsIfEnoughSpace(minWidth)
	setupViewOfRange(popupZindex)

	-- KEYMAPS & POPUP CLOSING
	local opts = { buffer = state.popupBufNr, nowait = true }
	vim.keymap.set({ "n", "x" }, config.keymaps.abort, closePopupWin, opts)
	vim.keymap.set({ "n", "x" }, config.keymaps.confirm, function()
		rg.executeSubstitution()
		closePopupWin()
	end, opts)
	vim.keymap.set("i", config.keymaps.insertModeConfirm, function()
		rg.executeSubstitution()
		closePopupWin()
		vim.cmd.stopinsert()
	end, opts)

	state.historyPosition = #state.popupHistory + 1
	vim.keymap.set({ "n", "x" }, config.keymaps.prevSubst, function()
		if state.historyPosition < 2 then return end
		if state.historyPosition == #state.popupHistory + 1 then
			state.popupPresentContent = vim.api.nvim_buf_get_lines(state.popupBufNr, 0, -1, true)
		end
		state.historyPosition = state.historyPosition - 1
		local content = state.popupHistory[state.historyPosition]
		vim.api.nvim_buf_set_lines(state.popupBufNr, 0, -1, false, content)
	end, opts)
	vim.keymap.set({ "n", "x" }, config.keymaps.nextSubst, function()
		if state.historyPosition == #state.popupHistory + 1 then return end -- already at present
		state.historyPosition = state.historyPosition + 1
		local content = state.historyPosition == #state.popupHistory + 1 and state.popupPresentContent
			or state.popupHistory[state.historyPosition]
		vim.api.nvim_buf_set_lines(state.popupBufNr, 0, -1, false, content)
	end, opts)

	-- also close the popup on leaving buffer, ensures there is not leftover
	-- buffer when user closes popup in a different way, such as `:close`.
	vim.api.nvim_create_autocmd("BufLeave", {
		buffer = state.popupBufNr,
		group = vim.api.nvim_create_augroup("rip-substitute-popup-leave", {}),
		callback = closePopupWin,
	})
end

--------------------------------------------------------------------------------
return M
