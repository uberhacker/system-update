#!/usr/bin/env bash
# lib/pkg/dnf.sh - Fedora, RHEL, Rocky, Alma, CentOS Stream (dnf5 > dnf > yum).

pkg_dnf_dry_needs_root() { return 1; }

# dnf_cmd: the best available front end.
dnf_cmd() {
  if has_cmd dnf5; then echo dnf5
  elif has_cmd dnf; then echo dnf
  elif has_cmd yum; then echo yum
  else return 1
  fi
}

# dnf_check LOGFILE: run the update check. Returns 100 when updates exist,
# 0 when none, anything else is an error. Works for dnf5, dnf4 and yum.
dnf_check() {
  local log="$1" dnf rc=0
  dnf=$(dnf_cmd) || return 1
  case "$dnf" in
    dnf5) SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_capture "$log" run_root dnf5 --refresh -q check-upgrade || rc=$? ;;
    dnf)  SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_capture "$log" run_root dnf --refresh -q check-update || rc=$? ;;
    yum)  SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_capture "$log" run_root yum -q check-update || rc=$? ;;
  esac
  return "$rc"
}

pkg_dnf_update() {
  local dnf log rc=0 count
  dnf=$(dnf_cmd) || { step_skip "no dnf/yum binary found"; return 0; }
  log=$(tmp_file) || return 1
  [ "$dnf" = yum ] && log_warn "using legacy yum; dnf was not found"

  rc=0
  dnf_check "$log" || rc=$?
  case "$rc" in
    0) count=0 ;;
    100) count=$(count_matching '^[^[:space:]]+\.[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+' "$log") ;;
    *) step_fail "$dnf check-update failed ($(rc_note "$rc"))"; return 0 ;;
  esac

  if [ "$SU_DRY_RUN" = 1 ]; then
    if [ "$count" = 0 ]; then
      step_dry "no updates available"
    else
      step_dry "$count package(s) would be upgraded"
    fi
    return 0
  fi

  if [ "$count" = 0 ]; then
    step_ok "no updates available"
    return 0
  fi
  rc=0
  case "$dnf" in
    yum) SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_root yum -y update || rc=$? ;;
    *)   SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_root "$dnf" -y upgrade || rc=$? ;;
  esac
  if [ "$rc" -ne 0 ]; then
    step_fail "$dnf upgrade failed ($(rc_note "$rc"))"
    return 0
  fi
  if cfg_bool AUTOREMOVE; then
    SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_root "$dnf" -y autoremove || log_warn "$dnf autoremove failed"
  fi
  run_root "$dnf" -q clean packages || true
  step_updated "$count package(s) upgraded"
}

pkg_dnf_install() {
  local dnf
  dnf=$(dnf_cmd) || return 1
  SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_root "$dnf" -y install "$@"
}

pkg_dnf_reboot_check() {
  local dnf rc=0
  dnf=$(dnf_cmd) || return 2
  if has_cmd needs-restarting; then
    needs-restarting -r >/dev/null 2>&1 || rc=$?
    case "$rc" in
      0) return 1 ;;
      1) echo "needs-restarting reports a pending reboot"; return 0 ;;
    esac
  elif [ "$dnf" = dnf5 ]; then
    # dnf5-plugins ships "dnf5 needs-restarting"; exit 1 means reboot needed.
    if dnf5 needs-restarting --help >/dev/null 2>&1; then
      dnf5 needs-restarting -r >/dev/null 2>&1 || rc=$?
      case "$rc" in
        0) return 1 ;;
        1) echo "dnf needs-restarting reports a pending reboot"; return 0 ;;
      esac
    fi
  fi
  return 2
}
