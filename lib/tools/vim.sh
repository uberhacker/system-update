#!/usr/bin/env bash
# lib/tools/vim.sh - Vim plugins kept as git submodules in ~/.vim.

tool_vim_detect() {
  [ -d "$SU_USER_HOME/.vim/.git" ] || [ -f "$SU_USER_HOME/.vim/.git" ] || return 1
  user_bin vim >/dev/null || user_bin nvim >/dev/null || return 1
  printf '%s\n' "$SU_USER_HOME/.vim"
}

tool_vim_update() {
  local dir="${SU_TOOL_BIN[vim]}" before after count rc=0
  before=$(run_user git -C "$dir" submodule status 2>/dev/null)
  count=$(printf '%s\n' "$before" | grep -c . || true)
  if [ "$count" = 0 ]; then
    step_skip "no git submodules in $dir"
    return 0
  fi
  log_info "$count submodule(s) in $dir"
  if [ "$SU_DRY_RUN" = 1 ]; then
    step_dry "would run git submodule update --init --remote --recursive for $count submodule(s)"
    return 0
  fi
  do_user git -C "$dir" submodule update --init --remote --recursive --jobs 4 || rc=$?
  if [ "$rc" -ne 0 ]; then
    step_fail "git submodule update failed ($(rc_note "$rc"))"
    return 0
  fi
  after=$(run_user git -C "$dir" submodule status 2>/dev/null)
  if [ "$before" != "$after" ]; then
    step_updated "submodules moved to new commits (commit the change in $dir to keep it)"
  else
    step_ok "all $count submodule(s) up to date"
  fi
}
