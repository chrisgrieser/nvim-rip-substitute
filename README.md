<!-- LTeX: enabled=false -->
# rip-substitute 🪦
<!-- LTeX: enabled=true -->
<!-- TODO uncomment shields when available in dotfyle.com 
<a href="https://dotfyle.com/plugins/chrisgrieser/rip-substitute">
<img alt="badge" src="https://dotfyle.com/plugins/chrisgrieser/rip-substitute/shield"/></a>
-->

A modern substitute for vim's `:substitute`, using `ripgrep`.

> [!NOTE]
> This plugin is still in early development. Its features and options are
> subject to change.

<img alt="Showcase" width=70% src="https://github.com/chrisgrieser/nvim-rip-substitute/assets/73286100/de7d4b38-e3b1-4bbb-afba-5bd8cefd8797">

## Table of Contents

<!-- toc -->

- [Features](#features)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [Advanced](#advanced)
- [Limitations](#limitations)
- [About the developer](#about-the-developer)

<!-- tocstop -->

## Features
- Search and replace in the current buffer using
  [ripgrep](https://github.com/BurntSushi/ripgrep).
- Uses common regex syntax (pcre2) — no more arcane vim regex.
- Live count of matches, incremental preview of matched strings and
  replacements.
- Popup window instead of command line. This entails:
	+ Syntax highlighting of the regex.
	+ Editing with vim motions.
	+ Snippets and completions work.
	+ No more dealing with delimiters.
- Sensible defaults: searches the entire buffer (`%`), all matches in a line
  (`/g`), case-sensitive (`/I`).
- Range support when started from visual line mode. Indicates range in the
  popup.
- Quality-of-Life features: automatic prefill of the escaped cursorword or
  selection, capture groups tokens can be automatically added, popup window
  adapts dynamically to length of input.
- History of previous substitutions.
- Performant: Even in a file with 5000 lines and thousands of matches, still
  performs blazingly fast.™
- Syntax comparison:
  ```txt
  # all three are equivalent

  # vim's :substitute
  :% s/\(foo\)bar\(\.\)\@!/\1baz/gI

  # vim's :substitute (very magic mode)
  :% s/\v(foo)bar(\.)@!/\1baz/gI

  # rip-substitute
  (foo)bar(?!\.)
  $1baz
  ```

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
		border = "single",
		matchCountHlGroup = "Keyword",
		hideSearchReplaceLabels = false,
	},
	prefill = {
		normal = "cursorWord", -- "cursorWord"|false
		visual = "selectionFirstLine", -- "selectionFirstLine"|false
	},
	keymaps = {
		-- normal & visual mode
		confirm = "<CR>",
		abort = "q",
		prevSubst = "<Up>",
		nextSubst = "<Down>",
		insertModeConfirm = "<C-CR>", -- (except this one, obviously)
	},
	incrementalPreview = {
		hlGroups = {
			replacement = "IncSearch",
			activeSearch = "IncSearch",
			inactiveSearch = "LspInlayHint",
		},
	},
	regexOptions = {
		-- pcre2 enables lookarounds and backreferences, but performs slower
		pcre2 = true,
		-- disable if you use named capture groups (see README for details)
		autoBraceSimpleCaptureGroups = true,
	},
	editingBehavior = {
		-- Experimental. When typing `()` in the `search` lines, automatically
		-- add `$n` to the `replacement` line.
		autoCaptureGroups = false,
	},
}
```

## Usage

```lua
require("rip-substitute").sub()
```

- Normal mode: prefills the cursorword.
- Visual mode: prefills the first line of the selection.
- Visual **line** mode: replacements are only applied to the selected lines,
  that is, the selection is used as range.

## Advanced
**`autoBraceSimpleCaptureGroups`**
One annoying *gotcha* of `ripgrep`'s regex syntax is it treats `$1a` as the
named capture group "1a," and *not* the as the first capture group followed by the
letter "a." (See `ripgrep`'s man page on `--replace` for details.)

If `regexOptions.autoBraceSimpleCaptureGroups = true` (the default),
`rip-substitute` automatically changes `$1a` to `${1}a`, to make writing the
regex more intuitive. However, if you regularly use named capture groups, you
may want to disable this setting.

**Filetype**
The plugin sets the filetype `rip-substitute`.

## Limitations
- `--multiline` and various other flags are not supported yet.
- This plugin only searches the current buffer. To search and replace in
  multiple files via `ripgrep`, use
  [grug-far.nvim](https://github.com/MagicDuck/grug-far.nvim).

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
