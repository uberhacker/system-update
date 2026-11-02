#!/usr/bin/env bash
# lib/core/util.sh - shared helpers: privilege handling, command runners,
# temp files, downloads with checksum verification, version comparison.

: "${SU_DRY_RUN:=0}"
: "${SU_DETAILED:=0}"         # --detailed: dry run that lists versions
: "${SU_TIMEOUT:=300}"        # seconds for each third-party command
: "${SU_PROBE_TIMEOUT:=20}"   # seconds for a "--version" style probe
: "${SU_PKG_TIMEOUT:=3600}"   # seconds for a package manager run

SU_TMP_PATHS=()

has_cmd() { command -v "$1" >/dev/null 2>&1; }

is_root() { [ "$(id -u)" -eq 0 ]; }

# ---------------------------------------------------------------------------
# Invoking user
# ---------------------------------------------------------------------------
# SU_USER / SU_USER_HOME describe the person the user-level tools belong to.
# When root got here through sudo that is SUDO_USER, otherwise the current user.
user_init() {
  SU_UID=$(id -u)
  SU_CUR_USER=$(id -un)
  SU_USER="$SU_CUR_USER"
  SU_USER_HOME="$HOME"
  SU_USER_VIA_SUDO=0
  if is_root && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    if getent passwd "$SUDO_USER" >/dev/null 2>&1; then
      SU_USER="$SUDO_USER"
      SU_USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
      SU_USER_VIA_SUDO=1
    fi
  fi
  export SU_USER SU_USER_HOME
}

# Is the invoking user the one we are running as right now?
user_is_current() { [ "$SU_USER" = "$SU_CUR_USER" ]; }

# ---------------------------------------------------------------------------
# sudo handling
# ---------------------------------------------------------------------------
SU_SUDO_OK=""   # "" unknown, 1 ok, 0 unavailable

# sudo_available: can we become root (we are root, or sudo exists)?
sudo_available() {
  is_root && return 0
  has_cmd sudo
}

# sudo_prime: validate sudo credentials once up front so later steps do not
# prompt in the middle of a long run. Returns 1 if sudo cannot be used.
sudo_prime() {
  if is_root; then SU_SUDO_OK=1; return 0; fi
  if ! has_cmd sudo; then
    SU_SUDO_OK=0
    return 1
  fi
  if [ -n "$SU_SUDO_OK" ]; then
    [ "$SU_SUDO_OK" = 1 ]
    return
  fi
  # A NOPASSWD rule or cached credentials: no prompt needed. Plain "sudo -v"
  # is not enough here because, with the default verifypw=all, it asks for a
  # password whenever any matching entry needs one (openSUSE ships
  # "ALL ALL=(ALL) ALL" next to the user's NOPASSWD rule).
  if sudo -n true 2>/dev/null; then
    SU_SUDO_OK=1
    return 0
  fi
  log_info "sudo is required for system packages; validating credentials"
  if sudo -v; then
    SU_SUDO_OK=1
    return 0
  fi
  SU_SUDO_OK=0
  return 1
}

# sudo_usable: can we become root right now without a prompt? True when we
# are root, when sudo_prime validated credentials, or when sudo -n works
# (NOPASSWD or a cached timestamp). The probe runs once per process.
SU_SUDO_NOPROMPT=""
sudo_usable() {
  is_root && return 0
  [ "${SU_SUDO_OK:-}" = 1 ] && return 0
  [ "${SU_SUDO_OK:-}" = 0 ] && return 1
  if [ -z "$SU_SUDO_NOPROMPT" ]; then
    if has_cmd sudo && sudo -n true 2>/dev/null; then SU_SUDO_NOPROMPT=1; else SU_SUDO_NOPROMPT=0; fi
  fi
  [ "$SU_SUDO_NOPROMPT" = 1 ]
}

