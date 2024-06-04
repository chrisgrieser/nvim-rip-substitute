local M = {}

---@class (exact) ripSubstituteState
---@field targetBuf number
---@field targetWin number
---@field targetFile string
---@field popupBufNr number
---@field popupWinNr number
---@field labelNs number
---@field matchHlNs number
M.state = {}

---@param newState ripSubstituteState
function M.new(newState) M.state = newState end

return M
