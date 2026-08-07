# Changelog

All notable changes to ContainerManager.

## 1.1.0 — 2026-08-07

Moves to Apple's container 1.2.1 and picks up two of its new capabilities.

### New
- **Forward your SSH agent to an image build.** A switch on the Build Image sheet passes `--ssh default`, so a Dockerfile can reach private repositories with `RUN --mount=type=ssh …` without a key ever being written into the image.
- **Export a container's filesystem.** Right-click a container ▸ **Export Filesystem…** to save it as a tar archive. Useful for inspecting or extracting what's inside a running container — note it's the files only, with no layers or image configuration, and `container` has no matching import, so it doesn't load back.
- **Save and load images as archives.** Right-click an image ▸ **Save as Archive…** writes an OCI archive (layers and configuration included), and **Load from Archive…** reads one back. Unlike the container export this genuinely round-trips, so it's the way to move an image to another Mac or keep one that isn't in a registry.

### Changed
- **Built against container 1.2.1** (was 1.0.0). Verified against both a 1.2.0 and a 1.2.1 daemon.
- **The minimum supported container version is now 1.2.0**, up from 1.0.0. That's the oldest daemon the 1.2.1 client libraries have been verified against; older ones failed obscurely over XPC instead of prompting you to update. Exporting a container needs 1.2.1.

## 1.0.8-1 — 2026-08-06

A rebuild of 1.0.8 fixing stacks that broke when restarted.

### Fixed
- **Restarting a stack no longer breaks the services in it.** Services find each other by IP, and those addresses are written into a container's environment when it's created — but the runtime reassigns them as containers start, so after a restart every dependant was left calling an address that no longer existed (`dial tcp 192.168.69.4:3306: connect: no route to host`). Starting a stack now brings its services up in dependency order and re-creates any whose addresses have gone stale. Only the address entries are changed — anything edited by hand since, such as a corrected password or a tweaked command, is carried over untouched.
- **Creating or starting a stack no longer stalls at the end.** Each service was waited on until it accepted connections, including the last one that nothing depends on — so a slow-starting app (Fleet running its database migrations, say) held the sheet open long after the work was done. Only services that others actually address are waited for now.
- **Custom stacks are remembered too.** Stacks built with the custom builder now save their definition like template and compose ones, so they also self-heal and can use **Re-create** and **Prefill from definition**.
- The readiness log names the address it's waiting on, and skips the wait entirely for a container that has no address yet, instead of timing out against nothing.

## 1.0.8 — 2026-08-05

### New
- **Environment variables when building an image.** The Build Image sheet has an **Environment** switch that reveals a `KEY=value` field, with **Import from File…** to load a `.env` file (the format `--env-file` accepts — comments, `export`, and quoted values are handled). Values are applied both ways: passed as `--build-arg` for Dockerfiles that declare matching `ARG`s, and baked into the image as `ENV` defaults so containers run from it inherit them. Saved builds remember their env.
- **Import an env file when running a container.** The container create sheet's Environment field gains the same **Import from File…** button.
- **Edit a stack's services.** A stack's detail view gains **Add Service…**, plus **Replace…** and **Remove from Stack** on each service. Replacing re-creates a service with new settings — the way to repair one that failed to create — carrying over the stack's labels, network, and web URL, and leaving named volumes untouched.
- **Stacks keep a log of how they were built.** A **Log** button on a stack shows what its import couldn't carry over, the full creation transcript including readiness waits and any failure, and services added or replaced since — the import summary previously appeared once in an alert and was then gone. Stored beside the stack's definition and removed with it.
- **Stacks list the volumes they use.** A **Volumes** section shows each named volume the stack mounts and which service mounts it where, so the association is visible without cross-referencing creation dates in the Volumes section.

### Changed
- **Compose import understands `${VAR}` and `command:`.** Compose files that interpolate variables (`MYSQL_PASSWORD=${MYSQL_PASSWORD}`) previously failed to import, because `${…}` clashed with the stack format's own field syntax. Each variable now becomes a field on the create sheet, prefilled from a `.env` sitting next to the compose file, with password-like names masked; `${VAR:-default}` is honoured. A service's `command:` (string or list form) is also carried through instead of being dropped, so images that need one — Fleet, Redis with flags — import intact.
- Commands are now split with quotes respected, so `sh -c "a && b"` stays a single argument instead of being torn apart on spaces.
- **Compose `platform:` is honoured.** Apple silicon can run `linux/amd64` images under emulation, so a service pinned to x86 now carries that through instead of failing with "image … does not support required platforms". Compose's `linux/x86_64` spelling is translated to the OCI `linux/amd64`.
- **Group volumes by label.** The Volumes list groups into collapsible sections so it's clear what belongs together, instead of guessing from creation dates. A volume's group comes from a label you set (right-click one or several → **Set Label…** / **Group N Volumes…**), a label recorded on the volume itself, or — while the stack is running — the stack that mounts it. Stacks now claim their named volumes up front so the association is written to the volume as a real label, surviving deletion of the stack. Right-clicking a group header acts on the whole group: select, relabel, or delete it.
- **Stacks remember what they were created from.** The definition and the values entered at create time — including anything pulled in from a compose file's `.env` — are saved with the stack. A stack that's missing services (one that failed to create) now shows them with a **Re-create** action that rebuilds them exactly as defined, and the service sheet can **Prefill from definition** instead of retyping image, command, env, ports, volumes, and platform. The saved definition can contain credentials, so it's written owner-read-only and deleted with the stack.
- **Stack services wait for their dependencies.** Compose's `depends_on: condition: service_healthy` can't be honoured directly, and "started" isn't "ready" — a database initialising a fresh volume can take a minute, while a dependent that connects on startup (Fleet runs `fleet prepare db` immediately) fails outright against it. Each service is now waited on until it accepts connections on the ports it exposes before the next one starts.
- **Open a terminal into a stack service.** Right-click a service in a stack for **Open Terminal** (in-app) or **Open in Terminal.app** — the shell sees the stack's volumes mounted, so its data is inspectable in place.
- **Creating a stack shows progress immediately.** The sheet scrolls to the progress log when you hit Create and seeds a first line, instead of appearing to hang while the first image downloads.
- **Compose imports say *why* a key was skipped.** Instead of a bare list, each entry explains the consequence — e.g. "`restart:` — restart policies aren't supported; start the stack again if a service stops" — and the list is kept in the stack's log rather than only shown once.

