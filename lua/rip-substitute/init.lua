local version = vim.version()
if version.major == 0 and version.minor < 10 then
	vim.notify('"nvim-rip-substitute" requires at least nvim 0.10.', vim.log.levels.ERROR)
	return
end
if vim.fn.executable("rg") == 0 then
	local msg = '"nvim-rip-substitute" requires `ripgrep`, which cannot be found.'
	vim.notify(msg, vim.log.levels.ERROR)
	return
end
--------------------------------------------------------------------------------

local M = {}
-- PERF do not import submodules here, since it results in them all being loaded
-- on initialization instead of lazy-loading them when needed.
--------------------------------------------------------------------------------

---@param userConfig? RipSubstitute.Config
function M.setup(userConfig) require("rip-substitute.config").setup(userConfig) end

function M.rememberCursorWord()
	local state = require("rip-substitute.state").state
	local u = require("rip-substitute.utils")
	local cword = vim.fn.expand("<cword>")
	state.rememberedPrefill = cword
	u.notify(("%q saved as prefill for next use."):format(cword))
end

---@alias exCmdArgs { range: number, line1: number, line2: number, args: string }

---@param exCmdArgs? exCmdArgs
function M.sub(exCmdArgs)
	if not vim.bo.modifiable then
		local u = require("rip-substitute.utils")
		u.notify("Buffer is not modifiable.", "error")
		return
	end

	require("rip-substitute.run-parameters").setParameters(exCmdArgs)
	require("rip-substitute.popup-win").openSubstitutionPopup()
end

--------------------------------------------------------------------------------
return M
