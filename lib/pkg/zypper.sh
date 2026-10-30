#!/usr/bin/env bash
# lib/pkg/zypper.sh - openSUSE Tumbleweed/Slowroll/MicroOS (dup) and Leap/SLE (update).

ZYPPER=(zypper --non-interactive --no-color)

pkg_zypper_dry_needs_root() { return 0; }

zypper_refresh() {
  SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_root "${ZYPPER[@]}" refresh
}

# zypper_count LOGFILE: sum of "The following N packages are going to be upgraded/installed".
zypper_count() {
  local n sum=0
  while read -r n; do
    sum=$((sum + n))
  done < <(grep -E -o 'The following [0-9]+ (NEW )?packages? (are|is) going to be (upgraded|installed)' "$1" \
    | grep -E -o '[0-9]+')
  printf '%s\n' "$sum"
}

pkg_zypper_update() {
  local mode="$SU_ZYPPER_MODE" log rc=0 count note
  log=$(tmp_file) || return 1
  log_info "mode: zypper $mode (${SU_OS_PRETTY})"

  zypper_refresh || { step_fail "zypper refresh failed"; return 0; }

  if [ "$SU_DRY_RUN" = 1 ]; then
    SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_capture "$log" run_root "${ZYPPER[@]}" "$mode" --dry-run || rc=$?
    if [ "$rc" -ne 0 ] && [ "$rc" -ne 100 ]; then
      step_fail "zypper $mode --dry-run failed ($(rc_note "$rc"))"
      return 0
    fi
    count=$(zypper_count "$log")
    if grep -q 'Nothing to do' "$log"; then
      step_dry "no updates available"
    else
      step_dry "$count package(s) would be upgraded/installed"
    fi
    return 0
  fi

  SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_capture "$log" run_root "${ZYPPER[@]}" "$mode" || rc=$?
  if [ "$rc" -eq 103 ]; then
    # zypper itself was updated; run once more.
    log_info "zypper was updated; running $mode again"
    rc=0
    SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_capture "$log" run_root "${ZYPPER[@]}" "$mode" || rc=$?
  fi
  case "$rc" in
    0|102) ;;
    *) step_fail "zypper $mode failed ($(rc_note "$rc"))"; return 0 ;;
  esac
  count=$(zypper_count "$log")
  if grep -q 'Nothing to do' "$log" && [ "$count" = 0 ]; then
    step_ok "no updates available"
  else
    note="$count package(s) upgraded/installed"
    [ "$rc" = 102 ] && note="$note; reboot required"
    step_updated "$note"
  fi
}

pkg_zypper_install() {
  SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_root "${ZYPPER[@]}" install "$@"
}

pkg_zypper_reboot_check() {
  local rc=0
  zypper needs-rebooting >/dev/null 2>&1 || rc=$?
  case "$rc" in
    0) return 1 ;;
    102) echo "zypper needs-rebooting reports a pending reboot"; return 0 ;;
    *) return 2 ;;
  esac
}
