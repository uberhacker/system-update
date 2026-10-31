#!/usr/bin/env bash
# lib/pkg/flatpak.sh - Flatpak (system installation as root, --user as the user).

flatpak_available() { has_cmd flatpak; }

# flatpak_count_updates SCOPE_FLAG: number of apps/runtimes with updates.
flatpak_count_updates() {
  local scope="$1"
  flatpak remote-ls --updates "$scope" --columns=ref 2>/dev/null | grep -c . || true
}

# flatpak_changes SCOPE_FLAG: "app//branch|installed|new" for pending
# updates. Versions come from the apps' metadata; many runtimes have none,
# and an update of the same version is a new build.
flatpak_changes() {
  local scope="$1" ref ver id
  local -a run=(flatpak)
  local -A have=()
  [ "$scope" = --user ] && run=(run_user flatpak)
  while IFS=$'\t' read -r ref ver; do
    ref="${ref#app/}"; ref="${ref#runtime/}"
    have[$ref]="$ver"
  done < <("${run[@]}" list "$scope" --columns=ref,version 2>/dev/null)
  while IFS=$'\t' read -r ref ver; do
    ref="${ref#app/}"; ref="${ref#runtime/}"
    [ -n "$ref" ] || continue
    id="${ref%%/*}//${ref##*/}"
    printf '%s|%s|%s\n' "$id" "${have[$ref]:-?}" "${ver:-(new build)}"
  done < <("${run[@]}" remote-ls --updates "$scope" --columns=ref,version 2>/dev/null)
}

flatpak_step() {
  local notes=() rc=0 n log
  flatpak_available || { step_skip "flatpak not installed"; return 0; }
  log=$(tmp_file) || return 1

  # System installation.
  if [ -n "$(flatpak remotes --system 2>/dev/null)" ]; then
    if [ "$SU_DRY_RUN" = 1 ]; then
      n=$(flatpak_count_updates --system)
      notes+=("system: $n update(s) available")
      detail_show "system flatpak(s)" flatpak_changes --system
    elif sudo_available; then
      SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_capture "$log" run_root flatpak update --system -y --noninteractive || rc=$?
      if [ "$rc" -ne 0 ]; then notes+=("system: failed ($(rc_note "$rc"))"); else notes+=("system: done"); fi
      rc=0
    else
      notes+=("system: skipped (needs root)")
    fi
  fi

  # Per-user installation of the invoking user.
  if [ -n "$(run_user flatpak remotes --user 2>/dev/null)" ]; then
    if [ "$SU_DRY_RUN" = 1 ]; then
      n=$(run_user flatpak remote-ls --updates --user --columns=ref 2>/dev/null | grep -c . || true)
      notes+=("user: $n update(s) available")
      detail_show "user flatpak(s)" flatpak_changes --user
    else
      SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_capture "$log" run_user flatpak update --user -y --noninteractive || rc=$?
      if [ "$rc" -ne 0 ]; then notes+=("user: failed ($(rc_note "$rc"))"); else notes+=("user: done"); fi
      rc=0
    fi
  fi

  if [ ${#notes[@]} -eq 0 ]; then
    step_skip "no flatpak remotes configured"
    return 0
  fi
  if [ "$SU_DRY_RUN" = 1 ]; then
    step_dry "$(join_by '; ' "${notes[@]}")"
  elif printf '%s\n' "${notes[@]}" | grep -q failed; then
    step_fail "$(join_by '; ' "${notes[@]}")"
  elif grep -q 'Nothing to do' "$log" && ! grep -qE '^ *[0-9]+\.' "$log"; then
    step_ok "no updates available"
  else
    step_updated "$(join_by '; ' "${notes[@]}")"
  fi
}
