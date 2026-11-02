# npm global packages (`npm-globals`) - opt-in

Runs `npm update -g` for a Node.js that belongs to you (nvm, nodebrew, `~/.npm-global`). **Off by default**: enable it with `--npm-globals` or `NPM_GLOBALS=1`.

| | |
| --- | --- |
| Step name | `npm-globals` |
| Runs as | the invoking user |
| Detected when | `npm` is on the user's `PATH` and resolves to a path inside the user's home |
| Settings | `NPM_GLOBALS` / `--npm-globals` (off by default); `npm update -g` uses the one-hour package-manager limit |

## What it does

1. Without `--npm-globals`: skipped.
2. `npm prefix -g` must be inside your home; a global prefix such as `/usr` or `/usr/local` (a distro Node) is refused, never written to.
3. `npm outdated -g --parseable` counts outdated packages; none ends the step.
4. `npm update -g` with `NO_UPDATE_NOTIFIER=1` and `npm_config_fund=false`.

## What will be affected

* Global packages under the active Node's global prefix, updated as `npm update -g` does it.
* With nvm, only the Node version `npm` currently resolves to; other installed versions keep their own globals.

## Dry run and `--detailed`

`--dry-run` reports `N outdated global package(s); would run npm update -g` or `all global packages up to date`. `--detailed` adds nothing beyond that.

## Warnings

* npm-installed CLIs that have their own step (Claude Code, Codex, Copilot, ...) are also updated by those steps; enabling this as well is harmless but redundant.

## Skipped / failed when

* Not enabled; npm outside the home; global prefix outside the home: skipped.
* `npm update -g` fails: failed.
