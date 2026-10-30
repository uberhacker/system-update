#!/usr/bin/env bash
# lib/core/selfupdate.sh - update this program from its own source.
#
# Git checkout:  verify origin matches SELF_UPDATE_REPO (re-point only with
#                --source), refuse a dirty tree, fetch, fast-forward only.
# Plain install: download the branch tarball over https, sanity-check it
#                (entry point present, bash -n passes) and swap the directory
#                in with two renames. Never `reset --hard`, never chown system
#                directories to the user.
#
# Branch: SELF_UPDATE_BRANCH when set; otherwise the checkout's current branch
# if the remote has it; otherwise the remote's default branch (git ls-remote
# --symref), falling back to "master".

SU_SELF_UPDATE_FALLBACK_BRANCH="master"

# selfupdate_norm_url URL: canonical form for comparing remotes.
selfupdate_norm_url() {
  local u="${1%/}"
  u="${u%.git}"
  u="${u#file://}"
  u="${u,,}"
  printf '%s\n' "$u"
}

# selfupdate_source_ok URL: https only (file:// for tests).
selfupdate_source_ok() {
  case "$1" in
    https://*) return 0 ;;
    file:///*) [ "${SYSTEM_UPDATE_ALLOW_FILE_SOURCE:-0}" = 1 ] && return 0 ;;
  esac
  log_error "self-update source must be an https:// URL: $1"
  return 1
}

# selfupdate_remote_default_branch URL: parse `git ls-remote --symref URL HEAD`.
selfupdate_remote_default_branch() {
  local url="$1" out
  has_cmd git || return 1
  out=$(timeout 60 git ls-remote --symref "$url" HEAD 2>/dev/null </dev/null) || return 1
  out=$(printf '%s\n' "$out" | sed -n 's|^ref: refs/heads/\([^[:space:]]*\)[[:space:]]*HEAD$|\1|p' | head -n1)
  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
}

# selfupdate_remote_has_branch URL BRANCH
selfupdate_remote_has_branch() {
  has_cmd git || return 1
  [ -n "$(timeout 60 git ls-remote --heads "$1" "refs/heads/$2" 2>/dev/null </dev/null)" ]
}

# _su_owner PATH: owner user name.
_su_owner() { stat -c %U "$1" 2>/dev/null; }

# _su_as_owner PATH CMD...: run CMD as the owner of PATH.
_su_as_owner() {
  local path="$1"; shift
  local owner me
  owner=$(_su_owner "$path")
  me=$(id -un)
  if [ -z "$owner" ] || [ "$owner" = "$me" ]; then
    log_cmd "$*"
    "$@" </dev/null
  elif is_root; then
    log_cmd "(as $owner) $*"
    if has_cmd runuser; then
      runuser -u "$owner" -- "$@" </dev/null
    else
      sudo -n -u "$owner" -H -- "$@" </dev/null
    fi
  elif [ "$owner" = root ]; then
    if ! has_cmd sudo; then
      log_error "$path is owned by root and sudo is not available"
      return 1
    fi
    log_cmd "sudo $*"
    sudo -n "$@" </dev/null
  else
    log_error "$path is owned by $owner; run self-update as that user"
    return 1
  fi
}

