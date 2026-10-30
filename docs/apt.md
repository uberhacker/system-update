# apt (`apt`, `system`)

Debian, Ubuntu, Linux Mint, Pop!_OS, elementary, Kali, Raspberry Pi OS and other Debian derivatives.

| | |
| --- | --- |
| Step name | `apt` or `system` |
| Runs as | root (`sudo`, asked for once at the start) |
| Settings | `AUTOREMOVE` / `--no-autoremove` |
| Time limit | 3600 s per command |

## What it does

1. `apt-get update`. apt exits 0 even when a source cannot be fetched, so the output is checked for `Failed to fetch`: some sources failing is a **warning** (the cached lists are used for those), all failing is a failure.
2. `apt-get -y dist-upgrade` with `DEBIAN_FRONTEND=noninteractive`, `NEEDRESTART_MODE=a` and `--force-confdef --force-confold`.
3. If the upgrade fails: `apt-get -f install` to repair, and the step is reported failed.
4. `apt-get autoremove --purge` (unless `--no-autoremove`).
5. `apt-get clean`.

## What will be affected

* All installed packages with a newer candidate. `dist-upgrade` (unlike `upgrade`) **may install new packages and remove installed ones** to resolve changed dependencies, for example a new kernel package.
* Configuration files you changed are kept (`--force-confold`); the maintainer's version is installed as `*.dpkg-dist` for you to merge.
* Services are restarted automatically by `needrestart` where it is installed (`NEEDRESTART_MODE=a`).
* `autoremove --purge` removes packages nothing depends on any more **together with their configuration files**.
* The package cache in `/var/cache/apt/archives` is emptied.

## Dry run and `--detailed`

`--dry-run` refreshes the lists when sudo works without a password (otherwise it uses the cached lists and says so), then runs `apt-get -s dist-upgrade`: a simulation that changes nothing. The summary shows `N package(s) would be upgraded/installed (apt's summary line)`.

`--detailed` adds one row per package from the simulation:

```
  ◦ 4 package(s) would change:
      base-files                    13ubuntu10.4    -> 13ubuntu10.5
      libc6                         2.39-0ubuntu8.8 -> 2.39-0ubuntu8.9
      libfoo1                       1.2-3           -> (removed)
      linux-image-6.8.0-90-generic  (new)           -> 6.8.0-90.91
```

## Warnings

* Read the "to remove" count in the dry run before a real run: `dist-upgrade` removals are rare but real (held-back transitions, renamed libraries).
* A new kernel is installed but only used after a reboot; the [reboot check](reboot-check.md) reports it.
* Packages on hold (`apt-mark hold`) are respected.
* Third-party repositories (Docker, VSCodium, ...) are upgraded like any other source.
