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
2. `fwupdmgr get-updates`: list updates for the devices fwupd knows.
3. Only with `--firmware`: `fwupdmgr update -y --no-reboot-check`.

Without `--firmware` the step ends after the listing with `N firmware update(s) available (not applied; use --firmware)`.

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
* Reboot when told to; the [reboot check](reboot-check.md) does not see pending firmware.
