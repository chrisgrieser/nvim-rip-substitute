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

---@param opts? ripSubstituteOpts
function M.sub(opts)
	local config = require("rip-substitute.config").config
	local mode = vim.fn.mode()

	-- PREFILL
	local searchPrefill = ""
	if mode == "n" and config.prefill.normal == "cursorWord" then
		searchPrefill = vim.fn.expand("<cword>")
	elseif mode == "v" and config.prefill.visual == "selectionFirstLine" then
		vim.cmd.normal { '"zy', bang = true }
		searchPrefill = vim.fn.getreg("z"):gsub("[\n\r].*", "") -- only first line
	end
	searchPrefill = searchPrefill:gsub("[.(){}[%]*+?^$]", [[\%1]]) -- escape special chars

	-- RANGE
	---@type CmdRange|false
	local range = require("rip-substitute.opts").getRange(opts, mode)

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

vim.api.nvim_create_user_command("RipSub", function(args)
	if args.range and args.range > 0 then
		M.sub {
			range = {
				startLine = args.line1,
				endLine = args.range > 1 and args.line2 or args.line1
			},
		}
	else
		M.sub()
	end
end, {
	range = true,
})

--------------------------------------------------------------------------------
return M
