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
