#!/usr/bin/env bash
# lib/tools/rvm.sh - RVM (rvm get stable), run as the invoking user.

tool_rvm_detect() {
  if [ -x "$SU_USER_HOME/.rvm/bin/rvm" ]; then
    printf '%s\n' "$SU_USER_HOME/.rvm/bin/rvm"
  else
    user_bin rvm
  fi
}

tool_rvm_update() {
  local bin="${SU_TOOL_BIN[rvm]}" installed latest rc=0 after
  installed=$(version_from_text "$(tool_probe "$bin" -v)")
  [ -n "$installed" ] && log_info "installed version: $installed"
  if latest=$(gh_latest_name rvm/rvm); then
    latest=$(version_norm "$latest")
    log_info "latest release: $latest"
    if [ -n "$installed" ] && ! version_lt "$installed" "$latest"; then
      step_ok "up to date ($installed)"
      return 0
    fi
  else
    log_info "latest release unknown; letting rvm decide"
  fi
  if [ "$SU_DRY_RUN" = 1 ]; then
    step_dry "would run 'rvm get stable'${installed:+ (installed $installed)}"
    return 0
  fi
  do_user "$bin" get stable || rc=$?
  if [ "$rc" -ne 0 ]; then
    step_fail "rvm get stable failed ($(rc_note "$rc"))"
    return 0
  fi
  after=$(version_from_text "$(tool_probe "$bin" -v)")
  if [ -n "$installed" ] && [ -n "$after" ] && [ "$installed" != "$after" ]; then
    step_updated "$installed -> $after"
  else
    step_ok "up to date (${after:-$installed})"
  fi
}
