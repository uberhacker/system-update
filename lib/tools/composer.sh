#!/usr/bin/env bash
# lib/tools/composer.sh - Composer (self-update), global packages, cgr and drush-versions.

tool_composer_detect() { user_bin composer; }

tool_composer_update() {
  local bin="${SU_TOOL_BIN[composer]}" before after rc=0 notes=() failed=0

  before=$(version_from_text "$(tool_probe "$bin" --version --no-ansi --no-interaction 2>/dev/null | grep -i '^composer version' | head -n1)")
  [ -n "$before" ] && log_info "installed version: $before"

  # 1. composer itself (a phar, possibly root-owned in /usr/local/bin).
  rc=0
  phar_update composer "$bin" composer self-update --no-interaction --no-ansi || rc=$?
  case "$rc" in
    0) notes+=("self-update ok") ;;
    3) notes+=("self-update skipped: $STEP_NOTE"); STEP_RESULT=""; STEP_NOTE="" ;;
    *) notes+=("self-update failed ($(rc_note "$rc"))"); failed=1 ;;
  esac

  # 2. The invoking user's global packages.
  if do_user composer global update --no-interaction --no-ansi --no-progress; then
    notes+=("global update ok")
  else
    notes+=("global update failed"); failed=1
  fi
  if has_cmd cgr; then
    if do_user cgr update; then notes+=("cgr ok"); else notes+=("cgr failed"); failed=1; fi
  fi
  if has_cmd drush-versions; then
    if do_user drush-versions up; then notes+=("drush-versions ok"); else notes+=("drush-versions failed"); failed=1; fi
  fi
  do_user composer clear-cache --no-interaction --no-ansi >/dev/null 2>&1 || true

  if [ "$SU_DRY_RUN" = 1 ]; then
    step_dry "would run self-update, global update${before:+ (installed $before)}"
    return 0
  fi
  if [ "$failed" = 1 ]; then
    step_fail "$(join_by '; ' "${notes[@]}")"
    return 0
  fi
  after=$(version_from_text "$(tool_probe "$bin" --version --no-ansi --no-interaction 2>/dev/null | grep -i '^composer version' | head -n1)")
  if [ -n "$before" ] && [ -n "$after" ] && [ "$before" != "$after" ]; then
    step_updated "$before -> $after; $(join_by '; ' "${notes[@]}")"
  else
    step_ok "${after:+$after; }$(join_by '; ' "${notes[@]}")"
  fi
}
