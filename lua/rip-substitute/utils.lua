local M = {}
--------------------------------------------------------------------------------

---@param msg string
---@param level? "info"|"trace"|"debug"|"warn"|"error"
function M.notify(msg, level)
	if not level then level = "info" end
	vim.notify(msg, vim.log.levels[level:upper()], { title = "rip-substitute" })
end

---@return number startLnum
---@return number endLnum
function M.getViewport()
	local state = require("rip-substitute.state").state
	local startLnum = vim.fn.line("w0", state.targetWin)
	local endLnum = vim.fn.line("w$", state.targetWin)
	return startLnum, endLnum
end
--------------------------------------------------------------------------------
return M
