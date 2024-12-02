local M = {}
--------------------------------------------------------------------------------

---@param msg string
---@param level? "info"|"trace"|"debug"|"warn"|"error"
function M.notify(msg, level)
	if not level then level = "info" end
	local icon = require("rip-substitute.config").config.notification.icon
	vim.notify(msg, vim.log.levels[level:upper()], { title = "rip-substitute", icon = icon })
end

---@return number startLnum
---@return number endLnum
function M.getViewport()
	local state = require("rip-substitute.state").state
	local startLnum = vim.fn.line("w0", state.targetWin)
	local endLnum = vim.fn.line("w$", state.targetWin)
	return startLnum, endLnum
end

---@param hlName string name of highlight group
---@param key "fg"|"bg"|"bold"
---@nodiscard
---@return string|nil the value, or nil if hlgroup or key is not available
function M.getHighlightValue(hlName, key)
	local hl
	repeat
		-- follow linked highlights
		hl = vim.api.nvim_get_hl(0, { name = hlName })
		hlName = hl.link
	until not hl.link
	local value = hl[key]
	if value then return ("#%06x"):format(value) end
end

--------------------------------------------------------------------------------
return M
