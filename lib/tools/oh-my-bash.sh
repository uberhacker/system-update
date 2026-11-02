#!/usr/bin/env bash
# lib/tools/oh-my-bash.sh - Oh My Bash via its tools/upgrade.sh (see oh-my-zsh.sh).

tool_oh_my_bash_detect() {
  local dir="${OSH:-$SU_USER_HOME/.oh-my-bash}"
  [ -f "$dir/tools/upgrade.sh" ] || return 1
  printf '%s\n' "$dir"
}

tool_oh_my_bash_update() {
  local dir="${SU_TOOL_BIN[oh-my-bash]}"
  shell_framework_update "Oh My Bash" "$dir" master env OSH="$dir" bash "$dir/tools/upgrade.sh"
}
