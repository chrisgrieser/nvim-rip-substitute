local version = vim.version()
if version.major == 0 and version.minor < 10 then
	vim.notify('"nvim-rip-substitute" requires at least nvim 0.10.', vim.log.levels.ERROR)
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
	local u = require("rip-substitute.utils")

	-- buffer modifiable & `rg` found
	if vim.fn.executable("rg") == 0 then
		u.notify("`nvim-rip-substitute` requires `ripgrep`, which cannot be found.", "error")
		return
	elseif not vim.bo.modifiable then
		u.notify("Buffer is not modifiable.", "error")
		return
	end

	-- `rg` version 15.0.0+, since it introduced `--json` supporting `--replace`
	local stdout = assert(vim.system({ "rg", "--version" }):wait().stdout, "rg --version failed")
	local majorVer = tonumber(stdout:match("^ripgrep (%d+)"))
	if not majorVer or majorVer < 15 then
		u.notify("`nvim-rip-substitute` requires `ripgrep` version 15.0.0 or newer.", "error")
		return
	end

	-- `rg` installations not built with `pcre2`, see #3
	local pcre2 = require("rip-substitute.config").config.regexOptions.pcre2
	if pcre2 and stdout:find("PCRE2 is not available in this build of ripgrep") then
		u.notify(
			"`regexOptions.pcre2` has been disabled, as the installed version of `ripgrep` lacks `pcre2` support.\n\n"
				.. "Please install `ripgrep` with `pcre2` support, or disable `regexOptions.pcre2`.",
			"warn"
		)
		require("rip-substitute.config").config.regexOptions.pcre2 = false
	end

	-----------------------------------------------------------------------------

	require("rip-substitute.run-parameters").setParameters(exCmdArgs)
	require("rip-substitute.popup-win").openSubstitutionPopup()
end

--------------------------------------------------------------------------------
return M
