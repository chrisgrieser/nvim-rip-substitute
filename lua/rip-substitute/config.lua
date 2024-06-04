local M = {}
--------------------------------------------------------------------------------

---@class ripSubstituteConfig
local defaultConfig = {
	window = {
		width = 40,
		border = "single",
	},
	keymaps = {
		confirm = "<CR>",
		abort = "q",
	},
	regexOptions = {
		-- enables lookarounds and backreferences, but slower performance
		pcre2 = true,
		-- By default, rg treats `$1a` as the named capture group "1a". When set
		-- to `true`, and `$1a` is automatically changed to `${1}a` to ensure the
		-- capture group is correctly determined. Disable this setting, if you
		-- plan an using named capture groups.
		autoBraceSimpleCaptureGroups = true,
	},
	prefill = {
		normal = "cursorword", -- "cursorword"|false
		visual = "selectionFirstLine", -- "selectionFirstLine"|false
	},
	notificationOnSuccess = true,
}
M.config = defaultConfig

---@param userConfig ripSubstituteConfig
function M.setup(userConfig) M.config = vim.tbl_deep_extend("force", M.config, userConfig or {}) end

--------------------------------------------------------------------------------
return M
