#!/usr/bin/env bash
# lib/core/tools.sh - third-party tool discovery and the shared update logic.
#
# Every file in lib/tools/<name>.sh defines:
#   tool_<name>_detect   -> returns 0 when the tool is installed and prints
#                           the path (or a short description) on stdout.
#                           Must be cheap and side-effect free.
#   tool_<name>_update   -> the step; reports with step_ok/step_updated/...
#   tool_<name>_scope    -> optional; prints "system" when the tool lives in
#                           system locations (default "user").
# A dash in the file name becomes an underscore in the function names.
#
# Identification guard: generic names (pi, kilo, grok, ...) collide with
# unrelated programs. tool_identify() decides what a binary is by (1) the
# package it came from (npm/bun/pnpm/uv/pipx path layout, or a distro
# package) and only then (2) a --version probe that runs with a timeout,
# stdin from /dev/null and whose output must match an expected pattern.

SU_TOOLS=()
declare -gA SU_TOOL_BIN=()
TOOL_METHOD="unknown"
TOOL_REAL=""
TOOL_PROBE_OUT=""

# tools_load: source every tool module.
tools_load() {
  local f
  for f in "$SU_ROOT"/lib/tools/*.sh; do
    [ -r "$f" ] || continue
    # shellcheck disable=SC1090
    source "$f"
  done
}

# tool_fn NAME SUFFIX: function name for a tool.
tool_fn() {
  local n="${1//-/_}"
  printf 'tool_%s_%s\n' "$n" "$2"
}

# tools_discover: run every detect function; fills SU_TOOLS / SU_TOOL_BIN.
tools_discover() {
  local f name fn out
  SU_TOOLS=()
  SU_TOOL_BIN=()
  for f in "$SU_ROOT"/lib/tools/*.sh; do
    [ -r "$f" ] || continue
    name=$(basename "$f" .sh)
    fn=$(tool_fn "$name" detect)
    declare -F "$fn" >/dev/null || continue
    if out=$("$fn" 2>/dev/null); then
      SU_TOOLS+=("$name")
      SU_TOOL_BIN[$name]="$out"
    fi
  done
}

# tool_scope NAME: user|system
tool_scope() {
  local fn
  fn=$(tool_fn "$1" scope)
  if declare -F "$fn" >/dev/null; then "$fn"; else echo user; fi
}

# user_bin NAME: command -v for the invoking user. When we are root acting
# for SUDO_USER the user's tools are run in a child process, so plain
# command -v is right in every context.
user_bin() { command -v "$1" 2>/dev/null; }

# install_method PATH: how was this binary installed?
# Prints one of: npm:PKG bun:PKG pnpm:PKG uv:PKG pipx:PKG cargo brew distro:PKG unknown
install_method() {
  local bin="$1" real rest pkg owner
  real=$(readlink -f -- "$bin" 2>/dev/null) || real="$bin"
  TOOL_REAL="$real"
  case "$real" in
    */node_modules/*)
      rest="${real##*/node_modules/}"
      if [[ "$rest" == @* ]]; then
        pkg="${rest%%/*}/$(printf '%s' "${rest#*/}" | cut -d/ -f1)"
      else
        pkg="${rest%%/*}"
      fi
      case "$real" in
        */.bun/*) echo "bun:$pkg" ;;
        */pnpm/*) echo "pnpm:$pkg" ;;
        *) echo "npm:$pkg" ;;
      esac
      return 0 ;;
    */uv/tools/*)
      rest="${real##*/uv/tools/}"; echo "uv:${rest%%/*}"; return 0 ;;
    */pipx/venvs/*)
      rest="${real##*/pipx/venvs/}"; echo "pipx:${rest%%/*}"; return 0 ;;
    */.cargo/bin/*) echo cargo; return 0 ;;
    */linuxbrew/*|*/Homebrew/*) echo brew; return 0 ;;
  esac
  if owner=$(distro_pkg_owner "$real"); then
    echo "distro:$owner"
    return 0
  fi
  echo unknown
}

# tool_probe BIN ARGS...: run a version query safely. Output is capped;
# exit status 124 (coreutils), 143 (busybox, SIGTERM) or 137 (SIGKILL after
# -k) means it hung.
tool_probe() {
  local bin="$1"; shift
  local out rc=0 text
  out=$(mktemp "${TMPDIR:-/tmp}/su-probe.XXXXXX") || return 1
  timeout -k 2 "$SU_PROBE_TIMEOUT" env TERM=dumb NO_COLOR=1 CI=1 "$bin" "$@" </dev/null >"$out" 2>&1 || rc=$?
  # Read, remove, then print: a caller that stops reading early (| head -n1)
  # kills this subshell with SIGPIPE, which must not leave the file behind.
  text=$(head -c 4096 "$out")
  rm -f -- "$out"
  printf '%s\n' "$text"
  return "$rc"
}

# version_from_text TEXT: first thing that looks like a version number.
version_from_text() {
  printf '%s\n' "$1" | grep -o -E '[0-9]+\.[0-9]+(\.[0-9]+)?([.-][0-9A-Za-z]+)*' | head -n1
}

# tool_identify NAME BIN REGEX EXPECT_PKGS PROBE_ARGS...
# Sets TOOL_METHOD / TOOL_REAL / TOOL_PROBE_OUT. Returns 0 when BIN is the
# program we think it is; otherwise records a skip and returns 1.
tool_identify() {
  local name="$1" bin="$2" regex="$3" expect="$4"; shift 4
  local method pkg
  TOOL_PROBE_OUT=""
  method=$(install_method "$bin")
  TOOL_METHOD="$method"
  pkg="${method#*:}"
  case "${method%%:*}" in
    npm|bun|pnpm|uv|pipx)
      if [ -n "$expect" ]; then
        if list_has "$expect" "$pkg"; then
          log_detail "$name: ${method%%:*} package $pkg"
          return 0
        fi
        step_skip "$bin is ${method%%:*} package '$pkg', not ${expect//,/ or }"
        return 1
      fi ;;
    distro)
      step_skip "$bin belongs to $SU_PKG package '$pkg' (updated with the system packages)"
      return 1 ;;
  esac
  if [ $# -eq 0 ]; then
    return 0
  fi
  tool_probe_check "$name" "$bin" "$regex" "$@"
}

# tool_probe_check NAME BIN REGEX PROBE_ARGS...: the probe half of
# tool_identify, for tools that stay ours to update even when a distro
# package installed them (rustup, mise: the toolchains and plugins they
# manage live in the user's home). Sets TOOL_PROBE_OUT; records a skip and
# returns 1 when the probe hangs or its output does not match REGEX.
tool_probe_check() {
  local name="$1" bin="$2" regex="$3"; shift 3
  local out rc=0
  TOOL_PROBE_OUT=""
  out=$(tool_probe "$bin" "$@") || rc=$?
  if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ] || [ "$rc" -eq 143 ]; then
    step_skip "$bin did not answer '$*' within ${SU_PROBE_TIMEOUT}s; it looks like a different program"
    return 1
  fi
  if ! printf '%s\n' "$out" | grep -q -E -- "$regex"; then
    step_skip "$bin does not look like $name (unexpected '$*' output)"
    return 1
  fi
  TOOL_PROBE_OUT="$out"
  return 0
}

# tool_pkg_update: update through the package that installed the tool.
# Returns 0 if a package manager handled it, 2 if none applies.
tool_pkg_update() {
  local pkg="${TOOL_METHOD#*:}"
  case "${TOOL_METHOD%%:*}" in
    npm)  has_cmd npm  || return 2; do_user npm install -g "${pkg}@latest" ;;
    bun)  has_cmd bun  || return 2; do_user bun install -g "${pkg}@latest" ;;
    pnpm) has_cmd pnpm || return 2; do_user pnpm add -g "${pkg}@latest" ;;
    uv)   has_cmd uv   || return 2; do_user uv tool upgrade "$pkg" ;;
    pipx) has_cmd pipx || return 2; do_user pipx upgrade "$pkg" ;;
    *) return 2 ;;
  esac
}

# tool_standard NAME BIN REGEX EXPECT_PKGS PROBE_ARGS... -- SELF_UPDATE_CMD...
# The common case: identify the binary, update it through its package
# manager when we know one, otherwise with its own self-update command, then
# compare versions before/after for the summary.
tool_standard() {
  local name="$1" bin="$2" regex="$3" expect="$4"; shift 4
  local -a probe=() cmd=()
  while [ $# -gt 0 ]; do
    if [ "$1" = -- ]; then shift; cmd=("$@"); break; fi
    probe+=("$1"); shift
  done
  tool_identify "$name" "$bin" "$regex" "$expect" "${probe[@]}" || return 0
  local before after rc=0 how
  before=$(version_from_text "$TOOL_PROBE_OUT")
  if [ -z "$before" ] && [ ${#probe[@]} -gt 0 ]; then
    before=$(version_from_text "$(tool_probe "$bin" "${probe[@]}")")
  fi
  [ -n "$before" ] && log_info "installed version: $before"

  case "${TOOL_METHOD%%:*}" in
    npm|bun|pnpm|uv|pipx) how="${TOOL_METHOD%%:*} (${TOOL_METHOD#*:})" ;;
    cargo)
      # The cargo step (lib/tools/cargo.sh) updates every installed crate
      # when cargo-update is available; otherwise say what to install.
      if has_cmd cargo-install-update || [ -x "${CARGO_HOME:-$SU_USER_HOME/.cargo}/bin/cargo-install-update" ]; then
        step_skip "installed with cargo; updated by the cargo step (cargo install-update -a)"
      else
        step_skip "installed with cargo; install cargo-update so the cargo step can update it (or run cargo install $name)"
      fi
      return 0 ;;
    brew) step_skip "installed with Homebrew; updated by the brew step (brew upgrade)"; return 0 ;;
    *) how="self-update" ;;
  esac
  log_info "update method: $how"

  if [ "$SU_DRY_RUN" = 1 ]; then
    if tool_pkg_update; then
      step_dry "would update via $how${before:+ (installed $before)}"
    elif [ ${#cmd[@]} -gt 0 ]; then
      log_dry "would run: ${cmd[*]}"
      step_dry "would run '${cmd[*]}'${before:+ (installed $before)}"
    else
      step_skip "no known update method"
    fi
    return 0
  fi

  rc=0
  tool_pkg_update || rc=$?
  if [ "$rc" -eq 2 ]; then
    if [ ${#cmd[@]} -eq 0 ]; then
      step_skip "no known update method"
      return 0
    fi
    rc=0
    do_user "${cmd[@]}" || rc=$?
  fi
  if [ "$rc" -ne 0 ]; then
    step_fail "update command failed ($(rc_note "$rc"))"
    return 0
  fi
  if [ ${#probe[@]} -gt 0 ]; then
    after=$(version_from_text "$(tool_probe "$bin" "${probe[@]}")")
  fi
  if [ -n "$before" ] && [ -n "$after" ] && [ "$before" != "$after" ]; then
    step_updated "$before -> $after"
  elif [ -n "$after" ]; then
    step_ok "up to date ($after)"
  else
    step_ok "update command succeeded"
  fi
}

# tool_opt_in KEY FLAG: for steps that are off by default. Returns 0 when
# the user turned the step on; otherwise records a skip that says how.
tool_opt_in() {
  local key="$1" flag="$2"
  cfg_bool "$key" && return 0
  step_skip "off by default; enable with $flag or $key=1"
  return 1
}

# tool_github_binary_update NAME REPO ASSET DEST INSTALLED: the standalone
# binary pattern (cloudflared, bicep, ...): compare INSTALLED with the
# latest GitHub release, download ASSET, verify it against the sha256 the
# project publishes (gh_release_checksum) and `install -m 0755` it over
# DEST, as the user when DEST is theirs and as root otherwise. Nothing is
# installed when no checksum is published or it does not match.
tool_github_binary_update() {
  local name="$1" repo="$2" asset="$3" dest="$4" installed="$5"
  local latest tmp sum url real dir
  [ -n "$installed" ] || { step_skip "could not read the installed version of $name"; return 0; }
  latest=$(gh_latest_tag "$repo") || { step_skip "latest release unknown (GitHub API unavailable)"; return 0; }
  log_info "installed version: $installed; latest release: $latest"
  if ! version_lt "$installed" "$latest"; then
    step_ok "up to date ($installed)"
    return 0
  fi
  if [ "$SU_DRY_RUN" = 1 ]; then
    step_dry "would download $asset $latest, verify its sha256 and install it to $dest ($installed -> $(version_norm "$latest"))"
    return 0
  fi
  if ! sum=$(gh_release_checksum "$repo" "$latest" "$asset"); then
    step_skip "no sha256 published for $asset $latest; refusing to install an unverified binary"
    return 0
  fi
  tmp=$(tmp_dir) || return 1
  url=$(gh_release_asset_url "$repo" "$latest" "$asset")
  download "$url" "$tmp/$asset" || { step_fail "download failed"; return 0; }
  verify_sha256 "$tmp/$asset" "$sum" || { step_fail "checksum verification failed; $dest left untouched"; return 0; }
  real=$(readlink -f -- "$dest" 2>/dev/null || printf '%s' "$dest")
  dir=$(dirname "$real")
  # As the invoking user with write access (a binary in ~/.local/bin):
  # install directly. Otherwise as root; when we are root acting for
  # SUDO_USER the system binary is ours to replace, not the user's.
  if user_is_current && [ -w "$dir" ] && { [ ! -e "$real" ] || [ -w "$real" ]; }; then
    do_user install -m 0755 "$tmp/$asset" "$real" || { step_fail "install failed"; return 0; }
  else
    install_bin "$tmp/$asset" "$real" || { step_fail "install failed"; return 0; }
  fi
  step_updated "$installed -> $(version_norm "$latest")"
}

# phar_update NAME BIN CMD...: update a PHP phar (composer, wp, terminus)
# that may live in a root-owned /usr/local/bin. Writable by us -> run as the
# user; owned by a distro package -> skip; otherwise run as root (sudo).
# Returns the command's status, or 3 when the update was skipped (STEP_NOTE
# then holds the reason).
phar_update() {
  local name="$1" bin="$2"; shift 2
  local real owner
  real=$(readlink -f -- "$bin" 2>/dev/null || printf '%s' "$bin")
  if owner=$(distro_pkg_owner "$real"); then
    step_skip "$bin belongs to $SU_PKG package '$owner' (updated with the system packages)"
    return 3
  fi
  if [ -w "$real" ]; then
    do_user "$@"
  elif sudo_available; then
    log_info "$real is not writable by $SU_USER; running the update as root"
    do_root env COMPOSER_ALLOW_SUPERUSER=1 "$@"
  else
    step_skip "$real is not writable and sudo is unavailable"
    return 3
  fi
}

# tools_run_all SCOPE_FILTER: run the update step of every discovered tool
# whose scope matches (user|system|all).
tools_run_all() {
  local filter="$1" name scope fn
  for name in "${SU_TOOLS[@]-}"; do
    [ -n "$name" ] || continue
    scope=$(tool_scope "$name")
    if [ "$filter" != all ] && [ "$scope" != "$filter" ]; then
      continue
    fi
    fn=$(tool_fn "$name" update)
    declare -F "$fn" >/dev/null || continue
    run_step tools "$name" "$fn"
  done
}
