#!/usr/bin/env bash
# tests/containers-inner.sh - runs inside a distro container (see containers.sh).
# Prints "RESULT <phase> <pass|fail|skip> <note>" lines that the driver parses.
# Env: SU_TEST_PHASES (comma list to restrict phases), PROBE_TIMEOUT, TIMEOUT.
# shellcheck disable=SC2016  # fake tool scripts are written with literal $1/$HOME

set -u
SRC=/src
SU="$SRC/system-update"
export NO_COLOR=1
export LANG=C.UTF-8

result() { printf 'RESULT %s %s %s\n' "$1" "$2" "${3:-}"; }
phase_enabled() { [ -z "${SU_TEST_PHASES:-}" ] || [[ ",$SU_TEST_PHASES," == *",$1,"* ]]; }
section() { printf '\n##### %s #####\n' "$*"; }

# Trust the sandbox proxy CA when the driver mounted one (again after a
# package install, which may regenerate the system bundle).
trust_proxy_ca() {
  [ -f /ca.crt ] || return 0
  local f
  for f in /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt /etc/ssl/ca-bundle.pem /etc/ssl/cert.pem; do
    [ -e "$f" ] && cp /ca.crt "$(readlink -f "$f")" 2>/dev/null
  done
  return 0
}
trust_proxy_ca

ID=""; ID_LIKE=""
# shellcheck disable=SC1091
. /etc/os-release 2>/dev/null
case "$ID $ID_LIKE" in
  debian*|ubuntu*|*" debian"*|*" ubuntu"*) FAM=apt ;;
  fedora*|rhel*|centos*|rocky*|almalinux*|*fedora*|*rhel*) FAM=dnf ;;
  arch*|*" arch"*) FAM=pacman ;;
  opensuse*|sles*|*suse*) FAM=zypper ;;
  alpine*) FAM=apk ;;
  *) FAM=unknown ;;
esac
echo "container: ${PRETTY_NAME:-?} (ID=$ID ID_LIKE=$ID_LIKE) expected manager: $FAM"

# changed_entries BEFORE AFTER: package entries present in only one snapshot
# (diffutils is not in every image, so sort/uniq from coreutils is used).
changed_entries() {
  printf '%s\n%s\n' "$1" "$2" | sort | uniq -u
}

snapshot() {
  case "$FAM" in
    apt) dpkg-query -W -f '${Package} ${Version}\n' 2>/dev/null | sort ;;
    dnf|zypper) rpm -qa 2>/dev/null | sort ;;
    pacman) pacman -Q 2>/dev/null | sort ;;
    apk) apk info -v 2>/dev/null | sort ;;
    *) echo none ;;
  esac
}

# install_pkgs PKG...: with the distro's manager (for sudo/shadow in the nonroot phase).
install_pkgs() {
  case "$FAM" in
    apt) apt-get update -q >/dev/null 2>&1; DEBIAN_FRONTEND=noninteractive apt-get install -y -q "$@" ;;
    dnf) (command -v dnf5 >/dev/null && dnf5 -y install "$@") || dnf -y install "$@" || yum -y install "$@" ;;
    pacman) pacman -S --noconfirm --needed "$@" ;;
    zypper) zypper --non-interactive install "$@" ;;
    apk) apk add "$@" ;;
    *) return 1 ;;
  esac
}

ensure_user() {
  id tester >/dev/null 2>&1 && return 0
  if command -v useradd >/dev/null 2>&1; then
    useradd -m -s /bin/bash tester
  elif command -v adduser >/dev/null 2>&1; then
    adduser -D -s /bin/bash tester
  else
    install_pkgs shadow >/dev/null 2>&1 && useradd -m -s /bin/bash tester
  fi
  id tester >/dev/null 2>&1
}

ensure_sudo() {
  command -v sudo >/dev/null 2>&1 && return 0
  install_pkgs sudo >/dev/null 2>&1
  command -v sudo >/dev/null 2>&1
}

