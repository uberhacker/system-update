#!/usr/bin/env bats
# PHP phar self-updates (wp-cli, composer, terminus): the update replaces the
# phar by writing next to it, so it runs as the user only when the user can
# write both the phar and its directory; otherwise as root.

load ../test_helper

setup() {
  SU_OUT=1
  load_su
  bindir="$BATS_TEST_TMPDIR/usr-local-bin"
  mkdir -p "$bindir"
  make_fake_bin "$bindir" wp 'echo "WP-CLI 2.11.0"'
  SU_PKG=apt
  SU_DRY_RUN=0
  STEP_RESULT=""; STEP_NOTE=""
  RAN="$BATS_TEST_TMPDIR/ran"; : > "$RAN"
  NOT_WRITABLE=""
  distro_pkg_owner() { return 1; }
  eval "real_user_can_write() $(declare -f user_can_write | tail -n +2)"
  # Tests run as root, so writability is what each test says it is.
  user_can_write() { case " $NOT_WRITABLE " in *" $1 "*) return 1 ;; esac; return 0; }
  do_user() { echo "user $*" >> "$RAN"; }
  do_root() { echo "root $*" >> "$RAN"; }
  sudo_available() { return 0; }
}

@test "phar and directory writable: updated as the user" {
  phar_update wp-cli "$bindir/wp" wp cli update --yes
  assert_equal "user wp cli update --yes" "$(cat "$RAN")"
}

@test "phar writable but its directory is not: updated as root (Ed's /usr/local/bin)" {
  NOT_WRITABLE="$bindir"
  phar_update wp-cli "$bindir/wp" wp cli update --yes
  assert_equal "root env HOME=/root COMPOSER_ALLOW_SUPERUSER=1 wp cli update --yes" "$(cat "$RAN")"
}

@test "phar not writable: updated as root" {
  NOT_WRITABLE="$bindir/wp"
  phar_update composer "$bindir/wp" composer self-update
  assert_equal "root env HOME=/root COMPOSER_ALLOW_SUPERUSER=1 composer self-update" "$(cat "$RAN")"
}

@test "directory not writable and no sudo: skipped with the directory named" {
  NOT_WRITABLE="$bindir"
  sudo_available() { return 1; }
  rc=0; phar_update wp-cli "$bindir/wp" wp cli update --yes || rc=$?
  assert_equal 3 "$rc"
  assert_equal skipped "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "$bindir is not writable by $SU_USER and sudo is unavailable"
  assert_equal "" "$(cat "$RAN")"
}

@test "a symlinked phar is judged by the real file's directory" {
  realdir="$BATS_TEST_TMPDIR/opt-wp"; mkdir -p "$realdir"
  mv "$bindir/wp" "$realdir/wp-cli.phar"; ln -s "$realdir/wp-cli.phar" "$bindir/wp"
  NOT_WRITABLE="$realdir"
  phar_update wp-cli "$bindir/wp" wp cli update --yes
  assert_contains "$(cat "$RAN")" "root env HOME=/root COMPOSER_ALLOW_SUPERUSER=1"
}

@test "wp-cli step: a root-owned /usr/local/bin no longer fails the step" {
  NOT_WRITABLE="$bindir"
  SU_TOOL_BIN[wp-cli]="$bindir/wp"
  tool_wp_cli_update
  assert_contains "$(cat "$RAN")" "root env HOME=/root COMPOSER_ALLOW_SUPERUSER=1 wp cli update --yes --no-color --allow-root"
  assert_equal ok "$STEP_RESULT"
}

@test "user_can_write checks as \$SU_USER when we are someone else (sudo)" {
  SU_USER=ed; SU_CUR_USER=root
  has_cmd() { [ "$1" = runuser ]; }
  runuser() { echo "runuser $*" >> "$RAN"; return 1; }
  ! real_user_can_write "$bindir"
  assert_equal "runuser -u ed -- test -w $bindir" "$(cat "$RAN")"
}
