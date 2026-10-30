#!/usr/bin/env bash
# lib/pkg/apt.sh - Debian, Ubuntu, Mint, Pop!_OS and friends.

# Never prompt; keep existing config files when a package ships a new one.
APT_ENV=(env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none NEEDRESTART_MODE=a)

pkg_apt_dry_needs_root() { return 1; }

# apt_summary LOGFILE: "N upgraded, N newly installed, N to remove and N not upgraded."
apt_summary() {
  grep -E '^[0-9]+ upgraded, [0-9]+ newly installed' "$1" | tail -n1
}

apt_refresh() {
  SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_root "${APT_ENV[@]}" apt-get -q update
}

pkg_apt_update() {
  local log summary upgraded rc=0
  log=$(tmp_file) || return 1

  if [ "$SU_DRY_RUN" = 1 ]; then
    if is_root || sudo -n true 2>/dev/null; then
      apt_refresh || log_warn "apt-get update failed; simulating with the cached package lists"
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
    step_dry "${upgraded} package(s) would be upgraded/installed${summary:+ ($summary)}"
    return 0
  fi

  apt_refresh || { step_fail "apt-get update failed"; return 0; }
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
    step_ok "no updates available"
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