run_as_tester() {
  if command -v runuser >/dev/null 2>&1; then
    runuser -u tester -- "$@"
  elif command -v su >/dev/null 2>&1; then
    su tester -s /bin/bash -c "$(printf '%q ' "$@")"
  else
    sudo -n -u tester -H -- "$@"
  fi
}

# summary_line GROUP OUTPUT: the summary row for a step ("ok apt no updates").
summary_line() {
  grep -E "^ +[^ ]+ +(ok|updated|skipped|failed|dry-run|warn) +$1 " <<< "$2" | head -n1 | sed 's/^ *[^ ]* *//'
}

# stage_upgrade: images are often already current, which would leave the real
# run with nothing to do. Downgrade one harmless installed package to an older
# version the repositories still carry so the upgrade path is really taken.
# Best effort: apt and dnf only; prints what it did.
stage_upgrade() {
  local pkg ver cur
  case "$FAM" in
    apt)
      apt-get update -q >/dev/null 2>&1
      for pkg in tar gzip grep sed bash coreutils tzdata; do
        dpkg-query -W -f '${db:Status-Status}' "$pkg" 2>/dev/null | grep -qx installed || continue
        cur=$(dpkg-query -W -f '${Version}' "$pkg" 2>/dev/null) || continue
        ver=$(apt-cache madison "$pkg" 2>/dev/null | cut -d'|' -f2 | tr -d ' ' | sort -u | sort -V | head -n1)
        { [ -n "$ver" ] && [ "$ver" != "$cur" ]; } || continue
        if DEBIAN_FRONTEND=noninteractive apt-get install -y -q --allow-downgrades "$pkg=$ver" >/dev/null 2>&1; then
          echo "staged: $pkg downgraded $cur -> $ver"
          return 0
        fi
      done ;;
    dnf)
      for pkg in bash tzdata curl less gzip coreutils; do
        cur=$(rpm -q "$pkg" 2>/dev/null) || continue
        if command -v dnf5 >/dev/null 2>&1; then
          dnf5 -y downgrade "$pkg" >/dev/null 2>&1
        else
          dnf -y downgrade "$pkg" >/dev/null 2>&1 || yum -y downgrade "$pkg" >/dev/null 2>&1
        fi
        if [ "$(rpm -q "$pkg" 2>/dev/null)" != "$cur" ]; then
          echo "staged: $pkg downgraded from $cur"
          return 0
        fi
      done ;;
  esac
  echo "staged: nothing (relying on the image being behind its repositories)"
  return 1
}

# ---------------------------------------------------------------- list
if phase_enabled list; then
  section "--list"
  out=$("$SU" --list 2>&1); rc=$?
  printf '%s\n' "$out"
  if [ "$rc" -eq 0 ] && grep -q "Package manager: $FAM" <<< "$out"; then
    result list pass "manager=$FAM"
  else
    result list fail "exit $rc"
  fi
fi

# ---------------------------------------------------------------- dry-run
if phase_enabled dry-run; then
  section "--dry-run"
  before=$(snapshot)
  out=$("$SU" --dry-run 2>&1); rc=$?
  printf '%s\n' "$out"
  after=$(snapshot)
  if [ "$before" != "$after" ]; then
    changed_entries "$before" "$after" | head -n 20
    result dry-run fail "package set changed during the dry run"
  elif [ "$rc" -ne 0 ]; then
    result dry-run fail "exit $rc"
  elif ! grep -q 'Summary (dry run)' <<< "$out"; then
    result dry-run fail "no dry-run summary"
  else
    result dry-run pass "$(grep -E '^  [0-9]+ ok, ' <<< "$out" | tail -n1 | sed 's/^ *//')"
  fi
fi

