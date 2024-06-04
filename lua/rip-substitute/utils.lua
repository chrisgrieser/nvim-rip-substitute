local M = {}
--------------------------------------------------------------------------------

---@param msg string
---@param level? "info"|"trace"|"debug"|"warn"|"error"
function M.notify(msg, level)
	if not level then level = "info" end
	vim.notify(msg, vim.log.levels[level:upper()], { title = "rip-substitute" })
end

---@param parameters string[]
---@return vim.SystemCompleted
function M.runRipgrep(parameters)
	local config = require("rip-substitute.config").config
	local state = require("rip-substitute.state").state

	local rgCmd = vim.list_extend({ "rg", "--no-config" }, parameters)
	if config.regexOptions.pcre2 then table.insert(rgCmd, "--pcre2") end
	vim.list_extend(rgCmd, { "--", state.targetFile })
	return vim.system(rgCmd):wait()
end

---@return string
---@return string
function M.getSearchAndReplace()
	local config = require("rip-substitute.config").config
	local state = require("rip-substitute.state").state

	local toSearch, toReplace = unpack(vim.api.nvim_buf_get_lines(state.popupBufNr, 0, -1, false))
	if config.regexOptions.autoBraceSimpleCaptureGroups then
		toReplace = toReplace:gsub("%$(%d+)", "${%1}")
	end
	return toSearch, toReplace
end

--------------------------------------------------------------------------------
return M
