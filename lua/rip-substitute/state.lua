local M = {}

---@class (exact) ripSubstituteState
---@field targetBuf number
---@field targetWin number
---@field targetFile string
---@field labelNs number
---@field matchHlNs number
---@field rgBuf number
M.state = {}

---@param newState ripSubstituteState
function M.new(newState) M.state = newState end

return M
