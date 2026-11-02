#!/usr/bin/env bash
# lib/tools/cloudflared.sh - Cloudflare Tunnel client as a standalone binary.
#
# cloudflared from Cloudflare's apt/rpm repository (or any distro package) is
# updated with the system packages. A plain binary (usually /usr/local/bin)
# is replaced from the cloudflare/cloudflared GitHub release, verified
# against the sha256 the release publishes; without one nothing is installed.

tool_cloudflared_detect() { command -v cloudflared 2>/dev/null; }
tool_cloudflared_scope() { echo system; }

tool_cloudflared_update() {
  local bin="${SU_TOOL_BIN[cloudflared]}" installed arch
  tool_identify cloudflared "$bin" '^cloudflared version [0-9]' '' --version || return 0
  case "${TOOL_METHOD%%:*}" in
    brew) step_skip "installed with Homebrew; updated by the brew step"; return 0 ;;
  esac
  installed=$(version_from_text "$TOOL_PROBE_OUT")
  arch=$(arch_name cloudflared)
  [ "$arch" != unknown ] || { step_skip "unsupported architecture $(uname -m)"; return 0; }
  tool_github_binary_update cloudflared cloudflare/cloudflared "cloudflared-linux-$arch" "$bin" "$installed"
}
