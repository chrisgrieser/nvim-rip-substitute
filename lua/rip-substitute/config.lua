local M = {}
--------------------------------------------------------------------------------

---@class ripSubstituteConfig
local defaultConfig = {
	popupWin = {
		border = "single",
		matchCountHlGroup = "Keyword",
		hideSearchReplaceLabels = false,
	},
	prefill = {
		normal = "cursorWord", -- "cursorWord"|false
		visual = "selectionFirstLine", -- "selectionFirstLine"|false
	},
	keymaps = {
		-- normal & visual mode
		confirm = "<CR>",
		abort = "q",
		prevSubst = "<Up>",
		nextSubst = "<Down>",
		insertModeConfirm = "<C-CR>", -- (except this one, obviously)
	},
	incrementalPreview = {
		hlGroups = {
			replacement = "IncSearch",
			activeSearch = "IncSearch",
			inactiveSearch = "LspInlayHint",
		},
		rangeBackdrop = {
			enabled = true,
			blend = 50, -- between 0 and 100
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
	notificationOnSuccess = true,
}
M.config = defaultConfig

---@param userConfig? ripSubstituteConfig
function M.setup(userConfig)
	M.config = vim.tbl_deep_extend("force", M.config, userConfig or {})

	-- VALIDATE border `none` does not work with and title/footer used by this plugin
	if M.config.popupWin.border == "none" then
		local fallback = defaultConfig.popupWin.border
		M.config.popupWin.border = fallback
		local msg = ('Border "none" is not supported, falling back to %q'):format(fallback)
		require("rip-substitute.utils").notify(msg, "warn")
	end
end

--------------------------------------------------------------------------------
return M
