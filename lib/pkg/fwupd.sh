#!/usr/bin/env bash
# lib/pkg/fwupd.sh - firmware updates with fwupd.
#
# Always: refresh metadata and list available updates. Apply only with
# FIRMWARE=1 (--firmware), because firmware updates may need a reboot and
# cannot be undone. fwupdmgr exit codes: 0 ok, 1 error, 2 nothing to do.
#
# `fwupdmgr get-updates` lists every newer release of every device, and
# keeps listing a device whose update could not be installed:
#   * an update scheduled for the next boot (UEFI capsules, dbx) stays listed
#     until the reboot ("Update State: Pending", or the problem "Device is
#     waiting for the update to be applied");
#   * an update that failed stays listed ("Update State: Failed" and an
#     "Update Error");
#   * a device with "Problems" (on battery, lid closed, ...) is skipped by
#     `fwupdmgr update`, which still exits 0.
# So the step counts devices, not releases, says which of these applies to
# each one, and reads the list again after an update to see what changed.

# Set when firmware waits for a reboot; the reboot-check step reports it.
SU_FIRMWARE_REBOOT=""

# fwupd_devices LOGFILE: one line per device offered an update, from the
# text of `LC_ALL=C fwupdmgr get-updates`:
#   name|current|newest|state|note
# state is one of
#   available  can be installed now
#   failed     the last attempt failed (note: the update error)
#   pending    already scheduled; finishes on the next boot
#   blocked    fwupd will not install it now (note: the problems)
# A device node has a "Device ID" (or "Current version"); a release node
# under it has a "New version". The tree characters (│ ├─ └─) are ignored.
fwupd_devices() {
  local line header="" key value last_key="" esc=$'\e'
  local -a names=() current=() newest=() ustate=() uerror=() problems=()
  local i=-1 n state note
  while IFS= read -r line || [ -n "$line" ]; do
    while [[ "$line" =~ ^(.*)$esc\[[0-9\;]*m(.*)$ ]]; do
      line="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
    done
    line="${line//│/ }"
    line="${line//$'\r'/}"
    if [[ "$line" =~ [└├]─[[:space:]]*(.+):[[:space:]]*$ ]]; then
      header="${BASH_REMATCH[1]}"; last_key=""; continue
    fi
    if [[ "$line" =~ ^[[:space:]]*([A-Z][A-Za-z ]*[A-Za-z]):[[:space:]]+(.*[^[:space:]])[[:space:]]*$ ]]; then
      key="${BASH_REMATCH[1]}"; value="${BASH_REMATCH[2]}"; last_key="$key"
    elif [[ "$line" =~ ^[[:space:]]*•[[:space:]]*(.*[^[:space:]])[[:space:]]*$ ]]; then
      key="$last_key"; value="•${BASH_REMATCH[1]}"
      [ "$key" = Problems ] || continue
    else
      last_key=""; continue
    fi
    case "$key" in
      "Device ID"|"Current version")
        if [ "$i" -lt 0 ] || [ "${names[$i]}" != "$header" ] || [ "$header" = "" ]; then
          i=$((i + 1)); names[i]="$header"; current[i]=""; newest[i]=""
          ustate[i]=""; uerror[i]=""; problems[i]=""
        fi
        [ "$key" = "Current version" ] && current[i]="$value"
        ;;
      "New version")
        [ "$i" -ge 0 ] && [ -z "${newest[$i]}" ] && newest[i]="$value"
        ;;
      "Update State") [ "$i" -ge 0 ] && ustate[i]="$value" ;;
      "Update Error") [ "$i" -ge 0 ] && uerror[i]="$value" ;;
      Problems)
        [ "$i" -ge 0 ] || continue
        value="${value#•}"; value="${value# }"
        problems[i]="${problems[$i]:+${problems[$i]}; }$value"
        ;;
    esac
  done < "$1"
  for ((n = 0; n <= i; n++)); do
    [ -n "${newest[$n]}" ] || continue
    note=""
    case "${problems[$n]}" in
      *"waiting for the update to be applied"*) state=pending ;;
      ?*) state=blocked; note="${problems[$n]}" ;;
      *)
        case "${ustate[$n]}" in
          Pending|"Needs reboot") state=pending ;;
          Failed|"Transient failure") state=failed; note="${uerror[$n]:-the last update attempt failed}" ;;
          *) state=available ;;
        esac ;;
    esac
    printf '%s|%s|%s|%s|%s\n' "${names[$n]}" "${current[$n]}" "${newest[$n]}" "$state" "${note//|//}"
  done
}

