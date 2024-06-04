<!-- LTeX: enabled=false -->
# rip-substitute
<!-- LTeX: enabled=true -->
<!-- TODO uncomment shields when available in dotfyle.com 
<a href="https://dotfyle.com/plugins/chrisgrieser/rip-substitute">
<img alt="badge" src="https://dotfyle.com/plugins/chrisgrieser/rip-substitute/shield"/></a>
-->

A modern substitute for vim's `:substitute` using `ripgrep`.

> [!WARNING]
> This plugin is still in early development and should therefore be considered
> experimental. It's features and options are subject to change without notice.

<!-- toc -->

- [Features](#features)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [Limitations](#limitations)
- [About the developer](#about-the-developer)

<!-- tocstop -->

## Features
- Search and replace using `ripgrep` – no more esoteric vim regex to learn.
- Incremental preview of matches and replacements.
- Popup window instead of command line. This means:
	+ Syntax highlighting of the regex.
	+ Editing with vim motions.
	+ No more delimiters decreasing readability.
- Sensible defaults: searches the entire buffer (`%`), all matches in a line
  (`/g`), case-sensitive (`/I`).
- Automatic prefill of the search term: cursorword (normal mode), selected text
  (visual mode).
- Notification on how many replacements were made (optional).

## Installation
**Requirements**
- `ripgrep`
- nvim >= 0.10
- `:TSInstall regex` (optional, but recommended)

```lua
-- lazy.nvim
{
	"chrisgrieser/nvim-rip-substitute",
	keys = {
		{
			"<leader>fs",
			function() require("rip-substitute").sub() end,
			mode = { "n", "x" },
			desc = " rip substitute",
		},
	},
},

-- packer
use {
	"chrisgrieser/nvim-rip-substitute",
}
```

## Configuration

```lua
-- default settings
require("rip-substitute").setup {
	popupWin = {
		width = 40,
		border = "single",
	},
	keymaps = {
		confirm = "<CR>",
		abort = "q",
	},
	regexOptions = {
		-- pcre2 enables lookarounds and backreferences, but performs slower.
		pcre2 = true,
		-- By default, rg treats `$1a` as the named capture group "1a". When set
		-- to `true`, `$1a` is automatically changed to `${1}a` to ensure the
		-- capture group is correctly determined. Disable this setting if you
		-- plan an using named capture groups.
		autoBraceSimpleCaptureGroups = true,
	},
	prefill = {
		normal = "cursorword", -- "cursorword"|false
		visual = "selectionFirstLine", -- "selectionFirstLine"|false
	},
	notificationOnSuccess = true,
}
```

```lua
require("rip-substitute").sub()
```

## Limitations
- `--multiline` and various other flags are not supported yet.
- The incremental preview does not support *hiding* the search terms.

<!-- vale Google.FirstPerson = NO -->
## About the developer
In my day job, I am a sociologist studying the social mechanisms underlying the
digital economy. For my PhD project, I investigate the governance of the app
economy and how software ecosystems manage the tension between innovation and
compatibility. If you are interested in this subject, feel free to get in touch.

I also occasionally blog about vim: [Nano Tips for Vim](https://nanotipsforvim.prose.sh)

- [Academic Website](https://chris-grieser.de/)
- [Mastodon](https://pkm.social/@pseudometa)
- [ResearchGate](https://www.researchgate.net/profile/Christopher-Grieser)
- [LinkedIn](https://www.linkedin.com/in/christopher-grieser-ba693b17a/)

<a href='https://ko-fi.com/Y8Y86SQ91' target='_blank'><img
	height='36'
	style='border:0px;height:36px;'
	src='https://cdn.ko-fi.com/cdn/kofi1.png?v=3'
	border='0'
	alt='Buy Me a Coffee at ko-fi.com'
/></a>
