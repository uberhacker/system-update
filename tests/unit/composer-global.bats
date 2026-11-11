#!/usr/bin/env bats
# composer global update (Ed's issue 7): look first with --dry-run, leave the
# global packages alone when the update would downgrade any of them, and put
# them back when a real update fails half way.

load ../test_helper

setup() {
  SU_OUT=1
  load_su
  SU_DRY_RUN=0
  CHOME="$BATS_TEST_TMPDIR/composer-home"
  mkdir -p "$CHOME/vendor/symfony/console"
  echo '{"require":{"consolidation/cgr":"^2"}}' > "$CHOME/composer.json"
  echo 'lock-v1' > "$CHOME/composer.lock"
  echo 'good' > "$CHOME/vendor/autoload.php"
  RAN="$BATS_TEST_TMPDIR/ran"; : > "$RAN"
  PLAN="Loading composer repositories with package information
Updating dependencies
Lock file operations: 0 installs, 2 updates, 0 removals
  - Upgrading symfony/console (v7.4.1 => v7.4.2)
  - Upgrading psr/log (3.0.1 => 3.0.2)"
  PLAN_RC=0
  UPDATE_RC=0
  export CHOME
  run_user() {
    case "$*" in
      "composer config --global home"*) echo "$CHOME" ;;
      "php -r"*) echo "8.4.14" ;;
      "composer global update --dry-run"*) echo "dry-run" >> "$RAN"; printf '%s\n' "$PLAN"; return "$PLAN_RC" ;;
      *) "$@" ;;
    esac
  }
  do_user() {
    case "$*" in
      "composer global update"*)
        echo "update" >> "$RAN"
        if [ "$UPDATE_RC" != 0 ]; then
          # What Ed saw: the update dies after removing part of vendor/.
          echo 'broken' > "$CHOME/vendor/autoload.php"
          rm -rf "$CHOME/vendor/symfony"
          echo 'lock-v2' > "$CHOME/composer.lock"
          return "$UPDATE_RC"
        fi
        [ -d "$CHOME" ] && echo 'lock-v2' > "$CHOME/composer.lock"; return 0 ;;
      *) "$@" ;;
    esac
  }
}

@test "upgrades only: the update runs and the rollback copy is removed" {
  composer_global_update
  assert_equal "global update ok" "$COMPOSER_GLOBAL_NOTE"
  assert_equal "dry-run
update" "$(cat "$RAN")"
  assert_equal lock-v2 "$(cat "$CHOME/composer.lock")"
}

@test "nothing to update: the real update is not run" {
  PLAN="Loading composer repositories with package information
Updating dependencies
Nothing to modify in lock file
Installing dependencies from lock file (including require-dev)
Nothing to install, update or remove"
  composer_global_update
  assert_equal "global packages up to date" "$COMPOSER_GLOBAL_NOTE"
  assert_equal "dry-run" "$(cat "$RAN")"
}

@test "a planned downgrade leaves everything alone and names the packages (issue 7)" {
  PLAN="Updating dependencies
Lock file operations: 0 installs, 1 update, 3 removals
  - Downgrading symfony/console (v7.4.1 => v5.4.47)
  - Downgrading psr/log (3.0.2 => 2.0.0)
  - Downgrading league/container (4.2.4 => 3.4.1)
  - Downgrading symfony/process (v7.4.0 => v5.4.47)
  - Removing symfony/polyfill-php81 (v1.33.0)"
  rc=0; composer_global_update || rc=$?
  assert_equal 2 "$rc"
  assert_equal "dry-run" "$(cat "$RAN")"
  assert_contains "$COMPOSER_GLOBAL_NOTE" "global update not run: it would downgrade 4 package(s)"
  assert_contains "$COMPOSER_GLOBAL_NOTE" "symfony/console 7.4.1 -> 5.4.47"
  assert_contains "$COMPOSER_GLOBAL_NOTE" "..."
  assert_equal lock-v1 "$(cat "$CHOME/composer.lock")"
}

@test "composer_downgrades reads composer's lines with or without a v prefix" {
  printf '  - Downgrading psr/log (3.0.2 => 2.0.0)\n  - Downgrading symfony/yaml (v7.4.1 => v5.4.45)\n  - Upgrading a/b (1.0 => 1.1)\n' > "$BATS_TEST_TMPDIR/plan"
  assert_equal "psr/log 3.0.2 -> 2.0.0
symfony/yaml 7.4.1 -> 5.4.45" "$(composer_downgrades "$BATS_TEST_TMPDIR/plan")"
}

@test "a failed update puts back composer.json, composer.lock and vendor" {
  UPDATE_RC=1
  rc=0; composer_global_update || rc=$?
  assert_equal 1 "$rc"
  assert_equal "global update failed (exit code 1); previous packages restored" "$COMPOSER_GLOBAL_NOTE"
  assert_equal lock-v1 "$(cat "$CHOME/composer.lock")"
  assert_equal good "$(cat "$CHOME/vendor/autoload.php")"
  [ -d "$CHOME/vendor/symfony/console" ]
}

@test "a failed dry run changes nothing and is reported" {
  PLAN_RC=2
  rc=0; composer_global_update || rc=$?
  assert_equal 1 "$rc"
  assert_equal "dry-run" "$(cat "$RAN")"
  assert_contains "$COMPOSER_GLOBAL_NOTE" "its dry run failed (exit code 2)"
}

@test "no global Composer directory: updates without a rollback copy" {
  rm -rf "$CHOME"
  composer_global_update
  assert_equal "global update ok" "$COMPOSER_GLOBAL_NOTE"
}
