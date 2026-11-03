# Firmware (`firmware`)

Checks for firmware updates with [fwupd](https://fwupd.org) and, only when asked, applies them.

| | |
| --- | --- |
| Step name | `firmware` |
| Runs as | root (`sudo`) |
| Detected when | `fwupdmgr` is installed (skipped in containers) |
| Settings | `FIRMWARE` / `--firmware` |
| Time limit | 3600 s |

## What it does

1. `fwupdmgr refresh` (download the latest metadata from LVFS).
2. `fwupdmgr get-updates`: list updates for the devices fwupd knows. Each **device** counts once, however many newer releases LVFS offers for it, and is put in one of four groups:

   | Group | Seen in fwupd's output as | Shown as |
   | --- | --- | --- |
   | available | a newer release and nothing below | `N firmware update(s) available` |
   | waiting for a reboot | `Update State: Pending` / `Needs reboot`, or the problem "Device is waiting for the update to be applied" | `N waiting for a reboot (device)`, and the [reboot check](reboot-check.md) reports it |
   | failed last time | `Update State: Failed` with an `Update Error` (for example a UEFI capsule the firmware rejected at boot) | `N failed last time (device)` |
   | needs user action | `Problems:` such as "Device requires AC power to be connected" or "the lid is closed" | `N need user action (device: problem)` |

   Each device is also logged with its current and offered version.
3. Only with `--firmware`, and only when something is available or failed last time: `fwupdmgr update -y --no-reboot-check`, then `get-updates` again to see what really changed. `fwupdmgr update` skips devices with problems and still exits 0, so the result comes from the second listing: `N of M firmware update(s) applied`, `reboot to finish (device)` for updates scheduled for the next boot, and a failure when nothing changed at all.

Without `--firmware` the step ends after the listing with `N firmware update(s) available (not applied; use --firmware): devices`. When some updates cannot be applied as they are (waiting for a reboot, failed, needs user action) the step is a warning and says which.

## What will be affected

With `--firmware` only:

* Device firmware: system UEFI/BIOS, Secure Boot databases (dbx), docks, SSDs, Thunderbolt controllers, peripherals, depending on the device.
* Many updates are scheduled for the **next boot**; UEFI capsule updates reboot into the updater.

## Dry run and `--detailed`

Firmware is never applied in a dry run. `--detailed` lists each device with its current and offered version:

```
  ◦ 1 firmware update(s) would change:
      UEFI dbx  20260402 -> 20260707
```

## Warnings

* **Firmware updates cannot always be undone**, and an interrupted update can leave a device unusable. Keep laptops on AC power.
* With BitLocker or a TPM-sealed LUKS key, a UEFI or dbx update can change PCR measurements; have your recovery key ready.
* Reboot when told to; the [reboot check](reboot-check.md) reports firmware that waits for the next boot.
* An update that keeps showing as "failed last time" after a reboot is being rejected by the device or the UEFI firmware; `fwupdmgr get-history` shows why. Running `--firmware` again retries it.
