#!/usr/bin/env bash
# lib/pkg/emerge.sh - Gentoo (best effort, untested in CI).
#
# A world update on Gentoo can take hours and may need manual USE/keyword
# changes; this module only does the straightforward part and reports.

pkg_emerge_dry_needs_root() { return 1; }

pkg_emerge_update() {
  local log rc=0 count
  log=$(tmp_file) || return 1
  log_warn "Gentoo support is best effort: emerge --sync followed by emerge -uDN @world"

  if [ "$SU_DRY_RUN" = 1 ]; then
    run_capture "$log" run_root emerge --pretend --update --deep --newuse --color n @world || rc=$?
    if [ "$rc" -ne 0 ]; then
      step_fail "emerge --pretend failed ($(rc_note "$rc"))"
      return 0
    fi
    count=$(count_matching '^\[ebuild' "$log")
    step_dry "$count package(s) would be rebuilt/updated (tree not synced in dry run)"
    return 0
  fi

  SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_root emerge --sync --quiet || { step_fail "emerge --sync failed"; return 0; }
  SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_capture "$log" run_root emerge --update --deep --newuse --color n @world || rc=$?
  if [ "$rc" -ne 0 ]; then
    step_fail "emerge @world failed ($(rc_note "$rc"))"
    return 0
  fi
  count=$(count_matching '^>>> Installing' "$log")
  if cfg_bool AUTOREMOVE; then
    SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_root emerge --depclean --quiet || log_warn "emerge --depclean failed"
  fi
  if [ "$count" = 0 ]; then
    step_ok "no updates available"
  else
    step_updated "$count package(s) installed"
  fi
}

pkg_emerge_install() {
  SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_root emerge --noreplace --quiet "$@"
}