# ---------------------------------------------------------------- bundle
# The single-file build, made inside the container (git is not needed), must
# detect the same things and plan the same dry run as the multi-file tree.
if phase_enabled bundle; then
  section "single-file build"
  bundle=/tmp/system-update-bundle
  if ! out=$("$SRC/build.sh" "$bundle" 2>&1); then
    printf '%s\n' "$out"
    result bundle fail "build.sh failed"
  else
    printf '%s\n' "$out"
    a=$("$SU" --list --no-color --no-log 2>&1 | tail -n +2)
    b=$("$bundle" --list --no-color --no-log 2>&1 | tail -n +2)
    da=$("$SU" --dry-run --no-color --no-log 2>&1 | sed -n '/^Summary/,$p')
    db=$("$bundle" --dry-run --no-color --no-log 2>&1 | sed -n '/^Summary/,$p')
    if [ "$a" != "$b" ]; then
      diff <(printf '%s\n' "$a") <(printf '%s\n' "$b") 2>/dev/null || printf 'multi:\n%s\nbundle:\n%s\n' "$a" "$b"
      result bundle fail "--list differs"
    elif [ "$da" != "$db" ]; then
      printf 'multi:\n%s\nbundle:\n%s\n' "$da" "$db"
      result bundle fail "dry-run summary differs"
    else
      result bundle pass "$("$bundle" --version)"
    fi
  fi
fi

# ---------------------------------------------------------------- detailed
# --detailed lists each pending package with its versions. With a staged
# downgrade (apt, dnf) that package must show up as a row of the table.
if phase_enabled detailed; then
  section "--detailed"
  staged_pkg=""
  if staged=$(stage_upgrade); then
    read -r _ staged_pkg _ <<< "$staged"
  fi
  echo "$staged"
  before=$(snapshot)
  out=$("$SU" --detailed --only system 2>&1); rc=$?
  printf '%s\n' "$out"
  after=$(snapshot)
  if [ "$before" != "$after" ]; then
    result detailed fail "package set changed during the detailed dry run"
  elif [ "$rc" -ne 0 ]; then
    result detailed fail "exit $rc"
  elif [ -n "$staged_pkg" ] && ! grep -qE "^ {6}${staged_pkg}(\.[a-z0-9_]+)? +[^ ]+ +-> " <<< "$out"; then
    result detailed fail "staged $staged_pkg is not in the change list"
  else
    result detailed pass "$(grep -E 'would change:' <<< "$out" | head -n1 | sed 's/^ *[^ ]* //')"
  fi
fi

# ---------------------------------------------------------------- real run
if phase_enabled real; then
  section "--yes (real run)"
  staged=0
  stage_upgrade && staged=1
  before=$(snapshot)
  out=$("$SU" --yes 2>&1); rc=$?
  printf '%s\n' "$out"
  after=$(snapshot)
  changed=$(changed_entries "$before" "$after" | grep -c . || true)
  sysline=$(summary_line "$FAM" "$out")
  if [ "$rc" -ne 0 ]; then
    result real fail "exit $rc; $sysline"
  elif [ "$changed" -gt 0 ]; then
    if grep -qE "updated +$FAM " <<< "$out"; then
      result real pass "$changed package entries changed; $sysline"
    else
      result real fail "packages changed but the summary did not say updated: $sysline"
    fi
  elif [ "$staged" = 1 ]; then
    result real fail "a downgraded package was not upgraded: $sysline"
  elif grep -qiE "$FAM .*no updates available" <<< "$out"; then
    result real pass "image already current; $sysline"
  else
    result real fail "nothing changed and no 'no updates' note: $sysline"
  fi
  section "--yes again (idempotent)"
  out=$("$SU" --yes 2>&1); rc=$?
  printf '%s\n' "$out" | tail -n 15
  if [ "$rc" -eq 0 ] && grep -qiE "$FAM .*no updates available" <<< "$out"; then
    result real-again pass "second run reports no updates"
  else
    result real-again fail "exit $rc"
  fi
fi

