local M = {}
--------------------------------------------------------------------------------

local function setPopupLabels()
	local state = require("rip-substitute.state").state
	vim.api.nvim_buf_clear_namespace(state.popupBufNr, state.labelNs, 0, -1)
	vim.api.nvim_buf_set_extmark(state.popupBufNr, state.labelNs, 0, 0, {
		virt_text = { { " Search", "DiagnosticVirtualTextInfo" } },
		virt_text_pos = "right_align",
	})
	vim.api.nvim_buf_set_extmark(state.popupBufNr, state.labelNs, 1, 0, {
		virt_text = { { "Replace", "DiagnosticVirtualTextInfo" } },
		virt_text_pos = "right_align",
	})
end

local function ensureOnly2LinesInPopup()
	local state = require("rip-substitute.state").state
	local lines = vim.api.nvim_buf_get_lines(state.popupBufNr, 0, -1, true)
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
	local lastPopupContent = vim.api.nvim_buf_get_lines(state.popupBufNr, 0, -1, true)
	local duplicate = vim.deep_equal(state.popupHistory[#state.popupHistory], lastPopupContent)
	if not duplicate then table.insert(state.popupHistory, lastPopupContent) end

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
	local state = require("rip-substitute.state").state
	local currentFooter = vim.deepcopy(vim.api.nvim_win_get_config(state.popupWinNr).footer)
	local keymapHint = table.remove(currentFooter)
	local footer = { keymapHint }

	if numOfMatches > 0 then
		local plural = numOfMatches == 1 and "" or "es"
		local matchText = (" %s match%s "):format(numOfMatches, plural)
		local matchSegment = numOfMatches > 0 and { matchText, "Keyword" } or nil
		table.insert(footer, 1, matchSegment)
	end

	vim.api.nvim_win_set_config(state.popupWinNr, {
		footer = footer,
	})
end

--------------------------------------------------------------------------------

function M.openSubstitutionPopup()
	-- IMPORTS & INITIALIZATION
	local rg = require("rip-substitute.rg-operations")
	local config = require("rip-substitute.config").config
	require("rip-substitute.state").update {
		targetBuf = vim.api.nvim_get_current_buf(),
		targetWin = vim.api.nvim_get_current_win(),
		labelNs = vim.api.nvim_create_namespace("rip-substitute-labels"),
		incPreviewNs = vim.api.nvim_create_namespace("rip-substitute-incpreview"),
		targetFile = vim.api.nvim_buf_get_name(0),
	}
	local state = require("rip-substitute.state").state

	-- PREFILL
	local prefill = ""
	local mode = vim.fn.mode()
	if mode == "n" and config.prefill.normal == "cursorWord" then
		prefill = vim.fn.expand("<cword>")
	elseif mode:find("[Vv]") and config.prefill.visual == "selectionFirstLine" then
		vim.cmd.normal { '"zy', bang = true }
		prefill = vim.fn.getreg("z"):gsub("[\n\r].*", "")
	end
	prefill = prefill:gsub("[.(){}[%]*+?^$]", [[\%1]]) -- escape special chars

	-- CREATE RG-BUFFER
	state.popupBufNr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(state.popupBufNr, 0, -1, false, { prefill, "" })
	-- adds syntax highlighting via treesitter `regex` parser
	vim.api.nvim_set_option_value("filetype", "regex", { buf = state.popupBufNr })
	vim.api.nvim_buf_set_name(state.popupBufNr, "rip-substitute")
	local scrollbarOffset = 3

	-- FOOTER & WIDTH
	local maps = config.keymaps
	local suffix = #state.popupHistory == 0 and ("%s Abort"):format(maps.abort)
		or ("%s/%s Prev/Next"):format(maps.prevSubst, maps.nextSubst)
	local keymapHint = maps.confirm .. " Confirm  " .. suffix
	keymapHint = keymapHint:gsub("<[Cc][Rr]>", "⏎"):gsub("<[dD]own>", "↓"):gsub("<[Uu]p>", "↑")

	local width = config.popupWin.width
	local expectedFooterLength = #keymapHint + 11 + 2 -- 11 for "123 matches" + 2 for border
	if expectedFooterLength > width then width = expectedFooterLength end

	-- CREATE WINDOW
	state.popupWinNr = vim.api.nvim_open_win(state.popupBufNr, true, {
		relative = "win",
		row = vim.api.nvim_win_get_height(0) - 4,
		col = vim.api.nvim_win_get_width(0) - width - scrollbarOffset - 2,
		width = width,
		height = 2,
		style = "minimal",
		border = config.popupWin.border,
		title = "  rip-substitute ",
		zindex = 2, -- below nvim-notify
		footer = {
			{ " " .. keymapHint .. " ", "Comment" },
		},
	})
	local winOpts = {
		list = true,
		listchars = "multispace:·,tab:▸▸",
		signcolumn = "no",
		number = false,
		sidescrolloff = 0,
		scrolloff = 0,
	}
	for key, value in pairs(winOpts) do
		vim.api.nvim_set_option_value(key, value, { win = state.popupWinNr })
	end
	vim.cmd.startinsert { bang = true }

	-- LABELS, MATCH-HIGHLIGHTS, AND STATIC WINDOW
	setPopupLabels()
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		buffer = state.popupBufNr,
		group = vim.api.nvim_create_augroup("rip-substitute-popup-changes", {}),
		callback = function()
			ensureOnly2LinesInPopup()
			local numOfMatches = rg.incrementalPreview()
			updateMatchCount(numOfMatches)
			setPopupLabels()
		end,
	})

	-- KEYMAPS
	vim.keymap.set(
		{ "n", "x" },
		config.keymaps.abort,
		closePopupWin,
		{ buffer = state.popupBufNr, nowait = true }
	)
	vim.keymap.set({ "n", "x" }, config.keymaps.confirm, function()
		rg.executeSubstitution()
		closePopupWin()
	end, { buffer = state.popupBufNr, nowait = true })

	-- only set keymap when there is a last run
	state.historyPosition = #state.popupHistory
	vim.keymap.set({ "n", "x" }, config.keymaps.prevSubst, function()
		state.historyPosition = state.historyPosition - 1
		local content = state.popupHistory[state.historyPosition]
		if content then
			vim.api.nvim_buf_set_lines(state.popupBufNr, 0, -1, false, content)
		else
			state.historyPosition = 1
		end
	end, { buffer = state.popupBufNr, nowait = true })
	vim.keymap.set({ "n", "x" }, config.keymaps.nextSubst, function()
		state.historyPosition = state.historyPosition + 1
		local content = state.popupHistory[state.historyPosition]
		if content then
			vim.api.nvim_buf_set_lines(state.popupBufNr, 0, -1, false, content)
		else
			state.historyPosition = #state.popupHistory
		end
	end, { buffer = state.popupBufNr, nowait = true })

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
