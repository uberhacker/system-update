# AnythingLLM Desktop (`anythingllm`)

Updates the [AnythingLLM](https://anythingllm.com) Desktop AppImage.

| | |
| --- | --- |
| Step name | `anythingllm` |
| Runs as | the invoking user |
| Detected when | `AnythingLLMDesktop.AppImage` is on `PATH` |
| Settings | `ALLOW_UNVERIFIED_INSTALLERS` / `--allow-unverified-installers`, `GITHUB_TOKEN` |

## What it does

1. Reads the real application version from the `.desktop` file embedded in the AppImage (`--appimage-extract '*.desktop'` into a temporary directory, `X-AppImage-Version`).
2. Compares it with the latest GitHub release of `Mintplex-Labs/anything-llm`.
3. If newer and only with `--allow-unverified-installers`: downloads `https://cdn.anythingllm.com/latest/installer.sh`, checks it parses as shell, and runs it as the user with `ANYTHING_LLM_INSTALL_DIR` set to the AppImage's directory.
4. Answers the installer's questions, which it would otherwise read from the closed stdin and exit 1:

   | Installer asks | Answer |
   | --- | --- |
   | Re-download and overwrite the existing AppImage? | `y` |
   | Create (or overwrite) the AppArmor profile? (only where AppArmor is active) | `n` |
   | Start AnythingLLM now? | `n` |

   The download gets the package manager time limit (one hour), not `TIMEOUT`.

## What will be affected

* The AppImage in its current directory, replaced by the vendor installer.
* The installer may also (re)create the desktop entry. Your workspaces and documents are not touched by this program.

## Dry run and `--detailed`

Both report `up to date (X)`, `OLD -> NEW available; ... rerun with --allow-unverified-installers`, or `would run the AnythingLLM installer into <dir> (OLD -> NEW)`.

## Warnings

* **The installer cannot be verified** (no checksum or signature is published). It only runs when you opt in with `--allow-unverified-installers`.
* Close AnythingLLM before updating: the installer writes over the AppImage in place.
* The AppArmor profile is never created or changed here, because that needs root. If AnythingLLM won't start on Ubuntu 24.04 or later, run the installer once by hand and answer `y` to the AppArmor question.
* Reading the version executes the AppImage with `--appimage-extract` (limited by `PROBE_TIMEOUT`); nothing else of the app is started.

## Skipped when

* The AppImage is not writable by the user the installer runs as (for example a root-owned copy in `/usr/local/bin`). Move it to a directory the user owns, such as `~/.local/bin`.
* The file on `PATH` resolves to a name other than `AnythingLLMDesktop.AppImage`. The installer only offers to overwrite that exact name, so the answers above would not line up.
