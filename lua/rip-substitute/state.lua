local M = {}

---@class (exact) ripSubstituteState
---@field targetBuf number
---@field targetWin number
---@field targetFile string
---@field popupBufNr? number
---@field popupWinNr? number
---@field labelNs number
---@field incPreviewNs number
---@field lastPopupContent? string[]
M.state = {}

---@param newState ripSubstituteState|{lastPopupContent: string[]}
function M.update(newState) M.state = vim.tbl_deep_extend("force", M.state, newState) end

return M