# fwupd_changes LOGFILE: "device|current|new" for --detailed.
fwupd_changes() {
  local name cur new state note
  while IFS='|' read -r name cur new state note; do
    printf '%s|%s|%s\n' "$name" "$cur" "$new"
  done < <(fwupd_devices "$1")
}

# fwupd_count DEVICES_FILE STATE...: devices in any of the states.
fwupd_count() {
  local file="$1" name cur new state note n=0 s; shift
  while IFS='|' read -r name cur new state note; do
    for s in "$@"; do [ "$state" = "$s" ] && n=$((n + 1)); done
  done < "$file"
  echo "$n"
}

# fwupd_names DEVICES_FILE STATE...: "A, B" for the devices in any STATE.
fwupd_names() {
  local file="$1" name cur new state note out="" s; shift
  while IFS='|' read -r name cur new state note; do
    for s in "$@"; do [ "$state" = "$s" ] && out="${out:+$out, }$name"; done
  done < "$file"
  printf '%s\n' "$out"
}

# fwupd_report DEVICES_FILE: one line per device for the log.
fwupd_report() {
  local name cur new state note what
  while IFS='|' read -r name cur new state note; do
    case "$state" in
      available) what="available" ;;
      failed)    what="the last attempt failed: $note" ;;
      pending)   what="scheduled; finishes on the next reboot" ;;
      blocked)   what="fwupd will not install it now: $note" ;;
    esac
    log_info "$name ${cur:-?} -> $new ($what)"
  done < "$1"
}

# fwupd_note DEVICES_FILE: the parts of the summary for devices that are not
# simply available, e.g. "1 waiting for a reboot (UEFI dbx)".
fwupd_note() {
  local file="$1" n out=""
  n=$(fwupd_count "$file" pending)
  [ "$n" -gt 0 ] && out="${out:+$out; }$n waiting for a reboot ($(fwupd_names "$file" pending))"
  n=$(fwupd_count "$file" failed)
  [ "$n" -gt 0 ] && out="${out:+$out; }$n failed last time ($(fwupd_names "$file" failed))"
  n=$(fwupd_count "$file" blocked)
  [ "$n" -gt 0 ] && out="${out:+$out; }$n need user action ($(fwupd_blocked_reasons "$file"))"
  printf '%s\n' "$out"
}

# fwupd_blocked_reasons DEVICES_FILE: "Name: problem" for blocked devices.
fwupd_blocked_reasons() {
  local name cur new state note out=""
  while IFS='|' read -r name cur new state note; do
    [ "$state" = blocked ] && out="${out:+$out, }$name: $note"
  done < "$1"
  printf '%s\n' "$out"
}

# fwupd_list LOGFILE DEVICES_FILE: run get-updates into LOGFILE (shown as it
# runs) and parse it into DEVICES_FILE. Returns fwupdmgr's exit code.
fwupd_list() {
  local log="$1" devices="$2" rc=0
  : > "$log"; : > "$devices"
  run_capture "$log" run_root env LC_ALL=C LANGUAGE= fwupdmgr get-updates --no-unreported-check --no-metadata-check || rc=$?
  [ "$rc" -eq 0 ] && fwupd_devices "$log" > "$devices"
  return "$rc"
}

# fwupd_set_reboot DEVICES_FILE: remember pending firmware for reboot-check.
fwupd_set_reboot() {
  local names
  names=$(fwupd_names "$1" pending)
  if [ -n "$names" ]; then
    SU_FIRMWARE_REBOOT="firmware waiting to be applied ($names)"
  fi
}