# ---------------------------------------------------------------- non-root
if phase_enabled nonroot; then
  section "non-root user with sudo"
  if ensure_sudo && ensure_user; then
    echo 'tester ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/tester
    chmod 0440 /etc/sudoers.d/tester
    before=$(snapshot)
    out=$(run_as_tester "$SU" --dry-run 2>&1); rc=$?
    printf '%s\n' "$out"
    after=$(snapshot)
    if [ "$rc" -eq 0 ] && [ "$before" = "$after" ] && grep -q 'Summary (dry run)' <<< "$out"; then
      result nonroot-dry pass "sudo dry run ok"
    else
      result nonroot-dry fail "exit $rc"
    fi
    out=$(run_as_tester "$SU" --yes 2>&1); rc=$?
    printf '%s\n' "$out" | tail -n 25
    if [ "$rc" -eq 0 ] && grep -qE "(ok|updated) +$FAM " <<< "$out"; then
      result nonroot-real pass "sudo real run ok: $(summary_line "$FAM" "$out")"
    else
      result nonroot-real fail "exit $rc: $(summary_line "$FAM" "$out")"
    fi
    # Root via sudo: user-level tools must run as SUDO_USER in a child.
    mkdir -p /home/tester/.local/bin
    printf '#!/usr/bin/env bash\ncase "$1" in --version) echo 1.2.3;; upgrade) echo "upgraded as $(id -un)" >&2;; esac\n' > /home/tester/.local/bin/kilo
    chmod 0755 /home/tester/.local/bin/kilo
    chown -R tester /home/tester/.local
    printf 'export PATH="$HOME/.local/bin:$PATH"\n' >> /home/tester/.profile
    printf 'export PATH="$HOME/.local/bin:$PATH"\n' >> /home/tester/.bash_profile
    chown tester /home/tester/.profile /home/tester/.bash_profile
    # Fake rustup, gh (with one extension) and brew: they must run as tester
    # too, and a dry run must not touch them. Each writes a marker when it
    # is asked to change something.
    cat > /home/tester/.local/bin/rustup <<'EOF'
#!/usr/bin/env bash
case "$1" in
  --version) echo "rustup 1.27.1 (2024-10-01)" ;;
  check) echo "stable-x86_64-unknown-linux-gnu - Up to date : 1.82.0" ;;
  self) echo "rustup self update as $(id -un)"; touch "$HOME/.rustup-touched" ;;
  update) echo "  stable-x86_64-unknown-linux-gnu unchanged - rustc 1.82.0"; touch "$HOME/.rustup-touched" ;;
esac
EOF
    cat > /home/tester/.local/bin/gh <<'EOF'
#!/usr/bin/env bash
case "$*" in
  'extension list') printf 'gh foo\towner/gh-foo\tv1.0.0\n' ;;
  'extension upgrade --all --dry-run') echo "[foo]: would have upgraded from v1.0.0 to v1.0.1" ;;
  'extension upgrade --all') echo "[foo]: upgraded from v1.0.0 to v1.0.1 as $(id -un)"; touch "$HOME/.gh-touched" ;;
esac
EOF
    cat > /home/tester/.local/bin/brew <<'EOF'
#!/usr/bin/env bash
case "$1" in
  update) echo "Already up-to-date." ;;
  outdated) echo foo ;;
  upgrade) echo "brew upgrade as $(id -un)"; touch "$HOME/.brew-touched" ;;
  autoremove) ;;
