#!/usr/bin/env bash
# lib/tools/docker-compose.sh - standalone docker-compose binary.
#
# The Docker Compose v2 plugin (`docker compose`) comes from the distro or
# Docker repository and is updated with the system packages. This step only
# manages an already present standalone binary that is a real file (not a
# symlink to the plugin, not a distro package, not Docker Desktop). Downloads
# are verified against the release's checksums.txt before `install -m 0755`.

tool_docker_compose_detect() { command -v docker-compose 2>/dev/null; }
tool_docker_compose_scope() { echo system; }

tool_docker_compose_update() {
  local bin="${SU_TOOL_BIN[docker-compose]}" real owner installed latest plugin=""
  local arch asset tmp sum url dir

  real=$(readlink -f -- "$bin" 2>/dev/null || printf '%s' "$bin")
  if docker compose version --short >/dev/null 2>&1; then
    plugin=$(docker compose version --short 2>/dev/null)
    log_info "docker compose v2 plugin present: $plugin (managed by the package manager)"
  fi
  case "$real" in
    *docker-desktop*) step_skip "managed by Docker Desktop"; return 0 ;;
    */cli-plugins/*) step_skip "$bin is a symlink to the compose v2 plugin (managed by the package manager)"; return 0 ;;
  esac
  if owner=$(distro_pkg_owner "$real"); then
    step_skip "$bin belongs to $SU_PKG package '$owner' (updated with the system packages)"
    return 0
  fi
  if [ ! -f "$real" ]; then
    step_skip "$bin is not a regular file"
    return 0
  fi

  installed=$(version_from_text "$(tool_probe "$bin" version --short)")
  if [ -z "$installed" ]; then
    step_skip "could not read the installed version"
    return 0
  fi
  log_info "installed version: $installed"
  case "$installed" in
    1.*) step_skip "Compose v1 ($installed) is end-of-life; install the docker-compose-plugin package instead"; return 0 ;;
  esac

  latest=$(gh_latest_tag docker/compose) || { step_skip "latest release unknown (GitHub API unavailable)"; return 0; }
  log_info "latest release: $latest"
  if ! version_lt "$installed" "$latest"; then
    step_ok "up to date ($installed)"
    return 0
  fi
  arch=$(arch_name compose)
  if [ "$arch" = unknown ]; then
    step_skip "unsupported architecture $(uname -m)"
    return 0
  fi
  asset="docker-compose-linux-${arch}"
  if [ "$SU_DRY_RUN" = 1 ]; then
    step_dry "would download $asset $latest, verify its sha256 and install it to $bin ($installed -> ${latest#v})"
    return 0
  fi

  tmp=$(tmp_dir) || return 1
  url=$(gh_release_asset_url docker/compose "$latest" "$asset")
  download "$url" "$tmp/$asset" || { step_fail "download failed"; return 0; }
  download "$(gh_release_asset_url docker/compose "$latest" checksums.txt)" "$tmp/checksums.txt" || {
    step_fail "could not download checksums.txt; refusing to install an unverified binary"; return 0; }
  sum=$(checksum_for "$tmp/checksums.txt" "$asset")
  verify_sha256 "$tmp/$asset" "$sum" || { step_fail "checksum verification failed; $bin left untouched"; return 0; }
  dir=$(dirname "$real")
  if [ -w "$dir" ] && [ -w "$real" ]; then
    do_user install -m 0755 "$tmp/$asset" "$real" || { step_fail "install failed"; return 0; }
  else
    install_bin "$tmp/$asset" "$real" || { step_fail "install failed"; return 0; }
  fi
  step_updated "$installed -> ${latest#v}"
}
