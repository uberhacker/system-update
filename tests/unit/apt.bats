#!/usr/bin/env bats
# apt on a system without systemd (sysvinit, OpenRC, runit): the step itself
# never needs systemd, and when a package's install script does (pcp's calls
# systemctl), the failure names the package and the cause instead of only
# "exit code 100".

load ../test_helper

PCP_ERROR="Setting up pcp (6.0.3-1.1) ...
System has not been booted with systemd as init system (PID 1). Can't operate.
Failed to connect to bus: Host is down
dpkg: error processing package pcp (--configure):
 installed pcp package post-installation script subprocess returned error exit status 1
Errors were encountered while processing:
 pcp
E: Sub-process /usr/bin/dpkg returned an error code (1)"

setup() {
  SU_OUT=1
  load_su
  bindir="$BATS_TEST_TMPDIR/bin"; state="$BATS_TEST_TMPDIR/state"
  mkdir -p "$bindir" "$state"
  export PATH="$bindir:$PATH"
  export SU_TIMEOUT=20 SU_PKG_TIMEOUT=20
  SU_DRY_RUN=0 SU_DETAILED=0
  STEP_RESULT=""; STEP_NOTE=""
  CALLS="$BATS_TEST_TMPDIR/calls.log"; : > "$CALLS"
  run_root() { "$@"; }
  # No systemd: the directory sd_booted(3) looks for does not exist.
  export SU_SYSTEMD_RUN_DIR="$BATS_TEST_TMPDIR/no-systemd"
  printf '%s\n' "$PCP_ERROR" > "$state/pcp_error"
  make_fake_bin "$bindir" systemctl "echo \"systemctl \$*\" >> '$CALLS'; exit 1"
  make_fake_bin "$bindir" apt-get "
echo \"apt-get \$*\" >> '$CALLS'
case \"\$*\" in
  *' update'*) echo 'Hit:1 http://deb.devuan.org/merged daedalus InRelease' ;;
  *dist-upgrade*)
    if [ -e '$state/fail' ]; then
      echo 'Unpacking pcp (6.0.3-1.1) over (6.0.3-1) ...'
      cat '$state/pcp_error'; exit 100
    fi
    echo 'Unpacking curl (7.88.1-10+deb12u8) over (7.88.1-10+deb12u7) ...'
    echo 'Setting up curl (7.88.1-10+deb12u8) ...'
    echo '1 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.' ;;
  *' -f install'*) cat '$state/pcp_error'; exit 100 ;;
  *) exit 0 ;;
esac"
}

@test "failed packages: configure and unpack errors, each package once" {
  f="$BATS_TEST_TMPDIR/log"
  { printf '%s\n' "$PCP_ERROR" "$PCP_ERROR"
    echo "dpkg: error processing archive /var/cache/apt/archives/libfoo1_1.2-3_amd64.deb (--unpack):"; } > "$f"
  run apt_failed_packages "$f"
  assert_equal "pcp" "${lines[0]}"
  assert_equal "libfoo1" "${lines[1]}"
  assert_equal 2 "${#lines[@]}"
}

@test "no systemd: a normal upgrade works and never calls systemctl" {
  pkg_apt_update >/dev/null 2>&1
  assert_equal updated "$STEP_RESULT"
  assert_equal "1 upgraded, 0 newly installed, 0 to remove and 0 not upgraded." "$STEP_NOTE"
  ! grep -q systemctl "$CALLS"
}

@test "no systemd: a package script that needs systemd is named in the failure" {
  touch "$state/fail"
  run pkg_apt_update_wrapped
  [ "$status" -eq 0 ]
  assert_equal failed "$(cat "$BATS_TEST_TMPDIR/result")"
  assert_equal "apt-get dist-upgrade failed (exit code 100): pcp could not be set up: its install script needs systemd, which this system does not run" "$(cat "$BATS_TEST_TMPDIR/note")"
  [[ "$output" == *"sudo apt-get remove pcp"* ]]
  [[ "$output" == *"reportbug pcp"* ]]
}

@test "with systemd: the same error only names the package" {
  mkdir -p "$SU_SYSTEMD_RUN_DIR"
  touch "$state/fail"
  run pkg_apt_update_wrapped
  assert_equal "apt-get dist-upgrade failed (exit code 100): dpkg stopped at pcp" "$(cat "$BATS_TEST_TMPDIR/note")"
  [[ "$output" == *"dpkg --configure -a"* ]]
}

@test "a failure dpkg did not explain keeps the plain message" {
  : > "$state/pcp_error"
  touch "$state/fail"
  pkg_apt_update >/dev/null 2>&1
  assert_equal failed "$STEP_RESULT"
  assert_equal "apt-get dist-upgrade failed (exit code 100)" "$STEP_NOTE"
}

@test "systemd_running follows the sd_booted directory" {
  ! systemd_running
  mkdir -p "$SU_SYSTEMD_RUN_DIR"
  systemd_running
}

# Run the step in `run` (to capture its log) and keep its result.
pkg_apt_update_wrapped() {
  pkg_apt_update
  printf '%s' "$STEP_RESULT" > "$BATS_TEST_TMPDIR/result"
  printf '%s' "$STEP_NOTE" > "$BATS_TEST_TMPDIR/note"
}
