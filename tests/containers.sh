#!/usr/bin/env bash
# tests/containers.sh - run system-update inside stock distro containers.
#
# For each image the repository is mounted read-only at /src and
# tests/containers-inner.sh runs these phases:
#   list      --list reports the expected package manager
#   dry-run   --dry-run exits 0 and the installed package set is unchanged
#   real      --yes exits 0 and really upgraded packages (one installed
#             package is downgraded first where the repositories allow it)
#             and a second run reports nothing to do
#   nonroot   the same as an unprivileged user with sudo (dry run, real run,
#             and `sudo system-update` delegating user tools to SUDO_USER)
#   apt-partial  (apt only) an unreachable source is a warning, not ok/failed
#   compose   a stand-alone docker-compose is updated from the real GitHub
#             release: download, sha256 verified, install -m 0755, idempotent
#   kilo      a fake hanging `kilo` editor on PATH is skipped, not run, and a
#             fake Kilo Code is updated
#
# Usage: tests/containers.sh [--restricted] [--keep-going] [IMAGE...]
#   --restricted  for sandboxes whose containers can only reach the network
#                 through the host's HTTPS proxy: uses --network host, passes
#                 https_proxy and mounts the proxy CA bundle (CONTAINER_CA,
#                 default /root/.ccr/ca-bundle.crt) for the container to trust.
#   IMAGE...      default: the full matrix below.
# Logs go to tests/containers.out/<image>.log. Exit status is non-zero when
# any phase failed. Images that cannot be pulled are reported and skipped.

set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OUT="$ROOT/tests/containers.out"
RESTRICTED=0
KEEP_GOING=1
IMAGES=()
DEFAULT_IMAGES=(ubuntu:24.04 debian:stable fedora:latest rockylinux:9 archlinux:latest opensuse/tumbleweed opensuse/leap alpine:latest)
PULL_TIMEOUT="${PULL_TIMEOUT:-900}"
RUN_TIMEOUT="${RUN_TIMEOUT:-3600}"

while [ $# -gt 0 ]; do
  case "$1" in
    --restricted) RESTRICTED=1 ;;
    --keep-going) KEEP_GOING=1 ;;
    --fail-fast) KEEP_GOING=0 ;;
    -h|--help) sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) IMAGES+=("$1") ;;
  esac
  shift
done
[ ${#IMAGES[@]} -gt 0 ] || IMAGES=("${DEFAULT_IMAGES[@]}")

command -v docker >/dev/null 2>&1 || { echo "docker is required" >&2; exit 2; }
mkdir -p "$OUT"

net_args=()
if [ "$RESTRICTED" = 1 ]; then
  ca="${CONTAINER_CA:-/root/.ccr/ca-bundle.crt}"
  proxy="${HTTPS_PROXY:-${https_proxy:-}}"
  [ -n "$proxy" ] || { echo "--restricted needs HTTPS_PROXY in the environment" >&2; exit 2; }
  net_args=(--network host -e "https_proxy=$proxy" -e "HTTPS_PROXY=$proxy" -e "no_proxy=${no_proxy:-}")
  [ -r "$ca" ] && net_args+=(-v "$ca:/ca.crt:ro")
fi

overall=0
summary=()

# bootstrap IMAGE: shell snippet run before the inner script (alpine has no bash).
bootstrap() {
  case "$1" in
    alpine*) echo 'if ! command -v bash >/dev/null 2>&1; then [ -f /ca.crt ] && cp /ca.crt /etc/ssl/certs/ca-certificates.crt; apk add --no-cache bash >/dev/null 2>&1 || apk add bash; fi;' ;;
    *) echo ':;' ;;
  esac
}

for image in "${IMAGES[@]}"; do
  tag="${image//[^A-Za-z0-9._-]/_}"
  log="$OUT/$tag.log"
  echo "=== $image"
  if ! docker image inspect "$image" >/dev/null 2>&1; then
    if ! timeout "$PULL_TIMEOUT" docker pull -q "$image" >/dev/null 2>&1; then
      echo "    could not pull $image; skipped"
      summary+=("$image: PULL FAILED (skipped)")
      continue
    fi
  fi
  rc=0
  timeout "$RUN_TIMEOUT" docker run --rm "${net_args[@]}" \
    -v "$ROOT:/src:ro" \
    -e "PROBE_TIMEOUT=${PROBE_TIMEOUT:-5}" -e "TIMEOUT=${TIMEOUT:-600}" \
    -e "GITHUB_TOKEN=${GITHUB_TOKEN:-${GH_TOKEN:-}}" \
    -e "SU_TEST_PHASES=${SU_TEST_PHASES:-}" \
    "$image" sh -c "$(bootstrap "$image") exec bash /src/tests/containers-inner.sh" > "$log" 2>&1 || rc=$?
  results=$(grep -E '^RESULT ' "$log" || true)
  if [ -z "$results" ]; then
    echo "    no results (exit $rc); see $log"
    tail -n 20 "$log" | sed 's/^/    | /'
    summary+=("$image: NO RESULTS (exit $rc)")
    overall=1
    [ "$KEEP_GOING" = 1 ] || break
    continue
  fi
  fails=0
  while read -r _ phase status note; do
    echo "    $phase $status $note"
    [ "$status" = fail ] && fails=$((fails + 1))
  done <<< "$results"
  if [ "$fails" -gt 0 ] || [ "$rc" -ne 0 ]; then
    summary+=("$image: $fails phase(s) FAILED (exit $rc)")
    overall=1
    [ "$KEEP_GOING" = 1 ] || break
  else
    summary+=("$image: all phases passed")
  fi
done

echo
echo "Container test summary:"
printf '  %s\n' "${summary[@]}"
exit "$overall"
