#!/usr/bin/env bash
# lib/pkg/flatpak.sh - Flatpak (system installation as root, --user as the user).
#
# Before each `flatpak update` the active commit of every installed app and
# runtime is recorded; afterwards the refs whose commit changed go to an undo
# file, so `system-update --undo-flatpak` can put them back on the commit they
# had and hold them there with `flatpak mask`. That covers the Flathub
# breakage where a runtime is rebuilt and an app that bundles libraries built
# against the old build stops starting until the app is rebuilt too (the Tor
# Browser launcher's bundled PySide6 against org.kde.Platform, for one).

flatpak_available() { has_cmd flatpak; }

# _flatpak SCOPE_FLAG ARGS...: a read-only flatpak command, as ourselves for
# --system (no root needed to read) and as the invoking user for --user.
_flatpak() {
  local scope="$1"; shift
  if [ "$scope" = --user ]; then run_user flatpak "$@"; else flatpak "$@"; fi
}

# flatpak_is_masked SHORT_REF PATTERN...: does a `flatpak mask` pattern
# hold SHORT_REF (id//branch) back? Patterns are globs; one without "//"
# matches every branch of the id.
flatpak_is_masked() {
  local short="$1" pat; shift
  for pat in "$@"; do
    [ -n "$pat" ] || continue
    if [[ "$pat" == *//* ]]; then
      # shellcheck disable=SC2053  # the pattern is a glob on purpose
      [[ "$short" == $pat ]] && return 0
    else
      # shellcheck disable=SC2053
      [[ "${short%%//*}" == $pat ]] && return 0
    fi
  done
  return 1
}

# flatpak_pending SCOPE_FLAG: refs (kind/id/arch/branch) with an update that
# `flatpak update` will apply, i.e. not held back by `flatpak mask`
# (remote-ls --updates still lists masked refs).
flatpak_pending() {
  local scope="$1" ref
  local -a masks=()
  mapfile -t masks < <(flatpak_masks "$scope")
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    flatpak_is_masked "$(flatpak_short_ref "$ref")" "${masks[@]}" && continue
    printf '%s\n' "$ref"
  done < <(_flatpak "$scope" remote-ls --updates "$scope" --columns=ref 2>/dev/null)
}

# flatpak_count_updates SCOPE_FLAG: number of apps/runtimes with updates.
flatpak_count_updates() {
  flatpak_pending "$1" | grep -c . || true
}

# flatpak_changes SCOPE_FLAG: "app//branch|installed|new" for pending
# updates. Versions come from the apps' metadata; many runtimes have none,
# and an update of the same version is a new build.
flatpak_changes() {
  local scope="$1" ref ver id
  local -A have=()
  while IFS=$'\t' read -r ref ver; do
    ref="${ref#app/}"; ref="${ref#runtime/}"
    have[$ref]="$ver"
  done < <(_flatpak "$scope" list "$scope" --columns=ref,version 2>/dev/null)
  while IFS=$'\t' read -r ref ver; do
    ref="${ref#app/}"; ref="${ref#runtime/}"
    [ -n "$ref" ] || continue
    id="${ref%%/*}//${ref##*/}"
    printf '%s|%s|%s\n' "$id" "${have[$ref]:-?}" "${ver:-(new build)}"
  done < <(_flatpak "$scope" remote-ls --updates "$scope" --columns=ref,version 2>/dev/null)
}

# flatpak_short_ref REF: org.kde.Platform/x86_64/6.11 -> org.kde.Platform//6.11
# (app/... and runtime/... refs too). `flatpak mask` takes this form.
flatpak_short_ref() {
  local ref="${1#app/}"
  ref="${ref#runtime/}"
  printf '%s//%s\n' "${ref%%/*}" "${ref##*/}"
}

# flatpak_snapshot SCOPE_FLAG: "kind/ref<TAB>commit" for every installed app
# and runtime (kind is app or runtime). `flatpak list` shortens the active
# commit to 12 characters, so the full one comes from `flatpak info`.
flatpak_snapshot() {
  local scope="$1" kind ref commit
  for kind in app runtime; do
    while IFS= read -r ref; do
      [ -n "$ref" ] || continue
      commit=$(_flatpak "$scope" info "$scope" --show-commit "$kind/$ref" 2>/dev/null) || continue
      [[ "$commit" =~ ^[0-9a-f]{64}$ ]] || continue
      printf '%s/%s\t%s\n' "$kind" "$ref" "$commit"
    done < <(_flatpak "$scope" list "$scope" "--$kind" --columns=ref 2>/dev/null)
  done
}

# flatpak_diff_snapshots SCOPE_FLAG BEFORE AFTER: "scope<TAB>ref<TAB>old<TAB>new"
# for refs whose commit changed. New refs (a runtime an app now needs) and
# removed ones are not listed: there is nothing to go back to.
flatpak_diff_snapshots() {
  local scope="${1#--}" before="$2" after="$3" ref commit
  local -A old=()
  while IFS=$'\t' read -r ref commit; do
    [ -n "$ref" ] && old[$ref]="$commit"
  done < "$before"
  while IFS=$'\t' read -r ref commit; do
    [ -n "$ref" ] && [ -n "${old[$ref]:-}" ] || continue
    [ "${old[$ref]}" = "$commit" ] && continue
    printf '%s\t%s\t%s\t%s\n' "$scope" "$ref" "${old[$ref]}" "$commit"
  done < "$after"
}

# flatpak_runtime_only_updates SCOPE_FLAG: "runtime//branch|app app ..." for
# each runtime that has an update while installed apps using it have none.
# That is when an app bundling libraries built against the runtime can stop
# starting (how the Tor Browser launcher broke in November 2026).
flatpak_runtime_only_updates() {
  local scope="$1" ref rt app short
  local -A pending=() users=()
  while IFS= read -r ref; do
    [ -n "$ref" ] && pending[$(flatpak_short_ref "$ref")]="${ref%%/*}"
  done < <(flatpak_pending "$scope")
  [ ${#pending[@]} -gt 0 ] || return 0
  while IFS=$'\t' read -r ref rt; do
    [ -n "$ref" ] && [ -n "$rt" ] || continue
    short=$(flatpak_short_ref "$rt")
    app=$(flatpak_short_ref "$ref")
    # An app with its own update pending is rebuilt along with the runtime.
    [ "${pending[$app]:-}" = app ] && continue
    users[$short]="${users[$short]:+${users[$short]} }${ref%%/*}"
  done < <(_flatpak "$scope" list "$scope" --app --columns=ref,runtime 2>/dev/null)
  for short in $(printf '%s\n' "${!pending[@]}" | sort); do
    [ "${pending[$short]}" = runtime ] && [ -n "${users[$short]:-}" ] || continue
    printf '%s|%s\n' "$short" "${users[$short]}"
  done
}

# flatpak_masks SCOPE_FLAG: patterns held back with `flatpak mask`, one per
# line (the "Masked patterns:" header a terminal gets is dropped).
flatpak_masks() {
  local scope="$1" line
  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"; line="${line%"${line##*[![:space:]]}"}"
    case "$line" in ''|*:|[Nn]o\ masked*) continue ;; esac
    printf '%s\n' "$line"
  done < <(_flatpak "$scope" mask "$scope" 2>/dev/null)
}

# flatpak_undo_file: where the last run's flatpak changes are kept:
# /var/lib/system-update as root, else ${XDG_STATE_HOME:-~/.local/state}/
# system-update. FLATPAK_UNDO_FILE overrides it.
flatpak_undo_file() {
  if [ -n "${FLATPAK_UNDO_FILE:-}" ]; then
    printf '%s\n' "$FLATPAK_UNDO_FILE"
  elif is_root; then
    printf '%s\n' /var/lib/system-update/flatpak-undo.tsv
  else
    printf '%s/system-update/flatpak-undo.tsv\n' "${XDG_STATE_HOME:-$SU_USER_HOME/.local/state}"
  fi
}

# flatpak_save_undo FILE: replace the undo file with FILE's lines (from
# flatpak_diff_snapshots). A run that changed nothing keeps the previous
# file: it still describes how to go back from what is installed now.
flatpak_save_undo() {
  local src="$1" dst dir
  [ -s "$src" ] || return 0
  dst=$(flatpak_undo_file)
  dir=$(dirname -- "$dst")
  if ! mkdir -p -- "$dir" 2>/dev/null; then
    log_warn "flatpak: cannot create $dir; undo not saved"
    return 1
  fi
  if ! {
    printf '# system-update flatpak undo, %(%Y-%m-%d %H:%M:%S %z)T\n' -1
    printf '# scope\tref\tprevious commit\tnew commit\n'
    cat -- "$src"
  } > "$dst.tmp" 2>/dev/null || ! mv -f -- "$dst.tmp" "$dst"; then
    rm -f -- "$dst.tmp"
    log_warn "flatpak: cannot write $dst; undo not saved"
    return 1
  fi
  [ -n "${SU_LOG_FILE:-}" ] && sed 's/^/flatpak undo: /' "$src" >> "$SU_LOG_FILE"
  return 0
}

# _flatpak_update SCOPE_FLAG LOG ACC: snapshot, update, snapshot again; the
# refs whose commit changed are appended to ACC. Returns flatpak's status.
_flatpak_update() {
  local scope="$1" log="$2" acc="$3" before after rc=0 runner=run_root
  [ "$scope" = --user ] && runner=run_user
  before=$(tmp_file) && after=$(tmp_file) || return 1
  flatpak_snapshot "$scope" > "$before"
  SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_capture "$log" "$runner" flatpak update "$scope" -y --noninteractive || rc=$?
  # A failed or timed-out update can still have deployed some refs.
  flatpak_snapshot "$scope" > "$after"
  flatpak_diff_snapshots "$scope" "$before" "$after" >> "$acc"
  return "$rc"
}

# _flatpak_note_runtime_only SCOPE_FLAG LOGGER: name the runtimes that
# update without their apps, so a broken app afterwards has an obvious cause.
_flatpak_note_runtime_only() {
  local line
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    "$2" "flatpak: ${line%%|*} updates without its app(s) ${line#*|}; if one stops starting: system-update --undo-flatpak"
  done < <(flatpak_runtime_only_updates "$1")
}

flatpak_step() {
  local notes=() held_notes=() rc n log acc scope label held
  flatpak_available || { step_skip "flatpak not installed"; return 0; }
  log=$(tmp_file) && acc=$(tmp_file) || return 1

  # The system installation (as root), then the invoking user's own.
  for scope in --system --user; do
    label="${scope#--}"
    [ -n "$(_flatpak "$scope" remotes "$scope" 2>/dev/null)" ] || continue
    held=$(flatpak_masks "$scope" | paste -sd ' ' -)
    [ -n "$held" ] && held_notes+=("$label held: $held")
    if [ "$SU_DRY_RUN" = 1 ]; then
      n=$(flatpak_count_updates "$scope")
      notes+=("$label: $n update(s) available${held:+, held: $held}")
      detail_show "$label flatpak(s)" flatpak_changes "$scope"
      detail_enabled && _flatpak_note_runtime_only "$scope" log_dry
      continue
    fi
    if [ "$scope" = --system ] && ! sudo_available; then
      notes+=("system: skipped (needs root)")
      continue
    fi
    _flatpak_note_runtime_only "$scope" log_info
    rc=0
    _flatpak_update "$scope" "$log" "$acc" || rc=$?
    if [ "$rc" -ne 0 ]; then
      notes+=("$label: failed ($(rc_note "$rc"))")
    else
      notes+=("$label: done${held:+, held: $held}")
    fi
  done

  if [ ${#notes[@]} -eq 0 ]; then
    step_skip "no flatpak remotes configured"
    return 0
  fi
  if [ "$SU_DRY_RUN" = 1 ]; then
    step_dry "$(join_by '; ' "${notes[@]}")"
    return 0
  fi
  n=$(grep -c . "$acc" || true)
  if [ "$n" -gt 0 ] && flatpak_save_undo "$acc"; then
    notes+=("$n changed, undo: system-update --undo-flatpak")
  fi
  if printf '%s\n' "${notes[@]}" | grep -q ': failed'; then
    step_fail "$(join_by '; ' "${notes[@]}")"
  elif [ "$n" -eq 0 ] && grep -q 'Nothing to do' "$log" && ! grep -qE '^ *[0-9]+\.' "$log"; then
    step_ok "no updates available${held_notes[*]:+; $(join_by '; ' "${held_notes[@]}")}"
  else
    step_updated "$(join_by '; ' "${notes[@]}")"
  fi
}

# flatpak_undo_main: --undo-flatpak. Puts every ref the last run changed back
# on the commit it had (`flatpak update --commit=`) and holds it there with
# `flatpak mask`, so the next run does not redo the update, then prints how
# to release the holds. With --dry-run it only prints the commands.
flatpak_undo_main() {
  local file scope ref old new short line runner rc=0 done_n=0 fail_n=0
  local -a releases=()
  if ! flatpak_available; then
    log_error "flatpak is not installed"
    return 1
  fi
  file=$(flatpak_undo_file)
  if [ ! -s "$file" ]; then
    log_error "no flatpak changes to undo: $file not found (run --undo-flatpak the way you ran system-update, with or without sudo)"
    return 1
  fi
  if [ "$SU_DRY_RUN" != 1 ] && ! is_root && grep -q $'^system\t' "$file" && ! sudo_prime; then
    log_error "the system installation needs root and sudo is not available"
    return 1
  fi
  while IFS=$'\t' read -r scope ref old new; do
    case "$scope" in system|user) ;; *) continue ;; esac
    if ! [[ "$old" =~ ^[0-9a-f]{64}$ ]] || ! [[ "$ref" =~ ^(app|runtime)/[A-Za-z0-9._-]+/[A-Za-z0-9_]+/[A-Za-z0-9._-]+$ ]]; then
      log_warn "flatpak undo: skipping a malformed line for '$ref'"
      continue
    fi
    short=$(flatpak_short_ref "$ref")
    runner=run_root; [ "$scope" = user ] && runner=run_user
    if [ "$SU_DRY_RUN" = 1 ]; then
      log_dry "would run: flatpak update --$scope -y --noninteractive --commit=$old $ref"
      log_dry "would run: flatpak mask --$scope $short"
      continue
    fi
    log_info "flatpak: $short back to ${old:0:12} (from ${new:0:12})"
    if SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT "$runner" flatpak update "--$scope" -y --noninteractive "--commit=$old" "$ref" \
       && "$runner" flatpak mask "--$scope" "$short"; then
      done_n=$((done_n + 1))
      releases+=("flatpak mask --$scope --remove $short")
    else
      fail_n=$((fail_n + 1)); rc=1
      log_warn "flatpak: could not put $short back on ${old:0:12}"
    fi
  done < "$file"
  [ "$SU_DRY_RUN" = 1 ] && return 0
  log_info "flatpak undo: $done_n ref(s) restored and held, $fail_n failed"
  if [ ${#releases[@]} -gt 0 ]; then
    log_info "they stay on these commits until released (for example once the app has a fixed build):"
    while IFS= read -r line; do log_plain "    $line"; done < <(printf '%s\n' "${releases[@]}" | sort -u)
  fi
  return "$rc"
}
