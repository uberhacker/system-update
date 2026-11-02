# Node.js via nvm (`nvm`)

Keeps the current Node.js LTS installed through [nvm](https://github.com/nvm-sh/nvm) and makes it the default.

| | |
| --- | --- |
| Step name | `nvm` |
| Runs as | the invoking user |
| Detected when | `$NVM_DIR/nvm.sh` (default `~/.nvm/nvm.sh`) exists |
| Settings | `PRUNE_NODE` / `--prune-node`, `TIMEOUT`, `PROBE_TIMEOUT` |

## What it does

nvm is a shell function, so every call runs in a fresh `bash` that sources `nvm.sh --no-use`, with stdin closed and a timeout.

1. Reads the current `default` alias (or the active version when there is no default) and asks `nvm version-remote --lts` for the newest LTS.
2. If that LTS is not installed: `nvm install <lts> --reinstall-packages-from=<previous default>`, so global npm packages (and the CLIs they provide) are reinstalled under the new version.
3. `nvm alias default 'lts/*'` and checks that `default` now resolves to the new LTS.
4. With `--prune-node` only: `nvm uninstall` every other installed version. The new default is never removed, and nothing is removed before the new default is in place.

Older versions are kept by default. iojs and very old Node lines are never installed.

## What will be affected

* A new directory under `~/.nvm/versions/node/<version>` (100 MB or more with global packages).
* The `default` alias in `~/.nvm/alias/default`: **new shells get the new Node version**. A move from one LTS line to the next (for example 22 to 24) is a major version change.
* Global npm packages are reinstalled for the new version; native add-ons are rebuilt, which can fail for old packages.
* With `--prune-node`: every other version under `~/.nvm/versions/node` is deleted together with its global packages.

## Dry run and `--detailed`

Both report `already on LTS vX` or `would install vX (migrating global packages from vY) and set default to lts/*`, plus `would remove other versions` with `--prune-node`. The LTS lookup is read-only.

## Warnings

* Projects pinned with `.nvmrc` or `engines` are not affected until you run `nvm use`, but anything that relies on the default `node` (editors, cron jobs, shells) switches to the new major version.
* `--prune-node` removes versions your projects may still use. Run `--dry-run --prune-node` first.
* `npm` packages installed globally with `sudo` into an nvm version are not supported by nvm and may fail to reinstall.

## Skipped / failed when

* No `nvm.sh` is found: not detected.
* `nvm version-remote --lts` fails (offline, nodejs.org unreachable): failed, nothing changed.
* `nvm install` fails: failed, the previous default is left in place.