esac
EOF
    chmod 0755 /home/tester/.local/bin/rustup /home/tester/.local/bin/gh /home/tester/.local/bin/brew
    mkdir -p /home/tester/.local/share/gh/extensions/gh-foo
    chown -R tester /home/tester/.local
    out=$(run_as_tester sudo -n "$SU" --only kilo,rustup,gh-extensions,brew 2>&1); rc=$?
    printf '%s\n' "$out"
    if [ "$rc" -eq 0 ] && grep -q 'running user-level tools as tester' <<< "$out" && grep -q 'upgraded as tester' <<< "$out" \
       && grep -q 'rustup self update as tester' <<< "$out" && grep -q 'upgraded from v1.0.0 to v1.0.1 as tester' <<< "$out" \
       && grep -q 'brew upgrade as tester' <<< "$out" \
       && [ "$(stat -c %U /home/tester/.rustup-touched /home/tester/.gh-touched /home/tester/.brew-touched | sort -u)" = tester ]; then
      result nonroot-sudo-tools pass "user tools (kilo, rustup, gh extensions, brew) delegated to SUDO_USER"
    else
      result nonroot-sudo-tools fail "exit $rc"
    fi
    rm -f /home/tester/.rustup-touched /home/tester/.gh-touched /home/tester/.brew-touched
    out=$(run_as_tester env HOME=/home/tester PATH="/home/tester/.local/bin:$PATH" "$SU" --dry-run --only kilo,rustup,gh-extensions,brew 2>&1); rc=$?
    printf '%s\n' "$out" | tail -n 12
    if [ "$rc" -eq 0 ] && grep -q 'Summary (dry run)' <<< "$out" && grep -qE 'dry-run +rustup ' <<< "$out" \
       && grep -qE 'dry-run +gh-extensions .*1 would be upgraded' <<< "$out" && grep -qE 'dry-run +brew .*1 outdated: foo' <<< "$out" \
       && [ ! -e /home/tester/.rustup-touched ] && [ ! -e /home/tester/.gh-touched ] && [ ! -e /home/tester/.brew-touched ]; then
      result nonroot-tools-dry pass "dry run of the user tools changed nothing"
    else
      result nonroot-tools-dry fail "exit $rc"
    fi
    rm -f /home/tester/.local/bin/kilo /home/tester/.local/bin/rustup /home/tester/.local/bin/gh /home/tester/.local/bin/brew
    rm -rf /home/tester/.local/share/gh
  else
    result nonroot skip "could not install sudo or create a user"
  fi
fi

# ---------------------------------------------------------------- apt: dead source
# apt-get update exits 0 when one source cannot be fetched; the step must
# still finish (exit 0) but report it as a warning, not as "ok".
if phase_enabled apt-partial && [ "$FAM" = apt ]; then
  section "apt with one unreachable package source"
  echo 'deb [trusted=yes] http://dead.invalid/debian stable main' > /etc/apt/sources.list.d/zz-dead-test.list
  out=$("$SU" --only apt --yes 2>&1); rc=$?
  printf '%s\n' "$out" | tail -n 12
  rm -f /etc/apt/sources.list.d/zz-dead-test.list
  if [ "$rc" -eq 0 ] && grep -qE 'warn +apt .*1 package source\(s\) could not be refreshed' <<< "$out" && grep -q '1 warning(s)' <<< "$out"; then
    result apt-partial pass "unreachable source reported as a warning, exit 0"
  else
    result apt-partial fail "exit $rc: $(summary_line apt "$out")"
  fi
fi

