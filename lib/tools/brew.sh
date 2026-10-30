#!/usr/bin/env bash
# lib/tools/brew.sh - Homebrew on Linux: brew update + brew upgrade, as the user.
#
# Homebrew refuses to run as root, and running it as root would break the
# prefix's ownership, so the step is skipped when the invoking user is root.
# With AUTOREMOVE=1 (default) `brew autoremove` runs afterwards. The dry run
# refreshes the formula index (brew update, metadata only) and lists what
# `brew outdated` reports.

tool_brew_detect() {
  local bin p
  if bin=$(user_bin brew); then printf '%s\n' "$bin"; return 0; fi
  for p in /home/linuxbrew/.linuxbrew/bin/brew "$SU_USER_HOME/.linuxbrew/bin/brew"; do
    [ -x "$p" ] && { printf '%s\n' "$p"; return 0; }
  done
  return 1
}

brew_env() {
  local -a e=(env HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_EMOJI=1 HOMEBREW_NO_COLOR=1)
  cfg_bool AUTOREMOVE || e+=(HOMEBREW_NO_INSTALL_CLEANUP=1)
  printf '%s\n' "${e[@]}"
}

tool_brew_update() {
  local bin="${SU_TOOL_BIN[brew]}" log rc=0 outdated count owner
  local -a env_cmd=()
  mapfile -t env_cmd < <(brew_env)

  if [ "$SU_USER" = root ]; then
    step_skip "Homebrew must not run as root; run system-update as your own user (sudo from it is fine)"
    return 0
  fi
  owner=$(stat -c %U "$(readlink -f -- "$bin" 2>/dev/null || printf '%s' "$bin")" 2>/dev/null || true)
  if [ -n "$owner" ] && [ "$owner" != "$SU_USER" ]; then
    step_skip "$bin is owned by $owner, not $SU_USER; not touching another user's Homebrew"
    return 0
  fi
  log=$(tmp_file) || return 1

  if ! SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_capture "$log" run_user "${env_cmd[@]}" "$bin" update; then
    step_fail "brew update failed"
    return 0
  fi
  outdated=$(run_user "${env_cmd[@]}" "$bin" outdated --quiet 2>/dev/null || true)
  count=$(printf '%s\n' "$outdated" | grep -c . || true)

  if [ "$SU_DRY_RUN" = 1 ]; then
    if [ "$count" -gt 0 ]; then
      step_dry "$count outdated: $(printf '%s\n' "$outdated" | tr '\n' ' ' | sed 's/ $//'); would run brew upgrade"
    else
      step_dry "nothing outdated"
    fi
    return 0
  fi

  if [ "$count" -eq 0 ]; then
    step_ok "nothing outdated"
    return 0
  fi
  : > "$log"
  SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_capture "$log" run_user "${env_cmd[@]}" "$bin" upgrade || rc=$?
  if [ "$rc" -ne 0 ]; then
    step_fail "brew upgrade failed ($(rc_note "$rc"))"
    return 0
  fi
  if cfg_bool AUTOREMOVE; then
    run_user "${env_cmd[@]}" "$bin" autoremove >/dev/null 2>&1 || log_warn "brew autoremove failed"
  fi
  step_updated "$count package(s) upgraded: $(printf '%s\n' "$outdated" | tr '\n' ' ' | sed 's/ $//')"
}
