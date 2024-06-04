#!/usr/bin/env zsh
set -e # abort when any command errors, prevents self-removing at the end
#───────────────────────────────────────────────────────────────────────────────

# plugin name is the same as the git repo name and can therefore be inferred
repo=$(git remote -v | head -n1 | sed -e 's/\.git.*//' -e 's/.*:\(.*\) .*/\1/')
name=$(echo "$repo" | cut -d/ -f2)
name_short=$(echo "$name" | sed -e 's/.nvim$//' -e 's/^nvim-//')

# desc can be inferred from github description (not using jq for portability)
desc=$(curl -sL "https://api.github.com/repos/$repo" | grep --max-count=1 "description" | cut -d'"' -f4)

# current year for license
year=$(date +"%Y")

#───────────────────────────────────────────────────────────────────────────────

LC_ALL=C # prevent byte sequence error
bootstrap_file=$(basename "$0")

# replace them all
# $1: placeholder name as {{mustache-template}}
# $2: the replacement
function replacePlaceholders() {
	# INFO macOS' sed requires `sed -i ''`, remove the `''` when on Linux or using GNU sed
	find . -type f -not -path '*/\.git/*' -not -name ".DS_Store" -not -name "$bootstrap_file" -exec \
		sed -i '' "s/$1/$2/g" {} \;
}

replacePlaceholders "%%plugin-name%%" "$name"
replacePlaceholders "%%plugin-desc%%" "$desc"
replacePlaceholders "%%year%%" "$year"
replacePlaceholders "%%plugin-name-short%%" "$name_short"

#───────────────────────────────────────────────────────────────────────────────
# Files
mkdir ./lua

# for panvimdoc
mkdir ./doc
touch "./doc/$name_short.txt"

rm -- "$0" # make this script delete itself

#───────────────────────────────────────────────────────────────────────────────

git add --all && git commit -m "init: bootstrap"
print "\e[1;32mSuccess.\e[0m"
