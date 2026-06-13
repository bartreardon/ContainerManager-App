# Stacks

A **stack** is several containers stood up together as one unit — for example a web app and the database it talks to. The `container` tool itself has no "compose" concept; **Stacks is a ContainerManager convenience** that orchestrates the individual pieces (a network, volumes, and containers) for you and labels them so they can be managed as a group.

## What a stack creates

When you create a stack named `mysite`, ContainerManager:

1. Creates a private **network** `mysite-net` (NAT).
2. Creates any named **volumes** the services need (for persistent data).
3. Creates and starts each **container**, named `mysite-<role>` (e.g. `mysite-db`, `mysite-web`), attached to the stack network.
4. **Wires the services together** — see [How services find each other](#how-services-find-each-other).

Every container in a stack is tagged with a label (`com.containermanager.stack=mysite`), which is how the Stacks list groups them. They also show up individually in the **Containers** section.

## Templates

### WordPress + MariaDB

A ready-to-use blog/CMS stack. Fields:

| Field | Default | Notes |
|---|---|---|
| Stack name | `mysite` | Lowercased; used as the name prefix |
| Database password | `wordpress` | Used for both the MariaDB root and the `wordpress` user |
| Web port | `8080` | Published on your Mac as `http://localhost:<port>` |

It creates:

- **`<name>-db`** — `mariadb:11`, data on volume `<name>-dbdata` at `/var/lib/mysql`, no published port (internal to the stack network).
- **`<name>-web`** — `wordpress:latest`, files on volume `<name>-wpdata` at `/var/www/html`, published on the web port. WordPress is pointed at the database automatically.

After it comes up, open `http://localhost:<web port>` (the stack detail view has an **Open in Browser** button) and you'll land on the WordPress install screen — already talking to the database.

### Custom stack

Build your own. You define a **web service** (image, published ports, environment, volume/bind mounts) and optionally a **database service** (image, environment, volumes). If the database is enabled, you also choose a variable name — **"Inject DB address into web as"**, default `DB_HOST` — and ContainerManager adds `DB_HOST=<database IP>` to the web service's environment at startup so your app can find the database. The database is started first so its address is known before the web service launches.

## How services find each other

Containers on the same network reach each other by **IP address**. Reaching them by *name* would require a DNS domain (`container system dns create …`), which needs an admin password — so ContainerManager avoids it.

Instead, the orchestrator starts the database first, reads the IP it was assigned, and substitutes it into later services' environment. In templates this uses a token, e.g. WordPress is configured with `WORDPRESS_DB_HOST=${IP:db}:3306`, where `${IP:db}` is replaced with the running database container's IP. The custom builder does the same via the "Inject DB address" field. No DNS, no manual IP copying.

## Managing a stack

Select a stack in the **Stacks** section to:

- **Start / Stop** all of its containers together.
- **Open in Browser** — jumps to the web service's published port.
- **Delete** — stops and removes all the stack's containers and its network. **Data volumes are kept** (so you don't lose a database by deleting the stack); remove them yourself from the **Volumes** section if you want them gone.

Like all containers, a running stack keeps running after you quit ContainerManager (it's managed by the `container` daemon). After a reboot it comes back **stopped** — start it again from the Stacks section.

## Limitations and notes

- **Not a compose replacement.** A stack is a convenience grouping created at one moment; there's no stored manifest. To change a stack's makeup, delete it and create it again (data volumes persist, so a database survives).
- **IPs aren't pinned across restarts.** A container's IP is assigned when it starts and isn't guaranteed to be identical after a stop/start. Because the web↔database wiring is injected as an IP at creation time, if you stop and restart a stack and the web tier can't reach the database, recreate the stack. (Stable name-based addressing would require setting up a DNS domain, which is outside the no-friction flow.)
- **Custom env wiring is your responsibility.** ContainerManager injects the database IP into the variable you name, but the variable has to be one your web image actually reads (the WordPress template knows the right names; a custom image may differ).
