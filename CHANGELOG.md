# Changelog

All notable changes to ContainerManager.

## 1.0.1 — 2026-06-14

### New
- **More one-click stack templates.** Alongside WordPress + MariaDB, the New Stack menu now offers **PostgreSQL**, **PostgreSQL + Adminer**, **Mailpit** (local email testing), **Gitea**, **code-server** (VS Code in the browser), and **Nginx + host folder** (serve a folder from your Mac). Templates are now data-driven, so they share one create flow.
- **Integrated terminal for containers.** Container detail gains a Details/Terminal toggle that opens an interactive shell inside a running container (`exec`), in addition to the existing machine terminal.
- **Guided setup & health checks.** ContainerManager now:
  - offers to **download and install** the `container` tool (latest release) when it isn't present;
  - requires a **minimum version (1.0.0)** and prompts to update an older install instead of failing silently;
  - detects when the services are running but the **base Linux environment** (kernel / init filesystem) didn't finish downloading, and offers a one-click **Repair**.
- **App identity.** The app now presents as "Container Manager" and is categorized as a Utility.

### Fixed
- **Machine terminal working directory.** The integrated machine terminal now opens in your shared macOS home (`/Users/<you>`), matching Terminal.app, instead of the machine's `/home/<you>`.
- **code-server stack start failure.** The code-server template no longer crashes on first launch with a permission error writing its config volume; it now uses an image that handles volume ownership correctly.

### Docs
- Added a Stacks guide and a note about the one-time Metal Toolchain component needed to build the app.

## 1.0.0 — 2026-06-12

Initial release — a native macOS app for Apple's `container` tool:

- **Machines, Containers, Images, Networks, Volumes,** and **System** control, all through `container`'s own client libraries.
- Create and run containers (image, command, env, resources, network, published ports, volume/bind mounts); create and manage container machines.
- **Guided Stacks**: WordPress + MariaDB, plus a custom web + database builder, with automatic networking between services.
- **Integrated terminal** for container machines, and an "Open in Terminal.app" option.
- Daemon status with start/stop, CLI auto-discovery, and machine boot diagnostics.
