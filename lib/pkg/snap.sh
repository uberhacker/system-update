#!/usr/bin/env bash
# lib/pkg/snap.sh - snapd.

# snap_changes REFRESH_LIST: "name|installed|new" from `snap refresh --list`
# (Name Version Rev ...) joined with the versions from `snap list`.
snap_changes() {
  local name ver _rest
  local -A have=()
  while read -r name ver _rest; do
    [ "$name" = Name ] || have[$name]="$ver"
  done < <(snap list 2>/dev/null)
  while read -r name ver _rest; do
    [ -n "$name" ] && [ "$name" != Name ] && [ -n "$ver" ] || continue
    printf '%s|%s|%s\n' "$name" "${have[$name]:-?}" "$ver"
  done < "$1"
}

snap_step() {
  local log rc=0 count
  has_cmd snap || { step_skip "snap not installed"; return 0; }
  if ! snap version >/dev/null 2>&1 || [ ! -S /run/snapd.socket ]; then
    step_skip "snapd is not running"
    return 0
  fi
  log=$(tmp_file) || return 1

  if [ "$SU_DRY_RUN" = 1 ]; then
    run_capture "$log" snap refresh --list || rc=$?
    if [ "$rc" -ne 0 ]; then step_fail "snap refresh --list failed ($(rc_note "$rc"))"; return 0; fi
    if grep -q 'All snaps up to date' "$log"; then
      step_dry "no updates available"
    else
      count=$(grep -c -E '^[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+[0-9]+' "$log" || true)
      detail_show "snap(s)" snap_changes "$log"
      step_dry "$count snap(s) would be refreshed"
    fi
    return 0
  fi

  SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_capture "$log" run_root snap refresh || rc=$?
  if [ "$rc" -ne 0 ]; then step_fail "snap refresh failed ($(rc_note "$rc"))"; return 0; fi
  if grep -q 'All snaps up to date' "$log"; then
    step_ok "no updates available"
  else
    count=$(count_matching ' refreshed$' "$log")
    step_updated "${count:-some} snap(s) refreshed"
  fi
}
