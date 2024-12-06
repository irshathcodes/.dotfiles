#!/bin/bash

wezterm_cli="wezterm.exe cli"
project_folder="$HOME/kanbased"
fe_folder="$project_folder/frontend"
be_folder="$project_folder/backend"


run_command() {
 echo "$2" | $wezterm_cli send-text --pane-id "$1" --no-paste
}

first_focused_pane_id=$($wezterm_cli list-clients --format=json | jq ".[0].focused_pane_id")

first_pane_id=$($wezterm_cli spawn)
$wezterm_cli set-tab-title --pane-id "$first_pane_id" "frontend"
run_command "$first_pane_id" "cd $fe_folder"
run_command "$first_pane_id" "pnpm run dev"

bottom_fe_term=$($wezterm_cli split-pane --pane-id "$first_pane_id" --percent 70)
run_command "$bottom_fe_term" "cd $fe_folder"


second_pane_id=$($wezterm_cli spawn)
$wezterm_cli set-tab-title --pane-id "$second_pane_id" "backend"
run_command "$second_pane_id" "cd $be_folder"
run_command "$second_pane_id" "pnpm run dev"
right_be_term=$($wezterm_cli split-pane --pane-id "$second_pane_id" --right)
run_command "$right_be_term" "cd $be_folder"


third_pane_id=$($wezterm_cli spawn)
$wezterm_cli set-tab-title --pane-id "$third_pane_id" "pg"
run_command "$third_pane_id" "cd $be_folder"
run_command "$third_pane_id" "pnpm run dev:start-db"

fourth_pane_id=$($wezterm_cli spawn)
$wezterm_cli set-tab-title --pane-id "$fourth_pane_id" "studio"
run_command "$fourth_pane_id" "cd $be_folder"
run_command "$fourth_pane_id" "pnpm run db:studio"

fifth_pane_id=$($wezterm_cli spawn)
run_command "$fifth_pane_id" "cd $project_folder"
run_command "$fifth_pane_id" "code ."

if [[ -n $first_focused_pane_id ]]; then
$wezterm_cli kill-pane --pane-id "$first_focused_pane_id"
fi

