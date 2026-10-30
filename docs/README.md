# Step reference

One page per step: what it runs, what it changes, what `--dry-run` and
`--detailed` show, and what to watch out for. The page name is the step
name used with `--only` and `--skip`. Start with the
[main README](../README.md) for installation and options.

## System packages (`system`)

| Step | Distributions |
| --- | --- |
| [apt](apt.md) | Debian, Ubuntu, Mint, Pop!_OS and derivatives |
| [dnf](dnf.md) | Fedora, RHEL, CentOS Stream, Rocky, AlmaLinux, Oracle, Amazon Linux |
| [rpm-ostree](rpm-ostree.md) | Fedora Atomic desktops, Bazzite, Bluefin, Aurora, CoreOS |
| [zypper](zypper.md) | openSUSE Tumbleweed, Slowroll, MicroOS, Leap, SLE |
| [pacman](pacman.md) | Arch, Manjaro, EndeavourOS, Garuda, CachyOS |
| [apk](apk.md) | Alpine, postmarketOS |
| [xbps](xbps.md) | Void |
| [emerge](emerge.md) | Gentoo, Funtoo (best effort) |
| [nix](nix.md) | NixOS (detected, not updated) |

## Extras

[flatpak](flatpak.md) · [snap](snap.md) · [firmware](firmware.md) · [reboot-check](reboot-check.md)

## Third-party tools (`tools`)

| Group | Steps |
| --- | --- |
| Node.js | [nvm](nvm.md), [nodebrew](nodebrew.md), [npm-globals](npm-globals.md) (opt-in) |
| AI coding CLIs | [claude](claude.md), [codex](codex.md), [copilot](copilot.md), [qwen](qwen.md), [kilo](kilo.md), [agy](agy.md), [devin](devin.md), [grok](grok.md), [hermes](hermes.md), [omp](omp.md), [pi](pi.md) |
| PHP | [composer](composer.md), [terminus](terminus.md), [wp-cli](wp-cli.md) |
| Python | [pip](pip.md) (pipx, pip, AWS CLI), [uv](uv.md), [zcmds](zcmds.md) |
| Rust | [rustup](rustup.md), [cargo](cargo.md) |
| Runtime managers | [mise](mise.md), [asdf](asdf.md), [go](go.md) (opt-in) |
| Package managers | [brew](brew.md), [gh-extensions](gh-extensions.md) |
| Cloud | [azure-cli](azure-cli.md), [bicep](bicep.md), [cloudflared](cloudflared.md) |
| Shell and editor | [oh-my-zsh](oh-my-zsh.md), [oh-my-bash](oh-my-bash.md), [tpm](tpm.md), [nvim-plugins](nvim-plugins.md) (opt-in) |
| Containers and dev environments | [docker-compose](docker-compose.md), [lando](lando.md), [containers](containers.md) (opt-in) |
| Desktop apps | [codium](codium.md), [ollama](ollama.md), [anythingllm](anythingllm.md) |
| Other | [rvm](rvm.md), [vim](vim.md) |

Opt-in steps are off by default: `--npm-globals`, `--go-toolchain`,
`--nvim-plugins`, `--containers` (config keys `NPM_GLOBALS`, `GO_TOOLCHAIN`,
`NVIM_PLUGINS`, `CONTAINERS`). `--runtimes` (`RUNTIMES`) additionally lets
[mise](mise.md) and [asdf](asdf.md) upgrade the runtimes they manage.
