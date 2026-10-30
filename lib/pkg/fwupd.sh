#!/usr/bin/env bash
# lib/pkg/fwupd.sh - firmware updates with fwupd.
#
# Always: refresh metadata and list available updates. Apply only with
# FIRMWARE=1 (--firmware), because firmware updates may need a reboot and
# cannot be undone. fwupdmgr exit codes: 0 ok, 1 error, 2 nothing to do.

# fwupd_changes LOGFILE: "device|current|new" from `fwupdmgr get-updates`.
# A device block carries "Current version:", each release under it
# "New version:"; the tree characters (│ └─ ├─) are ignored.
fwupd_changes() {
  local line header="" device="" current="" value
  while IFS= read -r line; do
    line="${line//│/ }"
    if [[ "$line" =~ [└├]─(.+):[[:space:]]*$ ]]; then
      header="${BASH_REMATCH[1]}"; continue
    fi
    if [[ "$line" =~ ^[[:space:]]*(Current|New)\ version:[[:space:]]+([^[:space:]]+) ]]; then
      value="${BASH_REMATCH[2]}"
      if [ "${BASH_REMATCH[1]}" = Current ]; then
        device="$header"; current="$value"
      elif [ -n "$device" ]; then
        printf '%s|%s|%s\n' "$device" "$current" "$value"
      fi
    fi
  done < "$1"
}

fwupd_step() {
  local log rc=0 count
  has_cmd fwupdmgr || { step_skip "fwupd not installed"; return 0; }
  if in_container; then step_skip "running in a container"; return 0; fi
  log=$(tmp_file) || return 1

  run_root fwupdmgr refresh >/dev/null 2>&1 || rc=$?
  case "$rc" in
    0|2) ;;
    *) step_skip "fwupd daemon unavailable (refresh failed with $rc)"; return 0 ;;
  esac
  rc=0
  run_capture "$log" run_root fwupdmgr get-updates --no-unreported-check --no-metadata-check || rc=$?
  case "$rc" in
    0) ;;
    2) step_ok "no firmware updates available"; return 0 ;;
    *) step_fail "fwupdmgr get-updates failed ($(rc_note "$rc"))"; return 0 ;;
  esac
  count=$(count_matching '^(│|\|)? *└?─?[^ ].*New version:' "$log")
  [ "${count:-0}" -gt 0 ] || count=$(count_matching 'New version' "$log")
  detail_show "firmware update(s)" fwupd_changes "$log"

  if ! cfg_bool FIRMWARE; then
    log_warn "firmware updates are available; rerun with --firmware to apply them"
    step_ok "${count:-some} firmware update(s) available (not applied; use --firmware)"
    return 0
  fi
  if [ "$SU_DRY_RUN" = 1 ]; then
    step_dry "${count:-some} firmware update(s) would be applied"
    return 0
  fi
  rc=0
  SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_root fwupdmgr update -y --no-reboot-check || rc=$?
  case "$rc" in
    0) log_warn "firmware updated; a reboot may be required to finish"; step_updated "firmware updated (reboot may be required)" ;;
    2) step_ok "nothing to do" ;;
    *) step_fail "fwupdmgr update failed ($(rc_note "$rc"))" ;;
  esac
}
