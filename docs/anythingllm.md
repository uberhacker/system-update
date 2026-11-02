# AnythingLLM Desktop (`anythingllm`)

Updates the [AnythingLLM](https://anythingllm.com) Desktop AppImage.

| | |
| --- | --- |
| Step name | `anythingllm` |
| Runs as | the invoking user |
| Detected when | `AnythingLLMDesktop.AppImage` is on `PATH` |
| Settings | `ALLOW_UNVERIFIED_INSTALLERS` / `--allow-unverified-installers`, `GITHUB_TOKEN`, `TIMEOUT` |

## What it does

1. Reads the real application version from the `.desktop` file embedded in the AppImage (`--appimage-extract '*.desktop'` into a temporary directory, `X-AppImage-Version`).
2. Compares it with the latest GitHub release of `Mintplex-Labs/anything-llm`.
3. If newer and only with `--allow-unverified-installers`: downloads `https://cdn.anythingllm.com/latest/installer.sh`, checks it parses as shell, and runs it as the user with `ANYTHING_LLM_INSTALL_DIR` set to the AppImage's directory.

## What will be affected

* The AppImage in its current directory, replaced by the vendor installer.
* The installer may also (re)create the desktop entry. Your workspaces and documents are not touched by this program.

## Dry run and `--detailed`

Both report `up to date (X)`, `OLD -> NEW available; ... rerun with --allow-unverified-installers`, or `would run the AnythingLLM installer into <dir> (OLD -> NEW)`.

## Warnings

* **The installer cannot be verified** (no checksum or signature is published). It only runs when you opt in with `--allow-unverified-installers`.
* Close AnythingLLM before updating.
* Reading the version executes the AppImage with `--appimage-extract` (limited by `PROBE_TIMEOUT`); nothing else of the app is started.
