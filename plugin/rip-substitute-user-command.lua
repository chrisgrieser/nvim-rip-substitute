vim.api.nvim_create_user_command(
	"RipSubstitute",
	function(args) require("rip-substitute").sub(args) end,
	{ desc = "nvim-rip-substitute", range = true, nargs = "?" }
)
