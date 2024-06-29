local version = vim.version()
if version.major == 0 and version.minor < 10 then
	vim.notify("nvim-rip-substitute requires at least nvim 0.10.", vim.log.levels.WARN)
	return
end
--------------------------------------------------------------------------------

local M = {}
-- PERF do not import submodules here, since it results in them all being loaded
-- on initialization instead of lazy-loading them when needed.
--------------------------------------------------------------------------------

---@param userConfig? ripSubstituteConfig
function M.setup(userConfig) require("rip-substitute.config").setup(userConfig) end

---@param exCmdArgs? { range: number, line1: number, line2: number } only set when called via ex command `:RipSubstitute`
function M.sub(exCmdArgs)
	vim.cmd("silent! update") -- ensure changes are written, so `rg` can read them
	local config = require("rip-substitute.config").config
	local mode = vim.fn.mode()
	local exCmdWithRange = exCmdArgs and exCmdArgs.range > 0

	-- PREFILL
	local searchPrefill = ""
	if mode == "n" and not exCmdWithRange and config.prefill.normal == "cursorWord" then
		searchPrefill = vim.fn.expand("<cword>")
	elseif mode == "v" and config.prefill.visual == "selectionFirstLine" then
		vim.cmd.normal { '"zy', bang = true }
		searchPrefill = vim.fn.getreg("z"):gsub("[\n\r].*", "") -- only first line
	end
	searchPrefill = searchPrefill:gsub("[.(){}[%]*+?^$]", [[\%1]]) -- escape special chars

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
	require("rip-substitute.state").update {
		targetBuf = vim.api.nvim_get_current_buf(),
		targetWin = vim.api.nvim_get_current_win(),
		labelNs = vim.api.nvim_create_namespace("rip-substitute-labels"),
		incPreviewNs = vim.api.nvim_create_namespace("rip-substitute-incpreview"),
		targetFile = vim.api.nvim_buf_get_name(0),
		range = range,
	}

	require("rip-substitute.popup-win").openSubstitutionPopup(searchPrefill)
end

--------------------------------------------------------------------------------
return M
