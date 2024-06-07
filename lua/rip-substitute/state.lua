local M = {}

---@class (exact) ripSubstituteState
---@field targetBuf number
---@field targetWin number
---@field targetFile string
---@field labelNs number
---@field incPreviewNs number
---@field popupBufNr? number
---@field popupWinNr? number
---@field popupHistory? string[][]
---@field historyPosition? number
M.state = {
	popupHistory = {},
}

---@param newState ripSubstituteState
function M.update(newState) M.state = vim.tbl_deep_extend("force", M.state, newState) end

return M
