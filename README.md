<!-- LTeX: enabled=false -->
# rip-substitute 🪦
<!-- LTeX: enabled=true -->
<a href="https://dotfyle.com/plugins/chrisgrieser/nvim-rip-substitute">
<img alt="badge" src="https://dotfyle.com/plugins/chrisgrieser/nvim-rip-substitute/shield"/></a>

Perform search and replace operations in the current buffer using a modern user
interface and contemporary regex syntax.

<https://github.com/chrisgrieser/nvim-rip-substitute/assets/73286100/4afad8d8-c0d9-4ba6-910c-0510d4b9b669>

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
- Uses **common regex syntax** — no more dealing with arcane vim regex.
- **Incremental preview** of matched strings and replacements, **live count** of
  matches.
- Popup window instead of command line. This entails:
	+ Syntax highlighting of the regex.
	+ Editing with vim motions.
	+ No more dealing with delimiters.
- **Sensible defaults**: entire buffer (`%`), all matches in a line
  (`/g`), case-sensitive (`/I`).
- **Range support**
- **History** of previous substitutions.
- **Performant**: In a file with 5000 lines and thousands of matches, still
  performs *blazingly fast*.™
- **Regex101 integration**: Open the planned substitution in a pre-configured
  [regex101](https://regex101.com/) browser-tab for debugging.
- **Quality-of-Life features**: automatic prefill of the escaped cursorword,
  adaptive popup window width, visual emphasis of the active range, …
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
- [ripgrep](https://github.com/BurntSushi/ripgrep) with `pcre2` support
	+ homebrew: `brew install ripgrep` (already includes `pcre2` by default)
	+ cargo: `cargo install ripgrep --features "pcre2"`
	+ You can also use this plugin without `pcre2` by setting
	  `regexOptions.pcre2 = false` in the [plugin config](#configuration).
- `nvim` >= 0.10
- `:TSInstall regex` (only needed for syntax highlighting)

```lua
-- lazy.nvim
{
	"chrisgrieser/nvim-rip-substitute",
	cmd = "RipSubstitute",
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
		title = " rip-substitute",
		border = "single",
		matchCountHlGroup = "Keyword",
		noMatchHlGroup = "ErrorMsg",
		hideSearchReplaceLabels = false,
		position = "bottom", -- "top"|"bottom"
	},
	prefill = {
		normal = "cursorWord", -- "cursorWord"|false
		visual = "selectionFirstLine", -- "selectionFirstLine"|false
		startInReplaceLineIfPrefill = false,
	},
	keymaps = {
		-- normal & visual mode
		confirm = "<CR>",
		abort = "q",
		prevSubst = "<Up>",
		nextSubst = "<Down>",
		openAtRegex101 = "R",
		insertModeConfirm = "<C-CR>", -- (except this one, obviously)
	},
	incrementalPreview = {
		matchHlGroup = "IncSearch",
		rangeBackdrop = {
			enabled = true,
			blend = 50, -- between 0 and 100
		},
	},
	regexOptions = {
		-- pcre2 enables lookarounds and backreferences, but performs slower
		pcre2 = true,
		---@type "case-sensitive"|"ignore-case"|"smart-case"
		casing = "case-sensitive",
		-- disable if you use named capture groups (see README for details)
		autoBraceSimpleCaptureGroups = true,
	},
	editingBehavior = {
		-- Experimental. When typing `()` in the `search` line, automatically
		-- adds `$n` to the `replace` line.
		autoCaptureGroups = false,
	},
	notificationOnSuccess = true,
}
```

> [!NOTE]
> Any `ripgrep` config file set via `RIPGREP_CONFIG_PATH` is ignored by this
> plugin.

## Usage
**lua function**  
```lua
vim.keymap.set(
	{ "n", "x" },
	"<leader>fs",
	function() require("rip-substitute").sub() end,
	{ desc = " rip substitute" }
)
```

- Normal mode: prefills the cursorword.
- Visual mode: prefills the selection.
- Visual **line** mode: replacements are only applied to the selected lines
  (the selection is used as range).

**Ex command**  
Alternatively, you can use the ex command `:RipSubstitute`, which also
accepts [a range
argument](https://neovim.io/doc/user/cmdline.html#cmdline-ranges). Note that
when using the ex command, visual mode and visual line mode both pass a range.
To prefill the current selection, you therefore need to use the lua function.

```vim
" Substitute in entire file. Prefills the cursorword.
:RipSubstitute

" Substitute in line range of the visual selection.
:'<,'>RipSubstitute

" Substitute in given range (in this case: current line to end of file).
:.,$ RipSubstitute
```

You can also pass a prefill for the search value, in which
case the prefill is not escaped.

```vim
:RipSubstitute prefilled string
```

## Advanced
**`autoBraceSimpleCaptureGroups`**  
A gotcha of `ripgrep`'s regex syntax is that it treats `$1a` as the named
capture group "1a" and *not* as the first capture group followed by the
letter "a." (See `ripgrep`'s man page on `--replace` for details.)

If `regexOptions.autoBraceSimpleCaptureGroups = true` (the default),
`rip-substitute` automatically changes `$1a` to `${1}a`, to make writing the
regex more intuitive. However, if you regularly use named capture groups, you
may want to disable this setting.

**Filetype**  
The popup window uses the filetype `rip-substitute`. This can be useful, for
instance, to disable auto-pairing plugins in the popup window.

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
