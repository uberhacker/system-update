#!/usr/bin/env bash
# lib/core/pkg.sh - dispatch to the detected package manager module.
#
# Each lib/pkg/<manager>.sh defines:
#   pkg_<m>_update          the step: refresh, (dry-run|upgrade), clean up
#   pkg_<m>_install PKG...  install packages (used for optional jq)
#   pkg_<m>_reboot_check    optional; return 0 when a reboot is required and
#                           print why, 1 when not, 2 when it cannot tell
#   pkg_<m>_dry_needs_root  optional; return 0 when even the dry run must
#                           become root (default: yes)

# pkg_fn SUFFIX: function name for the detected manager.
pkg_fn() { printf 'pkg_%s_%s\n' "${SU_PKG//-/_}" "$1"; }

pkg_supported() { declare -F "$(pkg_fn update)" >/dev/null; }

# run_capture LOGFILE CMD...: run CMD showing its output and also saving it.
run_capture() {
  local log="$1"; shift
  "$@" 2>&1 | tee -a "$log"
  return "${PIPESTATUS[0]}"
}

# pkg_install PKG...: install packages with the system manager (real runs only).
pkg_install() {
  local fn
  fn=$(pkg_fn install)
  if ! declare -F "$fn" >/dev/null; then
    log_warn "do not know how to install packages with $SU_PKG"
    return 1
  fi
  if [ "$SU_DRY_RUN" = 1 ]; then
    log_dry "would install: $*"
    return 0
  fi
  "$fn" "$@"
}

# pkg_dry_needs_root: does the dry run need root for this manager?
pkg_dry_needs_root() {
  local fn
  fn=$(pkg_fn dry_needs_root)
  if declare -F "$fn" >/dev/null; then "$fn"; else return 0; fi
}

# pkg_update_step: the "system packages" step body.
pkg_update_step() {
  local fn
  fn=$(pkg_fn update)
  if ! declare -F "$fn" >/dev/null; then
    step_skip "package manager '$SU_PKG' is not supported"
    return 0
  fi
  if ! sudo_available; then
    step_skip "not root and sudo is not installed; run as root to update system packages"
    return 0
  fi
  if ! is_root && [ "${SU_SUDO_OK:-}" = 0 ]; then
    step_skip "sudo credentials unavailable"
    return 0
  fi
  "$fn"
}

# count_matching REGEX FILE: number of lines matching REGEX.
count_matching() {
  grep -c -E -- "$1" "$2" 2>/dev/null || true
}

# in_container: are we inside a container (kernel checks are meaningless)?
in_container() {
  [ -n "${container:-}" ] && return 0
  [ -f /.dockerenv ] && return 0
  [ -f /run/.containerenv ] && return 0
  if has_cmd systemd-detect-virt && systemd-detect-virt --container --quiet 2>/dev/null; then
    return 0
  fi
  grep -qaE '(docker|lxc|containerd|podman|kubepods)' /proc/1/cgroup 2>/dev/null && return 0
  return 1
}

# kernel_reboot_check: running kernel's modules directory is gone => a
# newer kernel was installed. Skipped in containers.
kernel_reboot_check() {
  local running
  in_container && return 2
  running=$(uname -r)
  [ -n "$running" ] || return 2
  if [ -d "/usr/lib/modules/$running" ] || [ -d "/lib/modules/$running" ]; then
    return 1
  fi
  echo "running kernel $running is no longer installed"
  return 0
}

# reboot_check_step: the "reboot-check" step body.
reboot_check_step() {
  local fn reason rc
  if in_container; then
    step_skip "running in a container"
    return 0
  fi
  fn=$(pkg_fn reboot_check)
  if declare -F "$fn" >/dev/null; then
    reason=$("$fn"); rc=$?
    if [ "$rc" -eq 0 ]; then
      log_warn "reboot required: ${reason:-pending updates}"
      step_ok "REBOOT REQUIRED: ${reason:-pending updates}"
      return 0
    fi
  fi
  if reason=$(kernel_reboot_check); then
    log_warn "reboot required: $reason"
    step_ok "REBOOT REQUIRED: $reason"
    return 0
  fi
  step_ok "no reboot required"
}
