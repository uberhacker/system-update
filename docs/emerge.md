# emerge (`emerge`, `system`) - best effort

Gentoo and Funtoo. Support is deliberately minimal and not covered by the container tests.

| | |
| --- | --- |
| Step name | `emerge` or `system` |
| Runs as | root (`sudo`) |
| Settings | `AUTOREMOVE` / `--no-autoremove` |
| Time limit | 3600 s per command |

## What it does

1. `emerge --sync`.
2. `emerge --update --deep --newuse @world`.
3. Unless `--no-autoremove`: `emerge --depclean`.

## What will be affected

* Packages in `@world` and their dependencies are rebuilt from source where newer versions or changed USE flags apply.
* `--depclean` removes packages not required by `@world`.

## Dry run and `--detailed`

`--dry-run` runs `emerge --pretend --update --deep --newuse @world` **without** syncing the tree first, so it shows what the current tree would do.

`--detailed` lists each package from the pretend output: `sys-libs/glibc  2.38-r10 -> 2.39-r6`, new packages as `(new)`, rebuilds of the same version as `(new build)`.

## Warnings

* A world update can take hours and can stop on blockers, masked packages or USE conflicts that need a human; the one-hour time limit applies to each command.
* `--depclean` can remove things you rely on if they are not in `@world`; consider `--no-autoremove` on Gentoo.
* Configuration updates (`etc-update` / `dispatch-conf`) are left to you.
