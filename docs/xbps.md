# xbps (`xbps`, `system`)

Void Linux.

| | |
| --- | --- |
| Step name | `xbps` or `system` |
| Runs as | root (`sudo`) |
| Settings | `AUTOREMOVE` / `--no-autoremove` |
| Time limit | 3600 s per command |

## What it does

1. `xbps-install -Syu xbps`: xbps updates itself first when needed.
2. `xbps-install -Syu`.
3. Unless `--no-autoremove`: `xbps-remove -Ooy` (orphans and obsolete cached packages).

## What will be affected

* Every installed package with a newer version in the repositories.
* Orphaned packages and old package files in the cache.

## Dry run and `--detailed`

`--dry-run` runs `xbps-install -Sun` (sync and list, nothing installed) and reports the count.

`--detailed` lists each package with the installed version from `xbps-query` and the new one from the list.

## Warnings

* Kernel updates need a reboot; old kernels are kept until you remove them with `vkpurge`.
