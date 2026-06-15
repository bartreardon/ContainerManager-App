# Changelog

All notable changes to ContainerManager.

## 1.0.2 — 2026-06-15

### Fixed
- **False "Base Environment Missing" on a working install.** The readiness check looked for the init-filesystem (`vminit`) image by an exact, build-time version tag. When the app was built against a different `containerization` version than the installed `container` CLI, the tags didn't match and a perfectly healthy system was reported as missing its base environment, with a Repair button that couldn't fix it.
- **Fresh-install "Repair" deadlock.** Readiness no longer requires the `vminit` image to be present at all. That image is fetched on demand the first time a container or machine is created, so a brand-new install legitimately has none yet — but the old check hid the create UI behind a Repair wall, and the only thing that pulls `vminit` is creating something. The check now gates solely on a configured **default kernel** (the real boot prerequisite), which `system start --enable-kernel-install` installs and Repair can genuinely fix. The corresponding gate is retitled "Linux Kernel Not Installed."

### Changed
- **Dependency on the `container` package is now a pinned remote reference** (`apple/container`, exact `1.0.0`) instead of a local path that assumed a specific checkout layout. The project now builds on any machine without extra setup, and the pin keeps the app aligned with a known CLI version.

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
