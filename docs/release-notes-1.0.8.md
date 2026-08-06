# ContainerManager 1.0.8

This release is mostly about **stacks**, driven by running a real-world
`docker-compose` setup (FleetDM) end to end and fixing everything that got in the
way.

## New

**Compose files that actually run.** Imports now handle the things that
previously stopped them dead:

- `${VAR}` references become fields on the create form, prefilled from a `.env`
  beside the compose file — or loaded any time with **Import .env…**.
  Password-like names are masked automatically.
- `command:` is carried through instead of dropped, so images that need one
  (Fleet, Redis with flags) import intact.
- `platform:` is honoured, so `linux/amd64`-only images run under emulation on
  Apple silicon.
- Whatever *can't* be carried over is now listed with the reason and the
  consequence, rather than just a list of key names.

**Stacks are editable.** Add, replace, or remove a service on an existing stack.
Replacing is the way to repair one that failed or needs different settings — it
keeps the stack's network, labels, and web URL, and leaves your data volumes
alone.

**Stacks remember how they were built.** The definition and the values you
entered are saved with the stack, so a stack missing a service offers
**Re-create** to rebuild it exactly as defined — no retyping image, command, env,
ports, or platform.

**Services wait for their dependencies.** Each service is waited on until it
accepts connections before the next one starts, so a database still initialising
no longer causes the app that depends on it to fail on startup.

**Environment files for images and containers.** The Build Image sheet gains an
**Environment** section with `.env` import; values are passed as build args *and*
baked in as image defaults. The container create sheet gets the same import.

**Better visibility into stacks.** A stack now shows its **network** (name, mode,
subnet), the **volumes** its services mount and where, and a **Log** of how it
was built — including what the import skipped and any failure — so you can work
out what still needs doing.

**Open a terminal into a stack service.** Right-click any service for an in-app
terminal or Terminal.app; the shell sees the stack's volumes mounted.

**Group volumes by label.** The Volumes list groups into collapsible sections.
Volumes created for a stack are labelled automatically, and you can label any
others yourself — including several at once.

**Stacks are checked before anything is created.** Missing host paths, mount
paths left empty by an unset variable, invalid ports, and missing images are all
reported together up front, instead of building half a stack and failing on the
last service.

## Fixed

- **The app froze while creating a stack.** Image downloads and container
  creation ran on the main thread, so the window couldn't repaint or scroll —
  progress was invisible and it looked hung. That work now runs in the
  background, and the progress log stays put and readable throughout.
- **A failed create didn't say what happened.** The sheet showed "Cancel" next to
  a re-armed "Create" as though nothing had occurred, while services created
  before the failure were in fact running. It now reports how many services were
  created, why it stopped, and offers **Close** or **Retry**.
- **Pasting a compose file into the Build Image sheet** produced a cryptic
  `unknown instruction: services:`. It's now recognised, pointing you at
  Stacks ▸ New Stack ▸ Import Template… instead.

## Known limitations

Stack services reach each other by IP rather than hostname, and a service's
environment is fixed when it's created — so recreating a dependency leaves its
dependants pointing at the old address. See the
[stack definitions guide](stack-definitions.md) for the full list.
