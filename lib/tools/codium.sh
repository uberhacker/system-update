#!/usr/bin/env bash
# lib/tools/codium.sh - VSCodium.
#
# Preferred: the VSCodium apt/rpm repository, Flatpak or snap, all handled by
# the corresponding system step. Only when codium was installed from a
# downloaded .deb/.rpm (the package exists but no repository provides it) do
# we fetch the new package from the GitHub release, verify the published
# .sha256 and install it with the package manager.

tool_codium_detect() { command -v codium 2>/dev/null; }
tool_codium_scope() { echo system; }

# codium_repo_configured: is a repository that ships codium configured?
codium_repo_configured() {
  case "$SU_PKG" in
    apt)
      apt-cache policy codium 2>/dev/null | grep -qE '^\s+[0-9]+ https?://' ;;
    dnf|zypper)
      grep -rqiE 'codium' /etc/yum.repos.d /etc/zypp/repos.d 2>/dev/null ;;
    *) return 1 ;;
  esac
}

tool_codium_update() {
  local bin="${SU_TOOL_BIN[codium]}" real owner installed latest arch asset tmp sum url kind

  real=$(readlink -f -- "$bin" 2>/dev/null || printf '%s' "$bin")
  case "$real" in
    */flatpak/*) step_skip "installed as a Flatpak (see the flatpak step)"; return 0 ;;
    /snap/*|*/snapd/*) step_skip "installed as a snap (see the snap step)"; return 0 ;;
  esac

  installed=$(tool_probe "$bin" --version | grep -E -m1 '^[0-9]+\.[0-9]+\.[0-9]+' || true)
  installed=$(version_from_text "$installed")
  [ -n "$installed" ] || { step_skip "could not read the installed version"; return 0; }
  log_info "installed version: $installed"

  latest=$(gh_latest_tag VSCodium/vscodium) || { step_skip "latest release unknown (GitHub API unavailable)"; return 0; }
  latest=$(version_norm "$latest")
  log_info "latest release: $latest"
  if ! version_lt "$installed" "$latest"; then
    step_ok "up to date ($installed)"
    return 0
  fi

  owner=$(distro_pkg_owner "$real") || owner=""
  if [ -z "$owner" ]; then
    step_skip "$latest is available but codium was not installed from a package; update it the way it was installed"
    return 0
  fi
  if codium_repo_configured; then
    step_skip "$latest is available; codium comes from a configured repository and is updated with the system packages"
    return 0
  fi
  case "$SU_PKG" in
    apt) kind=deb; arch=$(arch_name deb); asset="codium_${latest}_${arch}.deb" ;;
    dnf|zypper) kind=rpm; arch=$(arch_name rpm); asset="codium-${latest}-el8.${arch}.rpm" ;;
    pacman) step_skip "$latest is available; codium on Arch comes from the AUR (use your AUR helper)"; return 0 ;;
    *) step_skip "$latest is available; no package download path for $SU_PKG"; return 0 ;;
  esac
  [ "$arch" = unknown ] && { step_skip "unsupported architecture $(uname -m)"; return 0; }
  if ! gh_release_has_asset VSCodium/vscodium "$asset"; then
    step_skip "release $latest has no asset named $asset"
    return 0
  fi
  if [ "$SU_DRY_RUN" = 1 ]; then
    step_dry "would download $asset, verify its sha256 and install it ($installed -> $latest)"
    return 0
  fi

  tmp=$(tmp_dir) || return 1
  url=$(gh_release_asset_url VSCodium/vscodium "$latest" "$asset")
  download "$url" "$tmp/$asset" || { step_fail "download failed"; return 0; }
  download "$url.sha256" "$tmp/$asset.sha256" || { step_fail "could not download $asset.sha256; refusing to install an unverified package"; return 0; }
  read -r sum _ < "$tmp/$asset.sha256" || sum=""
  verify_sha256 "$tmp/$asset" "$sum" || { step_fail "checksum verification failed; nothing installed"; return 0; }
  case "$kind" in
    deb) SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT do_root "${APT_ENV[@]}" apt-get -y -q install "$tmp/$asset" || { step_fail "apt-get install failed"; return 0; } ;;
    rpm)
      if [ "$SU_PKG" = zypper ]; then
        SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT do_root zypper --non-interactive install "$tmp/$asset" || { step_fail "zypper install failed"; return 0; }
      else
        SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT do_root "$(dnf_cmd)" -y install "$tmp/$asset" || { step_fail "dnf install failed"; return 0; }
      fi ;;
  esac
  step_updated "$installed -> $latest"
}
