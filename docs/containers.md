# Containers: distrobox, toolbox, podman, docker (`containers`) - opt-in

Upgrades the packages inside your distrobox and toolbox containers and pulls newer versions of the images your containers use. **Off by default**: enable it with `--containers` or `CONTAINERS=1`.

| | |
| --- | --- |
| Step name | `containers` |
| Runs as | the invoking user |
| Detected when | any of `distrobox`, `toolbox`, `podman` or `docker` is on the user's `PATH` |
| Settings | `CONTAINERS` / `--containers` (off by default); upgrades and pulls use the one-hour package-manager limit |

## What it does

Without `--containers`: skipped. With it, for each engine that is present:

* **distrobox**: `distrobox upgrade --all` when `distrobox list` shows containers; each container's own package manager runs non-interactively.
* **toolbox**: for every container in `toolbox list -c`, `toolbox run -c <name>` runs the first package manager it finds inside: `dnf5`/`dnf -y upgrade`, `apt-get update && dist-upgrade`, `zypper --non-interactive update`, `pacman -Syu --noconfirm` or `apk upgrade`, through `sudo` inside the container.
* **podman**: `podman auto-update` when units have opted in (`podman auto-update --dry-run` lists any), then every image used by an existing container is pulled again.
* **docker**: when the daemon is reachable as you, every image used by an existing container is pulled again.

Image IDs before and after each pull say how many images got a newer version. Local images (`localhost/...`, bare image IDs) cannot be pulled and are left alone.

## What will be affected

* The packages inside every distrobox and toolbox container (those containers are started if needed).
* Images in your podman and docker storage: newer versions are pulled, old ones stay until you prune them (`podman image prune`, `docker image prune`).
* Systemd units managed by `podman auto-update` are restarted by podman when their image changed; that is podman's own behaviour for units that opted in.
* **Containers are never recreated or restarted by this step.** A running container keeps its old image until you recreate it (`docker compose up -d`, `podman-compose up -d`, ...).

## Dry run and `--detailed`

`--dry-run` reports how many distrobox and toolbox containers would be upgraded, how many podman auto-update units would be checked, and lists each image it would pull (`would pull docker.io/library/postgres:16`). `--detailed` adds nothing beyond that.

## Warnings

* Pulling every image used by existing containers can download a lot. Images with a moving tag (`latest`, `16`) get new contents; pinned digests do not change.
* `toolbox run` uses `sudo` inside the container; a toolbox whose sudo needs a password makes that upgrade fail.
* `docker` must be usable without `sudo` (the user is in the `docker` group, or rootless Docker); otherwise docker is skipped with a note.

## Skipped / failed when

* Not enabled: skipped.
* Any distrobox, toolbox, podman auto-update or image pull fails: failed (the other parts still run).
