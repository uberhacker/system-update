#!/usr/bin/env bash
# lib/tools/npm-globals.sh - `npm update -g` (opt-in: NPM_GLOBALS=1 / --npm-globals).
#
# Only for a Node that belongs to the user (nvm, nodebrew, ~/.npm-global):
# the global prefix must be inside the user's home. A distro Node's prefix
# (/usr, /usr/local) is root-owned and is never written to.

tool_npm_globals_detect() {
  local npm real
  npm=$(user_bin npm) || return 1
  real=$(readlink -f -- "$npm" 2>/dev/null || printf '%s' "$npm")
  case "$real" in
    "$SU_USER_HOME"/*) printf '%s\n' "$npm" ;;
    *) return 1 ;;
  esac
}

tool_npm_globals_update() {
  local npm="${SU_TOOL_BIN[npm-globals]}" prefix log outdated rc=0
  tool_opt_in NPM_GLOBALS --npm-globals || return 0
  prefix=$(SU_RUN_TIMEOUT=$SU_PROBE_TIMEOUT run_user "$npm" prefix -g 2>/dev/null | tail -n1)
  case "$prefix" in
    "$SU_USER_HOME"/*) ;;
    *) step_skip "global prefix '${prefix:-?}' is not inside $SU_USER_HOME; refusing to write there"; return 0 ;;
  esac
  log_info "global prefix: $prefix"
  log=$(tmp_file) || return 1
  # `npm outdated` exits 1 when something is outdated; that is not an error.
  run_user "$npm" outdated -g --parseable >"$log" 2>/dev/null || true
  outdated=$(grep -c . "$log" || true)
  if [ "$SU_DRY_RUN" = 1 ]; then
    if [ "$outdated" -gt 0 ]; then
      step_dry "$outdated outdated global package(s); would run npm update -g"
    else
      step_dry "all global packages up to date"
    fi
    return 0
  fi
  if [ "$outdated" -eq 0 ]; then
    step_ok "all global packages up to date"
    return 0
  fi
  SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_user env NO_UPDATE_NOTIFIER=1 npm_config_fund=false "$npm" update -g || rc=$?
  if [ "$rc" -ne 0 ]; then
    step_fail "npm update -g failed ($(rc_note "$rc"))"
    return 0
  fi
  step_updated "$outdated global package(s) updated"
}
