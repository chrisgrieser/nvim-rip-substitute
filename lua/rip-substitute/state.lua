local M = {}

---@class (exact) RipSubstitute.CmdRange
---@field start number
---@field end_ number

---@class (exact) RipSubstitute.State
---@field popupHistory? string[][]
---@field matchCount? number
---@field useFixedStrings? boolean
---@field useIgnoreCase? boolean
---@field targetBuf? number
---@field targetWin? number
---@field range? RipSubstitute.CmdRange|false
---@field popupBufNr? number
---@field popupWinNr? number
---@field popupPresentContent? string[]
---@field historyPosition? number
---@field prefill? string[]
---@field rememberedPrefill? string

---@type RipSubstitute.State
M.state = {
	popupHistory = {},
	matchCount = 0,
	useFixedStrings = false,
	useIgnoreCase = false,
}

---@type string
M.targetBufCache = ""

---@param newState RipSubstitute.State
function M.update(newState) M.state = vim.tbl_deep_extend("force", M.state, newState) end

return M