# root_prefix: prints the words needed to run something as root, if any.
# Usage: "$(root_prefix)" cmd ...  -- but prefer run_root below.
root_prefix() {
  if is_root; then return 0; fi
  # -n: never prompt from inside a step; credentials are primed up front.
  printf 'sudo -n '
}

# ---------------------------------------------------------------------------
# Command runners
# ---------------------------------------------------------------------------
# All runners: stdin from /dev/null, wrapped in timeout, logged in verbose mode.
#   run_root   cmd...   run as root (sudo -n when needed). Always runs.
#   run_user   cmd...   run as the invoking user. Always runs.
#   do_root    cmd...   like run_root, but only reports in dry-run mode.
#   do_user    cmd...   like run_user, but only reports in dry-run mode.
#   run_root_opt cmd... as root when that needs no prompt, else as ourselves:
#                       for commands that work either way (apt-get -s,
#                       dnf check-upgrade), so a dry run does not fail for a
#                       user without sudo rights.
# Env: SU_RUN_TIMEOUT overrides the timeout for one call.
# With a run log open, each command's output also goes to the log, followed
# by its exit status and duration.

_timeout_cmd() {
  local secs="${SU_RUN_TIMEOUT:-$SU_TIMEOUT}"
  if has_cmd timeout && [ "$secs" != 0 ]; then
    printf 'timeout -k 10 %s' "$secs"
  fi
}

# _run_logged CMD...: run CMD; with a run log open, copy its stdout and
# stderr there as well and record how it ended. Output still reaches the
# caller unchanged, so $(run_user ...) captures work as before. Commands then
# write to a pipe rather than the terminal, so TTY-only progress bars are not
# shown. (stderr is copied asynchronously and may land a line late.)
_run_logged() {
  [ -n "${SU_LOG_FILE:-}" ] || { "$@"; return; }
  local rc start=$SECONDS log="$SU_LOG_FILE"
  { "$@" 2> >(tee -a "$log" >&2); } | tee -a "$log"
  rc=${PIPESTATUS[0]}
  printf '%(%H:%M:%S)T   -> exit %s after %ss\n' -1 "$rc" "$((SECONDS - start))" >> "$log"
  return "$rc"
}

run_root() {
  local tmo
  tmo=$(_timeout_cmd)
  if is_root; then
    log_cmd "$*"
    # shellcheck disable=SC2086
    _run_logged $tmo "$@" </dev/null
  else
    if ! has_cmd sudo; then
      log_error "sudo is not installed and we are not root; cannot run: $*"
      return 126
    fi
    log_cmd "sudo $*"
    # shellcheck disable=SC2086
    _run_logged $tmo sudo -n "$@" </dev/null
  fi
}

run_user() {
  local tmo
  tmo=$(_timeout_cmd)
  if user_is_current; then
    log_cmd "$*"
    # shellcheck disable=SC2086
    _run_logged $tmo "$@" </dev/null
  else
    log_cmd "(as $SU_USER) $*"
    if has_cmd runuser; then
      # shellcheck disable=SC2086
      _run_logged $tmo runuser -u "$SU_USER" -- "$@" </dev/null
    else
      # shellcheck disable=SC2086
      _run_logged $tmo sudo -n -u "$SU_USER" -H -- "$@" </dev/null
    fi
  fi
}

run_root_opt() {
  if sudo_usable; then
    run_root "$@"
  else
    log_detail "no sudo credentials; running as $SU_CUR_USER: $*"
    run_user "$@"
  fi
}

do_root() {
  if [ "$SU_DRY_RUN" = 1 ]; then
    log_dry "would run (root): $*"
    return 0
  fi
  run_root "$@"
}

do_user() {
  if [ "$SU_DRY_RUN" = 1 ]; then
    log_dry "would run: $*"
    return 0
  fi
  run_user "$@"
}

