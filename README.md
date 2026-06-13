# ContainerManager

A lightweight native macOS app for managing [Apple's `container`](https://github.com/apple/container) tool — Linux containers and the new **container machine** feature — without dropping to a terminal.

ContainerManager is a SwiftUI front-end that links `container`'s own Swift client libraries and talks to its background services directly over XPC. It is not a wrapper around the CLI: lists, lifecycle actions, image pulls, networks, and volumes all go through the same client APIs the `container` command uses. (The CLI is invoked only for `system start`/`system stop` and for opening an interactive shell in Terminal.)

## Features

- **Stacks** - collection of containers and configuration managed as one unit - WordPress + MariaDB template or custom stack builder (pick any web image and optionally a database image) 
- **Machines** — create persistent Linux VMs from an OCI image, start/stop, set default, edit boot config (CPUs, memory, home-mount), view logs, and open a shell. Each machine has an **integrated terminal** (a Terminal tab in its detail view) for an interactive session without leaving the app, plus an "Open in Terminal" option for Terminal.app. Surfaces boot diagnostics when an image lacks an init system. New to machines? See [what a container machine is and when to use it](docs/container-machine.md).
- **Containers** — create and run containers (image, command, env, CPUs/memory, network, published ports, volume/bind mounts), start/stop/kill/delete, and view logs.
- **Images** — list local images, pull from a registry with progress, and delete.
- **Networks** — create (NAT or host-only, optional CIDR), inspect subnet/gateway, and delete. The built-in `default` network is protected.
- **Volumes** — create named volumes for persistent storage, inspect host path/size, and delete (guarded while in use).
- **System** — see whether the `container` services are running, with the daemon version, and start/stop them from the status footer.

## Requirements

- A Mac with **Apple silicon**.
- **macOS 26** (the `container` tool relies on its virtualization/networking features).
- The **`container` tool** from [https://github.com/apple/container](https://github.com/apple/container)
  - If the services aren't running, ContainerManager shows a gate screen with a **Start** button (the first start downloads a Linux kernel, which can take a few minutes).

## Lifecycle: does my stuff keep running when I quit the ContainerManager app?

**Yes.** Containers and machines run as background services managed by `launchd` and the `container` daemon, independent of this app. Quitting ContainerManager leaves everything running.

- The **Stop** button in the status footer runs `container system stop`, which stops the entire `container` stack (all containers and the daemon). Quitting the app does **not** do that.
- After a **reboot**, the daemon relaunches automatically but containers come back **stopped** — `container` (as of 1.0) has no restart policy, so there is no automatic restart of individual containers.

## A note on machine images

A container machine boots the image's init system at `/sbin/init`. Minimal images like `alpine` work out of the box; plain `ubuntu`/`debian` images do **not** include an init system and will exit immediately on boot. See the [container machine docs](https://github.com/apple/container/blob/main/docs/container-machine.md) for building a machine-ready image.

## Status

Built against `apple/container` 1.0.0. The `container` project is pre-1.0-style in its API stability between minor releases, so expect to track upstream changes.
