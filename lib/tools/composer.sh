#!/usr/bin/env bash
# lib/tools/composer.sh - Composer (self-update), global packages, cgr and drush-versions.

tool_composer_detect() { user_bin composer; }

# composer_outdated: "vendor/package|installed|latest" for the invoking
# user's direct global requirements (`composer global outdated --direct`,
# rows like "drush/drush 12.4.3 ! 13.3.3 Drush is ...").
composer_outdated() {
  local line re='^([a-z0-9_.-]+/[a-z0-9_.-]+)[[:space:]]+v?([^[:space:]]+)[[:space:]]+[!~=]?[[:space:]]*v?([0-9][^[:space:]]*)'
  while IFS= read -r line; do
    [[ "$line" =~ $re ]] || continue
    [ "${BASH_REMATCH[2]}" = "${BASH_REMATCH[3]}" ] && continue
    printf '%s|%s|%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
  done < <(SU_RUN_TIMEOUT=$SU_TIMEOUT run_user composer global outdated --direct --no-interaction --no-ansi 2>/dev/null)
}

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
    local latest change="${before:+ (installed $before)}"
    if detail_enabled; then
      if latest=$(gh_latest_version composer/composer); then change=" (${before:-?} -> $latest)"; fi
      detail_show "global package(s)" composer_outdated
    fi
    step_dry "would run self-update, global update$change"
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
