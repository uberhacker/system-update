#!/usr/bin/env bash
# lib/pkg/pacman.sh - Arch, Manjaro, EndeavourOS and other pacman distros.
#
# Dry run: `checkupdates` (pacman-contrib) when present, otherwise the same
# trick done by hand - sync the repo databases into a temporary dbpath and
# run `pacman -Qu` against it, so the real sync database is never touched.
# An AUR helper is never run as root; with AUR_HELPER=1 (--aur) yay/paru is
# run as the invoking user for AUR packages only.

pkg_pacman_dry_needs_root() { has_cmd checkupdates && has_cmd fakeroot && return 1; return 0; }

# pacman_pending LOGFILE: list pending updates without touching the system db.
# Returns 0 when updates are pending, 1 when none, 2 on error.
pacman_pending() {
  local log="$1" tmp rc=0
  if has_cmd checkupdates && (has_cmd fakeroot || is_root); then
    checkupdates --nocolor >"$log" 2>/dev/null || rc=$?
    case "$rc" in
      0) return 0 ;;
      2) return 1 ;;
      *) log_detail "checkupdates failed ($rc); falling back to a temporary database" ;;
    esac
  fi
  tmp=$(tmp_dir) || return 2
  mkdir -p "$tmp/db"
  # pacman >= 6.1 downloads as the unprivileged DownloadUser (alpm), which
  # must be able to traverse into the temporary dbpath; mktemp made it 0700.
  chmod 0755 "$tmp" "$tmp/db"
  ln -s /var/lib/pacman/local "$tmp/db/local"
  rc=0
  SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_root pacman -Sy --dbpath "$tmp/db" --logfile /dev/null -q >"$tmp/sync.log" 2>&1 || rc=$?
  if [ "$rc" -ne 0 ]; then
    # Show why (mirror unreachable, bad signature, ...) instead of a bare failure.
    grep -E '^error:' "$tmp/sync.log" | tail -n 3 | while IFS= read -r line; do log_warn "$line"; done
    run_root rm -rf -- "$tmp/db" >/dev/null 2>&1 || true
    return 2
  fi
  rc=0
  run_root pacman -Qu --dbpath "$tmp/db" >"$log" 2>/dev/null || rc=$?
  # The temporary db is root-owned when sudo created it; remove it as root.
  run_root rm -rf -- "$tmp/db" >/dev/null 2>&1 || true
  case "$rc" in
    0) [ -s "$log" ] ;;
    1) return 1 ;;
    *) return 2 ;;
  esac
}

# pacman_changes LOGFILE: "name|installed|new" from checkupdates or
# `pacman -Qu` output ("gnupg 2.4.9-3 -> 2.4.9-4").
pacman_changes() {
  local name old arrow new _rest
  while read -r name old arrow new _rest; do
    [ "$arrow" = "->" ] && printf '%s|%s|%s\n' "$name" "$old" "$new"
  done < "$1"
}

pkg_pacman_update() {
  local log rc=0 count aur="" aur_note=""
  log=$(tmp_file) || return 1

  if cfg_bool AUR_HELPER; then
    if has_cmd paru; then aur=paru; elif has_cmd yay; then aur=yay; fi
    if [ -n "$aur" ] && [ "$SU_USER" = root ]; then
      log_warn "AUR helpers must not run as root; skipping $aur"
      aur=""
    fi
  fi

  if [ "$SU_DRY_RUN" = 1 ]; then
    rc=0
    pacman_pending "$log" || rc=$?
    case "$rc" in
      0) count=$(grep -c . "$log")
         detail_show "package(s)" pacman_changes "$log"
         step_dry "$count package(s) would be upgraded" ;;
      1) step_dry "no updates available" ;;
      *) step_fail "could not check for updates (database sync failed)"; return 0 ;;
    esac
    if [ -n "$aur" ]; then
      log_dry "would run: $aur -Sua --noconfirm (AUR, as $SU_USER)"
    fi
    return 0
  fi

  SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_capture "$log" run_root pacman -Syu --noconfirm --noprogressbar || rc=$?
  if [ "$rc" -ne 0 ]; then
    step_fail "pacman -Syu failed ($(rc_note "$rc"))"
    return 0
  fi
  count=$(count_matching '^(upgrading|installing) ' "$log")
  if [ -n "$aur" ]; then
    log_info "updating AUR packages with $aur as $SU_USER"
    if SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_user "$aur" -Sua --noconfirm; then
      aur_note="; AUR checked with $aur"
    else
      aur_note="; $aur failed"
    fi
  fi
  if cfg_bool AUTOREMOVE; then
    local orphans
    orphans=$(pacman -Qtdq 2>/dev/null || true)
    if [ -n "$orphans" ]; then
      # shellcheck disable=SC2086
      run_root pacman -Rns --noconfirm $orphans || log_warn "could not remove orphans"
    fi
  fi
  run_root paccache -rk2 >/dev/null 2>&1 || true
  if grep -q 'there is nothing to do' "$log" && [ "$count" = 0 ]; then
    step_ok "no updates available$aur_note"
  else
    step_updated "$count package(s) upgraded/installed$aur_note"
  fi
}

pkg_pacman_install() {
  # -S (not -Sy): a partial sync followed by an install can break Arch.
  SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_root pacman -S --noconfirm --needed "$@"
}

pkg_pacman_reboot_check() {
  # Arch has no marker file; the generic kernel check in pkg.sh covers it.
  return 2
}
