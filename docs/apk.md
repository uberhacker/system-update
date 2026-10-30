# apk (`apk`, `system`)

Alpine Linux and postmarketOS.

| | |
| --- | --- |
| Step name | `apk` or `system` |
| Runs as | root (`sudo`) |
| Time limit | 3600 s per command |

## What it does

1. `apk update`.
2. `apk upgrade`.
3. `apk cache clean`.

## What will be affected

* Every installed package with a newer version in the configured repositories (`/etc/apk/repositories`), including new dependencies they pull in.
* The local package cache, if one is configured.

## Dry run and `--detailed`

`--dry-run` runs `apk update` and `apk upgrade -s` (simulate) and reports how many packages would change.

`--detailed` lists each one from the simulation (`musl  1.2.4-r2 -> 1.2.5-r0`, new packages as `(new)`).

## Warnings

* Moving to a new Alpine release (changing the version in `/etc/apk/repositories`) is not done here.
* Orphan removal does not apply: apk removes unneeded dependencies itself.
