#!/usr/bin/env bats
# firmware (fwupd): devices are counted once however many releases they are
# offered; updates that wait for a reboot, failed last time or are blocked
# by a problem (AC power, lid) are named instead of reported as available;
# after `fwupdmgr update` the list is read again, so an update fwupd skipped
# is not reported as applied; firmware waiting for a reboot reaches the
# reboot check.

load ../test_helper

d() { fixture "detail/$1"; }

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
  in_container() { return 1; }
  kernel_reboot_check() { return 1; }
  # Fake fwupdmgr: get-updates prints state/list (exit 2 when it is
  # missing); update replaces state/list with state/after (removed when
  # state/after is empty) and exits with state/update_rc (default 0).
  make_fake_bin "$bindir" fwupdmgr "
echo \"fwupdmgr \$* LC_ALL=\${LC_ALL:-}\" >> '$CALLS'
case \"\$1\" in
  refresh) exit 0 ;;
  get-updates)
    [ -f '$state/list' ] || { echo 'No updates available'; exit 2; }
    cat '$state/list' ;;
  update)
    if [ -f '$state/after' ]; then
      if [ -s '$state/after' ]; then cp '$state/after' '$state/list'; else rm -f '$state/list'; fi
    fi
    exit \"\$(cat '$state/update_rc' 2>/dev/null || echo 0)\" ;;
esac"
}

firmware_on() { config_set FIRMWARE 1 flag; }

# get-updates text for a dbx update already scheduled for the next boot.
pending_dbx_list() {
  cat <<'TXT'
Example Vendor System Product Name
│
└─UEFI dbx:
  │   Device ID:          0000000000000000000000000000000000000000
  │   Current version:    20260402
  │   Update State:       Pending
  │   Problems:           • Device is waiting for the update to be applied
  │ 
  └─Secure Boot dbx Configuration Update:
        New version:      20260707
TXT
}

@test "devices: failed, blocked and pending are told apart; newest release kept" {
  run fwupd_devices "$(d fwupd-get-updates-mixed.txt)"
  assert_equal 3 "${#lines[@]}"
  assert_equal "UEFI dbx|20230501|20250507|failed|failed to write data to efivarfs: Error writing to file descriptor: Invalid argument" "${lines[0]}"
  assert_equal "Thunderbolt Controller|21.00|23.00|blocked|Device requires AC power to be connected; Device cannot be updated while the lid is closed" "${lines[1]}"
  assert_equal "SSD 512GB|5B2QGXA7|5B2QGXB7|pending|" "${lines[2]}"
}

@test "devices: three releases of one device are one update" {
  run fwupd_devices "$(d fwupd-get-updates-two-releases.txt)"
  assert_equal 1 "${#lines[@]}"
  assert_equal "System Firmware|01.10.00|01.14.00|available|" "${lines[0]}"
}

@test "devices: the no-update lists at the top are not counted" {
  run fwupd_devices "$(d fwupd-get-updates.txt)"
  assert_equal "UEFI dbx|20260402|20260707|available|" "$output"
}

@test "devices: colour codes are ignored" {
  f="$BATS_TEST_TMPDIR/color.txt"
  sed $'s/Update State:       Failed/Update State:       \e[31mFailed\e[0m/' "$(d fwupd-get-updates-mixed.txt)" > "$f"
  run fwupd_devices "$f"
  assert_equal "failed" "$(printf '%s\n' "${lines[0]}" | cut -d'|' -f4)"
}

@test "step: without --firmware, three releases of one device count as one" {
  cp "$(d fwupd-get-updates-two-releases.txt)" "$state/list"
  fwupd_step >/dev/null 2>&1
  assert_equal ok "$STEP_RESULT"
  assert_equal "1 firmware update(s) available (not applied; use --firmware): System Firmware" "$STEP_NOTE"
  assert_equal "" "$SU_FIRMWARE_REBOOT"
}

@test "step: get-updates runs with the C locale so the text can be read" {
  cp "$(d fwupd-get-updates.txt)" "$state/list"
  fwupd_step >/dev/null 2>&1
  grep -q 'fwupdmgr get-updates .*LC_ALL=C' "$CALLS"
}

@test "step: without --firmware, updates that cannot be applied are named, not counted as available" {
  cp "$(d fwupd-get-updates-mixed.txt)" "$state/list"
  fwupd_step >/dev/null 2>&1
  assert_equal warn "$STEP_RESULT"
  [[ "$STEP_NOTE" == *"1 waiting for a reboot (SSD 512GB)"* ]]
  [[ "$STEP_NOTE" == *"1 failed last time (UEFI dbx)"* ]]
  [[ "$STEP_NOTE" == *"1 need user action (Thunderbolt Controller: Device requires AC power to be connected; Device cannot be updated while the lid is closed)"* ]]
  [[ "$STEP_NOTE" != *"available (not applied"* ]]
  assert_equal "firmware waiting to be applied (SSD 512GB)" "$SU_FIRMWARE_REBOOT"
}

