# Snap (`snap`)

Refreshes snaps through `snapd`.

| | |
| --- | --- |
| Step name | `snap` |
| Runs as | root (`sudo`) |
| Detected when | `snap` is installed and `snapd` is running |
| Time limit | 3600 s |

## What it does

`snap refresh`: every snap is refreshed to the newest revision of the channel it tracks.

## What will be affected

* Each refreshed snap gets a new revision under `/snap/<name>/`; snapd keeps older revisions for `snap revert` (how many is set by `refresh.retain`).
* Running snap applications may be closed or refreshed when they exit, depending on the snap.

## Dry run and `--detailed`

`--dry-run` runs `snap refresh --list` and reports the count. `--detailed` lists each snap with the installed version (`snap list`) and the new one.

## Warnings

* snapd also refreshes on its own schedule; this step only does it now.
