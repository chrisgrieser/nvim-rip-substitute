local M = {}
--------------------------------------------------------------------------------

---@param exCmdArgs? exCmdArgs
function M.setParameters(exCmdArgs)
	local config = require("rip-substitute.config").config
	local state = require("rip-substitute.state").state
	local mode = vim.fn.mode()
	local exCmdWithRange = exCmdArgs and exCmdArgs.range > 0
	local exCmdHasSearchPrefill = exCmdArgs and exCmdArgs.args ~= ""

	-- PREFILL
	local searchPrefill = ""
	if state.rememberedPrefill then
		searchPrefill = state.rememberedPrefill or ""
	elseif exCmdHasSearchPrefill then
		---@diagnostic disable-next-line: need-check-nil done via condition `exSearchPrefil`
		searchPrefill = exCmdArgs.args
	elseif mode == "n" and not exCmdWithRange and config.prefill.normal == "cursorWord" then
		searchPrefill = vim.fn.expand("<cword>")
	elseif mode == "v" and config.prefill.visual == "selectionFirstLine" then
		vim.cmd.normal { '"zy', bang = true }
		searchPrefill = vim.fn.getreg("z"):gsub("[\n\r].*", "") -- only first line
	end
	if not exCmdHasSearchPrefill and not config.regexOptions.startWithFixedStringsOn then
		-- escape special chars only when not using prefill and not literal mode
		-- by default
		searchPrefill = searchPrefill:gsub("[.(){}[%]*+?^$]", [[\%1]])
	end

	-- RANGE
	---@type CmdRange|false
	local range = false
	if mode == "V" then
		vim.cmd.normal { "V", bang = true } -- leave visual mode, so marks are set
		local startLn = vim.api.nvim_buf_get_mark(0, "<")[1]
		local endLn = vim.api.nvim_buf_get_mark(0, ">")[1]
		range = { start = startLn, end_ = endLn }
	elseif exCmdWithRange then
		---@diagnostic disable-next-line: need-check-nil done via condition `exCmdWithRange`
		range = { start = exCmdArgs.line1, end_ = exCmdArgs.line2 }
	end

	-- SET STATE
	local stateModule = require("rip-substitute.state")
	local bufnr = vim.api.nvim_get_current_buf()
	stateModule.update {
		targetBuf = bufnr,
		targetWin = vim.api.nvim_get_current_win(),
		labelNs = vim.api.nvim_create_namespace("rip-substitute-labels"),
		incPreviewNs = vim.api.nvim_create_namespace("rip-substitute-incpreview"),
		range = range,
		rememberedPrefill = nil, -- reset for subsequent runs
		searchPrefill = searchPrefill,
	}

	local targetBufLines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	stateModule.targetBufCache = table.concat(targetBufLines, "\n")
end

--------------------------------------------------------------------------------
return M
