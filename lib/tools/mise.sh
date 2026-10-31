#!/usr/bin/env bash
# lib/tools/mise.sh - mise (formerly rtx): self-update, plugin updates and,
# with RUNTIMES=1 (--runtimes), `mise upgrade`.
#
# `mise upgrade` only moves a tool within the version spec configured for it
# (node = "20" stays on 20.x); it never rewrites pinned versions (that would
# be `mise upgrade --bump`, which is not used). Self-update is skipped when
# mise comes from the distro or Homebrew.

MISE_ENV=(env MISE_YES=1 MISE_QUIET=1 NO_COLOR=1)

tool_mise_detect() {
  local bin
  if bin=$(user_bin mise); then printf '%s\n' "$bin"; return 0; fi
  bin="$SU_USER_HOME/.local/bin/mise"
  [ -x "$bin" ] || return 1
  printf '%s\n' "$bin"
}

tool_mise_update() {
  local bin="${SU_TOOL_BIN[mise]}" method before after log notes=() failed=0 changed=0 plugins

  # Not tool_identify: a distro-packaged mise still manages the user's
  # plugins and runtimes; only its self-update is then left to the distro.
  method=$(install_method "$bin")
  tool_probe_check mise "$bin" '^(mise )?[0-9]{4}\.[0-9]+' --version || return 0
  before=$(version_from_text "$TOOL_PROBE_OUT")
  log=$(tmp_file) || return 1

  case "${method%%:*}" in
    distro) notes+=("mise itself comes from $SU_PKG package '${method#*:}'") ;;
    brew) notes+=("mise itself comes from Homebrew (see the brew step)") ;;
    *)
      if [ "$SU_DRY_RUN" = 1 ]; then
        notes+=("would run mise self-update --yes")
      elif run_capture "$log" run_user "${MISE_ENV[@]}" "$bin" self-update --yes; then
        after=$(version_from_text "$(tool_probe "$bin" --version)")
        if [ -n "$after" ] && [ "$after" != "$before" ]; then notes+=("mise $before -> $after"); changed=1; else notes+=("mise up to date ($before)"); fi
      elif grep -qiE 'not available|disabled|installed with|package manager' "$log"; then
        notes+=("self-update is not available for this install of mise")
      else
        notes+=("mise self-update failed"); failed=1
      fi ;;
  esac

  plugins=$(SU_RUN_TIMEOUT=$SU_PROBE_TIMEOUT run_user "${MISE_ENV[@]}" "$bin" plugins ls 2>/dev/null | grep -c . || true)
  if [ "$plugins" -gt 0 ]; then
    if [ "$SU_DRY_RUN" = 1 ]; then
      notes+=("would run mise plugins update ($plugins plugin(s))")
    elif run_user "${MISE_ENV[@]}" "$bin" plugins update >/dev/null 2>&1; then
      notes+=("$plugins plugin(s) updated")
    else
      notes+=("mise plugins update failed"); failed=1
    fi
  fi

  if cfg_bool RUNTIMES; then
    : > "$log"
    if [ "$SU_DRY_RUN" = 1 ]; then
      if SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_capture "$log" run_user "${MISE_ENV[@]}" "$bin" upgrade --dry-run; then
        if grep -q . "$log"; then notes+=("runtimes: would upgrade $(grep -c . "$log") tool version(s)"); else notes+=("runtimes: all within their specs"); fi
      else
        notes+=("runtimes: would run mise upgrade")
      fi
    elif SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_capture "$log" run_user "${MISE_ENV[@]}" "$bin" upgrade --yes; then
      if grep -qiE 'install|upgrad' "$log"; then notes+=("runtimes upgraded within their specs"); changed=1; else notes+=("runtimes: all within their specs"); fi
    else
      notes+=("mise upgrade failed"); failed=1
    fi
  else
    notes+=("runtimes: off; enable with --runtimes or RUNTIMES=1")
  fi

  if [ "$SU_DRY_RUN" = 1 ]; then step_dry "$(join_by '; ' "${notes[@]}")"; return 0; fi
  if [ "$failed" = 1 ]; then step_fail "$(join_by '; ' "${notes[@]}")"; return 0; fi
  if [ "$changed" = 1 ]; then step_updated "$(join_by '; ' "${notes[@]}")"; else step_ok "$(join_by '; ' "${notes[@]}")"; fi
}
