local M = {}
--------------------------------------------------------------------------------

---@class ripSubstituteConfig
local defaultConfig = {
	popupWin = {
		width = 40,
		border = "single",
	},
	keymaps = { -- normal & visual mode
		confirm = "<CR>",
		abort = "q",
		insertLastContent = "<Up>",
	},
	regexOptions = {
		-- pcre2 enables lookarounds and backreferences, but performs slower.
		pcre2 = true,
		-- By default, rg treats `$1a` as the named capture group "1a". When set
		-- to `true`, `$1a` is automatically changed to `${1}a` to ensure the
		-- capture group is correctly determined. Disable this setting if you
		-- plan an using named capture groups.
		autoBraceSimpleCaptureGroups = true,
	},
	prefill = {
		normal = "cursorWord", -- "cursorWord"|false
		visual = "selectionFirstLine", -- "selectionFirstLine"|false
	},
	notificationOnSuccess = true,
}
M.config = defaultConfig

---@param userConfig? ripSubstituteConfig
function M.setup(userConfig) M.config = vim.tbl_deep_extend("force", M.config, userConfig or {}) end

--------------------------------------------------------------------------------
return M
