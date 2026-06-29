# ContainerManager

<img width="128" height="128" alt="Container Manager v2 2-iOS-Default-1024@1x" src="https://github.com/user-attachments/assets/007ca2d9-4c60-4705-9512-ac57351e3bfa" />


A lightweight native macOS app for managing [Apple's `container`](https://github.com/apple/container) tool — Linux containers and the new **container machine** feature — without dropping to a terminal.

➡️ **[Download the latest version](https://github.com/bartreardon/ContainerManager-App/releases/latest/download/ContainerManager.dmg)**

ContainerManager is a SwiftUI front-end that links `container`'s own Swift client libraries and talks to its background services directly over XPC. It is not a wrapper around the CLI: lists, lifecycle actions, image pulls, networks, and volumes all go through the same client APIs the `container` command uses. (The CLI is invoked only for `system start`/`system stop`, `build`, and for opening an interactive shell in Terminal.)

## Features

- **Stacks** — stand up a multi-container setup in one step. Pick a ready-made template (e.g. **WordPress + MariaDB**) or build a **custom stack** (a web service plus an optional database). ContainerManager creates a private network, persistent volumes, and the containers, and wires the web tier to the database automatically — no DNS or terminal needed. Whole-stack start/stop/delete and an "Open in Browser" shortcut. See the [Stacks guide](docs/stacks.md) for details.
- **Machines** — create persistent Linux VMs from an OCI image, start/stop, set default, edit boot config (CPUs, memory, home-mount), view logs, and open a shell. Each machine has an **integrated terminal** (a Terminal tab in its detail view) for an interactive session without leaving the app, plus an "Open in Terminal" option for Terminal.app. Surfaces boot diagnostics when an image lacks an init system. New to machines? See [what a container machine is and when to use it](docs/container-machine.md).
- **Containers** — create and run containers (image, command, env, CPUs/memory, network, published ports, volume/bind mounts), start/stop/kill/delete, and view logs.
- **Images** — list local images, pull from a registry with progress, **build from a Dockerfile**, and delete. Each image can be turned straight into a container or machine from its detail view. See the [building images guide](docs/building-images.md).
- **Networks** — create (NAT or host-only, optional CIDR), inspect subnet/gateway, and delete. The built-in `default` network is protected.
- **Volumes** — create named volumes for persistent storage, inspect host path/size, and delete (guarded while in use).
- **System** — see whether the `container` services are running, with the daemon version, and start/stop them from the status footer.

## Requirements

- A Mac with **Apple silicon**.
- **macOS 26** (the `container` tool relies on its virtualization/networking features).
- The **`container` tool installed** and its services started:
  ```bash
  container system start
  ```
  If the services aren't running, ContainerManager shows a gate screen with a **Start** button (the first start downloads a Linux kernel, which can take a few minutes).

## Building

This is a standard Xcode project; no extra tooling required.

1. Open `ContainerManager.xcodeproj` in Xcode 26 or later.
2. The app depends on Apple's [`container`](https://github.com/apple/container) Swift package, pinned to an **exact released version** (currently `1.0.0`) as a remote package reference. Pin it to the same version as the `container` CLI you run, so the app and the installed services agree on the base image/kernel references. It also pulls [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (the integrated terminal) as a remote package. Both are fetched automatically — no separate checkout or path setup is required. The first build resolves the full dependency graph (Containerization, NIO, SwiftTerm, etc.) and may take a few minutes.
3. Build and run the **ContainerManager** scheme.

> [!NOTE]
> On the first build, Xcode may prompt to **"Download Xcode support for Metal Toolchain"** — click **Download & Install**. The integrated terminal (SwiftTerm) ships a Metal shader, and Xcode 26 provides the Metal compiler as a separate downloadable component (~688 MB). This is a one-time, per-developer-machine **build** requirement only; the compiled shader is baked into the app, so people *running* the built app never need it. (CLI equivalent: `xcodebuild -downloadComponent MetalToolchain`.)

### Notes for contributors

- **App Sandbox is disabled** and **Hardened Runtime is enabled**. The sandbox must stay off — the app connects to the unsandboxed `com.apple.container.*` Mach services over XPC, which the sandbox blocks.
- The app sends Apple Events to Terminal (for "Open Shell"); the automation entitlement is included and macOS prompts for consent on first use.
- **CLI path resolution** for the few shell-out operations: an explicit override, then `/usr/local/bin/container`, then the path learned from the running daemon's reported install root (persisted automatically). To force a development build of the CLI:
  ```bash
  defaults write com.bartreardon.ContainerManager containerBinaryPath /path/to/container
  ```
- Keep the linked client library and the installed `container` daemon on the **same version** — they exchange JSON-encoded payloads over XPC, so a version mismatch can cause decode errors.

## Lifecycle: does my stuff keep running when I quit?

**Yes.** Containers and machines run as background services managed by `launchd` and the `container` daemon, independent of this app. Quitting ContainerManager leaves everything running.

- The **Stop** button in the status footer runs `container system stop`, which stops the entire `container` stack (all containers and the daemon). Quitting the app does **not** do that.
- After a **reboot**, the daemon relaunches automatically but containers come back **stopped** — `container` (as of 1.0) has no restart policy, so there is no automatic restart of individual containers.

## A note on machine images

A container machine boots the image's init system at `/sbin/init`. Minimal images like `alpine` work out of the box; plain `ubuntu`/`debian` images do **not** include an init system and will exit immediately on boot. See the [container machine docs](https://github.com/apple/container/blob/main/docs/container-machine.md) for building a machine-ready image.

## Status

Built against `apple/container` 1.0.0. The `container` project is pre-1.0-style in its API stability between minor releases, so expect to track upstream changes.
