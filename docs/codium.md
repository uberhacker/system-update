# VSCodium (`codium`)

Updates [VSCodium](https://vscodium.com) when it was installed from a downloaded `.deb`/`.rpm` package. Every other install method is left to the step that owns it.

| | |
| --- | --- |
| Step name | `codium` |
| Runs as | root (installs a system package) |
| Detected when | `codium` is on `PATH` |
| Distros | apt (Debian/Ubuntu), dnf and zypper; Arch is skipped (AUR) |
| Settings | `GITHUB_TOKEN`, `TIMEOUT` |

## What it does

1. Skips Flatpak and snap installs (the [flatpak](flatpak.md) / [snap](snap.md) steps update those).
2. Reads the installed version (`codium --version`) and the latest release tag of `VSCodium/vscodium`. Nothing happens if it is current.
3. Skips when `codium` is not owned by a package (tarball install), or when a configured repository provides it (apt source, `/etc/yum.repos.d` or `/etc/zypp/repos.d` mentioning codium): the system package step updates it.
4. Otherwise downloads the release asset (`codium_<version>_<arch>.deb` or `codium-<version>-el8.<arch>.rpm`) and its `.sha256`, verifies it, and installs it with `apt-get install`, `dnf install` or `zypper install`.

## What will be affected

* The `codium` system package (files under `/usr/share/codium`, `/usr/bin/codium`, desktop entry).
* Your settings and extensions in `~/.config/VSCodium` and `~/.vscode-oss` are not touched.

## Dry run and `--detailed`

Both report `would download <asset>, verify its sha256 and install it (OLD -> NEW)` or the reason it is skipped.

## Warnings

* Close VSCodium before updating; a running instance keeps the old files mapped and may misbehave until restarted.
* The installed package is not tied to a repository, so it will only be updated again by this step. Adding the VSCodium repository is the better long-term setup.
