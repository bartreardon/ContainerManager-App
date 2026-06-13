# Understanding container machines

A common question when you first see **container machine** alongside regular containers is: *what is it for, and does it manage or run my other containers?* Short answer: **a container machine is its own thing — a persistent Linux workspace, not a controller for your containers.** This note explains the distinction and when to reach for each.

## Containers vs. container machines

| | **Container** | **Container machine** |
|---|---|---|
| Modeled after | An *application* | A *Linux environment* |
| Lifetime | Ephemeral — created to run one thing, often removed after | Persistent — you revisit it over days/weeks; changes inside it stick |
| Init | Runs your app process (e.g. `nginx`, `postgres`) | Runs the image's **init system** (`systemd`/OpenRC), so it can host long-running services |
| Your identity | Runs as the image's user (often `root`) | Automatically mapped to **your macOS username**, with your **home directory shared in** |
| Typical use | Package and run a service | Work *inside* Linux: build, test, run a toolchain |
| In this app | **Containers** / **Stacks** sections | **Machines** section (with an integrated terminal) |

In the words of Apple's docs: *"Containers are typically modeled after an application. A container machine is modeled after a Linux environment."*

## Does a machine interact with my existing containers?

**No — a container machine does not manage, start, stop, or `exec` into your containers.** It has no `container` daemon inside it. It is a Linux VM you log into and work in, the way you'd use a remote dev box or a WSL distro. Your containers are managed separately (the **Containers** and **Stacks** sections here, or `container run`/`exec` on the CLI).

There is one relationship worth knowing: a running machine is assigned an **IP address on the same virtual network as your containers** (you can see it in the Machines list). So a machine and your containers can reach each other **over the network by IP** — useful if you want to, say, hit a database container from a tool running inside your machine. That's network connectivity, not control: the machine still can't see or manage the containers as objects.

## What a machine is good for

- **Edit on the Mac, build inside Linux.** Your repo lives in `$HOME` on macOS and is mounted at `/Users/<username>` inside the machine. Edit with your Mac editor; compile and run inside the machine — no copy step.
- **Real Linux services for testing.** On an image with `systemd`, `systemctl start postgresql` works, because the machine runs a real init system.
- **One environment per target distro.** Keep separate `alpine`, `ubuntu`, `debian` machines, each with the same home directory and dotfiles, to test across distributions without dependency conflicts.
- **A durable scratch space.** Install tools over time; they persist across stop/start.

## Using a machine in ContainerManager

1. **Machines → New Machine** to create one from an OCI image. The image must include an init system at `/sbin/init` — `alpine` works out of the box; a plain `ubuntu`/`debian` image does not (see the [upstream guide](https://github.com/apple/container/blob/main/docs/container-machine.md) for a machine-ready Dockerfile).
2. Select the machine and switch the detail pane to the **Terminal** tab for an interactive shell right inside the app — you land as your own user, in your shared home directory. (The **Open in Terminal** toolbar button does the same in Terminal.app if you prefer.)
3. Adjust CPUs / memory / home-mount under **Details**; changes apply on the next stop + start.

Like containers, machines run under the `container` background services, so they keep running after you quit ContainerManager. Stop a machine explicitly when you're done with it.
