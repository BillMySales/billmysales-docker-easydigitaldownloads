Easy Digital Downloads Docker stack
===================================

Docker Compose stack for an [Easy Digital Downloads](https://easydigitaldownloads.com)
store (WordPress plugin for selling digital products), usable for local development and
for simple production deployments (a single server, better than shared
hosting). Maintained by [BillMySales](https://www.billmysales.com).

| Component   | Image                                | Default version      |
|-------------|--------------------------------------|----------------------|
| Web server  | `caddy:<ver>-alpine`                 | 2.11                 |
| WordPress   | `wordpress:<wp>-php<php>-fpm-alpine` | 7.1.2 / PHP 8.4      |
| Easy Digital Downloads | installed by WP-CLI (`setup`) | latest (dev: 3.7.1) |
| Database    | `mariadb`                            | 12.3 (LTS)           |
| WP-CLI      | `wordpress:cli-<ver>-php<php>`       | 2.12                 |
| Redis       | `redis:<ver>-alpine` (optional)      | 8.8                  |
| Mailpit     | `axllent/mailpit` (optional, dev)    | v1.31                |

All images are official (Docker Official Images, or the vendor's for Mailpit);
nothing is built locally.

Requirements
------------

- Docker Engine 24+ with the Compose v2 plugin (`docker compose`, 2.20+).
- Development: ports 8107, 8407 and 8025 free on the host.
- Production: a server with ports 80 and 443 reachable, and a DNS record for
  the store's domain pointing to it.

Quick start (development)
-------------------------

```shell
cp .env.dev.example .env
docker compose up -d
docker compose logs -f setup   # wait for "==> Done"
```

- Store: http://localhost:8107
- Admin: http://localhost:8107/wp-admin (user `admin`, password `admin`)
- Mailpit (every email the store sends): http://localhost:8025

Production
----------

```shell
cp .env.prod.example .env
# Fill in WP_URL, SITE_ADDRESS, DB_PASSWORD, DB_ROOT_PASSWORD,
# WP_ADMIN_PASSWORD, WP_ADMIN_EMAIL and the SMTP_* values.
docker compose up -d
```

- With `SITE_ADDRESS` set to the domain, Caddy gets a Let's Encrypt certificate
  and renews it automatically (certificates live in the `caddy_data` volume).
- Behind another TLS-terminating proxy, use `SITE_ADDRESS=:80`; the
  `X-Forwarded-Proto: https` header is enough for WordPress to detect HTTPS.
- Compose refuses to start while a required value is missing.
- Configure SMTP: without it WordPress can't send any mail (order emails,
  password resets).
- The `backup` profile is enabled by default in the production template.
- Behind an existing Traefik (no host ports), use `overrides/traefik.yaml`
  (see [Overrides](#overrides)).

Services
--------

| Service     | Profile   | Role                                                           |
|-------------|-----------|----------------------------------------------------------------|
| `db`        |           | MariaDB, data in the `db_data` volume.                         |
| `wordpress` |           | PHP-FPM + WordPress (port 9000, internal), files in `wp_data`. |
| `caddy`     |           | Web server and TLS, the only published ports (80, 443).        |
| `setup`     |           | One-shot WP-CLI job (`scripts/setup.sh`), runs on every `up`.  |
| `cron`      |           | Runs WP-Cron and EDD's Action Scheduler every minute.          |
| `backup`    | `backup`  | DB dump + `wp-content` archive on a schedule.                  |
| `redis`     | `redis`   | Object cache (with `REDIS_HOST=redis`).                        |
| `mailpit`   | `mailpit` | Development SMTP server that catches all mail.                 |
| `wp`        | `tools`   | Ad hoc WP-CLI, not started by `up`.                            |

Optional services are enabled with `COMPOSE_PROFILES` in `.env`, e.g.
`COMPOSE_PROFILES=backup,redis`.

### What `setup` does

- Installs WordPress and Easy Digital Downloads if they are missing.
- On the first run only: activates Easy Digital Downloads (which creates the
  checkout, receipt and order history pages), installs the language
  (`WP_LOCALE`), sets country (`EDD_COUNTRY`), currency (`EDD_CURRENCY`) and
  the Chilean number format, skips the onboarding wizard, sets
  pretty permalinks and removes the sample plugins. It then stores the option
  `docker_stack_initialized`, so later changes made in the admin are kept.
- `EDD_VERSION` empty: the latest Easy Digital Downloads is installed once, then updated
  from the admin as usual. `EDD_VERSION` set: that exact version is enforced on
  every `up` (useful to test a plugin against a given version).
- On every run, when `SMTP_FROM` is set: the sender of the store's emails
  (Easy Digital Downloads' `from_email` / `from_name`, which win over
  WordPress' sender).
- Enables or disables the Redis object cache to match `REDIS_HOST`.

Common commands
---------------

```shell
docker compose ps                          # status: every service "healthy", setup "Exited (0)"
docker compose logs -f caddy wordpress     # web server and PHP logs
docker compose run --rm wp plugin list     # any WP-CLI command
docker compose exec db mariadb -u wordpress -p wordpress   # SQL shell
docker compose down                        # stop, keep data
docker compose down -v                     # stop and DELETE all data
```

Backups
-------

With the `backup` profile, the `backup` service writes
`<timestamp>-db.sql.gz` and `<timestamp>-wp-content.tar.gz` to the `backups`
volume (or `./data/backups` with `overrides/local-dirs.yaml`) at start and then
every `BACKUP_INTERVAL_HOURS`, and deletes files older than
`BACKUP_KEEP_DAYS`. Files are readable by their owner
only. WordPress core is not backed up: it comes from the image.

```shell
docker compose run --rm --no-deps backup now                  # back up now
docker compose run --rm --no-deps backup list                 # list timestamps
docker compose stop cron                            # recommended while restoring
docker compose run --rm --no-deps backup restore <timestamp>  # restore DB and wp-content
docker compose start cron
```

`--no-deps` keeps the command from starting `setup` first (with damaged
data `setup` fails and the restore would never run); the database must
be running (`docker compose up -d db` if the stack is down).

Overrides
---------

Optional compose files in `overrides/`, enabled with `COMPOSE_FILE` in `.env`
(several are combined with `:`). Each file documents its variables.

```shell
COMPOSE_FILE=compose.yaml:overrides/traefik.yaml:overrides/local-dirs.yaml
```

| File                         | Purpose                                                           |
|------------------------------|-------------------------------------------------------------------|
| `overrides/traefik.yaml`     | Publish through an existing Traefik on a shared external network: |
|                              | no host ports, Traefik terminates TLS (`TRAEFIK_HOST`, ...).      |
| `overrides/local-dirs.yaml`  | Database, WordPress, Caddy and backups in local directories       |
|                              | (`DATA_DIR`, default `./data`) instead of named volumes.          |
| `overrides/plugin.yaml`      | Mount a plugin from a local directory, editable live              |
|                              | (`PLUGIN_PATH`, `PLUGIN_NAME`).                                   |

A local `compose.override.yaml` (gitignored) is also loaded automatically by
Docker Compose, for changes specific to one machine.

Configuration
-------------

Every variable is documented in `.env.prod.example`. Main groups:

- **Site and network**: `WP_URL`, `SITE_ADDRESS`, `HTTP_BIND`, `HTTP_PORT`,
  `HTTPS_PORT`.
- **Credentials**: `DB_PASSWORD`, `DB_ROOT_PASSWORD`, `WP_ADMIN_PASSWORD`,
  `WP_ADMIN_EMAIL` (required).
- **Store** (first install only): `WP_TITLE`, `WP_LOCALE`, `EDD_COUNTRY`,
  `EDD_CURRENCY`.
- **Versions**: `EDD_VERSION`, `WP_VERSION`, `PHP_VERSION`, `CADDY_VERSION`,
  `MARIADB_VERSION`, ...
- **PHP**: `PHP_MEMORY_LIMIT`, `UPLOAD_MAX_SIZE` (PHP and Caddy),
  `PHP_FPM_MAX_CHILDREN` and the rest of the FPM pool.
- **Mail**: `SMTP_HOST`, `SMTP_PORT`, `SMTP_SECURE`, `SMTP_USER`,
  `SMTP_PASSWORD`, `SMTP_FROM`, `SMTP_FROM_NAME`.
- **Resources and logs**: `*_MEMORY_LIMIT` per service, `LOG_MAX_SIZE`,
  `LOG_MAX_FILE` (Docker log rotation).

Configuration files, mounted read-only:

| File                                   | Purpose                                             |
|----------------------------------------|-----------------------------------------------------|
| `config/caddy/Caddyfile`               | Web server, TLS, security headers, blocked paths.   |
| `config/wordpress/config.php`          | Extra `wp-config.php` constants, from env vars.     |
| `config/wordpress/mu-plugins/smtp.php` | SMTP from env vars (`WPMU_PLUGIN_DIR` points here). |
| `config/wordpress/mu-plugins/currencies.php` | Chilean peso (CLP) for Easy Digital Downloads. |
| `config/php/php.ini`                   | PHP limits, from env vars.                          |
| `config/php/fpm-pool.conf`             | PHP-FPM pool sizing, from env vars.                 |

Notes:

- `WP_VERSION` only matters when the `wp_data` volume is created; afterwards
  WordPress core is updated from the admin (or with
  `docker compose run --rm wp core update`).
- The site URL comes from `WP_URL`, not from the database: changing the domain
  or port only needs `docker compose up -d`.
- Turning Redis off: remove `redis` from `COMPOSE_PROFILES`, empty
  `REDIS_HOST`, `docker compose up -d`, then `docker compose rm -sf redis`.
- From inside the containers, the host machine is reachable as
  `host.docker.internal`.
- Must-use plugins are loaded from `config/wordpress/mu-plugins`, not from
  `wp-content/mu-plugins`.
- Easy Digital Downloads has no Chilean peso: `currencies.php` adds CLP with
  the `$` symbol, no decimals and Chilean formatting (`$12.345`).

Security
--------

- Client IP headers: PHP gets only the real client IP (as Caddy sees it) in
  `REMOTE_ADDR`, `X-Forwarded-For` and `X-Real-IP`, and no `Client-Ip` or
  `Cf-Connecting-Ip` (a client could forge them): Easy Digital Downloads
  records customer IPs from `Client-Ip` or `X-Forwarded-For`.
- No default secrets: compose fails if the required passwords are missing. The
  development template uses public passwords; never use it on a server.
- Production defaults: `WP_DEBUG` off, `DISALLOW_FILE_EDIT` on, PHP version
  not exposed, no PHP execution in `uploads`, dotfiles blocked,
  `X-Content-Type-Options`, `X-Frame-Options` and `Referrer-Policy` headers.
- PHP gets the real client IP in `REMOTE_ADDR` (logs, login protection) also
  behind Traefik or another proxy on a private network.
- Only Caddy (and Mailpit in development) publishes ports; the database is
  internal. `HTTP_BIND` defaults to `127.0.0.1`.
- Not included: a web application firewall, login rate limiting, or off-site
  backup copies.

Validation
----------

What was checked for this stack (2026-09-24):

- Clean start (`down -v` + `up -d`) in about 40 s: every service `healthy`,
  `setup` `Exited (0)`; a second run makes no changes.
- Store, checkout pages, downloads archive and the EDD API (`/edd-api/v2/`)
  `200`; admin login; the dashboard and EDD's Downloads, Settings and Orders
  screens load all their CSS/JS (100+ files each, all `200`); no onboarding
  redirect; `/.htaccess` and PHP in `uploads` `403`.
- CLP, Chile and the `$12.345` format; store emails sent through SMTP to
  Mailpit with the configured sender.
- Settings changed in the admin survive `setup`; `EDD_VERSION` pins the version.
- Cron runs the Action Scheduler; backup and restore.
- HTTPS with `SITE_ADDRESS=localhost` (Caddy internal CA, HTTP/2); production
  defaults (`WP_DEBUG` off, file editor blocked).
- Overrides: Traefik v3.6 routing with no host ports and HTTPS links, local
  directories (including backups), a plugin mounted and served live.
- Not tested: issuing a real Let's Encrypt certificate (needs a public domain).

Resource usage
--------------

Idle, after a few requests: Caddy ~16 MiB, PHP-FPM ~80 MiB, MariaDB ~135 MiB,
cron and backup ~1 MiB between runs.

Why Caddy + PHP-FPM
-------------------

Lighter than the Apache image (about 170 MiB and 392 MB for Caddy + PHP-FPM,
versus 254 MiB and 801 MB for Apache + mod_php), the usual production layout,
and Caddy handles certificates by itself. `.htaccess` files are ignored; the
equivalent rules are in the Caddyfile. This stack shares its design with the
WooCommerce stack (same WordPress setup, another store plugin).

License
-------

[MIT](LICENSE).
