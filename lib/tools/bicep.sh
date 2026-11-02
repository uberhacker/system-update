#!/usr/bin/env bash
# lib/tools/bicep.sh - a standalone Bicep CLI binary (not the one az manages).
#
# Updated from the Azure/bicep GitHub release only when a sha256 for the
# asset is published (checksums file, .sha256 asset or release notes);
# otherwise the step says so and installs nothing.

tool_bicep_detect() {
  local bin real
  bin=$(user_bin bicep) || return 1
  real=$(readlink -f -- "$bin" 2>/dev/null || printf '%s' "$bin")
  case "$real" in
    "${AZURE_CONFIG_DIR:-$SU_USER_HOME/.azure}"/bin/*) return 1 ;;  # managed by az (azure-cli.sh)
  esac
  printf '%s\n' "$bin"
}

tool_bicep_scope() {
  local real
  real=$(readlink -f -- "${SU_TOOL_BIN[bicep]-}" 2>/dev/null || printf '%s' "${SU_TOOL_BIN[bicep]-}")
  case "$real" in
    "$SU_USER_HOME"/*) echo user ;;
    *) echo system ;;
  esac
}

tool_bicep_update() {
  local bin="${SU_TOOL_BIN[bicep]}" installed arch asset
  tool_identify bicep "$bin" '^Bicep CLI version [0-9]' '' --version || return 0
  case "${TOOL_METHOD%%:*}" in
    brew) step_skip "installed with Homebrew; updated by the brew step"; return 0 ;;
  esac
  installed=$(version_from_text "$TOOL_PROBE_OUT")
  arch=$(arch_name bicep)
  [ "$arch" != unknown ] || { step_skip "unsupported architecture $(uname -m)"; return 0; }
  asset="bicep-linux-$arch"
  if [ -f /etc/alpine-release ]; then asset="bicep-linux-musl-$arch"; fi
  tool_github_binary_update bicep Azure/bicep "$asset" "$bin" "$installed"
}
