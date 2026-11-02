# GitHub CLI extensions (`gh-extensions`)

Upgrades the extensions installed in the GitHub CLI (`gh extension upgrade --all`). `gh` itself comes from a package manager and is not updated here.

| | |
| --- | --- |
| Step name | `gh-extensions` |
| Runs as | the invoking user |
| Detected when | `gh` is on `PATH` and its extensions directory exists (`$GH_DATA_DIR/extensions`, default `~/.local/share/gh/extensions`) |
| Settings | `TIMEOUT` |

## What it does

1. `gh extension list`. Not authenticated: skipped with `run gh auth login`. No extensions: skipped.
2. `gh extension upgrade --all`.

Every `gh` call runs with `GH_NO_UPDATE_NOTIFIER=1`, `GH_PROMPT_DISABLED=1`, `GH_PAGER=cat` and `NO_COLOR=1`.

## What will be affected

* Each extension under the extensions directory moves to its latest release (binary extensions) or latest commit (script extensions). Extensions pinned with `gh extension install --pin` are left at their pin by gh.

## Dry run and `--detailed`

`--dry-run` runs `gh extension upgrade --all --dry-run` and reports how many extensions would be upgraded. `--detailed` adds nothing beyond that.

## Warnings

* Extensions are third-party code from their authors' repositories; an upgrade runs whatever the new version contains.

## Skipped / failed when

* gh is not authenticated, or no extensions are installed: skipped.
* `gh extension upgrade --all` fails for another reason: failed.
