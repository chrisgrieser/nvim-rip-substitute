local M = {}
local notify = require("rip-substitute.utils").notify
--------------------------------------------------------------------------------

---@class ripSubstituteOpts
local userOpts = {
	range = {
		startLine = 0,
		endLine = 0,
	},
}

---@param opts? ripSubstituteOpts
---@param mode string
---@return CmdRange|false
function M.getRange(opts, mode)
	local ABORT_MSG = "Aborting selection and using default substitution."

	if opts and opts.range and mode == "V" then
		notify(
			"Conflict of two ranges: of defined in opts and of VISUAL mode.\n\n" ..
			ABORT_MSG,
			"warn")
		return false
	end

	if opts and opts.range then
		local range = opts.range

		if not range.startLine then
			notify(
				"Invalid range from defined in opts: the start line is not defined.\n\n" ..
				ABORT_MSG,
				"warn")
			return false
		end

		if not range.endLine then
			notify(
				"Invalid range from defined in opts: the end line is not defined.\n\n" ..
				ABORT_MSG,
				"warn")
			return false
		end

		if range.startLine > range.endLine then
			notify(
				"Invalid range from defined in opts: the start is after of the end.\n\n" ..
				ABORT_MSG,
				"warn")
			return false
		end

		return { start = range.startLine, end_ = range.endLine }
	end

	if mode == "V" then
		vim.cmd.normal { "V", bang = true } -- leave visual mode, so marks are set
		local startLn = vim.api.nvim_buf_get_mark(0, "<")[1]
		local endLn = vim.api.nvim_buf_get_mark(0, ">")[1]
		return { start = startLn, end_ = endLn }
	end

	return false
end

--------------------------------------------------------------------------------
return M
