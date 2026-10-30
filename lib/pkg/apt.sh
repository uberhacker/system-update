#!/usr/bin/env bash
# lib/pkg/apt.sh - Debian, Ubuntu, Mint, Pop!_OS and friends.

# Never prompt; keep existing config files when a package ships a new one.
APT_ENV=(env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none NEEDRESTART_MODE=a)

pkg_apt_dry_needs_root() { return 1; }

# apt_summary LOGFILE: "N upgraded, N newly installed, N to remove and N not upgraded."
apt_summary() {
  grep -E '^[0-9]+ upgraded, [0-9]+ newly installed' "$1" | tail -n1
}

# apt_changes LOGFILE: "name|installed|new" from the Inst/Remv lines of an
# apt-get -s run, e.g.
#   Inst libc6 [2.36-9+deb12u4] (2.36-9+deb12u7 Debian:12.7/stable [amd64])
#   Inst linux-image-6.1.0-25-amd64 (6.1.106-3 Debian-Security:12/stable-security [amd64])
#   Remv libfoo1 [1.2-3]
apt_changes() {
  local line
  local re_up='^Inst ([^ ]+) \[([^]]+)\] \(([^ ]+) '
  local re_new='^Inst ([^ ]+) \(([^ ]+) '
  local re_rm='^Remv ([^ ]+)( \[([^]]+)\])?'
  while IFS= read -r line; do
    if [[ "$line" =~ $re_up ]]; then
      printf '%s|%s|%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
    elif [[ "$line" =~ $re_new ]]; then
      printf '%s||%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    elif [[ "$line" =~ $re_rm ]]; then
      printf '%s|%s|\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[3]:-?}"
    fi
  done < "$1"
}

# apt_refresh: apt-get update. apt exits 0 even when sources could not be
# fetched (it keeps the old lists), so the output is inspected as well.
# Returns 0 when every source was refreshed, 2 when some failed (the old
# lists are used for those; APT_REFRESH_NOTE says how many), 1 when apt-get
# update failed or no source at all could be reached.
APT_REFRESH_NOTE=""
apt_refresh() {
  local log rc=0 failed
  APT_REFRESH_NOTE=""
  log=$(tmp_file) || return 1
  SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_capture "$log" run_root "${APT_ENV[@]}" apt-get -q update || rc=$?
  if [ "$rc" -ne 0 ]; then
    APT_REFRESH_NOTE="apt-get update failed ($(rc_note "$rc"))"
    return 1
  fi
  failed=$(count_matching '^(W: |E: )?Failed to fetch ' "$log")
  [ "$failed" -gt 0 ] || return 0
  if grep -qE '^(Get|Hit):[0-9]+ ' "$log"; then
    APT_REFRESH_NOTE="$failed package source(s) could not be refreshed"
    return 2
  fi
  APT_REFRESH_NOTE="no package source could be reached"
  return 1
}

pkg_apt_update() {
  local log summary upgraded rc=0 refresh=0
  log=$(tmp_file) || return 1

  if [ "$SU_DRY_RUN" = 1 ]; then
    if is_root || sudo -n true 2>/dev/null; then
      apt_refresh || refresh=$?
      if [ "$refresh" -eq 1 ]; then
        step_fail "$APT_REFRESH_NOTE"
        return 0
      fi
      [ "$refresh" -eq 2 ] && log_warn "$APT_REFRESH_NOTE; using the cached lists for those"
    else
      log_warn "cannot refresh package lists without a password; simulating with the cached lists"
    fi
    run_capture "$log" run_root "${APT_ENV[@]}" apt-get -s -q dist-upgrade || rc=$?
    if [ "$rc" -ne 0 ]; then
      step_fail "apt-get -s dist-upgrade failed ($(rc_note "$rc"))"
      return 0
    fi
    summary=$(apt_summary "$log")
    upgraded=$(count_matching '^Inst ' "$log")
    detail_show "package(s)" apt_changes "$log"
    step_dry "${upgraded} package(s) would be upgraded/installed${summary:+ ($summary)}${APT_REFRESH_NOTE:+; $APT_REFRESH_NOTE}"
    return 0
  fi

  apt_refresh || refresh=$?
  if [ "$refresh" -eq 1 ]; then
    step_fail "$APT_REFRESH_NOTE"
    return 0
  fi
  [ "$refresh" -eq 2 ] && log_warn "$APT_REFRESH_NOTE; upgrading with the cached lists for those"
  SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_capture "$log" run_root "${APT_ENV[@]}" apt-get -y -q \
    -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
    dist-upgrade || rc=$?
  if [ "$rc" -ne 0 ]; then
    log_warn "dist-upgrade failed; attempting apt-get -f install"
    SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_root "${APT_ENV[@]}" apt-get -y -q -f install || true
    step_fail "apt-get dist-upgrade failed ($(rc_note "$rc"))"
    return 0
  fi
  summary=$(apt_summary "$log")
  upgraded=$(count_matching '^(Unpacking|Setting up) ' "$log")
  if cfg_bool AUTOREMOVE; then
    SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_root "${APT_ENV[@]}" apt-get -y -q autoremove --purge || log_warn "apt-get autoremove failed"
  fi
  run_root apt-get -q clean || true
  if [ -n "$summary" ] && [[ "$summary" == 0\ upgraded,\ 0\ newly\ installed* ]]; then
    summary="no updates available"
    if [ "$refresh" -eq 2 ]; then
      step_warn "$summary; $APT_REFRESH_NOTE"
    else
      step_ok "$summary"
    fi
  elif [ "$refresh" -eq 2 ]; then
    step_warn "${summary:-$upgraded package(s) processed}; $APT_REFRESH_NOTE"
  else
    step_updated "${summary:-$upgraded package(s) processed}"
  fi
}

pkg_apt_install() {
  apt_refresh || true
  SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_root "${APT_ENV[@]}" apt-get -y -q install "$@"
}

pkg_apt_reboot_check() {
  if [ -f /var/run/reboot-required ] || [ -f /run/reboot-required ]; then
    if [ -r /var/run/reboot-required.pkgs ]; then
      printf 'packages: %s\n' "$(sort -u /var/run/reboot-required.pkgs | tr '\n' ' ')"
    else
      echo "/var/run/reboot-required is present"
    fi
    return 0
  fi
  return 1
}
