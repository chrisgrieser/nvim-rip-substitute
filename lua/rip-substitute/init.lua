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

function M.sub() require("rip-substitute.popup-win").substitute() end

--------------------------------------------------------------------------------
return M
