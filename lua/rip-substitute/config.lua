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
		prevSubst = "<Up>",
		nextSubst = "<Down>",
	},
	regexOptions = {
		-- pcre2 enables lookarounds and backreferences, but performs slower.
		pcre2 = true,
		-- disable this, if you used named capture groups in your regex
		-- (see README for more information.)
		autoBraceSimpleCaptureGroups = true,
	},
	prefill = {
		normal = "cursorWord", -- "cursorWord"|"treesitterNode"|false
		visual = "selectionFirstLine", -- "selectionFirstLine"|false
	},
}
M.config = defaultConfig

---@param userConfig? ripSubstituteConfig
function M.setup(userConfig) M.config = vim.tbl_deep_extend("force", M.config, userConfig or {}) end

--------------------------------------------------------------------------------
return M