# rc_note rc: turns an exit code into a short human note.
rc_note() {
  case "$1" in
    124|137) printf 'timed out after %ss' "${SU_RUN_TIMEOUT:-$SU_TIMEOUT}" ;;
    126) printf 'could not execute' ;;
    *) printf 'exit code %s' "$1" ;;
  esac
}

# ---------------------------------------------------------------------------
# Temp files
# ---------------------------------------------------------------------------
tmp_cleanup() {
  local p
  for p in "${SU_TMP_PATHS[@]-}"; do
    [ -n "$p" ] && rm -rf -- "$p"
  done
  SU_TMP_PATHS=()
}
# The test harness owns the EXIT trap and calls tmp_cleanup itself.
if [ "${SU_SKIP_EXIT_TRAP:-0}" != 1 ]; then
  trap tmp_cleanup EXIT
fi

# tmp_dir: prints a fresh temp dir that is removed at exit.
tmp_dir() {
  local d
  d=$(mktemp -d "${TMPDIR:-/tmp}/system-update.XXXXXX") || return 1
  SU_TMP_PATHS+=("$d")
  printf '%s\n' "$d"
}

# tmp_file: prints a fresh temp file that is removed at exit.
tmp_file() {
  local f
  f=$(mktemp "${TMPDIR:-/tmp}/system-update.XXXXXX") || return 1
  SU_TMP_PATHS+=("$f")
  printf '%s\n' "$f"
}

# ---------------------------------------------------------------------------
# Downloads
# ---------------------------------------------------------------------------
# download URL DEST: fetch over https with curl -f into DEST (a temp path).
download() {
  local url="$1" dest="$2"
  case "$url" in
    https://*) ;;
    file:///*) [ "${SYSTEM_UPDATE_ALLOW_FILE_SOURCE:-0}" = 1 ] || { log_error "refusing non-https download: $url"; return 1; } ;;
    *) log_error "refusing non-https download: $url"; return 1 ;;
  esac
  has_cmd curl || { log_error "curl is not installed; cannot download $url"; return 1; }
  log_cmd "curl -fsSL $url"
  # --proto-redir: a redirect may not downgrade to http (file: is the test hook).
  if ! curl -fsSL --proto '=https,file' --proto-redir '=https' \
      --retry 2 --connect-timeout 20 --max-time "${SU_TIMEOUT}" \
      -o "$dest" "$url" </dev/null; then
    log_error "download failed: $url"
    rm -f -- "$dest"
    return 1
  fi
  [ -s "$dest" ] || { log_error "download produced an empty file: $url"; return 1; }
  return 0
}

# sha256_of FILE: prints the hex digest.
sha256_of() {
  if has_cmd sha256sum; then
    sha256sum "$1" | cut -d' ' -f1
  elif has_cmd shasum; then
    shasum -a 256 "$1" | cut -d' ' -f1
  else
    return 1
  fi
}

# verify_sha256 FILE EXPECTED: compare digests; EXPECTED may be a bare hash or
# a line like "<hash>  filename".
verify_sha256() {
  local file="$1" expected="$2" actual
  expected=${expected%%[[:space:]]*}
  expected=${expected,,}
  if ! [[ "$expected" =~ ^[0-9a-f]{64}$ ]]; then
    log_error "no valid sha256 checksum available for $(basename "$file")"
    return 1
  fi
  actual=$(sha256_of "$file") || { log_error "no sha256 tool available"; return 1; }
  if [ "$actual" != "$expected" ]; then
    log_error "checksum mismatch for $(basename "$file"): expected $expected got $actual"
    return 1
  fi
  log_detail "checksum ok: $expected"
  return 0
}

