#!/usr/bin/env bash
# lib/pkg/apk.sh - Alpine Linux.

pkg_apk_dry_needs_root() { return 0; }

pkg_apk_update() {
  local log rc=0 count
  log=$(tmp_file) || return 1

  SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_root apk update -q || { step_fail "apk update failed"; return 0; }

  if [ "$SU_DRY_RUN" = 1 ]; then
    run_capture "$log" run_root apk upgrade -s || rc=$?
    if [ "$rc" -ne 0 ]; then
      step_fail "apk upgrade -s failed ($(rc_note "$rc"))"
      return 0
    fi
    count=$(count_matching '^\([0-9]+/[0-9]+\) (Upgrading|Installing|Downgrading)' "$log")
    step_dry "$count package(s) would be upgraded"
    return 0
  fi

  SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_capture "$log" run_root apk upgrade || rc=$?
  if [ "$rc" -ne 0 ]; then
    step_fail "apk upgrade failed ($(rc_note "$rc"))"
    return 0
  fi
  count=$(count_matching '^\([0-9]+/[0-9]+\) (Upgrading|Installing|Downgrading)' "$log")
  run_root apk cache clean >/dev/null 2>&1 || true
  if [ "$count" = 0 ]; then
    step_ok "no updates available"
  else
    step_updated "$count package(s) upgraded"
  fi
}

pkg_apk_install() {
  SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_root apk add "$@"
}
