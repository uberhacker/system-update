#!/usr/bin/env bash
# lib/tools/terminus.sh - Pantheon Terminus (phar; terminus self:update).

tool_terminus_detect() { user_bin terminus; }

tool_terminus_update() {
  local bin="${SU_TOOL_BIN[terminus]}" before after rc=0
  before=$(version_from_text "$(tool_probe "$bin" --version --no-ansi)")
  [ -n "$before" ] && log_info "installed version: $before"
  rc=0
  phar_update terminus "$bin" terminus self:update --no-interaction --no-ansi || rc=$?
  case "$rc" in
    3) return 0 ;;   # skipped, reason already recorded
    0) ;;
    *) step_fail "terminus self:update failed ($(rc_note "$rc"))"; return 0 ;;
  esac
  if [ "$SU_DRY_RUN" = 1 ]; then
    phar_dry_result "terminus self:update" "$before" pantheon-systems/terminus
    return 0
  fi
  after=$(version_from_text "$(tool_probe "$bin" --version --no-ansi)")
  if [ -n "$before" ] && [ -n "$after" ] && [ "$before" != "$after" ]; then
    step_updated "$before -> $after"
  else
    step_ok "up to date (${after:-$before})"
  fi
}
