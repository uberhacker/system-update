# Node.js via nodebrew (`nodebrew`)

Keeps the active Node.js version managed by [nodebrew](https://github.com/hokaccha/nodebrew) on the newest release of its major line.

| | |
| --- | --- |
| Step name | `nodebrew` |
| Runs as | the invoking user |
| Detected when | `nodebrew` is on `PATH` |
| Settings | `PRUNE_NODE` / `--prune-node`, `TIMEOUT` |

## What it does

1. Reads the active version from `nodebrew ls` (`current: vX.Y.Z`).
2. Finds the newest release of the same major version in `nodebrew ls-remote`. It never moves to a new major version.
3. `nodebrew install-binary <new>` (falls back to `nodebrew install <new>`, which compiles from source).
4. `nodebrew migrate-package <old>` copies global npm packages; `nodebrew use <new>` switches to it.
5. With `--prune-node` only: `nodebrew uninstall <old>`.

## What will be affected

* A new version under `~/.nodebrew/node/<version>` and the `current` symlink.
* Global npm packages are copied to the new version.
* With `--prune-node`: the previous version and its packages are removed.

## Dry run and `--detailed`

Both report `up to date (vX)` or `would install vNEW, migrate global packages from vOLD and switch to it` (and `would remove vOLD` with `--prune-node`).

## Warnings

* If no binary build exists for your platform, `nodebrew install` compiles Node.js from source, which can take a long time and needs a compiler toolchain; `TIMEOUT` (300 s) may cut it short.
* A failed `migrate-package` is reported as a warning; the switch still happens and global packages must then be reinstalled by hand.

## Skipped / failed when

* No version is active in nodebrew: skipped.
* The remote version list cannot be read: failed.
