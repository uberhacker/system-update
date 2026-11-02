#!/usr/bin/env bash
# lib/tools/tpm.sh - tmux plugins through TPM (bin/update_plugins all).
#
# TPM's scripts talk to a tmux server, so tmux must be installed; they run
# as the user with a timeout. Each plugin is a git checkout: the commits
# before and after say how many moved.

tpm_plugins_dir() { printf '%s\n' "${TMUX_PLUGIN_MANAGER_PATH:-$SU_USER_HOME/.tmux/plugins}"; }

tool_tpm_detect() {
  local script
  script="$(tpm_plugins_dir)/tpm/bin/update_plugins"
  [ -x "$script" ] || [ -f "$script" ] || return 1
  printf '%s\n' "$script"
}

# tpm_heads: "<plugin> <commit>" for every plugin checkout.
tpm_heads() {
  local d
  for d in "$(tpm_plugins_dir)"/*/; do
    [ -d "$d/.git" ] || [ -f "$d/.git" ] || continue
    printf '%s %s\n' "$(basename "$d")" "$(git -C "$d" rev-parse --short HEAD 2>/dev/null || echo '?')"
  done
}

tool_tpm_update() {
  local script="${SU_TOOL_BIN[tpm]}" before after count rc=0 moved
  has_cmd tmux || { step_skip "tmux is not installed"; return 0; }
  before=$(tpm_heads)
  count=$(printf '%s\n' "$before" | grep -c . || true)
  if [ "$count" -eq 0 ]; then
    step_skip "no plugins installed under $(tpm_plugins_dir)"
    return 0
  fi
  log_info "$count plugin(s) under $(tpm_plugins_dir)"
  if [ "$SU_DRY_RUN" = 1 ]; then
    step_dry "would run tpm/bin/update_plugins all for $count plugin(s)"
    return 0
  fi
  run_user env TMUX_PLUGIN_MANAGER_PATH="$(tpm_plugins_dir)" bash "$script" all || rc=$?
  if [ "$rc" -ne 0 ]; then
    step_fail "update_plugins all failed ($(rc_note "$rc"))"
    return 0
  fi
  after=$(tpm_heads)
  moved=$(printf '%s\n%s\n' "$before" "$after" | sort | uniq -u | cut -d' ' -f1 | sort -u | grep -c . || true)
  if [ "$moved" -gt 0 ]; then
    step_updated "$moved of $count plugin(s) updated"
  else
    step_ok "$count plugin(s) up to date"
  fi
}