@test "step: no updates (exit 2) is ok and leaves nothing for the reboot check" {
  SU_FIRMWARE_REBOOT="stale"
  fwupd_step >/dev/null 2>&1
  assert_equal ok "$STEP_RESULT"
  assert_equal "no firmware updates available" "$STEP_NOTE"
  assert_equal "" "$SU_FIRMWARE_REBOOT"
}

@test "step --firmware: nothing installable means fwupdmgr update is not run" {
  firmware_on
  pending_dbx_list > "$state/list"
  fwupd_step >/dev/null 2>&1
  assert_equal warn "$STEP_RESULT"
  [[ "$STEP_NOTE" == "nothing to apply; 1 waiting for a reboot (UEFI dbx)" ]]
  ! grep -q 'fwupdmgr update' "$CALLS"
}

@test "step --firmware: update exits 0 but nothing changed is a failure, not 'updated'" {
  firmware_on
  cp "$(d fwupd-get-updates-two-releases.txt)" "$state/list"
  fwupd_step >/dev/null 2>&1
  grep -q 'fwupdmgr update -y --no-reboot-check' "$CALLS"
  assert_equal failed "$STEP_RESULT"
  assert_equal "fwupdmgr update finished but nothing was installed; still offered: System Firmware" "$STEP_NOTE"
}

@test "step --firmware: an update scheduled for the next boot says reboot and reaches the reboot check" {
  firmware_on
  cp "$(d fwupd-get-updates.txt)" "$state/list"
  pending_dbx_list > "$state/after"
  fwupd_step >/dev/null 2>&1
  assert_equal updated "$STEP_RESULT"
  assert_equal "1 of 1 firmware update(s) applied; reboot to finish (UEFI dbx)" "$STEP_NOTE"
  assert_equal "firmware waiting to be applied (UEFI dbx)" "$SU_FIRMWARE_REBOOT"
  SU_PKG=apt
  pkg_apt_reboot_check() { return 1; }
  reboot_check_step >/dev/null 2>&1
  assert_equal warn "$STEP_RESULT"
  assert_equal "reboot required: firmware waiting to be applied (UEFI dbx)" "$STEP_NOTE"
}

@test "step --firmware: installed at once (nothing left) is updated" {
  firmware_on
  cp "$(d fwupd-get-updates.txt)" "$state/list"
  : > "$state/after"
  fwupd_step >/dev/null 2>&1
  assert_equal updated "$STEP_RESULT"
  assert_equal "firmware updated" "$STEP_NOTE"
}

@test "step --firmware: some applied, a blocked device left is a warning that names it" {
  firmware_on
  cp "$(d fwupd-get-updates-mixed.txt)" "$state/list"
  # After the update: dbx installed, Thunderbolt still blocked, SSD pending.
  awk '/├─UEFI dbx:/{skip=1} /├─Thunderbolt Controller:/{skip=0} !skip' "$(d fwupd-get-updates-mixed.txt)" > "$state/after"
  fwupd_step >/dev/null 2>&1
  assert_equal warn "$STEP_RESULT"
  [[ "$STEP_NOTE" == "1 of 1 firmware update(s) applied; "* ]]
  [[ "$STEP_NOTE" == *"need user action (Thunderbolt Controller: Device requires AC power"* ]]
  assert_equal "firmware waiting to be applied (SSD 512GB)" "$SU_FIRMWARE_REBOOT"
}

@test "step --firmware: fwupdmgr update failing is a failure" {
  firmware_on
  cp "$(d fwupd-get-updates.txt)" "$state/list"
  echo 1 > "$state/update_rc"
  fwupd_step >/dev/null 2>&1
  assert_equal failed "$STEP_RESULT"
  assert_equal "fwupdmgr update failed (exit code 1)" "$STEP_NOTE"
}

@test "step --firmware --dry-run: counts what would be applied, runs no update" {
  firmware_on
  SU_DRY_RUN=1
  cp "$(d fwupd-get-updates-mixed.txt)" "$state/list"
  fwupd_step >/dev/null 2>&1
  assert_equal dry-run "$STEP_RESULT"
  [[ "$STEP_NOTE" == "1 firmware update(s) would be applied; "* ]]
  ! grep -q 'fwupdmgr update' "$CALLS"
}

@test "reboot check: firmware is added to a package manager's reason" {
  SU_PKG=apt
  pkg_apt_reboot_check() { echo "packages: linux-image-amd64"; return 0; }
  SU_FIRMWARE_REBOOT="firmware waiting to be applied (UEFI dbx)"
  reboot_check_step >/dev/null 2>&1
  assert_equal warn "$STEP_RESULT"
  assert_equal "reboot required: packages: linux-image-amd64; firmware waiting to be applied (UEFI dbx)" "$STEP_NOTE"
}

@test "reboot check: nothing pending is ok" {
  SU_PKG=apt
  pkg_apt_reboot_check() { return 1; }
  SU_FIRMWARE_REBOOT=""
  reboot_check_step >/dev/null 2>&1
  assert_equal ok "$STEP_RESULT"
}
