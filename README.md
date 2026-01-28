# nvim-rip-substitute 🪦 <!-- rumdl-disable-line MD063 -->
<a href="https://dotfyle.com/plugins/chrisgrieser/nvim-rip-substitute">
<img alt="badge" src="https://dotfyle.com/plugins/chrisgrieser/nvim-rip-substitute/shield"/></a>

Search and replace in the current buffer or workspace with incremental preview,
a convenient UI, and modern regex syntax.

A substitute for Vim's `:substitute` using `ripgrep`.

<https://github.com/chrisgrieser/nvim-rip-substitute/assets/73286100/4afad8d8-c0d9-4ba6-910c-0510d4b9b669>

## Table of contents

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
- Search and replace in the current buffer or workspace using
  [ripgrep](https://github.com/BurntSushi/ripgrep).
- Uses **common regex syntax** — no more dealing with arcane vim regex.
- **Incremental preview** of matched strings and replacements & **live count**
  of matches.
- Uses a **popup window** instead of command line. This entails:
    - Syntax highlighting of the regex.
    - Editing with vim motions.
    - No more dealing with delimiters.
- **Sensible defaults**: entire buffer (`%`), all matches in a line (`/g`),
  case-sensitive (`/I`).
- Can substitute only in a **range**, with visual emphasis of the range.
- **History** of previous substitutions.
- **Performant**: In a file with 5000 lines and thousands of matches, still
  performs *blazingly fast.™*
- **Workspace-wide substitutions**: Optionally, execute the substitution on
  all files in the current working directory with the same extension.
- **Regex101 integration**: Open the planned substitution in a preconfigured
  [regex101](https://regex101.com/) browser tab for debugging.
- **Quality-of-Life features**: automatic prefill of the escaped cursorword,
  adaptive window width, toggle `ripgrep` flags, …

**Syntax comparison:**

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
**Requirements** <!-- rumdl-disable-line MD036 -->
- nvim 0.10+
- [ripgrep](https://github.com/BurntSushi/ripgrep) with `pcre2` support
    - `brew install ripgrep` (already includes `pcre2` by default)
    - `cargo install ripgrep --features pcre2`
    - You can also use this plugin without `pcre2` by setting
      `regexOptions.pcre2 = false` in the config. However, some features like
      lookaheads will not be supported then.
- *Optional:* `:TSInstall regex` to add syntax highlighting for the popup
  window.

```lua
-- lazy.nvim
{
	"chrisgrieser/nvim-rip-substitute",
	cmd = "RipSubstitute",
	opts = {},
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
	config = function() 
		require("rip-substitute").setup()

		vim.keymap.set(
			{ "n", "x" },
			"<leader>fs",
			function() require("rip-substitute").sub() end,
			{ desc = " rip substitute" }
		)
	end,
}
```

## Configuration

```lua
-- default settings
require("rip-substitute").setup {
	popupWin = {
		title = " rip-substitute",
		border = getBorder(), -- `vim.o.winborder` on nvim 0.11, otherwise "rounded"
		matchCountHlGroup = "Keyword",
		noMatchHlGroup = "ErrorMsg",
		position = "bottom", ---@type "top"|"bottom"
		hideSearchReplaceLabels = false,
		hideKeymapHints = false,
		disableCompletions = true, -- such as from blink.cmp
	},
	prefill = {
		normal = "cursorWord", ---@type "cursorWord"|false
		visual = "selection", ---@type "selection"|false -- (not with ex-command, see README)
		startInReplaceLineIfPrefill = false,
		alsoPrefillReplaceLine = false,
	},
	keymaps = { -- normal mode (if not stated otherwise)
		abort = "q",
		confirm = "<CR>", -- current buffer
		insertModeConfirm = "<C-CR>", -- current buffer
		confirmAndSubstituteInCwd = "<S-CR>", -- cwd, only when not using range/visual mode
		prevSubstitutionInHistory = "<Up>",
		nextSubstitutionInHistory = "<Down>",
		toggleFixedStrings = "<C-f>", -- ripgrep's `--fixed-strings`
		toggleIgnoreCase = "<C-c>", -- ripgrep's `--ignore-case`
		openAtRegex101 = "R",
		showHelp = "?",
	},
	incrementalPreview = {
		matchHlGroup = "IncSearch",
		rangeBackdropBrightness = 50, ---@type number|false 0-100, false disables backdrop
	},
	regexOptions = {
		startWithFixedStrings = false,
		startWithIgnoreCase = false,
		pcre2 = true, -- enables lookarounds and backreferences, but slightly slower
		autoBraceSimpleCaptureGroups = true, -- disable if using named capture groups (see README)
	},
	editingBehavior = {
		-- typing `()` in the search line automatically adds `$n` to the replace line
		autoCaptureGroups = false,
	},
	history = {
		---@type string|false false to disable saving history, will only have sessional history
		path = vim.fn.stdpath("data") .. "/rip-substitute/history.json",
		maxSize = 30,
	},
	notification = {
		onSuccess = true,
		icon = "",
	},
	debug = false, -- extra notifications for debugging
}
```

> [!NOTE]
> A `ripgrep` config file set via `RIPGREP_CONFIG_PATH` is ignored by this
> plugin.

## Usage
**Lua function** <!-- rumdl-disable-line MD036 -->

```lua
vim.keymap.set(
	{ "n", "x" },
	"<leader>fs",
	function() require("rip-substitute").sub() end,
	{ desc = " rip substitute" }
)
```

- Normal mode: prefills the word under the cursor (escaped)
- Visual mode: prefills the selection (escaped)
- Visual **line** mode: replacements are only applied to the selected lines
  (= the selection is used as range)

> [!TIP]
> Use `showHelp` (default keymap: `?`) to show a notification containing all
> keymaps available in the popup window.

**Ex-command** <!-- rumdl-disable-line MD036 -->
Alternatively, you can use the ex command `:RipSubstitute`, which also
accepts [a range argument](https://neovim.io/doc/user/cmdline.html#cmdline-ranges).

Note that when using the ex-command, visual mode and visual line mode both pass
a range. To prefill the current selection, you therefore need to use the Lua
function.

```vim
" Substitute in entire file. Prefills the *escaped* word under the cursor.
:RipSubstitute

" Substitute in line range of the visual selection.
:'<,'>RipSubstitute

" Substitute in given range (in this case: current line to end of file).
:.,$ RipSubstitute
```

You can also pass a prefill for the search value, in which case the prefill
is *not* escaped.

```vim
:RipSubstitute prefilled_unescaped_string
```

> [!NOTE]
> If your substitution text contains a `$`, for example, if you want to replace
> `/Users/John/` with `$HOME`, `ripgrep` requires `$` to be escaped as `$$`,
> that is, the replacement must be `$$HOME`, not `$HOME`. Due to an issue with
> `ripgrep`, you even need to escape `$` if you use `--fixed-strings` (see [#57](https://github.com/chrisgrieser/nvim-rip-substitute/issues/57#issuecomment-3728751980)).

## Advanced
**Remember prefill** <!-- rumdl-disable-line MD036 -->  
The function `require("rip-substitute").rememberCursorWord()` can be used to
save the word under the cursor for the next time `rip-substitute` is called.
(This overrides any other prefill for that run.)

One use case for this is to set a prefill for when you intend to run substitute
with a range, since calling `rip-substitute` in visual line mode is not able to
pick up a prefill.

**Filetype** <!-- rumdl-disable-line MD036 -->  
The popup window uses the filetype `rip-substitute`. This can be useful, for
instance, to disable auto-pairing plugins in the popup window.

**`autoBraceSimpleCaptureGroups`**  
A gotcha of `ripgrep`'s regex syntax is that it treats `$1a` as the named
capture group "1a" and *not* as the first capture group followed by the
letter "a" (see `ripgrep`'s man page on `--replace` for details).

If `regexOptions.autoBraceSimpleCaptureGroups = true` (the default),
`rip-substitute` automatically changes `$1a` to `${1}a`, to make writing the
regex more intuitive. However, if you regularly use named capture groups, you
may want to disable this setting.

## Limitations
- Searching/replacing for line breaks (`\n` or `\r`) is not supported ([see
  #28](https://github.com/chrisgrieser/nvim-rip-substitute/issues/28)).
- Since `nvim`'s `conceal` feature does not allow distinguishing between
  different types of concealed text, `rip-substitute`'s incremental preview
  unfortunately will activate all conceals, including the built-in conceals in
  filetypes such as `markdown` or `json`. However, this only affects the
  incremental preview, and only hides some extra syntax like `**bold**` syntax
  in `markdown` or quotation marks in `json`; the actual substitution is not
  affected.

## About the developer
In my day job, I am a sociologist studying the social mechanisms underlying the
digital economy. For my PhD project, I investigate the governance of the app
economy and how software ecosystems manage the tension between innovation and
compatibility. If you are interested in this subject, feel free to get in touch.

- [Website](https://chris-grieser.de/)
- [Mastodon](https://pkm.social/@pseudometa)
- [ResearchGate](https://www.researchgate.net/profile/Christopher-Grieser)
- [LinkedIn](https://www.linkedin.com/in/christopher-grieser-ba693b17a/)

<a href='https://ko-fi.com/Y8Y86SQ91' target='_blank'><img height='36'
style='border:0px;height:36px;' src='https://cdn.ko-fi.com/cdn/kofi1.png?v=3'
border='0' alt='Buy Me a Coffee at ko-fi.com' /></a>
