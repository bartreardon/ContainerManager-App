# Building images from a Dockerfile

ContainerManager can build a local image from a Dockerfile, so you don't have to drop to
the terminal to run `container build`. The result is an ordinary local image that you can
then run as a container or use as a [container machine](container-machine.md).

Find it under **Images ▸ Build Image…** (the hammer button in the toolbar, or the button on
the empty Images view).

## What a build produces

A build runs `container build` and tags a **local image** (default `local/<name>:latest`).
When it finishes, the image appears in the **Images** list like any pulled image and is
selectable everywhere an image reference is — the create sheets, stacks, etc.

The build itself is the whole job; using the image afterwards is the normal create flow.
For convenience the build sheet also offers one-click **Run Container** / **Create Machine**
shortcuts after a successful build, and the same actions live in each image's detail view
(**Use Image**), so you can go from any image straight to a new container or machine.

## The build library

Each build is saved on disk so you can revisit and re-run it:

```
~/Library/Application Support/ContainerManager/Builds/<name>/
    Dockerfile          # edited in-app, or by hand
    …                   # any other files you add (build context)
```

- The **name** you give a build is its folder name; the **Load saved build** menu in the
  sheet lists existing ones.
- **Reveal in Finder** (button in the sheet) opens that folder so you can hand-manage the
  Dockerfile or add files.
- The folder **is the build context** — so `COPY`/`ADD` instructions resolve against files
  you place in it. A Dockerfile that only uses `FROM`/`RUN` needs nothing else; to copy
  local files in, drop them in the folder (via Reveal in Finder) and reference them
  relative to the folder root.

## Building a machine image

Container machines need an image with an init system at `/sbin/init`; minimal images like
`alpine` work, but a plain `ubuntu`/`debian` image does not (see
[Understanding container machines](container-machine.md)). You can build a machine-ready
image here and use it directly — this is the in-app version of Apple's
["bring your own container machine image"](https://github.com/apple/container/blob/main/docs/container-machine.md#bring-your-own-container-machine-image)
flow:

1. **Images ▸ Build Image…**, give it a name/tag (e.g. `local/ubuntu-machine:latest`).
2. Write a Dockerfile that installs an init system, then **Build**.
3. After it succeeds, click **Create Machine from Image** (or pick the tag in
   **Machines ▸ New Machine**).

## Notes

- The build streams plain log output as it runs; the first build of a session also brings up
  the BuildKit builder, which you'll see in the log.
- Builds require the container system to be running (the app already gates on that).
- A failed build surfaces in the log and won't report success — fix the Dockerfile and build
  again.
- Advanced `container build` options (build args, secrets, multi-platform) aren't exposed in
  the sheet yet; for those, build from the terminal against the same folder.
