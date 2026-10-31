# system-update

**One command to bring a whole Linux workstation up to date** - not just the
distribution's packages, but everything else that quietly goes stale next to
them: Flatpaks and snaps, device firmware, Node.js and Rust toolchains,
Homebrew, global npm and Composer packages, pipx and uv tools, shell and
editor plugins, standalone binaries such as Docker Compose, cloudflared and
the Azure CLI, and the growing list of AI coding CLIs (Claude Code, Codex,
Copilot, Qwen, Kilo, ...) that each have their own way of updating.

```
$ system-update --detailed      # see every package that would change, old -> new
$ system-update                 # update all of it, then print one summary
```

On a typical developer machine that replaces a dozen commands run by hand
(`sudo dnf upgrade`, `flatpak update`, `fwupdmgr get-updates`,
`nvm install --lts`, `npm i -g ...@latest`, `composer self-update`,
`pipx upgrade-all`, `claude update`, ...) and the habit of forgetting half of
them. It is plain bash (4.4 or newer) with coreutils, grep and sed, plus
`curl` for downloads, and it is safe to run from cron or a systemd timer.

This is a modular rewrite of [Ed Reel's](https://github.com/uberhacker)
original `system-update` script. The idea, the list of tools and most of the
update recipes are his; see [Changes from the original](#changes-from-the-original).

### Highlights

* **Nine distribution families** detected from `/etc/os-release`: Debian and
  Ubuntu, Fedora and RHEL clones, Fedora Atomic (rpm-ostree/bootc), openSUSE,
  Arch, Alpine, Void, Gentoo, and NixOS (detected, left to you).
* **42 third-party tool steps**, each updated the way it was installed:
  through npm, pnpm, bun, pipx or uv when that is where it came from, with
  its own self-update command otherwise, or from a checksum-verified GitHub
  release.
* **A real dry run for everything**, and `--detailed` to list every package,
  app, plugin and tool that would change with its installed and new version.
* **One summary, one exit status.** Every step is independent; a failure is
  reported and the run continues. Exit 0 means nothing failed.
* **A full log of every run**, with each command's complete output, exit
  status and timing, for when the summary is not enough.
* **Careful by default.** It never prompts, never disables signature or TLS
  checks, verifies every download, refuses to touch a binary it cannot
  identify, runs user tools as the user even under `sudo`, and keeps
  irreversible or risky actions (firmware, pruning old Node versions, AUR
  builds, unverified vendor installers) behind explicit flags.
* **Documented step by step.** Every step has a page in [`docs/`](docs/README.md)
  saying exactly what it runs, what it changes, and what to watch out for.

### How a run works

1. **Detect.** Read `/etc/os-release` to pick the package manager, then look
   for each supported tool on the invoking user's `PATH` and in the usual
   places (`~/.nvm`, `~/.rvm`, `~/.local/bin`, ...). `--list` stops here and
   shows what was found.
2. **Ask for `sudo` once**, up front, if a step needs root, so a long run is
   never interrupted by a password prompt.
3. **Run the steps in order:** system packages, Flatpak, Snap, firmware, the
   third-party tools, and finally the reboot check. Each one prints its own
   section and a one-line result.
4. **Summarise.** A table of every step's result, the totals, the exit
   status, and where the run's log was written.

## Contents

* [Quick start](#quick-start)
* [What it does](#what-it-does)
* [Before you run it](#before-you-run-it)
* [Dry run and `--detailed`](#dry-run-and---detailed)
* [System packages](#system-packages) and [extras](#flatpak-snap-firmware-and-the-reboot-check)
* [Third-party tools](#third-party-tools)
* [Installation](#installation), [single file](#single-file) and [tab completion](#tab-completion)
* [Usage](#usage), [privileges](#privileges) and [examples](#examples)
* [Configuration](#configuration) · [Logs](#logs) · [Self-update](#self-update)
* [Running it unattended](#running-it-unattended) · [Troubleshooting](#troubleshooting)
* [Development](#development)

## Quick start

```
$ git clone https://github.com/bradvrudney/system-update.git
$ cd system-update
$ ./system-update --list         # what was detected; nothing runs
$ ./system-update --detailed     # every package and tool that would change, old -> new
$ ./system-update                # do it
```

Run it as yourself, not with `sudo`: it asks for your password once when a
step needs root and updates your own tools as you. `./install.sh` puts it on
your `PATH` (see [Installation](#installation)); after that it is just
`system-update`.

## What it does

```
$ system-update
system-update 2.0.0 on Fedora Linux 42 (Workstation Edition) [id=fedora] package manager: dnf

▶ dnf
  ...
  ↑ dnf: 14 package(s) upgraded

▶ flatpak
  ✔ flatpak: no updates available

▶ firmware
  ✔ firmware: 2 firmware update(s) available (not applied; use --firmware)

▶ nvm
  ✔ nvm: default is v22.16.0

▶ composer
  ↑ composer: 2.8.8 -> 2.8.9; self-update ok; global update ok

▶ reboot-check
  ⚠ reboot-check: reboot required: running kernel 6.14.5-300.fc42.x86_64 is no longer installed

Summary
  ↑ updated  dnf          14 package(s) upgraded
  ✔ ok       flatpak      no updates available
  ✔ ok       firmware     2 firmware update(s) available (not applied; use --firmware)
  ✔ ok       nvm          default is v22.16.0
  ↑ updated  composer     2.8.8 -> 2.8.9; self-update ok; global update ok
  ⚠ warn     reboot-check reboot required: running kernel 6.14.5-300.fc42.x86_64 is no longer installed

  3 ok, 2 updated, 0 skipped, 0 failed, 0 dry-run, 1 warning(s)
```

The steps run in this order: system packages, Flatpak, Snap, firmware, the
third-party tools, and finally the reboot check. Every step is independent:

| Result | Meaning | Exit status |
| --- | --- | --- |
| `✔ ok` | nothing needed doing, or it was already current | unchanged |
| `↑ updated` | something was installed or upgraded | unchanged |
| `– skipped` | not applicable, not installed, or deliberately left alone (the note says why) | unchanged |
| `◦ dry-run` | what would happen; nothing was changed | unchanged |
| `⚠ warn` | finished, but needs your attention (a pending reboot, an apt source that could not be refreshed) | unchanged |
| `✖ failed` | the step's command failed; the other steps still run | **1** |

The exit status is 0 unless a step failed, and 2 for a usage error.

## Before you run it

A real run changes a lot at once. The per-step pages list everything; the
short version:

* **System packages are fully upgraded**, the way the distribution intends:
  `apt-get dist-upgrade`, `dnf upgrade`, `zypper dup` on Tumbleweed,
  `pacman -Syu`. That can install new packages (kernels) and, with apt and
  zypper `dup`, remove packages to resolve dependencies.
* **Orphaned packages are removed** afterwards (`apt-get autoremove --purge`,
  `dnf autoremove`, `pacman -Rns $(pacman -Qtdq)`, `xbps-remove -Oo`,
  `emerge --depclean`). Use `--no-autoremove` to keep them.
* **Nothing prompts.** Package managers run with their non-interactive
  flags; on Debian your changed configuration files are kept
  (`--force-confold`) and services may be restarted by `needrestart`.
* **Third-party tools move to their latest release**, including new major
  versions (Docker Compose, global Composer and pipx packages, uv tools).
  Node.js moves to the new LTS line through nvm and becomes the default for
  new shells.
* **Some things only happen when you ask:** applying firmware
  (`--firmware`), removing old Node versions (`--prune-node`), AUR packages
  (`--aur`), vendor `curl | sh` installers for Ollama and AnythingLLM
  (`--allow-unverified-installers`), and the opt-in steps: Neovim plugins
  (`--nvim-plugins`), mise/asdf runtimes (`--runtimes`), global npm packages
  (`--npm-globals`), the Go toolchain in `/usr/local/go` (`--go-toolchain`)
  and container images (`--containers`). Read their pages before turning
  them on: `--go-toolchain` replaces all of `/usr/local/go`, `--runtimes`
  rewrites the pins in your home `~/.tool-versions` for asdf, and
  `--containers` re-pulls every image used by an existing container (a large
  download) and lets `podman auto-update` restart the units that opted in.
* **A reboot may be needed** afterwards (new kernel, staged rpm-ostree
  deployment, firmware). The reboot check reports it; nothing reboots
  automatically.
* **Some things are never done:** distribution release upgrades (Fedora 43
  to 44, Debian 12 to 13, Alpine 3.20 to 3.21), NixOS rebuilds, disabling
  signature or TLS checks, downloads without a checksum, `chown` of system
  directories.

Run `system-update --detailed` first to see exactly what would change.

## Dry run and `--detailed`

`--dry-run` (`-n`) runs every step in a mode that changes nothing: package
managers only refresh metadata and simulate (`apt-get -s`,
`dnf check-upgrade`, `zypper --dry-run`, `checkupdates`, `apk upgrade -s`,
`xbps-install -Sun`, `emerge --pretend`, `rpm-ostree upgrade --check`), and
each tool reports what it would run. Nothing is installed, removed or
auto-removed. A user without `sudo` rights can dry-run apt, dnf, pacman and
emerge too: their simulations run as that user with the cached package
lists (zypper, rpm-ostree, apk and xbps need root even to check). A few steps refresh metadata the same way to find out what
is pending: `brew update` (Homebrew's formula index) and `git fetch` in the
Oh My Zsh / Oh My Bash checkouts. Those only update indexes and
remote-tracking refs, never installed software.

`--detailed` is a dry run that also lists **each package, application or
plugin that would change, with its installed and new version**:

```
$ system-update --detailed --only apt,flatpak,nvm,docker-compose
dry run (detailed): nothing will be changed

▶ apt
  ...
  ◦ 4 package(s) would change:
      base-files                    13ubuntu10.4    -> 13ubuntu10.5
      libc6                         2.39-0ubuntu8.8 -> 2.39-0ubuntu8.9
      libfoo1                       1.2-3           -> (removed)
      linux-image-6.8.0-90-generic  (new)           -> 6.8.0-90.91
  ◦ apt: 3 package(s) would be upgraded/installed (2 upgraded, 1 newly installed, 1 to remove and 0 not upgraded.)

▶ flatpak
  ◦ 3 system flatpak(s) would change:
      com.github.jeromerobert.pdfarranger//stable  1.14.0 -> 1.14.0 (new build)
      org.freedesktop.Platform.GL.default//24.08   ?      -> (new build)
      org.gimp.GIMP//stable                        3.0.4  -> 3.0.6
  ◦ flatpak: system: 3 update(s) available

▶ nvm
  ◦ nvm: would install v24.11.0 (migrating global packages from v22.21.1) and set default to lts/*

▶ docker-compose
  ◦ docker-compose: would download docker-compose-linux-x86_64 v5.6.1, verify its sha256 and install it to /usr/local/bin/docker-compose (2.33.1 -> 5.6.1)
```

`(new)` is a package that would be installed, `(removed)` one that would be
removed, `(new build)` a new build of the same version, and `?` a version
that could not be determined.

| Step | Where the list comes from |
| --- | --- |
| [apt](docs/apt.md) | the `Inst`/`Remv` lines of `apt-get -s dist-upgrade` |
| [dnf](docs/dnf.md) | `check-upgrade`, with installed versions from `rpm -q` |
| [zypper](docs/zypper.md) | `zypper dup`/`update --dry-run --details` |
| [pacman](docs/pacman.md) | `checkupdates` or `pacman -Qu` against a temporary database |
| [apk](docs/apk.md) | `apk upgrade -s` |
| [xbps](docs/xbps.md) | `xbps-install -Sun`, with installed versions from `xbps-query` |
| [emerge](docs/emerge.md) | `emerge --pretend` |
| [rpm-ostree](docs/rpm-ostree.md) | `rpm-ostree upgrade --preview` (bootc images: no package list) |
| [flatpak](docs/flatpak.md) | `flatpak remote-ls --updates` joined with `flatpak list` |
| [snap](docs/snap.md) | `snap refresh --list` joined with `snap list` |
| [firmware](docs/firmware.md) | `fwupdmgr get-updates` (current and new version per device) |
| npm-installed CLIs, [claude](docs/claude.md), [codex](docs/codex.md), ... | `npm view <package> version` |
| pipx / `uv tool` installed CLIs, [pip](docs/pip.md) | PyPI's JSON API (needs `jq`; see `--install-jq`) |
| [uv](docs/uv.md) | `uv tool list --outdated` |
| [composer](docs/composer.md) | `composer global outdated --direct`, Composer's latest GitHub release |
| [terminus](docs/terminus.md), [wp-cli](docs/wp-cli.md), [rvm](docs/rvm.md), [docker-compose](docs/docker-compose.md), [codium](docs/codium.md), [ollama](docs/ollama.md), [anythingllm](docs/anythingllm.md) | the latest GitHub release |
| [nvm](docs/nvm.md), [nodebrew](docs/nodebrew.md) | the Node.js release index |
| [vim](docs/vim.md) | `git ls-remote` per submodule (commits, not versions) |

All lookups are read-only. They do cost network requests (one per pipx
package or vim plugin, for instance) and GitHub API calls, so set
`GITHUB_TOKEN` if you run `--detailed` often. Tools that update themselves
through their own installer (`agy update`, `grok update`, ...) do not
publish their latest version anywhere this program can ask; for those only
the installed version is shown. `--quiet` hides the lists along with the
rest of the per-step output.

## System packages

The package manager is chosen from `ID` and `ID_LIKE` in `/etc/os-release`,
with a fallback on the managers that are actually present. Step name:
`system`, or the manager's name.

| Family | Manager | Covers | Details |
| --- | --- | --- | --- |
| Debian | `apt-get update`, `dist-upgrade`, `autoremove --purge` | Debian, Ubuntu, Mint, Pop!_OS, elementary, Kali, Raspberry Pi OS, ... | [docs/apt.md](docs/apt.md) |
| Red Hat | `dnf5`, `dnf` or `yum`: `upgrade`, `autoremove` | Fedora, RHEL, CentOS Stream, Rocky, AlmaLinux, Oracle, Amazon Linux | [docs/dnf.md](docs/dnf.md) |
| Fedora Atomic | `rpm-ostree upgrade` or `bootc upgrade` (staged, applied on reboot) | Silverblue, Kinoite, Bazzite, Bluefin, Aurora, uCore, CoreOS | [docs/rpm-ostree.md](docs/rpm-ostree.md) |
| SUSE | `zypper dup` on Tumbleweed/Slowroll/MicroOS, `zypper update` on Leap/SLE | openSUSE, SLE | [docs/zypper.md](docs/zypper.md) |
| Arch | `pacman -Syu`; AUR via `yay`/`paru` only with `--aur` and never as root | Arch, Manjaro, EndeavourOS, Garuda, CachyOS | [docs/pacman.md](docs/pacman.md) |
| Alpine | `apk update && apk upgrade` | Alpine, postmarketOS | [docs/apk.md](docs/apk.md) |
| Void | `xbps-install -Su` | Void | [docs/xbps.md](docs/xbps.md) |
| Gentoo | `emerge --sync && emerge -uDN @world` (best effort) | Gentoo, Funtoo | [docs/emerge.md](docs/emerge.md) |
| NixOS | detected; prints the `nixos-rebuild` hint and skips | NixOS | [docs/nix.md](docs/nix.md) |

### Flatpak, Snap, firmware and the reboot check

| Step | What it does | Details |
| --- | --- | --- |
| `flatpak` | `flatpak update` for the system installation (as root) and the invoking user's own | [docs/flatpak.md](docs/flatpak.md) |
| `snap` | `snap refresh` when snapd is running | [docs/snap.md](docs/snap.md) |
| `firmware` | `fwupdmgr refresh` and `get-updates`; applies them only with `--firmware` | [docs/firmware.md](docs/firmware.md) |
| `reboot-check` | `needs-restarting`, `/var/run/reboot-required`, `zypper needs-rebooting`, a staged ostree deployment, or a running kernel that is no longer installed; reports, never reboots | [docs/reboot-check.md](docs/reboot-check.md) |

## Third-party tools

Tools are discovered on the invoking user's `PATH` (and in the usual places
such as `~/.nvm`, `~/.rvm`, `~/.local/bin`) and updated with their native
mechanism. A tool that is not installed is simply not shown. Step name: the
first column (also the group name `tools` for all of them).

| Step | Tool | How it is updated | Runs as | Notes |
| --- | --- | --- | --- | --- |
| [`nvm`](docs/nvm.md) | Node.js via nvm | installs the current LTS with `--reinstall-packages-from`, makes it the default | user | old versions kept unless `--prune-node` |
| [`nodebrew`](docs/nodebrew.md) | Node.js via nodebrew | newest release of the current major, `migrate-package`, `use` | user | old version kept unless `--prune-node` |
| [`claude`](docs/claude.md) | Claude Code | npm/pnpm/bun package, or `claude update` | user | |
| [`codex`](docs/codex.md) | OpenAI Codex CLI | npm package, or `codex update` | user | |
| [`copilot`](docs/copilot.md) | GitHub Copilot CLI | npm package, or `copilot update` | user | |
| [`qwen`](docs/qwen.md) | Qwen Code | npm package, or `qwen update` | user | |
| [`kilo`](docs/kilo.md) | Kilo Code CLI | npm package, or `kilo upgrade` | user | antirez's `kilo` editor is recognised and left alone |
| [`agy`](docs/agy.md), [`devin`](docs/devin.md), [`grok`](docs/grok.md), [`omp`](docs/omp.md), [`pi`](docs/pi.md) | agent CLIs | the package manager that installed them, or `<tool> update` | user | identified by `--version` output |
| [`hermes`](docs/hermes.md) | Hermes Agent | `uv tool`/`pipx`, or `hermes update` | user | |
| [`zcmds`](docs/zcmds.md) | zcmds | `pipx upgrade` / `uv tool upgrade` | user | |
| [`lando`](docs/lando.md) | Lando | `lando update -y` | user | |
| [`composer`](docs/composer.md) | Composer | `self-update`, `global update`, `cgr update`, `drush-versions up` | user; `self-update` as root for a root-owned phar | global packages can move to new majors |
| [`terminus`](docs/terminus.md) | Pantheon Terminus | `terminus self:update` | user, or root for a root-owned phar | |
| [`wp-cli`](docs/wp-cli.md) | WP-CLI | `wp cli update --yes` | user, or root for a root-owned phar | WordPress sites are not touched |
| [`docker-compose`](docs/docker-compose.md) | standalone Docker Compose | GitHub release, sha256-verified, `install -m 0755` | user or root, whoever can write the binary | the `docker compose` plugin is left to the package manager |
| [`codium`](docs/codium.md) | VSCodium | `.deb`/`.rpm` release asset, sha256-verified, installed with the package manager | root | only when no repository provides it |
| [`ollama`](docs/ollama.md) | Ollama | vendor installer | root | only when it installed Ollama, or with `--allow-unverified-installers` |
| [`anythingllm`](docs/anythingllm.md) | AnythingLLM Desktop | vendor installer | user | only with `--allow-unverified-installers` |
| [`pip`](docs/pip.md) | pipx, user pip, AWS CLI | `pipx upgrade-all`; pip only outside PEP 668 | user | nothing is installed into system Python |
| [`uv`](docs/uv.md) | uv | `uv self update`, `uv tool upgrade --all` | user | |
| [`rvm`](docs/rvm.md) | RVM | `rvm get stable` | user | Rubies and gems are not changed |
| [`vim`](docs/vim.md) | Vim plugins | `git submodule update --init --remote --recursive` in `~/.vim` | user | leaves `~/.vim` with uncommitted submodule changes |

A tool owned by a distro package (for example a `pi` or `copilot` from
`apt`/`dnf`) is skipped: the system package step already updates it.
| [`rustup`](docs/rustup.md) | Rust toolchains | `rustup self update` (not for distro/Homebrew rustup), `rustup update --no-self-update` | user | |
| [`cargo`](docs/cargo.md) | crates installed with `cargo install` | `cargo install-update -a` when the `cargo-update` crate is installed | user | tools under `~/.cargo/bin` are routed here |
| [`brew`](docs/brew.md) | Homebrew on Linux | `brew update`, `brew upgrade`, `brew autoremove` | user, never root | |
| [`gh-extensions`](docs/gh-extensions.md) | GitHub CLI extensions | `gh extension upgrade --all` | user | skipped when none are installed or `gh` is not logged in |
| [`azure-cli`](docs/azure-cli.md) | Azure CLI | `az upgrade --yes --all false` | user | only when `az` is not a distro/Microsoft-repo package |
| [`bicep`](docs/bicep.md) | Bicep | `az bicep upgrade`, or a standalone binary from the release when a sha256 is published | user for a copy in your home, otherwise root | |
| [`cloudflared`](docs/cloudflared.md) | cloudflared | GitHub release, sha256-verified, `install -m 0755` | user or root, whoever can write the binary | a copy from Cloudflare's repository is left to the system step |
| [`oh-my-zsh`](docs/oh-my-zsh.md), [`oh-my-bash`](docs/oh-my-bash.md) | Oh My Zsh, Oh My Bash | their own `tools/upgrade.sh`, non-interactively | user | |
| [`tpm`](docs/tpm.md) | tmux plugins | `~/.tmux/plugins/tpm/bin/update_plugins all` | user | |
| [`mise`](docs/mise.md) | mise | `mise self-update --yes`, `mise plugins update`; runtimes with `--runtimes` | user | runtimes stay within their configured specs |
| [`asdf`](docs/asdf.md) | asdf | `asdf update` (bash asdf), `asdf plugin update --all`; runtimes with `--runtimes` | user | the Go asdf has no self-update |
| [`nvim-plugins`](docs/nvim-plugins.md) | Neovim plugins | lazy.nvim `Lazy! sync`, `PackerSync` or `PlugUpdate`, headless | user | **opt-in**: `--nvim-plugins` |
| [`npm-globals`](docs/npm-globals.md) | global npm packages | `npm update -g` under the user's own Node | user | **opt-in**: `--npm-globals`; never a system prefix |
| [`go`](docs/go.md) | Go in `/usr/local/go` | latest stable from go.dev, sha256-verified, swapped in atomically | root, unless you can write `/usr/local` | **opt-in**: `--go-toolchain` |
| [`containers`](docs/containers.md) | distrobox, toolbox, podman, docker | `distrobox upgrade --all`, package manager inside each toolbox, `podman auto-update`, image re-pulls | user | **opt-in**: `--containers`; containers are never recreated or restarted |

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
`/usr/local/share/system-update`):

```
$ git clone https://github.com/bradvrudney/system-update.git
$ cd system-update
$ sudo ./install.sh
```

Per user (`~/.local/bin` and `~/.local/share/system-update`):

```
$ ./install.sh --user
```

Or just run it from the checkout: `./system-update`. `install.sh --prefix
DIR` installs under `DIR/bin` and `DIR/share`, and `install.sh --uninstall`
(with the same `--user`/`--prefix`) removes an installation. The checkout's
`.git` directory is copied along so that `--self-update` can pull later.

A system-wide installation is owned by root (the installer `chown`s it),
because it is run with `sudo` and its completion file is sourced by every
shell, including root's: no user account can edit it. `--self-update` of
such an installation asks for `sudo` once. A `--user` installation is yours.

### Single file

The whole program also comes as **one executable file**, handy for copying
to a server, a container or a USB stick. It is the same bash code with every
module inlined (nothing is compiled), so it needs the same bash 4.4 and
coreutils, and it behaves exactly like the installed version: the tests
check that `--help`, `--list` and the dry-run plan are identical.

From a release (each `v*` tag publishes `system-update` and its `.sha256`):

```
$ curl -fLO https://github.com/bradvrudney/system-update/releases/latest/download/system-update
$ curl -fLO https://github.com/bradvrudney/system-update/releases/latest/download/system-update.sha256
$ sha256sum -c system-update.sha256
$ sudo install -m 0755 system-update /usr/local/bin/system-update
```

Or build it from a checkout:

```
$ ./build.sh                     # writes dist/system-update
$ ./build.sh ~/bin/system-update # or anywhere else
```

`system-update --version` says `single file` and which commit it was built
from. Tab completion is built in (`source <(system-update --completion bash)`,
or save that output as `~/.local/share/bash-completion/completions/system-update`),
and `--self-update` replaces the file with the latest release (see
[Self-update](#self-update)). A build is never edited by hand: change the
modules and rebuild.

### Tab completion

`install.sh` links [bash completion](completions/system-update.bash) into
bash-completion's directory (`/usr/local/share/bash-completion/completions`,
or `~/.local/share/bash-completion/completions` with `--user`), so new shells
complete every option, `--color` values, `--config` file names, and the step
names for `--only` and `--skip`, one comma-separated item at a time:

```
$ system-update --only apt,fl<Tab>       ->  --only apt,flatpak
$ system-update --skip co<Tab><Tab>      ->  codex codium composer copilot
```

Step names are asked of the command itself (`system-update --_steps`), so
new tools complete without changes to the completion file. This needs the `bash-completion` package (installed
by default on most desktops). Without installing, or in zsh:

```
$ source completions/system-update.bash                       # bash
$ autoload -U bashcompinit && bashcompinit && source completions/system-update.bash   # zsh
```

Requirements: bash 4.4 or newer and GNU `coreutils` (`timeout`, `install`,
`sha256sum`), `grep` and `sed`. `curl` is needed for GitHub release lookups,
downloads and the PyPI lookups of `--detailed` (without it those steps are
skipped with a warning); `jq` is optional.

## Usage

```
Usage: system-update [OPTIONS]

Options:
  -n, --dry-run           show what would be updated; change nothing (-d is an alias)
      --detailed          dry run that also lists each package/tool with its
                          installed and new version (implies --dry-run)
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
      --log FILE          write this run's log to FILE (default: a new file in
                          ~/.local/state/system-update or /var/log/system-update)
      --no-log            do not write a log file for this run
  Opt-in steps (off by default; config keys NVIM_PLUGINS, RUNTIMES, ...):
      --nvim-plugins      sync Neovim plugins (lazy.nvim, packer or vim-plug)
      --runtimes          upgrade runtimes managed by mise/asdf within their configured specs
      --npm-globals       npm update -g under the user's own Node (nvm); never a system prefix
      --go-toolchain      replace /usr/local/go with the latest stable Go (sha256-verified)
      --containers        distrobox/toolbox upgrades, podman auto-update, re-pull container images
      --self-update       update this script from its git source and exit
      --source URL        git source for --self-update (https only)
      --branch NAME       branch for --self-update (default: the remote's default branch)
      --completion SHELL  print the bash completion script and exit
                          (source <(system-update --completion bash))
      --version           print the version and exit
  -h, --help              show this help and exit
```

Step names for `--only` and `--skip`: `system` (or the package manager's
name: `apt`, `dnf`, `zypper`, `pacman`, `apk`, `xbps`, `emerge`,
`rpm-ostree`), `flatpak`, `snap`, `firmware`, `reboot-check`, `tools`, and
any tool name shown by `--list` (`rustup`, `cargo`, `azure-cli`, `bicep`,
`cloudflared`, `gh-extensions`, `brew`, `oh-my-zsh`, `oh-my-bash`, `tpm`,
`mise`, `asdf`, `nvim-plugins`, `npm-globals`, `go`, `containers`, `nvm`,
`composer`, `docker-compose`, ...).

### Opt-in steps

Five steps are detected and listed but do nothing until you turn them on,
because they change things a system update normally leaves alone: Neovim
plugins (`--nvim-plugins` / `NVIM_PLUGINS=1`), the runtimes managed by mise
and asdf (`--runtimes` / `RUNTIMES=1`), npm global packages (`--npm-globals`
/ `NPM_GLOBALS=1`), the Go toolchain in `/usr/local/go` (`--go-toolchain`,
or `--go` / `GO_TOOLCHAIN=1`) and containers (`--containers` /
`CONTAINERS=1`). Each flag is its config key in lower case; off, the step
shows in the summary as `skipped: off by default; enable with ...`. The
runtime upgrades are conservative: mise moves a tool only within the version
spec configured for it, asdf only within the major of the pin in your home
`~/.tool-versions`, and neither touches a project's own pinned versions.

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
`--allow-unverified-installers`. It runs from `/`, so configuration that
tools such as mise, asdf, cargo and npm read from the current directory
cannot come from a shared or foreign one. A `GITHUB_TOKEN` is never put on
a command line (`ps` shows those to every user): curl reads it from a pipe,
and under `sudo` it is handed to the user-level child over a pipe and
removed from the environment before any tool runs.

### Examples

```
$ system-update --dry-run                 # show everything that would change
$ system-update --detailed                # ... with every package's old and new version
$ system-update --detailed --only system  # just the distro packages, in detail
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
| `PROBE_TIMEOUT` | `20` | seconds a `--version` probe (and the npm and git lookups of `--detailed`) may take |
| `GITHUB_TOKEN` | empty | raises the GitHub API rate limit (`GH_TOKEN` is accepted too) |
| `COLOR` | `auto` | `auto`, `always`, `never` |
| `INSTALL_JQ` | `0` | install `jq` with the package manager when missing |
| `ALLOW_UNVERIFIED_INSTALLERS` | `0` | allow vendor `curl \| sh` installers ([ollama](docs/ollama.md), [anythingllm](docs/anythingllm.md)) |
| `FIRMWARE` | `0` | apply fwupd updates instead of listing them ([firmware](docs/firmware.md)) |
| `PRUNE_NODE` | `0` | remove other Node.js versions after installing the LTS ([nvm](docs/nvm.md), [nodebrew](docs/nodebrew.md)) |
| `AUR_HELPER` | `0` | run `yay`/`paru` as the invoking user on Arch ([pacman](docs/pacman.md)) |
| `AUTOREMOVE` | `1` | remove orphaned packages after upgrading (also `brew autoremove`) |
| `NVIM_PLUGINS` | `0` | sync Neovim plugins headlessly (`--nvim-plugins`, [nvim-plugins](docs/nvim-plugins.md)) |
| `RUNTIMES` | `0` | upgrade mise/asdf runtimes within their specs (`--runtimes`, [mise](docs/mise.md), [asdf](docs/asdf.md)) |
| `NPM_GLOBALS` | `0` | `npm update -g` under the user's own Node (`--npm-globals`, [npm-globals](docs/npm-globals.md)) |
| `GO_TOOLCHAIN` | `0` | replace `/usr/local/go` with the latest stable Go (`--go-toolchain`, [go](docs/go.md)) |
| `CONTAINERS` | `0` | distrobox/toolbox upgrades, `podman auto-update`, image re-pulls (`--containers`, [containers](docs/containers.md)) |
| `LOGGING` | `1` | write a [log file](#logs) for every run |
| `LOG_DIR` | empty | where logs go; empty is `/var/log/system-update` as root, `${XDG_STATE_HOME:-~/.local/state}/system-update` otherwise |
| `LOG_KEEP` | `10` | how many logs to keep; `0` keeps all |

System package commands have a fixed limit of one hour each.

## Logs

Every run (real or dry) writes a log file; the summary ends with its path:

```
  2 ok, 3 updated, 1 skipped, 0 failed, 0 dry-run
  log: /home/you/.local/state/system-update/system-update-20261030-174821-1324223.log
```

The terminal shows what you need to follow the run (`--quiet` keeps only
this program's own lines; a tool's output then exists only in the log); the
log has everything, so a failed step can be investigated after the fact:

* **A header** describing the run: version and git commit, start time, host
  and kernel, distribution and package manager, user (and the user whose
  tools are updated under `sudo`), the full command line, dry or real run,
  and every setting that differs from the default and where it came from.
  `GITHUB_TOKEN` is shown only as `<set>`.
* **Every message**, timestamped and without colours, including the ones
  `--quiet` hides and the verbose-only ones (`--only`/`--skip` decisions,
  checksum results, ...).
* **Every command** run as root or as the user: the command line, its
  complete output (stdout and stderr), then `-> exit N after Ns`.
* **Every `--version` probe** of the identification guard, with its output,
  so a tool skipped as "a different program" can be checked.
* The user-level tools of a `sudo` run, from the child process that runs
  them as you, in the same file.
* **A footer** with the end time, exit status and total duration.

```
17:48:21 ▶ firmware
17:48:21   $ sudo fwupdmgr get-updates --no-unreported-check --no-metadata-check
Devices with no available firmware updates:
 ...
17:48:22   -> exit 0 after 1s
17:48:22   ✔ firmware: 1 firmware update(s) available (not applied; use --firmware)
```

| | |
| --- | --- |
| Where | `/var/log/system-update/` when run as root (also with `sudo`), `${XDG_STATE_HOME:-~/.local/state}/system-update/` otherwise, or `LOG_DIR` |
| Names | `system-update-YYYYmmdd-HHMMSS-PID.log`, plus `latest.log` pointing at the newest |
| Kept | the newest `LOG_KEEP` (10); older ones are deleted at the start of a run |
| Permissions | 0600, in a 0700 directory created on first use: logs can list packages, paths and host details |
| Off | `--no-log` for one run, `LOGGING=0` for good |
| One file | `--log FILE` writes to exactly that file (appending) and prunes nothing |

`--list` shows where logs go. While a log is being written, commands send
their output through a pipe instead of straight to the terminal, so
progress bars that only draw on a terminal are not shown; `--no-log` brings
them back. A log directory that cannot be created or written is a warning,
never a reason to stop.

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
* A [single file](#single-file): fetches `system-update.sha256` from the
  repository's latest GitHub release and compares it with the file it is
  running from; when they differ it downloads `system-update`, verifies it
  against that checksum, checks that it parses and is a single-file build,
  and renames it over the old file (as the file's owner, through `sudo` for
  a root-owned `/usr/local/bin`). It follows releases, so `--branch` does not
  apply; without a published checksum nothing is replaced.

`--self-update --dry-run` fetches and checks but does not change anything.

To follow Ed Reel's original repository instead:

```
$ system-update --self-update --source https://github.com/uberhacker/system-update
```

## Running it unattended

The script never prompts, closes stdin for every command it runs, and puts a
time limit on each one, so it can run from a timer. Two things decide what a
non-interactive run can do: `sudo` and whose home directory it runs in.

* **System packages need root.** Run as root, or as a user with a `NOPASSWD`
  sudo rule; without either the system steps are skipped with a warning.
* **Tools belong to a user.** As plain root (no `SUDO_USER`) the tools found
  are root's own, which is rarely what you want. Split the work instead: a
  root job for the system, a user job for the tools. The few tools that live
  in system locations ([docker-compose](docs/docker-compose.md),
  [codium](docs/codium.md), [ollama](docs/ollama.md)) also need root to
  install, so the user job needs a `NOPASSWD` rule for them, or skip them
  there.

A systemd timer for the system part, as root:

```ini
# /etc/systemd/system/system-update.service
[Unit]
Description=Update system packages, Flatpaks and firmware metadata
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/system-update --skip tools --no-color

# /etc/systemd/system/system-update.timer
[Timer]
OnCalendar=daily
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
```

```
$ sudo systemctl enable --now system-update.timer
```

And the tools, as yourself (a user unit in `~/.config/systemd/user/`, or a
crontab line):

```
0 9 * * 1  ~/.local/bin/system-update --only tools --quiet --no-color
```

The exit status is 1 when a step failed, so systemd marks the run as failed
and `systemctl --failed` or your cron mail shows it. Each run also leaves a
[log](#logs) with the full output (in `/var/log/system-update` for the root
job), so you can see what a night-time run did. Output without a
terminal has no colours; `--quiet` keeps only the status lines and the
summary. Read the [warnings](#before-you-run-it) before automating real
runs; `--dry-run` from a timer is a safe way to get a daily report instead.

## Troubleshooting

| You see | What it means | What to do |
| --- | --- | --- |
| `skipped: ... does not look like <tool>` or `... did not answer '--version' within 20s; it looks like a different program` | A program with that name is on `PATH`, but it is not the tool this script knows (see the [identification guard](#identification-guard)). | Nothing, if it is a different program. Otherwise check `<tool> --version`; `-v` shows the probe. `--skip <tool>` silences it. |
| `skipped: ... belongs to dnf package 'x'` | The tool came from your distribution and is updated with the system packages. | Nothing. |
| `GitHub API rate limit reached` | Unauthenticated GitHub lookups are limited to 60 an hour; the rest of the run skips them. | Set `GITHUB_TOKEN` (any token, no scopes needed) in the config file or environment. |
| `sudo credentials unavailable` / system step skipped | `sudo` asked for a password and none was given, or the run is not interactive. | Run it from a terminal, or add a `NOPASSWD` rule for unattended runs. |
| `timed out after 300s` | A third-party command ran longer than `TIMEOUT`. | `--timeout 900`, or `TIMEOUT=900` in the config. Package managers have their own one-hour limit. |
| `⚠ warn apt: ... package source(s) could not be refreshed` | A repository was unreachable; apt used the old lists for it. | Check the source in `/etc/apt/sources.list.d`; the rest of the upgrade went ahead. |
| `⚠ warn reboot-check: reboot required` | A new kernel, a staged ostree deployment or a package asked for a reboot. | Reboot when convenient. |
| A tool you use is not in the summary | It was not found on your `PATH`, or it is not supported. | `--list` shows every tool that was detected and where. |

Every run's [log](#logs) has the full output and exit status of each
command, which is usually enough to see why a step did what it did; the
summary ends with its path, and `latest.log` points at the newest. `-v`
(`--verbose`) shows the commands on the terminal as they run. Each step's page in
[`docs/`](docs/README.md) lists its skip and failure reasons.

## Development

```
$ tests/lint.sh          # bash -n and shellcheck -x on everything
$ tests/run.sh           # bats unit tests (bats-core is fetched into tests/vendor if missing)
$ tests/containers.sh    # the real thing inside stock distro containers (needs docker)
$ ./build.sh             # the single-file build, dist/system-update
```

Releases: bump `VERSION`, commit, then tag and push it (`git tag v2.1.0 &&
git push origin v2.1.0`). `.github/workflows/release.yml` runs the lint and
unit tests, checks the tag matches `VERSION`, builds the single file and
publishes it with its `.sha256` as a GitHub release. CI also uploads a
build of every push as an artifact.

The unit tests cover OS detection against `/etc/os-release` fixtures, the
config parser (including hostile values), argument handling, colour and icon
selection, the JSON fallback, the GitHub helper against a stubbed `curl`
(rate limits, null fields, annotated tags), the step runner and exit codes,
the tool identification guard (a hanging `kilo` editor, a `pi` that is not
Pi), nvm against a stubbed `nvm.sh`, every tool module against fake
binaries (detect, skip, dry run, update, failure, distro-owned copies; the
verified-download modules against the stubbed `curl` with and without a
published checksum; the git-based ones against local bare repositories),
self-update against a local bare repository, the bash completion against
`--help`, and the `--detailed` parsers against package manager output
captured from real containers (`tests/fixtures/detail`).
`tests/containers.sh` runs
`--list`, `--dry-run`, a real `--yes` run (after downgrading one package so
there is something to upgrade), the same as a non-root user with `sudo`
(including fake `rustup`, `gh` and `brew` that must run as that user, and a
dry run that must leave them alone), an unreachable apt source (a warning,
not a failure), a stand-alone `docker-compose` updated from the real GitHub
release (downloaded, sha256-verified, `install -m 0755`), a `--detailed`
run that must list a package downgraded beforehand, and the `kilo` guard
inside Ubuntu, Debian, Fedora, Rocky, Arch, openSUSE Tumbleweed and Leap,
and Alpine. The GitHub Actions workflow
in `.github/workflows/ci.yml` runs all three.

Adding a tool is one file in `lib/tools/` and one page in `docs/` (tab
completion picks the new step name up by itself):

```bash
#!/usr/bin/env bash
# lib/tools/foo.sh
tool_foo_detect() { user_bin foo; }
tool_foo_update() {
  tool_standard foo "${SU_TOOL_BIN[foo]}" '^foo [0-9]' 'foo' --version -- foo self-update
}
```

`tool_<name>_detect` says whether the tool is present, `tool_<name>_update`
updates it and reports through `step_ok`/`step_updated`/`step_skip`/
`step_dry`/`step_warn`/`step_fail`, or returns non-zero to mark the step
failed. `tool_standard` wraps the usual case: identify the binary (expected
package and `--version` pattern), update it through the package manager that
installed it or with its own update command, compare versions before and
after, and look up the latest version for `--detailed`. Optional
`tool_<name>_scope` returns `system` for tools that live in `/usr/local/bin`
(updated as root) rather than in the user's home.

A step that can tell what would change writes `name|installed|new` lines and
passes them to `detail_show` (see `lib/core/runner.sh`); `--detailed` then
prints them as a table.

## Changes from the original

Ed Reel's `system-update` was a single script that grew one tool at a time;
this version keeps its spirit and most of its recipes, restructured so it can
be trusted on any distribution:

* `lib/core`, `lib/pkg`, `lib/tools` modules instead of one file; tools are
  auto-discovered, so adding one does not touch the main flow.
* Distribution detection from `/etc/os-release` instead of a short list of
  names; `dnf5`/`yum`, `zypper dup` vs `update`, `pacman`, `apk`, `xbps`,
  `emerge`, `rpm-ostree`, Flatpak, Snap, fwupd and a reboot check.
* A dry run for everything, not only `apt`, and `--detailed` with the
  version of every package that would change.
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
* More of the developer toolbox: rustup and cargo, the Azure CLI and Bicep,
  cloudflared, gh extensions, Homebrew on Linux, Oh My Zsh/Oh My Bash and
  TPM, mise and asdf; and, behind flags, Neovim plugins, mise/asdf runtimes,
  npm globals, the Go toolchain and containers.
* Config file, environment and flags; `--self-update`; `install.sh`; unit and
  container tests; CI.

Thanks to Ed Reel ([@uberhacker](https://github.com/uberhacker)) for the
original and for years of keeping it current.

## License

GPL-3.0, as the original. See [LICENSE](LICENSE).
