#!/usr/bin/env bash
# lib/tools/ollama.sh - Ollama.
#
# Distro package -> updated with the system packages. Otherwise the only
# update path is the vendor's install.sh, which needs root and cannot be
# verified (no checksum or signature is published), so it runs only with
# ALLOW_UNVERIFIED_INSTALLERS=1 (--allow-unverified-installers), as the
# README promises for every vendor installer. When ollama was evidently
# installed by that installer (its systemd unit exists and the binary is
# under /usr/local or /usr/bin without a package owner) the skip says so.
# Nothing is chown'ed afterwards.
#
# `ollama -v` prints the version of the *running server* first and adds
# "Warning: client version is X" when the binary on disk differs, so the
# installed version is the client's. The installer restarts the server only
# through systemd; without systemd an old `ollama serve` keeps running, which
# the step restarts through /etc/init.d/ollama when that exists and reports
# otherwise.

OLLAMA_INSTALLER="https://ollama.com/install.sh"
OLLAMA_INITD="${SU_OLLAMA_INITD:-/etc/init.d/ollama}"

# ollama_versions TEXT: from `ollama -v` output set OLLAMA_CLIENT (the binary
# on disk) and OLLAMA_SERVER (the running server, empty when none answered).
ollama_versions() {
  local text="$1" line
  OLLAMA_CLIENT=""; OLLAMA_SERVER=""
  line=$(printf '%s\n' "$text" | grep -i 'client version is' | head -n1)
  [ -n "$line" ] && OLLAMA_CLIENT=$(version_from_text "$line")
  if ! printf '%s\n' "$text" | grep -qi 'could not connect'; then
    line=$(printf '%s\n' "$text" | grep -i 'ollama version is' | head -n1)
    [ -n "$line" ] && OLLAMA_SERVER=$(version_from_text "$line")
  fi
  [ -n "$OLLAMA_CLIENT" ] || OLLAMA_CLIENT="$OLLAMA_SERVER"
  [ -n "$OLLAMA_CLIENT" ] || OLLAMA_CLIENT=$(version_from_text "$(printf '%s\n' "$text" | grep -i 'version' || true)")
}

# ollama_stale_server: true when a server answered with a version other
# than the client's (it was started from the old binary).
ollama_stale_server() {
  [ -n "$OLLAMA_SERVER" ] && [ "$OLLAMA_SERVER" != "$OLLAMA_CLIENT" ]
}

# ollama_restart_note: how to get the new server running, for the step note.
ollama_restart_note() {
  printf 'the running ollama server is still %s; restart it (stop it and run ollama serve) to use %s' \
    "$OLLAMA_SERVER" "$OLLAMA_CLIENT"
}

# ollama_fix_server BIN: without systemd, restart a stale server through its
# init script when there is one. Returns 0 when the server now matches.
ollama_fix_server() {
  local bin="$1"
  ollama_stale_server || return 0
  systemd_running && return 1
  [ -x "$OLLAMA_INITD" ] || return 1
  do_root "$OLLAMA_INITD" restart || return 1
  ollama_versions "$(tool_probe "$bin" -v || true)"
  ! ollama_stale_server
}

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

  ollama_versions "$(tool_probe "$bin" -v || true)"
  installed="$OLLAMA_CLIENT"
  [ -n "$installed" ] || { step_skip "could not read the installed version"; return 0; }
  log_info "installed version: $installed"
  ollama_stale_server && log_info "running server version: $OLLAMA_SERVER"
  latest=$(gh_latest_version ollama/ollama) || { step_skip "latest release unknown (GitHub API unavailable)"; return 0; }
  log_info "latest release: $latest"
  if ! version_lt "$installed" "$latest"; then
    if [ "$SU_DRY_RUN" != 1 ] && ! ollama_fix_server "$bin"; then
      step_warn "up to date ($installed), but $(ollama_restart_note)"
    else
      step_ok "up to date ($installed)"
    fi
    return 0
  fi
  if ! cfg_bool ALLOW_UNVERIFIED_INSTALLERS; then
    if [ "$by_installer" = 1 ]; then
      step_skip "$installed -> $latest available; the vendor installer that installed ollama cannot be verified, rerun with --allow-unverified-installers to run it again"
    else
      step_skip "$installed -> $latest available; install method unknown and the vendor installer is unverified, rerun with --allow-unverified-installers"
    fi
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
  ollama_versions "$(tool_probe "$bin" -v || true)"
  after="$OLLAMA_CLIENT"
  if [ -n "$after" ] && [ "$after" = "$installed" ]; then
    step_fail "the installer finished but ollama is still $installed"
    return 0
  fi
  if ! ollama_fix_server "$bin"; then
    step_warn "$installed -> ${after:-$latest}; $(ollama_restart_note)"
    return 0
  fi
  step_updated "$installed -> ${after:-$latest}"
}
