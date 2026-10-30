# uv (`uv`)

Updates [uv](https://docs.astral.sh/uv/) itself and every tool installed with `uv tool install`.

| | |
| --- | --- |
| Step name | `uv` |
| Runs as | the invoking user |
| Detected when | `uv` is on `PATH` |
| Settings | `TIMEOUT` |

## What it does

1. **uv itself**: `uv self update`, unless uv came from a distro package, `pipx` or `uv` (then the note says so and that method updates it). An install whose updater says self-update is unavailable is reported, not failed.
2. **uv tools**: `uv tool upgrade --all` when the tool directory (`$UV_TOOL_DIR`, default `~/.local/share/uv/tools`) exists.

## What will be affected

* The `uv` and `uvx` binaries of a standalone install (usually `~/.local/bin`).
* Each tool environment under the uv tool directory, upgraded within the constraints it was installed with.

## Dry run and `--detailed`

`--dry-run` reports `would run uv self update; would run uv tool upgrade --all`.

`--detailed` also lists the tools that would change from `uv tool list --outdated` (read-only; needs a uv recent enough to have `--outdated`, otherwise the list is simply empty).

## Warnings

* Tools installed with a version constraint (`uv tool install 'ruff<0.5'`) stay within it; others move to their newest release, including major versions.
