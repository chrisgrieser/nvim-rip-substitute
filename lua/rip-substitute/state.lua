local M = {}

---@class (exact) RipSubstitute.CmdRange
---@field start number
---@field end_ number

---@class (exact) RipSubstitute.State
---@field popupHistory? [string, string][]
---@field matchCount? number
---@field useFixedStrings? boolean
---@field useIgnoreCase? boolean
---@field targetBuf? number
---@field targetWin? number
---@field range? RipSubstitute.CmdRange|false
---@field popupBufNr? number
---@field popupWinNr? number
---@field popupPresentContent? [string, string]
---@field historyPosition? number
---@field prefill? [string, string]
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

--------------------------------------------------------------------------------

function M.readHistoryFromDisk()
	local rawPath = require("rip-substitute.config").config.history.path
	if rawPath == "" or rawPath == false then return end
	local historyPath = vim.fs.normalize(rawPath)

	if vim.uv.fs_stat(historyPath) == nil then return end -- no history exists yet
	local historyFile, errmsg = io.open(historyPath, "r")
	assert(historyFile, errmsg)
	local content = historyFile:read("*a")
	historyFile:close()
	M.state.popupHistory = vim.json.decode(content)
end

function M.writeHistoryToDisk()
	local rawPath = require("rip-substitute.config").config.history.path
	if rawPath == "" or rawPath == false then return end
	local historyPath = vim.fs.normalize(rawPath)

	vim.fn.mkdir(vim.fs.dirname(historyPath), "p")
	local historyFile, err = io.open(historyPath, "w")
	assert(historyFile, err)
	local content = vim.json.encode(M.state.popupHistory)
	historyFile:write(content)
	historyFile:close()
end

---@param newState RipSubstitute.State
function M.update(newState) M.state = vim.tbl_deep_extend("force", M.state, newState) end

return M
