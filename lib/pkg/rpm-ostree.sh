#!/usr/bin/env bash
# lib/pkg/rpm-ostree.sh - Fedora Atomic (Silverblue, Kinoite, ...), Bazzite,
# Bluefin, CoreOS: image based systems. Uses bootc when the system is booted
# from a bootc container image, otherwise rpm-ostree. Updates are staged and
# take effect after a reboot; dnf is never run here.

pkg_rpm_ostree_dry_needs_root() { return 0; }

# ostree_use_bootc: booted from a bootc image?
ostree_use_bootc() {
  has_cmd bootc || return 1
  local f
  f=$(tmp_file) || return 1
  run_root bootc status --format=json >"$f" 2>/dev/null || return 1
  local img
  img=$(json_get .status.booted.image.image.image "$f" 2>/dev/null) || img=$(json_get .image "$f" 2>/dev/null) || return 1
  [ -n "$img" ]
}

# ostree_changes LOGFILE: "name|installed|new" from `rpm-ostree upgrade
# --preview`: "  name old -> new" rows under Upgraded:/Downgraded:, and NEVRAs
# under Added:/Removed:.
ostree_changes() {
  local line section="" nevra name ver
  local re_change='^[[:space:]]+([^[:space:]]+)[[:space:]]+([^[:space:]]+)[[:space:]]+->[[:space:]]+([^[:space:]]+)[[:space:]]*$'
  while IFS= read -r line; do
    case "$line" in
      *Added:*) section=add; continue ;;
      *Removed:*) section=rm; continue ;;
      *Upgraded:*|*Downgraded:*) section=change; continue ;;
    esac
    if [[ "$line" =~ $re_change ]]; then
      printf '%s|%s|%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
      continue
    fi
    [[ "$line" =~ ^[[:space:]]+([^[:space:]]+)[[:space:]]*$ ]] || { section=""; continue; }
    nevra="${BASH_REMATCH[1]}"
    nevra="${nevra%.*}"             # drop .arch
    name="${nevra%-*-*}"
    ver="${nevra#"$name"-}"
    case "$section" in
      add) printf '%s||%s\n' "$name" "$ver" ;;
      rm) printf '%s|%s|\n' "$name" "$ver" ;;
    esac
  done < "$1"
}

pkg_rpm_ostree_update() {
  local log rc=0
  log=$(tmp_file) || return 1

  if ostree_use_bootc; then
    log_info "bootc image based system"
    if [ "$SU_DRY_RUN" = 1 ]; then
      run_capture "$log" run_root bootc upgrade --check || rc=$?
      if [ "$rc" -ne 0 ]; then step_fail "bootc upgrade --check failed ($(rc_note "$rc"))"; return 0; fi
      if grep -qi 'no changes' "$log"; then step_dry "no updates available"; else step_dry "a new image is available"; fi
      return 0
    fi
    SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_capture "$log" run_root bootc upgrade || rc=$?
    if [ "$rc" -ne 0 ]; then step_fail "bootc upgrade failed ($(rc_note "$rc"))"; return 0; fi
    if grep -qi 'no changes' "$log"; then
      step_ok "no updates available"
    else
      step_updated "new image staged; reboot to apply"
    fi
    return 0
  fi

  if ! has_cmd rpm-ostree; then
    step_skip "rpm-ostree not found on an ostree system"
    return 0
  fi
  if [ "$SU_DRY_RUN" = 1 ]; then
    # --preview is --check plus the package diff of the new deployment.
    if detail_enabled; then
      run_capture "$log" run_root rpm-ostree upgrade --preview || rc=$?
    else
      run_capture "$log" run_root rpm-ostree upgrade --check || rc=$?
    fi
    case "$rc" in
      0) detail_show "package(s)" ostree_changes "$log"
         step_dry "updates available (see above)" ;;
      77) step_dry "no updates available" ;;
      *) step_fail "rpm-ostree upgrade --check failed ($(rc_note "$rc"))" ;;
    esac
    return 0
  fi
  SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_capture "$log" run_root rpm-ostree upgrade || rc=$?
  case "$rc" in
    0) step_updated "new deployment staged; reboot to apply" ;;
    77) step_ok "no updates available" ;;
    *) step_fail "rpm-ostree upgrade failed ($(rc_note "$rc"))" ;;
  esac
}

pkg_rpm_ostree_install() {
  # Layering packages changes the deployment; only do it on explicit request.
  log_warn "not layering '$*' on an image based system; install it with rpm-ostree install yourself"
  return 1
}

pkg_rpm_ostree_reboot_check() {
  local f booted
  has_cmd rpm-ostree || return 2
  f=$(tmp_file) || return 2
  rpm-ostree status --json >"$f" 2>/dev/null || return 2
  # The first deployment listed is the one that boots next.
  booted=$(json_get '.deployments[0].booted' "$f" 2>/dev/null) || return 2
  if [ "$booted" = false ]; then
    echo "a new deployment is staged"
    return 0
  fi
  return 1
}
