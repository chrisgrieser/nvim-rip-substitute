local M = {}
--------------------------------------------------------------------------------

---@class ripSubstituteConfig
local defaultConfig = {
	popupWin = {
		title = " rip-substitute",
		border = "single",
		matchCountHlGroup = "Keyword",
		noMatchHlGroup = "ErrorMsg",
		hideSearchReplaceLabels = false,
		---@type "top"|"bottom"
		position = "bottom",
	},
	prefill = {
		---@type "cursorWord"| false
		normal = "cursorWord",
		---@type "selectionFirstLine"| false does not work with ex-command (see README).
		visual = "selectionFirstLine",
		startInReplaceLineIfPrefill = false,
	},
	keymaps = { -- normal & visual mode, if not stated otherwise
		abort = "q",
		confirm = "<CR>",
		insertModeConfirm = "<C-CR>",
		prevSubst = "<Up>",
		nextSubst = "<Down>",
		toggleFixedStrings = "<C-f>", -- ripgrep's `--fixed-strings`
		toggleIgnoreCase = "<C-c>", -- ripgrep's `--ignore-case`
		openAtRegex101 = "R",
	},
	incrementalPreview = {
		matchHlGroup = "IncSearch",
		rangeBackdrop = {
			enabled = true,
			blend = 50, -- between 0 and 100
		},
	},
	regexOptions = {
		startWithFixedStringsOn = false,
		startWithIgnoreCase = false,
		-- pcre2 enables lookarounds and backreferences, but performs slower
		pcre2 = true,
		-- disable if you use named capture groups (see README for details)
		autoBraceSimpleCaptureGroups = true,
	},
	editingBehavior = {
		-- When typing `()` in the `search` line, automatically adds `$n` to the
		-- `replace` line.
		autoCaptureGroups = false,
	},
	notificationOnSuccess = true,
}

--------------------------------------------------------------------------------

M.config = defaultConfig

---@param userConfig? ripSubstituteConfig
function M.setup(userConfig)
	M.config = vim.tbl_deep_extend("force", M.config, userConfig or {})
	local notify = require("rip-substitute.utils").notify

	-- set initial state for regex options
	if M.config.regexOptions.startWithFixedStringsOn then
		require("rip-substitute.state").state.useFixedStrings = true
	end
	if M.config.regexOptions.startWithIgnoreCase then
		require("rip-substitute.state").state.useIgnoreCase = true
	end

	-- VALIDATE `rg` installations not built with `pcre2`, see #3
	if M.config.regexOptions.pcre2 then
		vim.system({ "rg", "--pcre2-version" }, {}, function(out)
			if out.code ~= 0 or out.stderr:find("PCRE2 is not available in this build of ripgrep") then
				local msg = "`regexOptions.pcre2` has been disabled, as the installed version of `ripgrep` lacks `pcre2` support.\n\n"
					.. "Please install `ripgrep` with `pcre2` support, or disable `regexOptions.pcre2`."
				notify(msg, "warn")
				M.config.regexOptions.pcre2 = false
			end
		end)
	end

	-- VALIDATE border `none` does not work with and title/footer used by this plugin
	if M.config.popupWin.border == "none" then
		local fallback = defaultConfig.popupWin.border
		M.config.popupWin.border = fallback
		local msg = ('Border "none" is not supported, falling back to %q.'):format(fallback)
		notify(msg, "warn")
	end
end

--------------------------------------------------------------------------------
return M
