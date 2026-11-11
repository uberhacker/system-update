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

# composer_global_home: the global Composer directory (COMPOSER_HOME) of the
# invoking user, e.g. ~/.config/composer.
composer_global_home() {
  local d
  d=$(SU_RUN_TIMEOUT=$SU_PROBE_TIMEOUT run_user composer config --global home --no-interaction --no-ansi 2>/dev/null | tail -n1)
  [[ "$d" == /* ]] && [ -d "$d" ] || return 1
  printf '%s\n' "$d"
}

# composer_downgrades LOGFILE: "vendor/package A -> B" for each package a
# `composer global update --dry-run` would downgrade.
composer_downgrades() {
  local line re='Downgrading ([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+) \(v?([^ ]+) => v?([^ )]+)\)'
  while IFS= read -r line; do
    [[ "$line" =~ $re ]] && printf '%s %s -> %s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
  done < "$1" | sort -u
}

# composer_global_update: update the user's global packages, but
#   * look first (--dry-run): nothing to do -> done; any package that would
#     be DOWNGRADED -> leave everything as it is and say which ones (a
#     resolver that suddenly prefers old majors usually means a different
#     PHP, a platform setting or a new constraint, which the user should
#     look at before it rewrites the lock file);
#   * keep a copy of composer.json, composer.lock and vendor/ and put it
#     back if the update fails half way, so the global tools (cgr, drush)
#     are not left with a broken autoloader.
# Sets COMPOSER_GLOBAL_NOTE. Returns 0 ok, 2 left alone (warn), 1 failed.
composer_global_update() {
  local home plan rc=0 downs n php snap="" f
  COMPOSER_GLOBAL_NOTE=""
  php=$(SU_RUN_TIMEOUT=$SU_PROBE_TIMEOUT run_user php -r 'echo PHP_VERSION;' 2>/dev/null) || php=""
  [ -n "$php" ] && log_info "PHP for the global packages: $php"
  plan=$(tmp_file) || return 1
  SU_RUN_TIMEOUT=$SU_TIMEOUT run_capture "$plan" run_user composer global update --dry-run --no-interaction --no-ansi --no-progress || rc=$?
  if [ "$rc" -ne 0 ]; then
    COMPOSER_GLOBAL_NOTE="global update not run: its dry run failed ($(rc_note "$rc"))"
    return 1
  fi
  if grep -qE 'Nothing to (modify in lock file|install, update or remove)' "$plan" && ! grep -qE '^ *- (Upgrading|Downgrading|Installing|Removing|Locking) ' "$plan"; then
    COMPOSER_GLOBAL_NOTE="global packages up to date"
    return 0
  fi
  downs=$(composer_downgrades "$plan")
  if [ -n "$downs" ]; then
    n=$(printf '%s\n' "$downs" | wc -l)
    log_warn "composer global update would downgrade $n package(s)${php:+ (PHP $php)}; nothing was changed:"
    printf '%s\n' "$downs" | while IFS= read -r f; do log_plain "      $f"; done
    log_warn "check why with: composer global why-not $(printf '%s\n' "$downs" | head -n1 | awk '{print $1, $4}'); then run composer global update yourself"
    COMPOSER_GLOBAL_NOTE="global update not run: it would downgrade $n package(s) ($(printf '%s\n' "$downs" | head -n3 | paste -sd, - | sed 's/,/, /g')$([ "$n" -gt 3 ] && printf ', ...'))"
    return 2
  fi
  if home=$(composer_global_home) && snap=$(tmp_dir); then
    chmod 0700 "$snap"
    [ -n "$SU_USER" ] && ! user_is_current && chown "$SU_USER" "$snap" 2>/dev/null
    for f in composer.json composer.lock vendor; do
      [ -e "$home/$f" ] || continue
      do_user cp -a -- "$home/$f" "$snap/$f" >/dev/null 2>&1 || { log_warn "could not copy $home/$f for a rollback"; snap=""; break; }
    done
  else
    snap=""
    log_detail "global Composer directory not found; updating without a rollback copy"
  fi
  rc=0
  do_user composer global update --no-interaction --no-ansi --no-progress || rc=$?
  if [ "$rc" -eq 0 ]; then
    [ -n "$snap" ] && rm -rf -- "$snap"
    COMPOSER_GLOBAL_NOTE="global update ok"
    return 0
  fi
  if [ -n "$snap" ]; then
    log_warn "composer global update failed; putting back the global packages as they were"
    for f in composer.json composer.lock vendor; do
      [ -e "$snap/$f" ] || continue
      if ! { do_user rm -rf -- "${home:?}/$f" && do_user cp -a -- "$snap/$f" "$home/$f"; }; then
        COMPOSER_GLOBAL_NOTE="global update failed ($(rc_note "$rc")) and restoring $home/$f failed too"
        return 1
      fi
    done
    rm -rf -- "$snap"
    COMPOSER_GLOBAL_NOTE="global update failed ($(rc_note "$rc")); previous packages restored"
    return 1
  fi
  COMPOSER_GLOBAL_NOTE="global update failed ($(rc_note "$rc"))"
  return 1
}

tool_composer_update() {
  local bin="${SU_TOOL_BIN[composer]}" before after rc=0 notes=() failed=0 warned=0

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
  if [ "$SU_DRY_RUN" = 1 ]; then
    do_user composer global update --no-interaction --no-ansi --no-progress
  else
    rc=0
    composer_global_update || rc=$?
    case "$rc" in
      0) notes+=("$COMPOSER_GLOBAL_NOTE") ;;
      2) notes+=("$COMPOSER_GLOBAL_NOTE"); warned=1 ;;
      *) notes+=("$COMPOSER_GLOBAL_NOTE"); failed=1 ;;
    esac
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
  if [ "$warned" = 1 ]; then
    step_warn "$(join_by '; ' "${notes[@]}")"
    return 0
  fi
  after=$(version_from_text "$(tool_probe "$bin" --version --no-ansi --no-interaction 2>/dev/null | grep -i '^composer version' | head -n1)")
  if [ -n "$before" ] && [ -n "$after" ] && [ "$before" != "$after" ]; then
    step_updated "$before -> $after; $(join_by '; ' "${notes[@]}")"
  else
    step_ok "${after:+$after; }$(join_by '; ' "${notes[@]}")"
  fi
}
