local u = require("rip-substitute.utils")
--------------------------------------------------------------------------------

return function()
	local state = require("rip-substitute.state").state
	local toSearch, toReplace =
		require("rip-substitute.rg-operations").getSearchAndReplaceValuesFromPopup()
	local usePcre2 = require("rip-substitute.config").config.regexOptions.pcre2

	local viewStart, viewEnd = u.getViewport()
	local viewportLines = vim.api.nvim_buf_get_lines(state.targetBuf, viewStart - 1, viewEnd, false)

	local data = {
		regex = toSearch,
		substitution = toReplace,
		delimiter = usePcre2 and "/" or '"',
		flags = "gm",
		flavor = usePcre2 and "pcre2" or "rust", -- `rg` uses rust regex
		testString = table.concat(viewportLines, "\n"),
	}

	-- DOCS https://github.com/firasdib/Regex101/wiki/API#curl-3
	local curlTimeoutSecs = 10
	-- stylua: ignore
	local out = vim.system({
		"curl",
		"--silent",
		"--max-time", tostring(curlTimeoutSecs),
		"--request", "POST",
		"--header", "Expect:",
		"--header", "Content-Type: application/json",
		"--data", vim.json.encode(data),
		"https://regex101.com/api/regex",
	}):wait()

	if out.code ~= 0 then
		u.notify("curl failed:\n" .. out.stderr, "error")
		return
	end
	local response = vim.json.decode(out.stdout)
	if response.error then
		u.notify("regex101 API error:\n" .. response.error, "error")
		return
	end
	vim.ui.open("https://regex101.com/r/" .. response.permalinkFragment)
end
