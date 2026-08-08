# ContainerManager 1.1.0

Moves to Apple's container 1.2.1, picks up what it added, and tidies the parts of
the interface that had drifted apart.

## New

**Save and load images as archives.** Right-click an image ▸ **Save as
Archive…** writes an OCI archive — layers and configuration included — and
**Load from Archive…** reads one back. This is the way to move an image to
another Mac, or keep one that isn't in a registry.

**Export a container's filesystem.** Right-click a container ▸ **Export
Filesystem…**. Useful for looking inside a running container or pulling files out
of it. Note this is the files only, with no layers or image configuration, and
`container` has no matching import — so unlike an image archive it doesn't load
back. Reach for the archive if you want something restorable.

**Forward your SSH agent to a build.** A switch on the Build Image sheet lets a
Dockerfile reach private repositories with `RUN --mount=type=ssh …`, without a
key ever being written into the image.

**See which images nothing is using.** Images no container or machine references
are badged **Unused**, and **Delete Unused Images…** clears them out. Stopped
containers count as references — which is why deleting an image can appear to
free nothing, while something still holds on to its data.

**Lists group what belongs together.** Volumes group by label or the stack that
created them, containers and networks by their stack, and images by what uses
them. Group headers collapse with a click and stay collapsed.

## Fixed

- **A partly-running stack couldn't be stopped.** The toolbar swapped Start for
  Stop based on *every* service running — which a stack containing a one-shot
  init container, one that exits by design, can never be. Both buttons now hold
  their positions and enable or disable instead.
- **The same mistake misreported web UIs.** The menu bar offered to *start* a
  stack whose site was already up, and "Open in Browser" stayed enabled when the
  web service was down. Both now check the service that actually serves the
  address.
- **A build couldn't be stopped.** `container build` runs for minutes and there
  was no way to interrupt it — closing the sheet left it building with nothing
  showing its progress. The Build Image sheet now has a **Stop** button, and
  closing it stops the build.
- **Cancel now cancels.** On the machine, container and pull sheets, Cancel
  closed the sheet but left the work running, and if it then failed there was
  nowhere for the failure to appear. It now stops the work on the way out.

## Changed

- **Consistent toolbars.** Actions that create things sit at the window's leading
  edge, where Finder puts its own, so they stop shifting sideways when you select
  something. The selected item's actions — start/stop, item-specific ones, and
  Delete — sit together on the detail side. Delete is a direct button everywhere,
  rather than hiding inside the ⋯ menu on Machines and Containers.
- **Long operations show progress** and reveal the finished file in Finder.
- **Built in Swift 6 language mode.** Data passing between the interface and the
  work going on behind it is now checked by the compiler rather than taken on
  trust — the class of mistake that surfaces as a glitch nobody can reproduce.
  Nothing was misbehaving; four places that relied on convention now state what
  they were already doing.
- **Built against container 1.2.1**, and **the minimum supported version is now
  1.2.0** — the oldest daemon these libraries have been verified against. Older
  ones failed obscurely over XPC rather than prompting you to update; you'll now
  be told to update instead. Exporting a container needs 1.2.1.

## Known limitations

On macOS 27 beta, published ports accept a connection and then reset it, so
`localhost:<port>` doesn't reach a container while its own address still works —
[apple/container#2029](https://github.com/apple/container/issues/2029). This is
upstream and not worked around here.
