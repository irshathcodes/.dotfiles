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
	local -r git_restore="echo {+} | $strip | xargs git checkout --"
	local -r enter_cmd="if [[ \$FZF_PROMPT =~ '$prompt_add' ]]; then $git_add; else $git_reset; fi"

	local -r add_header=$(cat <<-EOF
		> CTRL-S to switch between Add Mode and Reset mode
		> enter to stage, alt-r to restore, ctrl-d for diff
		> ctrl-e to open in editor, alt-p to add patch
		EOF
	)

	local -r reset_header=$(cat <<-EOF
		> CTRL-S to switch between Add Mode and Reset mode
		> enter to unstage, ctrl-d for diff, ctrl-e to open in editor
		EOF
	)

	local -r mode_reset="change-prompt($prompt_reset)+reload($git_staged_files)+change-header($reset_header)+unbind(alt-p)+unbind(alt-r)"
	local -r mode_add="change-prompt($prompt_add)+reload($git_unstaged_files)+change-header($add_header)+rebind(alt-p)+rebind(alt-r)"

	eval "$git_unstaged_files" | fzf \
	--multi \
	--reverse \
	--no-sort \
	--prompt="Add > " \
	--header "$add_header" \
	--header-first \
	--bind="enter:execute($enter_cmd)" \
	--bind="enter:+reload([[ \$FZF_PROMPT =~ '$prompt_add' ]] && $git_unstaged_files || $git_staged_files)" \
	--bind="alt-r:execute($git_restore)" \
	--bind="alt-r:+reload($git_unstaged_files)" \
	--bind="ctrl-d:execute(echo {+} | $strip | xargs git difftool --no-symlinks)" \
	--bind="ctrl-d:+refresh-preview" \
	--bind="ctrl-e:execute(echo {+} | $strip | xargs \${EDITOR:-nvim})" \
	--bind="ctrl-s:transform:[[ \$FZF_PROMPT =~ '$prompt_add' ]] && echo '$mode_reset' || echo '$mode_add'" \
	--bind="alt-p:execute(echo {+} | $strip | xargs git add --patch)" \
	--bind="alt-p:+reload($git_unstaged_files)" \
	--bind='f1:toggle-header' \
}

