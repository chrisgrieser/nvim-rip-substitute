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
		local sel = vim.fn.getregion(vim.fn.getpos("."), vim.fn.getpos("v"), { type = vim.fn.mode() })
		searchPrefill = sel[1]
	end
	local replacePrefill = config.prefill.alsoPrefillReplaceLine and searchPrefill or ""
	-- escape
	if not exCmdHasSearchPrefill and not config.regexOptions.startWithFixedStringsOn then
		searchPrefill = searchPrefill:gsub("[.(){}[%]*+?^$]", [[\%1]])
	end

	-- RANGE
	---@type RipSubstitute.CmdRange|false
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
		range = range,
		rememberedPrefill = nil, -- reset for subsequent runs
		prefill = { searchPrefill, replacePrefill },
	}

	local targetBufLines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	stateModule.targetBufCache = table.concat(targetBufLines, "\n")
end

--------------------------------------------------------------------------------
return M