# selfupdate_git ROOT REPO BRANCH
selfupdate_git() {
  local root="$1" repo="$2" branch="$3"
  local origin current target old_rev new_rev old_ver new_ver behind
  local -a git=(_su_as_owner "$root" git -C "$root")

  origin=$("${git[@]}" remote get-url origin 2>/dev/null) || {
    log_error "cannot read the origin remote of $root"
    return 1
  }
  if [ "$(selfupdate_norm_url "$origin")" != "$(selfupdate_norm_url "$repo")" ]; then
    if [ -n "$SU_ARG_SOURCE" ]; then
      log_info "re-pointing origin from $origin to $repo (--source)"
      if [ "$SU_DRY_RUN" != 1 ]; then
        "${git[@]}" remote set-url origin "$repo" || return 1
      fi
    else
      log_error "checkout origin ($origin) does not match the configured source ($repo)"
      log_error "pass --source '$repo' to re-point it, or set SELF_UPDATE_REPO to match"
      return 1
    fi
  fi

  if [ -n "$("${git[@]}" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
    log_error "refusing to update: $root has local changes (commit or stash them first)"
    return 1
  fi

  old_rev=$("${git[@]}" rev-parse --short HEAD 2>/dev/null)
  old_ver=$(cat "$root/VERSION" 2>/dev/null || echo unknown)
  current=$("${git[@]}" symbolic-ref --short -q HEAD 2>/dev/null || true)

  if [ -n "$branch" ]; then
    target="$branch"
  elif [ -n "$current" ] && selfupdate_remote_has_branch "$repo" "$current"; then
    target="$current"
  else
    target=$(selfupdate_remote_default_branch "$repo") || target="$SU_SELF_UPDATE_FALLBACK_BRANCH"
  fi
  log_info "source: $repo (branch $target)"
  log_info "installed: $old_ver ($old_rev${current:+, on $current})"

  "${git[@]}" fetch --quiet origin "$target" || { log_error "git fetch failed"; return 1; }
  behind=$("${git[@]}" rev-list --count "HEAD..FETCH_HEAD" 2>/dev/null || echo "?")

  if [ "$SU_DRY_RUN" = 1 ]; then
    new_rev=$("${git[@]}" rev-parse --short FETCH_HEAD 2>/dev/null)
    if [ "$behind" = 0 ] && [ "$current" = "$target" ]; then
      log_dry "already up to date ($old_rev)"
    else
      log_dry "would fast-forward $old_rev -> $new_rev ($behind new commit(s) on $target)"
    fi
    return 0
  fi

  if [ "$current" != "$target" ]; then
    "${git[@]}" checkout --quiet "$target" || { log_error "could not switch to branch $target"; return 1; }
  fi
  "${git[@]}" pull --ff-only --quiet origin "$target" || {
    log_error "fast-forward failed; the checkout has diverged from $repo ($target)"
    return 1
  }
  new_rev=$("${git[@]}" rev-parse --short HEAD 2>/dev/null)
  new_ver=$(cat "$root/VERSION" 2>/dev/null || echo unknown)
  if [ "$old_rev" = "$new_rev" ]; then
    log_ok "already up to date: $new_ver ($new_rev)"
  else
    log_updated "updated $old_ver ($old_rev) -> $new_ver ($new_rev)"
  fi
  return 0
}

# selfupdate_check_tree DIR: is DIR a plausible system-update tree?
selfupdate_check_tree() {
  local dir="$1" f
  [ -f "$dir/bin/system-update" ] || { log_error "downloaded tree has no bin/system-update"; return 1; }
  [ -d "$dir/lib/core" ] || { log_error "downloaded tree has no lib/core"; return 1; }
  bash -n "$dir/bin/system-update" || { log_error "downloaded entry point does not parse"; return 1; }
  while IFS= read -r -d '' f; do
    bash -n "$f" || { log_error "downloaded file does not parse: ${f#"$dir"/}"; return 1; }
  done < <(find "$dir/lib" -name '*.sh' -type f -print0)
  return 0
}

# selfupdate_tarball ROOT REPO BRANCH
selfupdate_tarball() {
  local root="$1" repo="$2" branch="$3"
  local url tmp tarball top old_ver new_ver parent base staging old owner

  if [ -z "$branch" ]; then
    branch=$(selfupdate_remote_default_branch "$repo") || branch="$SU_SELF_UPDATE_FALLBACK_BRANCH"
  fi
  url="${repo}/archive/refs/heads/${branch}.tar.gz"
  old_ver=$(cat "$root/VERSION" 2>/dev/null || echo unknown)
  log_info "source: $url"
  log_info "installed: $old_ver (not a git checkout)"

  tmp=$(tmp_dir) || return 1
  tarball="$tmp/source.tar.gz"
  download "$url" "$tarball" || return 1
  mkdir -p "$tmp/x"
  tar -xzf "$tarball" -C "$tmp/x" || { log_error "could not extract the downloaded tarball"; return 1; }
  top=$(find "$tmp/x" -mindepth 1 -maxdepth 1 -type d | head -n1)
  [ -n "$top" ] || { log_error "tarball is empty"; return 1; }
  selfupdate_check_tree "$top" || return 1
  new_ver=$(cat "$top/VERSION" 2>/dev/null || echo unknown)

  if [ "$SU_DRY_RUN" = 1 ]; then
    log_dry "would replace $root ($old_ver) with $new_ver from $branch"
    return 0
  fi

  parent=$(dirname "$root"); base=$(basename "$root")
  staging="$parent/.$base.new.$$"
  old="$parent/.$base.old.$$"
  owner=$(_su_owner "$root")
  _su_as_owner "$root" cp -a "$top" "$staging" || return 1
  if is_root && [ -n "$owner" ] && [ "$owner" != root ]; then
    chown -R "$owner" "$staging" 2>/dev/null || true
  fi
  if ! _su_as_owner "$root" mv "$root" "$old"; then
    _su_as_owner "$root" rm -rf "$staging"
    return 1
  fi
  if ! _su_as_owner "$old" mv "$staging" "$root"; then
    log_error "swap failed; restoring the previous installation"
    _su_as_owner "$old" mv "$old" "$root"
    return 1
  fi
  _su_as_owner "$root" rm -rf "$old"
  log_updated "updated $old_ver -> $new_ver ($branch)"
  return 0
}

# selfupdate_main: entry for --self-update.
selfupdate_main() {
  local repo branch root="$SU_ROOT"
  repo=$(cfg SELF_UPDATE_REPO)
  branch=$(cfg SELF_UPDATE_BRANCH)
  selfupdate_source_ok "$repo" || return 1
  log_step "self-update"
  if [ -e "$root/.git" ]; then
    has_cmd git || { log_error "git is required to update a git checkout"; return 1; }
    selfupdate_git "$root" "$repo" "$branch"
  else
    selfupdate_tarball "$root" "$repo" "$branch"
  fi
}
