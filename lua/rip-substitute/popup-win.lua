local M = {}
--------------------------------------------------------------------------------

local function setRgBufLabels()
	local state = require("rip-substitute.state").state
	vim.api.nvim_buf_clear_namespace(state.rgBuf, state.labelNs, 0, -1)
	vim.api.nvim_buf_set_extmark(state.rgBuf, state.labelNs, 0, 0, {
		virt_text = { { " Search", "DiagnosticVirtualTextInfo" } },
		virt_text_pos = "right_align",
	})
	vim.api.nvim_buf_set_extmark(state.rgBuf, state.labelNs, 1, 0, {
		virt_text = { { "Replace", "DiagnosticVirtualTextInfo" } },
		virt_text_pos = "right_align",
	})
end

local function rgBufEnsureOnly2Lines()
	local state = require("rip-substitute.state").state
	local lines = vim.api.nvim_buf_get_lines(state.rgBuf, 0, -1, true)
	if #lines == 2 then return end
	if #lines == 1 then
		lines[2] = ""
	elseif #lines > 2 then
		if lines[1] == "" then table.remove(lines, 1) end
		if lines[3] and lines[2] == "" then table.remove(lines, 2) end
	end
	vim.api.nvim_buf_set_lines(state.rgBuf, 0, -1, true, { lines[1], lines[2] })
	vim.cmd.normal { "zb", bang = true } -- enforce scroll position
end

function M.substitute()
	-- IMPORTS & INITIALIZATION
	local rg = require("rip-substitute.rg-operations")
	local config = require("rip-substitute.config").config
	require("rip-substitute.state").new {
		targetBuf = vim.api.nvim_get_current_buf(),
		targetWin = vim.api.nvim_get_current_win(),
		labelNs = vim.api.nvim_create_namespace("rip-substitute-labels"),
		matchHlNs = vim.api.nvim_create_namespace("rip-substitute-match-hls"),
		targetFile = vim.api.nvim_buf_get_name(0),
		rgBuf = -999, -- placeholder value
	}
	local state = require("rip-substitute.state").state

	-- PREFILL
	local prefill = ""
	local mode = vim.fn.mode()
	if mode == "n" and config.prefill.normal == "cursorword" then
		prefill = vim.fn.expand("<cword>")
	elseif mode:find("[Vv]") and config.prefill.visual == "selectionFirstLine" then
		vim.cmd.normal { '"zy', bang = true }
		prefill = vim.fn.getreg("z"):gsub("[\n\r].*", "")
	end
	prefill = prefill:gsub("[.(){}[%]*+?^$]", [[\%1]]) -- escape special chars

	-- CREATE RG-BUFFER
	state.rgBuf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(state.rgBuf, 0, -1, false, { prefill, "" })
	-- adds syntax highlighting via treesitter `regex` parser
	vim.api.nvim_set_option_value("filetype", "regex", { buf = state.rgBuf })
	vim.api.nvim_buf_set_name(state.rgBuf, "rip-substitute")
	local scrollbarOffset = 3

	-- CREATE WINDOW
	local footerStr = ("%s: Confirm   %s: Abort"):format(
		config.keymaps.confirm,
		config.keymaps.abort
	)
	local rgWin = vim.api.nvim_open_win(state.rgBuf, true, {
		relative = "win",
		row = vim.api.nvim_win_get_height(0) - 4,
		col = vim.api.nvim_win_get_width(0) - config.popupWin.width - scrollbarOffset - 2,
		width = config.popupWin.width,
		height = 2,
		style = "minimal",
		border = config.popupWin.border,
		title = "  rip-substitute ",
		title_pos = "center",
		zindex = 1, -- below nvim-notify
		footer = { { " " .. footerStr .. " ", "Comment" } },
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
		vim.api.nvim_set_option_value(key, value, { win = rgWin })
	end
	vim.cmd.startinsert { bang = true }

	-- LABELS, MATCH-HIGHLIGHTS, AND STATIC WINDOW
	setRgBufLabels()
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		buffer = state.rgBuf,
		group = vim.api.nvim_create_augroup("rip-substitute-popup-changes", {}),
		callback = function()
			rgBufEnsureOnly2Lines()
			rg.highlightMatches()
			setRgBufLabels()
		end,
	})

	-- POPUP CLOSING
	local function closeRgWin()
		if vim.api.nvim_win_is_valid(rgWin) then vim.api.nvim_win_close(rgWin, true) end
		if vim.api.nvim_buf_is_valid(state.rgBuf) then
			vim.api.nvim_buf_delete(state.rgBuf, { force = true })
		end
		vim.api.nvim_buf_clear_namespace(0, state.matchHlNs, 0, -1)
	end
	-- also close the popup on leaving buffer, ensures there is not leftover
	-- buffer when user closes popup in a different way, such as `:close`.
	vim.api.nvim_create_autocmd("BufLeave", {
		buffer = state.rgBuf,
		group = vim.api.nvim_create_augroup("rip-substitute-popup-leave", {}),
		callback = closeRgWin,
	})

	-- KEYMAPS
	vim.keymap.set(
		{ "n", "x" },
		config.keymaps.abort,
		closeRgWin,
		{ buffer = state.rgBuf, nowait = true }
	)
	vim.keymap.set({ "n", "x" }, config.keymaps.confirm, function()
		rg.executeSubstitution()
		closeRgWin()
	end, { buffer = state.rgBuf, nowait = true })
end

--------------------------------------------------------------------------------
return M
