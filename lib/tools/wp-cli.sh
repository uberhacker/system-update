#!/usr/bin/env bash
# lib/tools/wp-cli.sh - WP-CLI (phar; wp cli update --yes).

tool_wp_cli_detect() { user_bin wp; }

tool_wp_cli_update() {
  local bin="${SU_TOOL_BIN[wp-cli]}" before after rc=0
  before=$(version_from_text "$(tool_probe "$bin" cli version --no-color)")
  [ -n "$before" ] && log_info "installed version: $before"
  # --allow-root is harmless for a normal user and needed when the phar is
  # root-owned and the update therefore runs as root.
  rc=0
  phar_update wp-cli "$bin" wp cli update --yes --no-color --allow-root || rc=$?
  case "$rc" in
    3) return 0 ;;
    0) ;;
    *) step_fail "wp cli update failed ($(rc_note "$rc"))"; return 0 ;;
  esac
  if [ "$SU_DRY_RUN" = 1 ]; then
    step_dry "would run wp cli update${before:+ (installed $before)}"
    return 0
  fi
  after=$(version_from_text "$(tool_probe "$bin" cli version --no-color)")
  if [ -n "$before" ] && [ -n "$after" ] && [ "$before" != "$after" ]; then
    step_updated "$before -> $after"
  else
    step_ok "up to date (${after:-$before})"
  fi
}
