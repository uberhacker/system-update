#!/usr/bin/env bash
# lib/tools/oh-my-zsh.sh - Oh My Zsh via its own tools/upgrade.sh, non-interactively.
#
# Also provides shell_framework_update(), shared with oh-my-bash.sh: both
# frameworks are git checkouts updated by a bundled script; the commit before
# and after tells us whether anything changed. upgrade.sh exits 80 when it
# is already current, which is a success.

tool_oh_my_zsh_detect() {
  local dir="${ZSH:-$SU_USER_HOME/.oh-my-zsh}"
  [ -f "$dir/tools/upgrade.sh" ] || return 1
  printf '%s\n' "$dir"
}

# shell_framework_update NAME DIR BRANCH CMD...: run the framework's own
# upgrade command (CMD) as the user and report by comparing HEAD.
shell_framework_update() {
  local name="$1" dir="$2" branch="$3"; shift 3
  local before after rc=0 behind
  if [ ! -d "$dir/.git" ] && [ ! -f "$dir/.git" ]; then
    step_skip "$dir is not a git checkout; its upgrade script cannot update it"
    return 0
  fi
  has_cmd git || { step_skip "git is not installed"; return 0; }
  before=$(run_user git -C "$dir" rev-parse --short HEAD 2>/dev/null || true)
  if [ "$SU_DRY_RUN" = 1 ]; then
    if run_user git -C "$dir" fetch --quiet origin "$branch" 2>/dev/null; then
      behind=$(run_user git -C "$dir" rev-list --count "HEAD..origin/$branch" 2>/dev/null || echo '?')
      if [ "$behind" = 0 ]; then
        step_dry "already at the latest version (${before:-?})"
      else
        step_dry "$behind commit(s) behind origin/$branch; would run $name's upgrade script"
      fi
    else
      step_dry "would run $name's upgrade script (could not fetch origin/$branch)"
    fi
    return 0
  fi
  run_user "$@" || rc=$?
  case "$rc" in
    0|80) ;;
    *) step_fail "$name upgrade script failed ($(rc_note "$rc"))"; return 0 ;;
  esac
  after=$(run_user git -C "$dir" rev-parse --short HEAD 2>/dev/null || true)
  if [ -n "$before" ] && [ -n "$after" ] && [ "$before" != "$after" ]; then
    step_updated "$before -> $after"
  else
    step_ok "already at the latest version${after:+ ($after)}"
  fi
}

tool_oh_my_zsh_update() {
  local dir="${SU_TOOL_BIN[oh-my-zsh]}"
  has_cmd zsh || { step_skip "zsh is not installed"; return 0; }
  # No -i/--interactive: the script then never prompts.
  shell_framework_update "Oh My Zsh" "$dir" master env ZSH="$dir" DISABLE_UPDATE_PROMPT=true zsh "$dir/tools/upgrade.sh"
}
