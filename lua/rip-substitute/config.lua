local M = {}
--------------------------------------------------------------------------------

local fallbackBorder = "rounded"

---@return string
local function getBorder()
	local hasWinborder, winborder = pcall(function() return vim.o.winborder end)
	if not hasWinborder or winborder == "" or winborder == "none" then return fallbackBorder end
	return winborder
end

--------------------------------------------------------------------------------

---@class RipSubstitute.Config
local defaultConfig = {
	popupWin = {
		title = " rip-substitute",
		border = getBorder(), -- `vim.o.winborder` on nvim 0.11, otherwise "rounded"
		matchCountHlGroup = "Keyword",
		noMatchHlGroup = "ErrorMsg",
		position = "bottom", ---@type "top"|"bottom"
		hideSearchReplaceLabels = false,
		hideKeymapHints = false,
		disableCompletions = true, -- such as from blink.cmp
	},
	prefill = {
		normal = "cursorWord", ---@type "cursorWord"|false
		visual = "selection", ---@type "selection"|false -- (does not work with ex-command – see README)
		startInReplaceLineIfPrefill = false,
		alsoPrefillReplaceLine = false,
	},
	keymaps = { -- normal mode (if not stated otherwise)
		abort = "q",
		confirm = "<CR>",
		insertModeConfirm = "<C-CR>",
		prevSubstitutionInHistory = "<Up>",
		nextSubstitutionInHistory = "<Down>",
		toggleFixedStrings = "<C-f>", -- ripgrep's `--fixed-strings`
		toggleIgnoreCase = "<C-c>", -- ripgrep's `--ignore-case`
		openAtRegex101 = "R",
		showHelp = "?",
	},
	incrementalPreview = {
		matchHlGroup = "IncSearch",
		rangeBackdropBrightness = 50, ---@type number|false 0-100, false disables backdrop
	},
	regexOptions = {
		startWithFixedStrings = false,
		startWithIgnoreCase = false,
		pcre2 = true, -- enables lookarounds and backreferences, but slightly slower
		autoBraceSimpleCaptureGroups = true, -- disable if using named capture groups (see README for details)
	},
	editingBehavior = {
		-- typing `()` in the search line automatically adds `$n` to the replace line
		autoCaptureGroups = false,
	},
	notification = {
		onSuccess = true,
		icon = "",
	},
	debug = false, -- extra notifications for debugging
}

--------------------------------------------------------------------------------

M.config = defaultConfig

---@param userConfig? RipSubstitute.Config
function M.setup(userConfig)
	M.config = vim.tbl_deep_extend("force", M.config, userConfig or {})
	local warn = function(msg) require("rip-substitute.utils").notify(msg, "warn") end

	-- DEPRECATION (2025-11-19)
	if M.config.regexOptions.startWithFixedStringsOn ~= nil then
		M.config.regexOptions.startWithFixedStrings = M.config.regexOptions.startWithFixedStringsOn
		warn(
			"`regexOptions.startWithFixedStringsOn` has been renamed to `regexOptions.startWithFixedStrings`"
		)
	end
	if M.config.incrementalPreview.rangeBackdrop then
		warn(
			"`incrementalPreview.rangeBackdrop` configs have been merged to `incrementalPreview.rangeBackdropBrightness`"
		)
	end

	-- set initial state for regex options
	if M.config.regexOptions.startWithFixedStrings then
		require("rip-substitute.state").state.useFixedStrings = true
	end
	if M.config.regexOptions.startWithIgnoreCase then
		require("rip-substitute.state").state.useIgnoreCase = true
	end

	-- VALIDATE border `none` does not work with and title/footer used by this plugin
	if M.config.popupWin.border == "none" or M.config.popupWin.border == "" then
		M.config.popupWin.border = fallbackBorder
		warn(('Border "none" is not supported, falling back to %q.'):format(fallbackBorder))
	end
end

--------------------------------------------------------------------------------
return M
