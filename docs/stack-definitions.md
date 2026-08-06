# Stack definitions (`.containerstack`)

Stack templates are plain JSON documents. The templates that ship with the app use
the exact same format — open any template's create sheet and click **Export…** to
get a working example to tweak.

## Importing

- **Stacks ▸ New Stack ▸ Import Template…** — choose a `.containerstack`/`.json`
  file, or a `docker-compose.yml` (converted on the way in, see below).
- **Double-click** a `.containerstack` file in Finder.
- Imported templates live in
  `~/Library/Application Support/ContainerManager/StackTemplates/` and appear in the
  New Stack menu. That folder *is* the management UI: **New Stack ▸ Show Templates
  Folder** opens it — edit a file in place or delete it, and the menu reflects it
  the next time it opens.

## Format

```json
{
  "version": 1,
  "id": "wordpress",
  "name": "WordPress + MariaDB",
  "summary": "Shown under the create form.",
  "systemImage": "globe",
  "fields": [
    {"key": "name", "label": "Stack name", "default": "mysite"},
    {"key": "password", "label": "Database password", "default": "wordpress", "kind": "password"},
    {"key": "port", "label": "Web port", "default": "8080", "kind": "port"}
  ],
  "services": [
    {
      "key": "db", "displayName": "MariaDB", "image": "mariadb:11",
      "env": ["MARIADB_ROOT_PASSWORD=${password}"],
      "volumes": ["${name}-dbdata:/var/lib/mysql"]
    },
    {
      "key": "web", "displayName": "WordPress", "image": "wordpress:latest",
      "env": ["WORDPRESS_DB_HOST=${IP:db}:3306"],
      "publishPorts": ["${port}:80"]
    }
  ],
  "web": {"serviceKey": "web", "portField": "port"}
}
```

- **`fields`** define the create form. `kind` is `text` (default), `password`,
  `port` (validated 1–65535), or `directory` (folder picker, required). A `name`
  field is required; its value is sanitized to a valid resource name and also names
  the stack's network (`<name>-net`) and is handy for volume names.
- **`services`** are created and started in order. Two token kinds may appear in
  `image`, `env`, `volumes`, and `publishPorts` strings:
  - `${<fieldKey>}` — replaced with the value entered on the create form.
  - `${IP:<serviceKey>}` — replaced *at start time* with that service's IP, for
    wiring services together (e.g. `WORDPRESS_DB_HOST=${IP:db}:3306`).
- **`web`** (optional) marks which service has the browser-facing port; the stack
  then gets an **Open in Browser** affordance at `http://localhost:<port field>`.
- Named volumes (`mydata:/path`) persist across stack deletion; host paths
  (`/Users/you/site:/path[:ro]`) bind-mount from your Mac.

## docker-compose import

Importing a `.yml`/`.yaml` compose file converts a practical subset: `image`
(required — `build:` isn't supported; build the image in Images ▸ Build Image…
first), `environment`, `ports`, `volumes` (relative host paths resolved against the
compose file's location), and `depends_on` (start order). References to another
service by name (`db`, `db:3306`, `…@db:…`) are rewritten to `${IP:…}` tokens,
since containers don't resolve each other by hostname here. Anything else
(`restart:`, `healthcheck:`, …) is skipped and listed in the imported template's
`notes` so you can see what didn't carry over.

A compose file's `${VAR}` references become fields on the create form, prefilled
from a `.env` sitting beside it (or loaded later with **Import .env…**), with
password-like names masked. `${VAR:-default}` is honoured. Whatever couldn't be
carried over is listed with the reason it was skipped, both in the summary shown
after import and in the stack's log.

## Limitations

These are deliberate, and worth knowing before you plan around them.

- **Services reach each other by IP, not name.** Container-name DNS doesn't
  resolve on stock `container` (network aliases are not available), which is why
  imports rewrite service references to `${IP:…}`. The address is substituted
  when the container is *created*, and the runtime hands out new ones as
  containers start. **Starting a stack reconciles this**: services come up in
  dependency order, and any whose addresses have gone stale are re-created with
  the current ones — changing only the address entries, so anything you've edited
  by hand survives. A service started on its own, outside the stack, isn't
  reconciled.
- **Environment is otherwise fixed at creation.** Editing a `.env` afterwards
  changes nothing until the service is replaced. The same applies to anything a
  service stores about itself, such as a server URL recorded during first-run
  setup — point those at `localhost:<published port>` rather than a container
  address, since that survives a restart.
- **`depends_on` conditions are approximated.** Compose's `service_healthy` and
  `service_completed_successfully` aren't evaluated; instead each service is
  waited on until it accepts TCP connections on the ports it exposes, up to two
  minutes, before the next one starts.
- **Images aren't built.** `build:` services are skipped rather than failing the
  whole file. Build the image first, then reference it by tag.
- **Image `VOLUME` contents aren't copied into fresh volumes.** Some images
  expect a mounted directory to be pre-populated or owned by their runtime user;
  those may need an init service that fixes ownership before the main service
  starts.
- **Only what the runtime supports.** `restart:`, `healthcheck:`, `cap_add:`,
  `profiles:`, `secrets:`, `extends:` and similar have no equivalent here.

If you need full compose fidelity, `container-compose` implements far more of the
spec as a `container` CLI plugin, at the cost of running a forked runtime.
