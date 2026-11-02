#!/usr/bin/env bash
# lib/tools/devin.sh - Devin CLI (self-update: devin update).
#
# The official installer (cli.devin.ai/install.sh) reads the current
# release from a public manifest. We read the same manifest first and only
# call "devin update" when the installed version is older: run without a
# terminal, "devin update" can sit there until the timeout even when it has
# nothing to do (reported on 3000.11.234, already the latest).

DEVIN_MANIFEST_URL="https://static.devin.ai/cli/current/manifest.json"

tool_devin_detect() { user_bin devin; }

# devin_latest: the version in the public release manifest.
devin_latest() {
  local f v
  f=$(tmp_file) || return 1
  SU_TIMEOUT=$SU_PROBE_TIMEOUT download "$DEVIN_MANIFEST_URL" "$f" 2>/dev/null || return 1
  v=$(json_get .version "$f" 2>/dev/null) || return 1
  [[ "$v" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || return 1
  printf '%s\n' "$v"
}

tool_devin_update() {
  local bin="${SU_TOOL_BIN[devin]}" regex='[0-9]+\.[0-9]+' before latest
  tool_identify devin "$bin" "$regex" '' --version || return 0
  case "${TOOL_METHOD%%:*}" in
    npm|bun|pnpm|uv|pipx|cargo|brew) ;;  # tool_standard picks the right route
    *)
      before=$(version_from_text "$TOOL_PROBE_OUT")
      if [ -n "$before" ] && latest=$(devin_latest); then
        log_info "latest release: $latest"
        if ! version_lt "$before" "$latest"; then
          step_ok "up to date ($before)"
          return 0
        fi
        if [ "$SU_DRY_RUN" = 1 ]; then
          log_info "installed version: $before"
          log_dry "would run: devin update"
          step_dry "would run 'devin update' ($before -> $latest)"
          return 0
        fi
      fi ;;
  esac
  tool_standard devin "$bin" "$regex" '' --version -- devin update
}