### Fixed
- **Creating a stack no longer freezes the app.** Image pull, unpack and container creation ran on the main actor (the target defaults every type to `MainActor`, and the orchestrator was explicitly annotated too), so the create sheet couldn't repaint or scroll for the whole run. That work now runs off the main actor, with only progress callbacks hopping back.
- **The progress log stays in view.** The sheet scrolled to the log once when the run started, then the log box grew line by line and slid below the fold. The log and status areas are now fixed-height, and the sheet re-pins to them as they update.
- **A create sheet says what happened.** A failed run left "Cancel" beside a re-armed "Create", as though nothing had occurred — while services created before the failure were in fact running. Both sheets now report "Created N of M services" with the reason, and offer **Close** (plus **Retry** on failure) instead.
- **Stacks are checked before anything is created.** Missing host bind paths, mount paths left empty by an unset variable, invalid port mappings, and missing images are all reported together up front, instead of standing up half a stack and failing on the last service.
- **Replacing a service kept the whole command.** The runtime stores a container's executable separately from its arguments, so the prefill dropped `argv[0]` — `sh -c "…"` came back as `-c "…"` and the container failed to start.
- **Pasting a docker-compose file into the Build Image sheet** produced a cryptic `unknown instruction: services:` from the builder. It's now detected up front, pointing at Stacks ▸ New Stack ▸ Import Template… instead.

## 1.0.7 — 2026-07-21

### New
- **Menu bar item.** ContainerManager now lives in the menu bar: the icon reflects whether the container subsystem is running, and its menu gives quick access to **running machines** (Open Terminal, Copy IP) and **stack web UIs**, plus Start/Stop services and Open/Quit. A web UI that's running opens in the browser; one that's stopped starts the stack instead. ContainerManager keeps running in the menu bar after you close the window, and the **Dock icon hides while no window is open** and returns when you open one. "Open Container Manager" reuses the existing window rather than opening another. Settings ▸ Menu Bar toggles the icon.
- **Custom stack name & icon.** A stack's detail view now has an **Appearance** section to give it a friendly name and pick an icon (from a set of SF Symbols). These show in the Stacks list, the window title, and the menu bar.

## 1.0.6 — 2026-06-30

### New
- **Software updates.** ContainerManager now checks GitHub for newer releases of **both itself and the Apple container tool** (previously it only flagged container installs *below* its minimum version). **Check for Updates…** in the app menu runs a check and reports a per-component summary. Settings ▸ Updates shows a **Components** panel with each piece's installed version and status, an automatic-check cadence (on launch / daily / weekly / never), and the last-checked time. A newer container release also surfaces as a passive **Update to …** badge in the sidebar. Applying a container update reuses the signed-installer flow; ContainerManager updates open the release page for download (the app doesn't self-update yet).
- **Stack definitions are now files.** Templates are declarative JSON documents (`.containerstack`) instead of code — see the [stack definitions guide](docs/stack-definitions.md):
  - **Import**: New Stack ▸ **Import Template…** (or double-click a `.containerstack` in Finder). Imported templates join the New Stack menu, stored in `Application Support/ContainerManager/StackTemplates` (New Stack ▸ **Show Templates Folder** to hand-manage them).
  - **Export**: every template's create sheet has **Export…** — including the built-ins, which now ship in the same format and double as documented examples.
  - **docker-compose import**: choosing a `compose.yml` converts a practical subset (image, environment, short- and long-form ports/volumes, depends_on ordering; service-name references become `${IP:…}` tokens). Services that can't be represented (e.g. `build:`) are skipped rather than failing the whole file, and everything that didn't carry over is summarised in an "Imported with caveats" alert.

### Fixed
- **Container services left stopped after an update.** Updating the container tool stops services so the installer can replace files; it now restarts them afterwards only if they were running beforehand, instead of leaving them down.

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
