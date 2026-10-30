# system-update

Update a Linux system with every update imaginable: the distribution's
packages, Flatpak, Snap, firmware, and the third-party developer tools that
live outside the package manager (Node via nvm, Composer, Docker Compose,
VSCodium, the AI coding CLIs, ...). One command, one summary, a non-zero exit
when anything failed.

This is a modular rewrite of [Ed Reel's](https://github.com/uberhacker)
original `system-update` script. The idea, the list of tools and most of the
update recipes are his; see [Changes from the original](#changes-from-the-original).

## What it does

```
$ sudo system-update
system-update 2.0.0 on Fedora Linux 42 (Workstation Edition) [id=fedora] package manager: dnf

▶ dnf
  ...
  ↑ dnf: 14 package(s) upgraded

▶ flatpak
  ✔ flatpak: no updates available

▶ firmware
  – firmware: 2 update(s) available; run with --firmware to apply

▶ reboot-check
  ⚠ reboot-check: reboot required: running kernel 6.14.5-300.fc42.x86_64 is no longer installed

▶ nvm
  ✔ nvm: lts/* (v22.16.0) already installed and default

▶ composer
  ↑ composer: 2.8.8 -> 2.8.9

Summary
  ↑ updated  dnf          14 package(s) upgraded
  ✔ ok       flatpak      no updates available
  – skipped  firmware     2 update(s) available; run with --firmware to apply
  ⚠ warn     reboot-check reboot required: running kernel 6.14.5-300.fc42.x86_64 is no longer installed
  ✔ ok       nvm          lts/* (v22.16.0) already installed and default
  ↑ updated  composer     2.8.8 -> 2.8.9

  2 ok, 2 updated, 1 skipped, 0 failed, 0 dry-run, 1 warning(s)
```

Every step is independent: a failing tool does not stop the others, it shows
up as `✖ failed` in the summary and makes the exit status 1. A step that
finished but needs your attention (a pending reboot, an apt source that could
not be refreshed) shows as `⚠ warn` and leaves the exit status alone.

## Supported distributions

The package manager is chosen from `ID` and `ID_LIKE` in `/etc/os-release`,
with a fallback on the managers that are actually present.

| Family | Package manager | Covers |
| --- | --- | --- |
| Debian | `apt` (`apt-get update`, `dist-upgrade`, `autoremove`) | Debian, Ubuntu, Mint, Pop!_OS, elementary, Kali, Raspberry Pi OS, ... |
| Red Hat | `dnf5`, `dnf` or `yum`, whichever exists | Fedora, RHEL, CentOS Stream, Rocky, AlmaLinux, Oracle, Amazon Linux |
| Fedora Atomic | `rpm-ostree upgrade` (or `bootc upgrade`) | Silverblue, Kinoite, Bazzite, Bluefin, Aurora, uCore |
| SUSE | `zypper dup` on Tumbleweed/Slowroll/MicroOS, `zypper update` on Leap/SLE | openSUSE, SLE |
| Arch | `pacman -Syu`; AUR via `yay`/`paru` only with `--aur` and never as root | Arch, Manjaro, EndeavourOS, Garuda, CachyOS |
| Alpine | `apk update && apk upgrade` | Alpine, postmarketOS |
| Void | `xbps-install -Su` | Void |
| Gentoo | `emerge --sync && emerge -uDN @world` (best effort) | Gentoo, Funtoo |
| NixOS | detected; prints the `nixos-rebuild` hint and skips | NixOS |

Also handled when present: Flatpak (system and per-user remotes), Snap,
firmware through `fwupdmgr` (listed by default, applied with `--firmware`),
and a reboot check (`needs-restarting`, `/var/run/reboot-required`,
`zypper needs-rebooting`, or running vs. installed kernel).

Every package manager has a real dry run: `--dry-run` only refreshes metadata
and lists what would change (`apt-get -s`, `dnf check-upgrade`,
`zypper dup --dry-run`, `checkupdates`, `apk upgrade -s`, `xbps-install -Sun`,
`rpm-ostree upgrade --check`, ...). Nothing is installed, removed or
auto-removed.

## Third-party tools

Tools are discovered on `PATH` (and, for the invoking user, in the usual
places such as `~/.nvm`, `~/.rvm`, `~/.local/bin`). Each one is updated with
its native mechanism:

| Tool | How |
| --- | --- |
| nvm / Node.js | installs the current `lts/*`, migrates global packages with `--reinstall-packages-from`, makes it the default; older versions stay unless `--prune-node` |
| nodebrew | `nodebrew install stable` + `use` |
| npm-installed CLIs: `@anthropic-ai/claude-code`, `@openai/codex`, `@github/copilot`, `@qwen-code/qwen-code`, `@kilocode/cli`, `agy`, `devin`, `grok`, `omp`, `pi`, `zcmds`, `hermes-agent` | the tool's own `update`/`upgrade` command, or the package manager that installed it (`npm`, `pnpm`, `bun`, `uv`, `pipx`, `cargo`, Homebrew, or the distro package) |
| Composer | `composer self-update` (`--stable`), `composer global update`, `cgr`, `drush-versions` |
| Terminus, WP-CLI | `terminus self:update`, `wp cli update --yes` (`--allow-root` when root) |
| Lando | `lando update -y` |
| Docker Compose | prefers the `docker compose` plugin from the distro repo; a standalone `docker-compose` binary is updated from the GitHub release with its published sha256 checked and installed with `install -m 0755` |
| VSCodium | updated through the repository when one is configured; otherwise the `.deb`/`.rpm` release asset, sha256-verified |
| AnythingLLM Desktop | AppImage version read from the file; the vendor installer is used only with `--allow-unverified-installers` |
| Ollama | `ollama` updates itself through the distro package where that is how it was installed; the vendor installer only with `--allow-unverified-installers` |
| pip tools | `pipx upgrade-all`, `uv self update`, `uv tool upgrade --all`; nothing is `pip install --upgrade`d into system Python (PEP 668) |
| AWS CLI | v2 is noted as managed by its own installer; v1 via pipx when it lives there |
| rvm | `rvm get stable` |
| vim | `git submodule update --init --remote --recursive` on `~/.vim` when it is a git checkout |

### Identification guard

A command called `kilo`, `pi`, `omp` or `codex` on your `PATH` may be a
different program than the one this script knows about (antirez's `kilo`
editor, for instance, never returns when asked for `--version`). Before a
tool is updated the script

1. works out how the binary was installed (which `npm`/`pnpm`/`bun`/`pipx`/
   `uv`/`cargo` package, Homebrew, or which distro package owns it), and
2. runs `--version` with a short timeout (`PROBE_TIMEOUT`, 20 s by default),
   stdin closed and `TERM=dumb`, and checks the answer against what the real
   tool prints.

Anything that does not match is reported as `skipped: ... does not look like
...` and left alone.

Version lookups on GitHub go through one helper with optional `GITHUB_TOKEN`
auth, rate-limit detection (a warning once, then every lookup is skipped for
the rest of the run), per-run caching, and `jq` when available with a small
built-in extractor otherwise. An unknown latest version always means "skip",
never "reinstall".

## Installation

System wide (puts `system-update` in `/usr/local/bin`, the program in
`/usr/local/lib/system-update`):

```
$ git clone https://github.com/bradvrudney/system-update.git
$ cd system-update
$ sudo ./install.sh
```

Per user (`~/.local/bin` and `~/.local/lib/system-update`):

```
$ ./install.sh --user
```

Or just run it from the checkout: `./system-update`. `install.sh --uninstall`
removes either installation. The checkout's `.git` directory is copied along
so that `--self-update` can pull later.

Requirements: bash 4.4 or newer and GNU `coreutils` (`timeout`, `install`,
`sha256sum`). `curl` is needed for GitHub release lookups and downloads
(without it those steps are skipped with a warning); `jq` is optional.

## Usage

```
Usage: system-update [OPTIONS]

Options:
  -n, --dry-run           show what would be updated; change nothing (-d is an alias)
  -y, --yes               non-interactive (package managers already never prompt)
      --only LIST         run only these steps (comma separated; see --list)
      --skip LIST         skip these steps (comma separated)
      --list              show detected distro, package manager and tools, then exit
  -v, --verbose           show every command that is run
  -q, --quiet             hide third-party output; show only status and summary
      --no-color          disable colours (NO_COLOR and non-TTY output do too)
      --color WHEN        auto (default), always or never
      --timeout SECONDS   per-command timeout for third-party tools (default 300)
      --config FILE       read this config file instead of the user config
      --firmware          apply firmware updates with fwupd (default: list only)
      --prune-node        remove Node.js versions other than the new default (nvm/nodebrew)
      --install-jq        allow installing jq with the package manager when missing
      --allow-unverified-installers
                          allow vendor "curl | sh" installers (ollama, AnythingLLM)
      --aur               run an AUR helper (yay/paru) as the invoking user on Arch
      --no-autoremove     do not remove orphaned packages after upgrading
      --self-update       update this script from its git source and exit
      --source URL        git source for --self-update (https only)
      --branch NAME       branch for --self-update (default: the remote's default branch)
      --version           print the version and exit
  -h, --help              show this help and exit
```

Step names for `--only` and `--skip`: `system` (or the package manager's
name: `apt`, `dnf`, `zypper`, `pacman`, `apk`, `xbps`, `emerge`,
`rpm-ostree`), `flatpak`, `snap`, `firmware`, `reboot-check`, `tools`, and
any tool name shown by `--list`.

The script never prompts. Package managers run with their non-interactive
flags (`-y`, `--noconfirm`, `--non-interactive`, `DEBIAN_FRONTEND=noninteractive`
with `--force-confold`), third-party tools run with stdin closed and a
timeout, so it is safe in cron, systemd timers and CI. `--yes` exists for
habit and compatibility.

### Privileges

Run it as yourself. Steps that need root (`apt`, `dnf`, system Flatpak
remotes, firmware, installing to `/usr/local/bin`) use `sudo`, asked for once
at the start; everything else runs as you. Run with `sudo system-update` and
the user-level tools (nvm, Composer, npm globals, per-user Flatpaks, ...) are
still updated as the invoking user (`SUDO_USER`), in a child process with that
user's `HOME` and `PATH`. As plain root with no `SUDO_USER` the tools are
updated in root's own home, with a warning.

Nothing in the script ever disables signature or TLS verification, downloads
without a checksum, `chown`s system directories, or runs `curl | sh` without
`--allow-unverified-installers`.

### Examples

```
$ system-update --dry-run                 # show everything that would change
$ system-update                           # update everything
$ system-update --only apt,flatpak        # just the distro packages and Flatpak
$ system-update --skip tools              # no third-party tools this time
$ system-update --only nvm --prune-node   # new LTS, remove the old versions
$ system-update --firmware                # also apply fwupd updates
$ system-update --list                    # what would be touched, nothing runs
$ system-update --quiet                   # status lines and summary only
```

## Configuration

Settings come, lowest precedence first, from built-in defaults,
`/etc/system-update.conf`, `${XDG_CONFIG_HOME:-~/.config}/system-update/config`
(or `--config FILE`), environment variables of the same name, and command
line flags. Files are `KEY=value` lines that are parsed, never sourced, so
nothing in them can run code; unknown keys and invalid values are reported and
ignored. See [`config.example`](config.example).

| Key | Default | Meaning |
| --- | --- | --- |
| `SELF_UPDATE_REPO` | `https://github.com/bradvrudney/system-update` | git source for `--self-update` (https only) |
| `SELF_UPDATE_BRANCH` | empty | branch for `--self-update`; empty follows the checkout's branch if the remote has it, else the remote's default branch (`master` here) |
| `SKIP` / `ONLY` | empty | comma separated step names |
| `TIMEOUT` | `300` | seconds a third-party tool may run |
| `PROBE_TIMEOUT` | `20` | seconds a `--version` probe may take |
| `GITHUB_TOKEN` | empty | raises the GitHub API rate limit (`GH_TOKEN` is accepted too) |
| `COLOR` | `auto` | `auto`, `always`, `never` |
| `INSTALL_JQ` | `0` | install `jq` with the package manager when missing |
| `ALLOW_UNVERIFIED_INSTALLERS` | `0` | allow vendor `curl \| sh` installers |
| `FIRMWARE` | `0` | apply fwupd updates instead of listing them |
| `PRUNE_NODE` | `0` | remove other Node.js versions after installing the LTS |
| `AUR_HELPER` | `0` | run `yay`/`paru` as the invoking user on Arch |
| `AUTOREMOVE` | `1` | remove orphaned packages after upgrading |

## Self-update

`system-update --self-update` updates the program itself and exits:

* In a git checkout: `git fetch` and `git pull --ff-only` on the configured
  branch. It refuses to touch a checkout with local changes, a different
  `origin` (unless `--source` says so), or a branch the remote does not have,
  and never runs `git reset --hard`.
* Installed without `.git`: downloads the branch tarball from the
  `SELF_UPDATE_REPO` over https, checks that it looks like this program
  (`bin/system-update` present, every file passes `bash -n`), and swaps the
  directories atomically.

To follow Ed Reel's original repository instead:

```
$ system-update --self-update --source https://github.com/uberhacker/system-update
```

## Development

```
$ tests/lint.sh          # bash -n and shellcheck -x on everything
$ tests/run.sh           # bats unit tests (bats-core is fetched into tests/vendor if missing)
$ tests/containers.sh    # the real thing inside stock distro containers (needs docker)
```

The unit tests cover OS detection against `/etc/os-release` fixtures, the
config parser (including hostile values), argument handling, colour and icon
selection, the JSON fallback, the GitHub helper against a stubbed `curl`
(rate limits, null fields, annotated tags), the step runner and exit codes,
the tool identification guard (a hanging `kilo` editor, a `pi` that is not
Pi), nvm against a stubbed `nvm.sh`, and self-update against a local bare
repository. `tests/containers.sh` runs `--list`, `--dry-run`, a real `--yes`
run (after downgrading one package so there is something to upgrade), the
same as a non-root user with `sudo`, an unreachable apt source (a warning,
not a failure), a stand-alone `docker-compose` updated from the real GitHub
release (downloaded, sha256-verified, `install -m 0755`), and the `kilo`
guard inside Ubuntu, Debian, Fedora, Rocky,
Arch, openSUSE Tumbleweed and Leap, and Alpine. The GitHub Actions workflow
in `.github/workflows/ci.yml` runs all three.

Adding a tool is one file in `lib/tools/`:

```bash
#!/usr/bin/env bash
# lib/tools/foo.sh
tool_foo_detect() { have foo; }
tool_foo_update() {
  tool_standard foo foo '^foo [0-9]' 'npm:foo' --version -- foo self-update
}
```

`tool_<name>_detect` says whether the tool is present, `tool_<name>_update`
updates it and reports through `log_ok`/`log_updated`/`log_skipped`/`log_warn`
or returns non-zero to mark the step failed. `tool_standard` wraps the usual
case: identify the binary (expected install method and `--version` pattern),
run the tool's own update command, compare versions before and after.
Optional `tool_<name>_scope` returns `system` for tools that live in
`/usr/local/bin` (updated as root) rather than in the user's home.

## Changes from the original

Ed Reel's `system-update` was a single script that grew one tool at a time;
this version keeps its spirit and most of its recipes, restructured so it can
be trusted on any distribution:

* `lib/core`, `lib/pkg`, `lib/tools` modules instead of one file; tools are
  auto-discovered, so adding one does not touch the main flow.
* Distribution detection from `/etc/os-release` instead of a short list of
  names; `dnf5`/`yum`, `zypper dup` vs `update`, `pacman`, `apk`, `xbps`,
  `emerge`, `rpm-ostree`, Flatpak, Snap, fwupd and a reboot check.
* A dry run for everything, not only `apt`.
* Per-step results, a summary and a meaningful exit status.
* Tool identification before updating (the `kilo` problem), timeouts and
  closed stdin everywhere.
* Verified downloads (`sha256`) and `install -m 0755` instead of
  `chmod 777`/`chown` of system directories; no disabled signature checks.
* One GitHub API helper with token support, rate-limit handling and a fix
  for annotated tags in the release-commit lookup.
* `nvm` keeps the current LTS and migrates global packages instead of
  installing every LTS line; old versions are removed only with `--prune-node`.
* pip-installed tools through `pipx`/`uv` rather than `pip install --upgrade`
  into the system interpreter; AWS CLI v2 is left to its own installer.
* Vendor `curl | sh` installers (Ollama, AnythingLLM) are opt-in.
* Config file, environment and flags; `--self-update`; `install.sh`; unit and
  container tests; CI.

Thanks to Ed Reel ([@uberhacker](https://github.com/uberhacker)) for the
original and for years of keeping it current.

## License

GPL-3.0, as the original. See [LICENSE](LICENSE).
