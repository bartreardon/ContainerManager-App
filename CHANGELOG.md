# Changelog

All notable changes to ContainerManager.

## 1.0.5 — 2026-06-23

A "Mac-native polish" release.

### New
- **Multi-selection + bulk actions.** Shift/⌘-click to select several items (⌘A selects all); right-click acts on the whole selection — Start / Stop / Delete many machines, containers, stacks, images, networks, or volumes at once.
- **Copy & drag-out.** ⌘C (and drag) copies an item's name/id as text — images copy their full reference (e.g. `docker.io/library/nginx:latest`) — to paste into Terminal, a Dockerfile, or the app's own fields.
- **Search.** Each section has a search field (⌘F) to filter by name/id/image.
- **Settings window (⌘,).** Set the container CLI location (or leave it Automatic) and the list refresh interval.
- **Window tabs.** ⌘T opens a new tab (⌘N still opens a new window); the tab title shows the current section and selected item, e.g. "Machines — dev".

### Changed
- The detail pane shows a count when several items are selected.
- Status indicators now convey state by **shape and colour** (and read out to VoiceOver), not colour alone.
- Remembers the selected section per window across launches.

## 1.0.4 — 2026-06-23

### New
- **Right-click context menus.**
  - Sidebar category rows → **New …** for that category.
  - A list's empty/blank area → **New …** for the current category.
  - A list item → **Start / Stop / Delete** (as applicable). Machines and containers also offer **Open Terminal** (in-app tab) and **Open in Terminal.app**.
- **Menu bar commands** (with shortcuts where it makes sense):
  - **File ▸ New ▸** Machine (⇧⌘M), Container (⇧⌘K), Stack (⇧⌘S), Image (⇧⌘B), Network, Volume.
  - **File ▸ Start / Stop Container Services.**
  - **View ▸** one item per category, **⌘1–⌘6**, switching the focused window.
  - **Help** rebuilt with links to the GitHub repo and the bundled guides (replacing the default "Help isn't available").
- **Import a Dockerfile from a file.** The Build Image sheet has an **Import from File…** button next to the editor — pick any file on disk and its contents load in.
- **Drag a Dockerfile to build.** Drop a Dockerfile (or a folder containing one) onto the Images view or the sidebar's **Images** entry to open the Build sheet prefilled with it.

### Fixed
- **Homebrew installs not detected** ([#1](https://github.com/bartreardon/ContainerManager-App/issues/1)). When `container` was installed via Homebrew (`/opt/homebrew/bin`), the app reported it as not installed and offered to reinstall. The CLI path resolver now checks the Homebrew location in addition to `/usr/local/bin`.

## 1.0.2 — 2026-06-15

### New
- **Build images from a Dockerfile.** The Images section gains a **Build Image…** action: edit a Dockerfile in-app, give it a tag, and build a local image with live output. Builds are saved under Application Support (Images › Build › *Reveal in Finder* to hand-manage and add files for `COPY`/`ADD`), and the build folder is the build context. The result is a normal local image, so it's immediately usable for containers and machines — with one-click **Create Machine** / **Run Container** shortcuts after a successful build (matching the "bring your own machine image" flow).
- **Create a container or machine from any image.** The image detail view now has **Run Container** and **Create Machine** actions that open the create sheet prefilled with that image — so the shortcut isn't limited to a freshly built image.

### Fixed
- **False "Base Environment Missing" on a working install.** The readiness check looked for the init-filesystem (`vminit`) image by an exact, build-time version tag. When the app was built against a different `containerization` version than the installed `container` CLI, the tags didn't match and a perfectly healthy system was reported as missing its base environment, with a Repair button that couldn't fix it.
- **Fresh-install "Repair" deadlock.** Readiness no longer requires the `vminit` image to be present at all. That image is fetched on demand the first time a container or machine is created, so a brand-new install legitimately has none yet — but the old check hid the create UI behind a Repair wall, and the only thing that pulls `vminit` is creating something. The check now gates solely on a configured **default kernel** (the real boot prerequisite), which `system start --enable-kernel-install` installs and Repair can genuinely fix. The corresponding gate is retitled "Linux Kernel Not Installed."

### Changed
- **Start/Stop moved to the toolbar's leading edge** in the machine and container detail views, with the Details/Terminal toggle centred and the remaining actions kept on the right. Stop is no longer next to "Open in Terminal," so reaching for a shell can't accidentally stop the machine or container.
- **Dependency on the `container` package is now a pinned remote reference** (`apple/container`, exact `1.0.0`) instead of a local path that assumed a specific checkout layout. The project now builds on any machine without extra setup, and the pin keeps the app aligned with a known CLI version.

### Docs
- Added a [building images guide](docs/building-images.md); updated the Images feature list and the container-machine guide to point at the in-app build flow.

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