fwupd_step() {
  local log devices rc=0 count installable extra pending left done_note
  SU_FIRMWARE_REBOOT=""
  has_cmd fwupdmgr || { step_skip "fwupd not installed"; return 0; }
  if in_container; then step_skip "running in a container"; return 0; fi
  log=$(tmp_file) || return 1
  devices=$(tmp_file) || return 1

  run_root fwupdmgr refresh >/dev/null 2>&1 || rc=$?
  case "$rc" in
    0|2) ;;
    *) step_skip "fwupd daemon unavailable (refresh failed with $rc)"; return 0 ;;
  esac
  rc=0
  fwupd_list "$log" "$devices" || rc=$?
  case "$rc" in
    0) ;;
    2) step_ok "no firmware updates available"; return 0 ;;
    *) step_fail "fwupdmgr get-updates failed ($(rc_note "$rc"))"; return 0 ;;
  esac
  if [ ! -s "$devices" ]; then
    step_ok "no firmware updates available"
    return 0
  fi
  detail_show "firmware update(s)" fwupd_changes "$log"
  fwupd_report "$devices"
  fwupd_set_reboot "$devices"
  count=$(fwupd_count "$devices" available)
  installable=$(fwupd_count "$devices" available failed)
  extra=$(fwupd_note "$devices")

  if ! cfg_bool FIRMWARE; then
    if [ "$installable" -gt 0 ]; then
      log_warn "firmware updates are available; rerun with --firmware to apply them"
    fi
    if [ "$count" -gt 0 ] && [ -z "$extra" ]; then
      step_ok "$count firmware update(s) available (not applied; use --firmware): $(fwupd_names "$devices" available)"
    elif [ "$count" -gt 0 ]; then
      step_warn "$count firmware update(s) available (not applied; use --firmware): $(fwupd_names "$devices" available); $extra"
    else
      step_warn "$extra"
    fi
    return 0
  fi
  if [ "$SU_DRY_RUN" = 1 ]; then
    if [ "$installable" -gt 0 ]; then
      step_dry "$installable firmware update(s) would be applied${extra:+; $extra}"
    else
      step_warn "nothing to apply; $extra"
    fi
    return 0
  fi
  if [ "$installable" -eq 0 ]; then
    # fwupdmgr update would skip all of them and still exit 0.
    step_warn "nothing to apply; $extra"
    return 0
  fi

  rc=0
  SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_root fwupdmgr update -y --no-reboot-check || rc=$?
  case "$rc" in
    0) ;;
    2) step_ok "nothing to do"; return 0 ;;
    *) step_fail "fwupdmgr update failed ($(rc_note "$rc"))"; return 0 ;;
  esac

  # Read the list again: what is still offered was not installed.
  rc=0
  fwupd_list "$log" "$devices" || rc=$?
  case "$rc" in
    0) ;;
    2) step_updated "firmware updated"; return 0 ;;
    *) log_warn "could not list firmware updates after updating ($(rc_note "$rc"))"
       step_updated "firmware update finished (could not check the result)"; return 0 ;;
  esac
  fwupd_report "$devices"
  fwupd_set_reboot "$devices"
  left=$(fwupd_count "$devices" available failed)
  pending=$(fwupd_count "$devices" pending)
  extra=$(fwupd_note "$devices")
  if [ "$left" -ge "$installable" ]; then
    step_fail "fwupdmgr update finished but nothing was installed; still offered: $(fwupd_names "$devices" available failed)${extra:+; $extra}"
    return 0
  fi
  done_note="$((installable - left)) of $installable firmware update(s) applied"
  [ "$pending" -gt 0 ] && log_warn "reboot to finish the firmware update(s)"
  if [ "$left" -gt 0 ] || [ "$(fwupd_count "$devices" blocked)" -gt 0 ]; then
    [ "$left" -gt 0 ] && extra="still offered: $(fwupd_names "$devices" available failed)${extra:+; $extra}"
    step_warn "$done_note; $extra"
  elif [ "$pending" -gt 0 ]; then
    step_updated "$done_note; reboot to finish ($(fwupd_names "$devices" pending))"
  else
    step_updated "$done_note"
  fi
}
