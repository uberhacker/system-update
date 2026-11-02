#!/usr/bin/env bash
# lib/tools/containers.sh - distrobox, toolbox and container images
# (opt-in: CONTAINERS=1 / --containers), as the invoking user.
#
#  * distrobox: `distrobox upgrade --all` (each container's own package
#    manager, non-interactively);
#  * toolbox: the package manager found inside each toolbox runs its
#    non-interactive upgrade through `toolbox run`;
#  * podman: `podman auto-update` for units that opted in with the
#    io.containers.autoupdate label, then every image used by an existing
#    container is pulled again;
#  * docker: the same re-pull of images used by existing containers.
# Images are only pulled; containers are never recreated or restarted here.
# Local images (localhost/, bare IDs) cannot be pulled and are left alone.

tool_containers_detect() {
  local c found=()
  for c in distrobox toolbox podman docker; do
    user_bin "$c" >/dev/null && found+=("$c")
  done
  [ ${#found[@]} -gt 0 ] || return 1
  join_by , "${found[@]}"
}

# The non-interactive upgrade that runs inside a toolbox (whatever its distro).
TOOLBOX_UPGRADE_SCRIPT='if command -v dnf5 >/dev/null 2>&1; then sudo dnf5 -y upgrade;
elif command -v dnf >/dev/null 2>&1; then sudo dnf -y upgrade;
elif command -v apt-get >/dev/null 2>&1; then sudo apt-get -q update && sudo DEBIAN_FRONTEND=noninteractive apt-get -y -q dist-upgrade;
elif command -v zypper >/dev/null 2>&1; then sudo zypper --non-interactive update;
elif command -v pacman >/dev/null 2>&1; then sudo pacman -Syu --noconfirm;
elif command -v apk >/dev/null 2>&1; then sudo apk upgrade;
else echo "no known package manager in this toolbox" >&2; exit 3; fi'

# containers_pull_images ENGINE: re-pull images used by existing containers.
containers_pull_images() {
  local engine="$1" img before after pulled=0 checked=0 failed=0 note
  while IFS= read -r img; do
    [ -n "$img" ] || continue
    case "$img" in
      localhost/*|sha256:*) continue ;;
      *[/:]*) ;;
      *) ;;   # a bare name such as "alpine" is a registry image too
    esac
    [[ "$img" =~ ^[0-9a-f]{12,64}$ ]] && continue
    checked=$((checked + 1))
    if [ "$SU_DRY_RUN" = 1 ]; then
      log_dry "would pull $img"
      continue
    fi
    before=$(run_user "$engine" image inspect --format '{{.Id}}' "$img" 2>/dev/null | head -n1)
    if SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_user "$engine" pull -q "$img" >/dev/null; then
      after=$(run_user "$engine" image inspect --format '{{.Id}}' "$img" 2>/dev/null | head -n1)
      [ "$before" != "$after" ] && pulled=$((pulled + 1))
    else
      failed=$((failed + 1))
    fi
  done < <(run_user "$engine" ps -a --format '{{.Image}}' 2>/dev/null | sort -u)
  if [ "$SU_DRY_RUN" = 1 ]; then
    CT_NOTES+=("$engine: would re-pull $checked image(s)")
  else
    note="$engine: $pulled of $checked image(s) got a newer version"
    [ "$failed" -gt 0 ] && note+=", $failed pull(s) failed"
    CT_NOTES+=("$note")
    [ "$pulled" -gt 0 ] && CT_CHANGED=1
    [ "$failed" -gt 0 ] && CT_FAILED=1
  fi
  return 0
}

tool_containers_update() {
  local tools="${SU_TOOL_BIN[containers]}" log rc n name units
  CT_NOTES=(); CT_CHANGED=0; CT_FAILED=0
  tool_opt_in CONTAINERS --containers || return 0
  log=$(tmp_file) || return 1

  if list_has "$tools" distrobox; then
    n=$(run_user distrobox list --no-color 2>/dev/null | tail -n +2 | grep -c . || true)
    if [ "$n" -eq 0 ]; then
      CT_NOTES+=("distrobox: no containers")
    elif [ "$SU_DRY_RUN" = 1 ]; then
      CT_NOTES+=("distrobox: would upgrade $n container(s)")
    elif SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_user distrobox upgrade --all; then
      CT_NOTES+=("distrobox: $n container(s) upgraded"); CT_CHANGED=1
    else
      CT_NOTES+=("distrobox upgrade --all failed"); CT_FAILED=1
    fi
  fi

  if list_has "$tools" toolbox; then
    n=0; rc=0
    while read -r _ name _; do
      [ -n "$name" ] || continue
      [ "$name" != NAME ] || continue
      n=$((n + 1))
      if [ "$SU_DRY_RUN" = 1 ]; then
        log_dry "would run the package manager upgrade inside toolbox '$name'"
      elif ! SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_user toolbox run -c "$name" sh -c "$TOOLBOX_UPGRADE_SCRIPT"; then
        rc=1
      fi
    done < <(run_user toolbox list -c 2>/dev/null | tail -n +2)
    if [ "$n" -eq 0 ]; then
      CT_NOTES+=("toolbox: no containers")
    elif [ "$SU_DRY_RUN" = 1 ]; then
      CT_NOTES+=("toolbox: would upgrade $n container(s)")
    elif [ "$rc" -ne 0 ]; then
      CT_NOTES+=("toolbox: an upgrade failed"); CT_FAILED=1
    else
      CT_NOTES+=("toolbox: $n container(s) upgraded"); CT_CHANGED=1
    fi
  fi

  if list_has "$tools" podman; then
    units=$(run_user podman auto-update --dry-run --format '{{.Unit}}' 2>/dev/null | grep -c . || true)
    if [ "$units" -gt 0 ]; then
      if [ "$SU_DRY_RUN" = 1 ]; then
        CT_NOTES+=("podman: $units auto-update unit(s) would be checked")
      elif run_user podman auto-update >/dev/null 2>&1; then
        CT_NOTES+=("podman auto-update: $units unit(s) checked")
      else
        CT_NOTES+=("podman auto-update failed"); CT_FAILED=1
      fi
    fi
    containers_pull_images podman
  fi

  if list_has "$tools" docker; then
    if ! run_user docker ps -q >/dev/null 2>&1; then
      CT_NOTES+=("docker: daemon not reachable as $SU_USER (not running, or not in the docker group)")
    else
      containers_pull_images docker
    fi
  fi

  if [ "$SU_DRY_RUN" = 1 ]; then step_dry "$(join_by '; ' "${CT_NOTES[@]}")"; return 0; fi
  if [ "$CT_FAILED" = 1 ]; then step_fail "$(join_by '; ' "${CT_NOTES[@]}")"; return 0; fi
  if [ "$CT_CHANGED" = 1 ]; then step_updated "$(join_by '; ' "${CT_NOTES[@]}")"; else step_ok "$(join_by '; ' "${CT_NOTES[@]}")"; fi
}
