local version = vim.version()
if version.major == 0 and version.minor < 10 then
	vim.notify('"nvim-rip-substitute" requires at least nvim 0.10.', vim.log.levels.WARN)
	return
end
--------------------------------------------------------------------------------

local M = {}
-- PERF do not import submodules here, since it results in them all being loaded
-- on initialization instead of lazy-loading them when needed.
--------------------------------------------------------------------------------

---@param userConfig? ripSubstituteConfig
function M.setup(userConfig) require("rip-substitute.config").setup(userConfig) end

function M.rememberCursorWord()
	local state = require("rip-substitute.state").state
	local u = require("rip-substitute.utils")
	local cword = vim.fn.expand("<cword>")
	state.rememberedPrefill = cword
	u.notify(("%q saved as prefill for next use."):format(cword))
end

---@param exCmdArgs? exCmdArgs
function M.sub(exCmdArgs)
	vim.cmd("silent! update") -- ensure changes are written, so `rg` can read them, see #8
	require("rip-substitute.run-parameters").setParameters(exCmdArgs)
	require("rip-substitute.popup-win").openSubstitutionPopup()
end

--------------------------------------------------------------------------------
return M
