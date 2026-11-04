# Ollama (`ollama`)

Updates [Ollama](https://ollama.com). A distro-packaged Ollama is left to the system packages; otherwise the vendor installer is the only update path.

| | |
| --- | --- |
| Step name | `ollama` |
| Runs as | root (the vendor installer needs it) |
| Detected when | `ollama` is on `PATH` |
| Settings | `ALLOW_UNVERIFIED_INSTALLERS` / `--allow-unverified-installers`, `GITHUB_TOKEN`, `TIMEOUT` |

## What it does

1. A binary owned by a distro package: skipped (updated with the system packages).
2. Reads the installed version from `ollama -v` and the latest GitHub release of `ollama/ollama`. `ollama -v` prints the running server's version first and adds `Warning: client version is X` when the binary on disk differs; the installed version is the client's. Nothing is installed if it is current.
3. Runs the vendor installer only with `--allow-unverified-installers`. Without it the step is skipped with the versions, and says when Ollama was evidently installed by that installer (`/etc/systemd/system/ollama.service` exists and the binary is under `/usr/local` or `/usr/bin` without a package owner).
4. Downloads `https://ollama.com/install.sh`, checks it parses as shell, and runs it as root.
5. Reads the version again. Still the old one: the step fails (`the installer finished but ollama is still X`).
6. A server still answering with the old version (the installer restarts it only through systemd, so this happens on SysV init systems such as MX Linux): restarted with `/etc/init.d/ollama restart` when that script exists and systemd is not running; otherwise the step warns `the running ollama server is still X; restart it (stop it and run ollama serve) to use Y`. The same warning shows on a later run when the binary is current but an old server is still running.

## What will be affected

The installer is Ollama's own script, not this program's. It typically:

* replaces the `ollama` binary and its libraries under `/usr/local` (or `/usr`);
* creates or updates the `ollama` system user and the `ollama.service` systemd unit, and restarts the service, interrupting running models;
* on machines with an NVIDIA or AMD GPU, may install or update GPU runtime libraries.

Downloaded models (in `/usr/share/ollama/.ollama` or `~/.ollama`) are not removed. Nothing is `chown`ed by this program afterwards.

## Dry run and `--detailed`

Both report `would run the ollama installer as root (OLD -> NEW)`, or `OLD -> NEW available; ... rerun with --allow-unverified-installers` when the installer is not allowed.

## Warnings

* **The installer is downloaded over HTTPS but cannot be verified** (Ollama publishes no checksum or signature for it). Running it means trusting ollama.com at that moment.
* The service restart stops in-flight requests.
* Without systemd, a server you started yourself (`ollama serve`) is not stopped by this program; restart it to use the new version.

## Skipped when

* Owned by a distro package; `--allow-unverified-installers` not given; no `sudo`; version unreadable; latest release unknown.