# checksum_for CHECKSUMS_FILE NAME: extract the sha256 for NAME from a
# "sha256sum"-style checksums file (hash, whitespace, optional '*', name).
checksum_for() {
  local file="$1" name="$2" hash f _rest
  # `|| [ -n "$hash" ]`: a last line without a newline still counts.
  while read -r hash f _rest || [ -n "$hash" ]; do
    f=${f#\*}
    f=${f#./}
    if [ -n "$hash" ] && [ "$f" = "$name" ]; then
      printf '%s\n' "$hash"
      return 0
    fi
  done < "$file"
  return 1
}

# install_bin SRC DEST: install a verified file as root with mode 0755.
install_bin() {
  local src="$1" dest="$2"
  do_root install -m 0755 "$src" "$dest"
}

# ---------------------------------------------------------------------------
# Versions
# ---------------------------------------------------------------------------
# version_norm: strip a leading "v" and anything after the first space.
version_norm() {
  local v="${1#v}"
  v="${v#V}"
  printf '%s\n' "${v%% *}"
}

# version_lt A B: true when A sorts strictly before B (sort -V semantics).
version_lt() {
  local a b
  a=$(version_norm "$1"); b=$(version_norm "$2")
  [ "$a" = "$b" ] && return 1
  [ "$(printf '%s\n%s\n' "$a" "$b" | sort -V | head -n1)" = "$a" ]
}

# arch_name STYLE: map uname -m to a vendor's naming. STYLES: deb, rpm, go, compose
arch_name() {
  local m style="$1"
  m=$(uname -m)
  case "$style" in
    deb)
      case "$m" in
        x86_64|amd64) echo amd64 ;;
        aarch64|arm64) echo arm64 ;;
        armv7l|armv6l|armhf) echo armhf ;;
        *) echo unknown ;;
      esac ;;
    rpm)
      case "$m" in
        x86_64|amd64) echo x86_64 ;;
        aarch64|arm64) echo aarch64 ;;
        armv7l) echo armv7hl ;;
        *) echo unknown ;;
      esac ;;
    compose)
      case "$m" in
        x86_64|amd64) echo x86_64 ;;
        aarch64|arm64) echo aarch64 ;;
        armv7l|armv7) echo armv7 ;;
        armv6l|armv6) echo armv6 ;;
        ppc64le) echo ppc64le ;;
        riscv64) echo riscv64 ;;
        s390x) echo s390x ;;
        *) echo unknown ;;
      esac ;;
    go)
      # go.dev/dl file names: go1.x.linux-<arch>.tar.gz
      case "$m" in
        x86_64|amd64) echo amd64 ;;
        aarch64|arm64) echo arm64 ;;
        armv7l|armv6l) echo armv6l ;;
        i686|i386) echo 386 ;;
        ppc64le) echo ppc64le ;;
        s390x) echo s390x ;;
        riscv64) echo riscv64 ;;
        loongarch64) echo loong64 ;;
        *) echo unknown ;;
      esac ;;
    cloudflared)
      case "$m" in
        x86_64|amd64) echo amd64 ;;
        aarch64|arm64) echo arm64 ;;
        armv7l|armv6l|armhf) echo arm ;;
        i686|i386) echo 386 ;;
        *) echo unknown ;;
      esac ;;
    bicep)
      case "$m" in
        x86_64|amd64) echo x64 ;;
        aarch64|arm64) echo arm64 ;;
        *) echo unknown ;;
      esac ;;
    *) echo "$m" ;;
  esac
}

# ---------------------------------------------------------------------------
# Lists
# ---------------------------------------------------------------------------
# list_has LIST ITEM: LIST is comma/space separated.
list_has() {
  local list="$1" item="$2" x
  local IFS=', '
  for x in $list; do
    [ "$x" = "$item" ] && return 0
  done
  return 1
}

# join_by SEP items...
join_by() {
  local sep="$1"; shift
  local out="" x
  for x in "$@"; do
    if [ -z "$out" ]; then out="$x"; else out="$out$sep$x"; fi
  done
  printf '%s\n' "$out"
}

# bool VALUE: true for 1/yes/true/on (case-insensitive).
bool() {
  case "${1,,}" in
    1|yes|true|on|y) return 0 ;;
    *) return 1 ;;
  esac
}