# ---------------------------------------------------------------- docker-compose
# A stand-alone docker-compose binary is updated from the GitHub release:
# download, sha256 against the release's checksums.txt, install -m 0755.
# The release lookup goes to a local stub of the API (SU_GITHUB_API, a
# documented test hook) so the phase does not depend on api.github.com's
# anonymous rate limit; the download and the checksum file are the real ones.
if phase_enabled compose; then
  section "docker-compose: verified download of a pinned release"
  COMPOSE_TAG=v2.40.3
  if ! command -v curl >/dev/null 2>&1; then
    install_pkgs curl ca-certificates >/dev/null 2>&1
    trust_proxy_ca
  fi
  if ! command -v curl >/dev/null 2>&1; then
    result compose skip "curl not available in this image"
  else
    mkdir -p /tmp/ghapi/repos/docker/compose/releases
    printf '{"tag_name":"%s","name":"%s"}\n' "$COMPOSE_TAG" "$COMPOSE_TAG" > /tmp/ghapi/repos/docker/compose/releases/latest
    printf '#!/bin/sh\necho "Docker Compose version v2.24.0"\n' > /usr/local/bin/docker-compose
    chmod 0755 /usr/local/bin/docker-compose
    out=$(SU_GITHUB_API=file:///tmp/ghapi "$SU" --only docker-compose --dry-run 2>&1); rc=$?
    if [ "$rc" -eq 0 ] && grep -q 'would download docker-compose-linux' <<< "$out" && [ "$(/usr/local/bin/docker-compose --version)" = "Docker Compose version v2.24.0" ]; then
      result compose-dry pass "dry run left the binary alone"
    else
      printf '%s\n' "$out"
      result compose-dry fail "exit $rc"
    fi
    out=$(SU_GITHUB_API=file:///tmp/ghapi "$SU" --only docker-compose -v 2>&1); rc=$?
    printf '%s\n' "$out" | grep -v 'skipping reboot-check' | tail -n 12
    ver=$(/usr/local/bin/docker-compose version 2>&1 | head -n1)
    mode=$(stat -c %a /usr/local/bin/docker-compose 2>/dev/null)
    if [ "$rc" -eq 0 ] && grep -q 'checksum ok' <<< "$out" \
        && grep -qE "updated +docker-compose +2\.24\.0 -> ${COMPOSE_TAG#v}" <<< "$out" \
        && [[ "$ver" == *"$COMPOSE_TAG"* ]] && [ "$mode" = 755 ]; then
      result compose pass "2.24.0 -> ${COMPOSE_TAG#v}, sha256 verified, mode $mode"
    else
      result compose fail "exit $rc: $(summary_line docker-compose "$out") version='$ver' mode=$mode"
    fi
    out=$(SU_GITHUB_API=file:///tmp/ghapi "$SU" --only docker-compose 2>&1); rc=$?
    if [ "$rc" -eq 0 ] && grep -qE "ok +docker-compose +up to date" <<< "$out"; then
      result compose-again pass "second run reports up to date"
    else
      printf '%s\n' "$out" | tail -n 5
      result compose-again fail "exit $rc"
    fi
    rm -f /usr/local/bin/docker-compose
  fi
fi

# ---------------------------------------------------------------- kilo guard
if phase_enabled kilo; then
  section "kilo guard: hanging editor"
  mkdir -p /usr/local/bin
  printf '#!/bin/sh\nwhile :; do sleep 1; done\n' > /usr/local/bin/kilo
  chmod 0755 /usr/local/bin/kilo
  start=$(date +%s)
  out=$(PATH="/usr/local/bin:$PATH" "$SU" --only kilo 2>&1); rc=$?
  end=$(date +%s)
  printf '%s\n' "$out"
  if [ "$rc" -eq 0 ] && grep -q 'did not answer' <<< "$out" && grep -qE 'skipped +kilo' <<< "$out" && [ $((end - start)) -lt 120 ]; then
    result kilo-editor pass "skipped in $((end - start))s"
  else
    result kilo-editor fail "exit $rc after $((end - start))s"
  fi
  section "kilo guard: Kilo Code look-alike"
  printf '#!/bin/sh\ncase "$1" in --version) cat /tmp/kilo-version 2>/dev/null || echo 4.2.1;; upgrade) echo 4.3.0 > /tmp/kilo-version;; esac\n' > /usr/local/bin/kilo
  rm -f /tmp/kilo-version
  out=$(PATH="/usr/local/bin:$PATH" "$SU" --only kilo 2>&1); rc=$?
  printf '%s\n' "$out"
  if [ "$rc" -eq 0 ] && grep -qE 'updated +kilo +4\.2\.1 -> 4\.3\.0' <<< "$out"; then
    result kilo-code pass "4.2.1 -> 4.3.0"
  else
    result kilo-code fail "exit $rc"
  fi
  out=$(PATH="/usr/local/bin:$PATH" "$SU" --only kilo --dry-run 2>&1); rc=$?
  if [ "$rc" -eq 0 ] && grep -qE 'dry-run +kilo' <<< "$out" && [ "$(cat /tmp/kilo-version)" = 4.3.0 ]; then
    result kilo-dry pass "dry run did not run upgrade"
  else
    printf '%s\n' "$out"
    result kilo-dry fail "exit $rc"
  fi
  rm -f /usr/local/bin/kilo
fi

echo "inner script done"
