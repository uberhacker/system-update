#!/usr/bin/env bash
# lib/pkg/xbps.sh - Void Linux.

pkg_xbps_dry_needs_root() { return 0; }

pkg_xbps_update() {
  local log rc=0 count
  log=$(tmp_file) || return 1

  if [ "$SU_DRY_RUN" = 1 ]; then
    # -S sync, -u update, -n dry run
    run_capture "$log" run_root xbps-install -Sun || rc=$?
    if [ "$rc" -ne 0 ]; then
      step_fail "xbps-install -Sun failed ($(rc_note "$rc"))"
      return 0
    fi
    count=$(count_matching ' (update|install) ' "$log")
    step_dry "$count package(s) would be updated"
    return 0
  fi

  # xbps must be updated on its own first when a new version is available.
  SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_root xbps-install -Syu xbps || rc=$?
  if [ "$rc" -ne 0 ] && [ "$rc" -ne 17 ]; then
    step_fail "updating xbps failed ($(rc_note "$rc"))"
    return 0
  fi
  rc=0
  SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_capture "$log" run_root xbps-install -Syu || rc=$?
  if [ "$rc" -ne 0 ] && [ "$rc" -ne 17 ]; then
    step_fail "xbps-install -Syu failed ($(rc_note "$rc"))"
    return 0
  fi
  count=$(count_matching ' (update|install) ' "$log")
  if cfg_bool AUTOREMOVE; then
    run_root xbps-remove -Ooy >/dev/null 2>&1 || log_warn "xbps-remove -Oo failed"
  fi
  if [ "$count" = 0 ]; then
    step_ok "no updates available"
  else
    step_updated "$count package(s) updated"
  fi
}

pkg_xbps_install() {
  SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_root xbps-install -Sy "$@"
}
