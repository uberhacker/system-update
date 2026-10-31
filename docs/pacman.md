# pacman (`pacman`, `system`)

Arch Linux, Manjaro, EndeavourOS, Garuda, CachyOS and other pacman distributions.

| | |
| --- | --- |
| Step name | `pacman` or `system` |
| Runs as | root (`sudo`); an AUR helper as the invoking user |
| Settings | `AUTOREMOVE` / `--no-autoremove`, `AUR_HELPER` / `--aur` |
| Time limit | 3600 s per command |

## What it does

1. `pacman -Syu --noconfirm`: full system upgrade (Arch does not support partial upgrades).
2. With `--aur` and `paru` or `yay` installed: `<helper> -Sua --noconfirm` as the invoking user, for AUR packages only. Never as root.
3. Unless `--no-autoremove`: removes orphans (`pacman -Rns $(pacman -Qtdq)`).
4. `paccache -rk2` when available: keeps the two newest versions of each package in the cache.

## What will be affected

* Every package with a newer version in the sync repositories.
* Orphans (packages installed as dependencies that nothing needs any more) are removed with their configuration files (`-Rns`).
* The package cache in `/var/cache/pacman/pkg` is trimmed.
* With `--aur`: AUR packages are rebuilt and reinstalled by the helper.

## Dry run and `--detailed`

`--dry-run` lists pending updates without touching the system's sync database: `checkupdates` (pacman-contrib) when available, otherwise the same thing by hand (sync into a temporary database, `pacman -Qu` against it). AUR updates are only mentioned.

`--detailed` adds one row per package from that list:

```
  ◦ 2 package(s) would change:
      device-mapper  2.03.43-2 -> 2.03.44-1
      gnupg          2.4.9-3   -> 2.4.9-4
```

## Warnings

* Read the Arch news (archlinux.org) before upgrading when an update needs manual intervention; this program does not check it.
* `.pacnew` files are created for configuration you changed; merge them with `pacdiff`.
* `--noconfirm` answers the default to every question, including package replacements and conflicts. A conflict that needs a choice makes the step fail instead.
* AUR packages are user-produced; `--noconfirm` skips reviewing their PKGBUILDs. Only use `--aur` if you are comfortable with that.
