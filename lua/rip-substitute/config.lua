local M = {}
--------------------------------------------------------------------------------

---@class ripSubstituteConfig
local defaultConfig = {
	popupWin = {
		width = 40,
		border = "single",
		matchCountHlGroup = "Keyword",
	},
	prefill = {
		normal = "cursorWord", -- "cursorWord"|"treesitterNode"|false
		visual = "selectionFirstLine", -- "selectionFirstLine"|false
	},
	keymaps = { -- normal & visual mode
		confirm = "<CR>",
		abort = "q",
		prevSubst = "<Up>",
		nextSubst = "<Down>",
	},
	incrementalPreview = {
		replacementDisplay = "sideBySide", -- "sideBySide"|"overlay"
		hlGroups = {
			replacement = "IncSearch",
			activeSearch = "IncSearch",
			inactiveSearch = "LspInlayHint",
		},
	},
	regexOptions = {
		-- pcre2 enables lookarounds and backreferences, but performs slower
		pcre2 = true,
		-- disable if you use named capture groups (see README for details)
		autoBraceSimpleCaptureGroups = true,
	},
	editingBehavior = {
		-- Experimental. When typing `()` in the `search` lines, automatically
		-- add `$n` to the `replacement` line.
		autoCaptureGroups = false,
	},
}
M.config = defaultConfig

---@param userConfig? ripSubstituteConfig
function M.setup(userConfig) M.config = vim.tbl_deep_extend("force", M.config, userConfig or {}) end

--------------------------------------------------------------------------------
return M
