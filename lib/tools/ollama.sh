#!/usr/bin/env bash
# lib/tools/ollama.sh - Ollama.
#
# Distro package -> updated with the system packages. Otherwise the only
# update path is the vendor's install.sh, which needs root and cannot be
# verified. It runs only when ollama was evidently installed by it (the
# installer's systemd unit exists and the binary is under /usr/local or
# /usr/bin without a package owner) or with ALLOW_UNVERIFIED_INSTALLERS=1.
# Nothing is chown'ed afterwards.

OLLAMA_INSTALLER="https://ollama.com/install.sh"

tool_ollama_detect() { command -v ollama 2>/dev/null; }
tool_ollama_scope() { echo system; }

tool_ollama_update() {
  local bin="${SU_TOOL_BIN[ollama]}" real owner installed latest by_installer=0 tmp rc=0 after

  real=$(readlink -f -- "$bin" 2>/dev/null || printf '%s' "$bin")
  if owner=$(distro_pkg_owner "$real"); then
    step_skip "$bin belongs to $SU_PKG package '$owner' (updated with the system packages)"
    return 0
  fi
  if [ -f /etc/systemd/system/ollama.service ]; then
    case "$real" in
      /usr/local/bin/*|/usr/local/lib/ollama/*|/usr/bin/ollama|/usr/lib/ollama/*) by_installer=1 ;;
    esac
  fi

  installed=$(version_from_text "$(tool_probe "$bin" -v | grep -i 'version' || true)")
  [ -n "$installed" ] || { step_skip "could not read the installed version"; return 0; }
  log_info "installed version: $installed"
  latest=$(gh_latest_version ollama/ollama) || { step_skip "latest release unknown (GitHub API unavailable)"; return 0; }
  log_info "latest release: $latest"
  if ! version_lt "$installed" "$latest"; then
    step_ok "up to date ($installed)"
    return 0
  fi
  if [ "$by_installer" != 1 ] && ! cfg_bool ALLOW_UNVERIFIED_INSTALLERS; then
    step_skip "$installed -> $latest available; install method unknown and the vendor installer is unverified, rerun with --allow-unverified-installers"
    return 0
  fi
  if ! sudo_available; then
    step_skip "$installed -> $latest available; the installer needs root"
    return 0
  fi
  if [ "$SU_DRY_RUN" = 1 ]; then
    step_dry "would run the ollama installer as root ($installed -> $latest)"
    return 0
  fi
  tmp=$(tmp_dir) || return 1
  download "$OLLAMA_INSTALLER" "$tmp/install.sh" || { step_fail "download failed"; return 0; }
  bash -n "$tmp/install.sh" || { step_fail "installer did not parse as a shell script"; return 0; }
  do_root sh "$tmp/install.sh" || rc=$?
  if [ "$rc" -ne 0 ]; then
    step_fail "installer failed ($(rc_note "$rc"))"
    return 0
  fi
  after=$(version_from_text "$(tool_probe "$bin" -v | grep -i 'version' || true)")
  step_updated "$installed -> ${after:-$latest}"
}
