local M = {}

---@class (exact) CmdRange
---@field start number
---@field end_ number

---@class (exact) RipSubstituteState
---@field targetBuf number
---@field targetWin number
---@field targetFile string
---@field range CmdRange|false
---@field labelNs number
---@field incPreviewNs number
---@field popupBufNr? number
---@field popupWinNr? number
---@field popupHistory? string[][]
---@field popupPresentContent? string[]
---@field historyPosition? number
---@field matchCount? number
---@field matches? RipSubstituteMatch[]
---@field selectedMatch? RipSubstituteMatch
M.state = {
	popupHistory = {},
	matchCount = 0,
	matches = {},
}

---@param newState RipSubstituteState
function M.update(newState) M.state = vim.tbl_deep_extend("force", M.state, newState) end

return M
