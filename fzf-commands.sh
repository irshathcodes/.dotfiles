#!/usr/bin/env bash

function fgf() {
	local -r prompt_add="Add > "
	local -r prompt_reset="Reset > "

	local -r git_root_dir=$(git rev-parse --show-toplevel)
	local -r git_unstaged_files="git -C $git_root_dir status --short | grep -E \"^(\\?\\?|.[MD])\""

	local git_staged_files="git -C $git_root_dir status --short | grep -E \"^[AMDRC]\""

	local -r strip="cut -c4-"
	local -r git_reset="echo {+} | $strip | xargs git reset --"
	local -r git_add="echo {+} | $strip | xargs git add"
	local -r enter_cmd="if [[ \$FZF_PROMPT =~ '$prompt_add' ]]; then $git_add; else $git_reset; fi"

	local -r header=$(cat <<-EOF
		> CTRL-S to switch between Add Mode and Reset mode
		> enter for diff preview, ctrl-enter for staging / resetting
		> ALT-E to open files in your editor
		EOF
	)

	local -r add_header=$(cat <<-EOF
		$header
		> ALT-P to add patch
	EOF
	)

	local -r reset_header=$(cat <<-EOF
		$header
	EOF
	)

	local -r mode_reset="change-prompt($prompt_reset)+reload($git_staged_files)+change-header($reset_header)"
	local -r mode_add="change-prompt($prompt_add)+reload($git_unstaged_files)+change-header($add_header)+rebind(alt-p)+unbind(alt-d)"

	eval "$git_unstaged_files" | fzf \
	--multi \
	--reverse \
	--no-sort \
	--prompt="Add > " \
	--header "$add_header" \
	--header-first \
	--bind="enter:execute(echo {+} | $strip | xargs git difftool --no-symlinks)" \
	--bind="ctrl-e:execute(git difftool --no-symlinks --dir-diff)" \
	--bind="ctrl-s:transform:[[ \$FZF_PROMPT =~ '$prompt_add' ]] && echo '$mode_reset' || echo '$mode_add'" \
	--bind="alt-enter:execute($enter_cmd)" \
	--bind="alt-enter:+reload([[ \$FZF_PROMPT =~ '$prompt_add' ]] && $git_unstaged_files || $git_staged_files)" \
	--bind="enter:+refresh-preview" \
	--bind="alt-p:execute(echo {+} | $strip | xargs git add --patch)" \
	--bind="alt-p:+reload($git_unstaged_files)" \
	--bind="alt-e:execute(echo {+} | $strip | xargs \${EDITOR:-vim})" \
	--bind='f1:toggle-header' \
}

