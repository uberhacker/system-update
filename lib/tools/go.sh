#!/usr/bin/env bash
# lib/tools/go.sh - the Go toolchain in /usr/local/go (opt-in: GO_TOOLCHAIN=1 / --go-toolchain).
#
# Only when /usr/local/go already exists and no distro package owns it. The
# latest stable release and its sha256 come from go.dev/dl/?mode=json; the
# archive is verified, unpacked next to /usr/local/go and swapped in with two
# renames, so a failure leaves the old toolchain in place.
#
# Test hooks: SU_GO_ROOT (default /usr/local/go), SU_GO_DL_JSON (the JSON
# URL) and SU_GO_DL_BASE (where <filename> is downloaded from).

: "${SU_GO_ROOT:=/usr/local/go}"
: "${SU_GO_DL_JSON:=https://go.dev/dl/?mode=json}"
: "${SU_GO_DL_BASE:=https://go.dev/dl}"

tool_go_detect() {
  [ -x "$SU_GO_ROOT/bin/go" ] || return 1
  printf '%s\n' "$SU_GO_ROOT/bin/go"
}
tool_go_scope() { echo system; }

# go_latest_info JSONFILE ARCH: prints "VERSION SHA256 FILENAME" for the
# newest stable linux/ARCH archive.
go_latest_info() {
  local file="$1" arch="$2" line
  if json_has_jq; then
    jq -r --arg a "$arch" '[.[] | select(.stable == true)][0] | .files[] | select(.os == "linux" and .arch == $a and .kind == "archive") | "\(.version) \(.sha256) \(.filename)"' "$file" 2>/dev/null | head -n1 | grep .
    return
  fi
  # Fallback: the file objects list filename, os, arch, version, sha256 in
  # that order; the first match belongs to the newest release.
  line=$(tr -d ' \n\r\t' < "$file" | grep -o -E "\"filename\":\"go[0-9.]+\.linux-${arch}\.tar\.gz\",\"os\":\"linux\",\"arch\":\"${arch}\",\"version\":\"go[0-9.]+\",\"sha256\":\"[0-9a-f]{64}\"" | head -n1)
  [ -n "$line" ] || return 1
  [[ "$line" =~ \"filename\":\"([^\"]+)\".*\"version\":\"([^\"]+)\".*\"sha256\":\"([0-9a-f]{64})\" ]] || return 1
  printf '%s %s %s\n' "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" "${BASH_REMATCH[1]}"
}

# go_priv CMD...: as root unless the parent of SU_GO_ROOT is ours to write.
go_priv() {
  if [ -w "$(dirname "$SU_GO_ROOT")" ]; then do_user "$@"; else do_root "$@"; fi
}

tool_go_update() {
  local gobin="${SU_TOOL_BIN[go]}" owner installed arch json info latest sum filename tmp stage old parent
  tool_opt_in GO_TOOLCHAIN --go-toolchain || return 0
  if owner=$(distro_pkg_owner "$gobin"); then
    step_skip "$SU_GO_ROOT belongs to $SU_PKG package '$owner' (updated with the system packages)"
    return 0
  fi
  installed=$(tool_probe "$gobin" version | grep -o -E 'go[0-9]+(\.[0-9]+)+' | head -n1)
  [ -n "$installed" ] || { step_skip "could not read the installed version ($gobin version)"; return 0; }
  arch=$(arch_name go)
  [ "$arch" != unknown ] || { step_skip "unsupported architecture $(uname -m)"; return 0; }
  log_info "installed: $installed ($SU_GO_ROOT)"

  tmp=$(tmp_dir) || return 1
  json="$tmp/go-dl.json"
  download "$SU_GO_DL_JSON" "$json" || { step_fail "could not fetch the Go release list"; return 0; }
  info=$(go_latest_info "$json" "$arch") || { step_fail "no linux/$arch archive in the Go release list"; return 0; }
  read -r latest sum filename <<< "$info"
  log_info "latest stable: $latest"
  if ! version_lt "${installed#go}" "${latest#go}"; then
    step_ok "up to date ($installed)"
    return 0
  fi
  if [ "$SU_DRY_RUN" = 1 ]; then
    step_dry "would download $filename, verify its sha256 and replace $SU_GO_ROOT ($installed -> $latest)"
    return 0
  fi

  download "$SU_GO_DL_BASE/$filename" "$tmp/$filename" || { step_fail "download failed"; return 0; }
  verify_sha256 "$tmp/$filename" "$sum" || { step_fail "checksum verification failed; $SU_GO_ROOT left untouched"; return 0; }
  parent=$(dirname "$SU_GO_ROOT")
  stage="$parent/.go-update.$$"
  old="$parent/.go-old.$$"
  go_priv mkdir -p "$stage" || { step_fail "could not create $stage"; return 0; }
  if ! go_priv tar -C "$stage" -xzf "$tmp/$filename" || ! go_priv test -x "$stage/go/bin/go"; then
    go_priv rm -rf -- "$stage"
    step_fail "could not unpack $filename; $SU_GO_ROOT left untouched"
    return 0
  fi
  if ! go_priv mv -- "$SU_GO_ROOT" "$old"; then
    go_priv rm -rf -- "$stage"
    step_fail "could not move $SU_GO_ROOT aside"
    return 0
  fi
  if ! go_priv mv -- "$stage/go" "$SU_GO_ROOT"; then
    go_priv mv -- "$old" "$SU_GO_ROOT"
    go_priv rm -rf -- "$stage"
    step_fail "could not move the new toolchain into place; old one restored"
    return 0
  fi
  if ! tool_probe "$gobin" version | grep -q "$latest"; then
    go_priv rm -rf -- "$SU_GO_ROOT"
    go_priv mv -- "$old" "$SU_GO_ROOT"
    go_priv rm -rf -- "$stage"
    step_fail "new toolchain does not report $latest; old one restored"
    return 0
  fi
  go_priv rm -rf -- "$old" "$stage"
  step_updated "$installed -> $latest"
}
