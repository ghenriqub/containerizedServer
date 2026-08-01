# Inception — Developer Documentation

This document describes how to set up the environment from scratch, build and launch the
infrastructure through the `Makefile` and Docker Compose, manage the containers and
volumes, and understand where the data lives and how it persists.

The examples use `ghenriqu` as the 42 login, `ghenriqu.42.fr` as the domain and
`/home/ghenriqu/data` as the data path. All three come from `srcs/.env`; substitute your
own values.

---

## 1. Setting up the environment from scratch

### 1.1 Virtual machine

The subject requires the project to run inside a virtual machine. Any hypervisor works
(VirtualBox, VMware, QEMU/KVM, UTM); the guest must be a Linux distribution with Docker
support — Debian, Ubuntu and Fedora are all fine.

Suggested resources:

| Resource | Mandatory stack | With bonus |
|---|---|---|
| CPU | 2 cores | 2–4 cores |
| RAM | 2 GB | 4 GB — the Uptime Kuma build runs `npm ci` and a native compile step, which is the memory-hungry part of the whole project |
| Disk | 15 GB | 20–25 GB |
| Network | NAT or bridged — required, since every image installs packages at build time |

If you intend to reach the site from the physical host rather than from inside the VM, use
a bridged adapter or forward port 443 (plus 21 and 30000–30009 for FTPS).

### 1.2 Docker Engine and the Compose plugin

On Fedora:

```bash
sudo dnf -y install dnf-plugins-core
sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
sudo dnf -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
```

On Debian / Ubuntu:

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/debian $(. /etc/os-release && echo $VERSION_CODENAME) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo usermod -aG docker $USER
```

The group change takes effect on the next login — `newgrp docker` applies it to the current
shell. Verify:

```bash
docker --version
docker compose version     # must be v2.x; the Makefile uses the plugin syntax
docker run --rm hello-world
```

Distribution note: on Fedora, `dnf install docker` installs Moby, not Docker CE. Both work,
but the Docker CE repository is closer to upstream and keeps `docker compose` in sync with
the plugin releases. `make` verifies at startup that the daemon answers and that the
Compose v2 plugin is present, and fails with a clear message otherwise.

### 1.3 Repository layout

```
containerizedServer/
├── Makefile                     # the only interface you are expected to use
├── README.md
├── USER_DOC.md
├── DEV_DOC.md
├── .gitignore                   # excludes secrets/ and srcs/.env
├── secrets/                     # generated locally, never committed
└── srcs/
    ├── .env.example             # committed template
    ├── .env                     # your local copy, never committed
    ├── docker-compose.yml
    └── requirements/
        ├── mariadb/
        │   ├── Dockerfile
        │   ├── .dockerignore
        │   ├── conf/50-server.cnf
        │   └── tools/init.sh
        ├── nginx/
        │   ├── Dockerfile
        │   ├── .dockerignore
        │   ├── conf/nginx.conf
        │   └── tools/entrypoint.sh
        ├── wordpress/
        │   ├── Dockerfile
        │   ├── .dockerignore
        │   ├── conf/www.conf
        │   └── tools/init.sh
        └── bonus/
            ├── adminer/         # Dockerfile, conf/{www.conf,99-adminer.ini}, tools/init.sh
            ├── ftp/             # Dockerfile, conf/vsftpd.conf, tools/init.sh
            ├── redis/           # Dockerfile, conf/redis.conf, tools/init.sh
            ├── uptime-kuma/     # Dockerfile, tools/init.sh
            └── website/         # Dockerfile, conf/nginx.conf, site/, tools/init.sh
```

Every service follows the same shape: `Dockerfile` + `.dockerignore` + `conf/` +
`tools/`. Keeping that consistent matters more than it looks — it means the build context
of each image contains only what that image needs, and a reader can find any file without
searching.

### 1.4 The environment file

```bash
cp srcs/.env.example srcs/.env
$EDITOR srcs/.env
```

| Variable | Meaning |
|---|---|
| `DOMAIN_NAME` | Public name of the site; also used for the certificate CN/SAN and the `/etc/hosts` entry |
| `DATA_PATH` | Absolute host path backing the named volumes — must be `/home/<login>/data` per the subject |
| `MYSQL_DATABASE` | Name of the WordPress database |
| `MYSQL_USER` | Database user WordPress connects with (must not be `root`) |
| `WP_TITLE` | Site title passed to `wp core install` |
| `WP_ADMIN_USER`, `WP_ADMIN_EMAIL` | WordPress administrator account |
| `WP_USER`, `WP_USER_EMAIL` | Second WordPress account, created with the `editor` role |
| `FTP_USER` | System user created inside the FTP image (bonus) |
| `FTP_PASV_ADDRESS` | Address advertised to FTPS clients for passive data connections (bonus) |

No password ever goes in this file. Passwords that need to reach a container go through
Docker secrets; passwords that only describe configuration do not exist.

`make check-env` validates the file before anything is built:

- `srcs/.env` exists, and `DOMAIN_NAME` and `DATA_PATH` are non-empty
- `DATA_PATH` is an **absolute** path, and is not one of `/`, `/home`, `/root`, `/usr`,
  `/var`, `/etc` or `$HOME` — `make clean` and `make fclean` run `sudo rm -rf` on
  directories derived from it, so an empty or careless value would be catastrophic
- `WP_ADMIN_USER` does not contain `admin` in any case combination, which the subject
  forbids

These checks exist because the failure modes they prevent are silent and expensive.

### 1.5 Secrets

The `Makefile` generates them; you do not create them by hand:

```bash
make secrets
```

For each of the six files it creates the file only if it is missing or empty:

```
openssl rand -base64 24 | tr -d '\n' > secrets/<name>.txt
chmod 600 secrets/<name>.txt      # directory is chmod 700
```

Two details matter.

**`tr -d '\n'`** strips the trailing newline. The entrypoints read these files with `cat`,
so a trailing newline would become part of the password string. MariaDB would store the
password *with* the newline while some clients send it *without* — an authentication
failure that looks like a wrong password and is genuinely unpleasant to debug. Removing the
newline at creation time eliminates the whole class of bug.

**Existing files are never overwritten.** Secrets are the shared state between the
`secrets/` directory and the initialised database. If a fresh secret were generated while
`DATA_PATH` still held a MariaDB data directory created with the old one, WordPress would
fail to connect on every boot. This is also why `make fclean` removes the data *and* the
secrets together, and `make clean` removes neither.

Generation happens at runtime, in the `Makefile`, never at build time in a `Dockerfile` — a
secret baked into an image layer is readable by anyone who obtains the image.

### 1.6 Host directories and `/etc/hosts`

Both are handled by `make`, but they are worth knowing about.

`make dirs` creates `$(DATA_PATH)/mariadb`, `$(DATA_PATH)/wordpress` and
`$(DATA_PATH)/uptime-kuma`. They must exist *before* Compose starts, because the named
volumes use `type: none, o: bind`, and the Linux bind mount fails if the source directory
does not exist.

`make hosts` rewrites the project's line in `/etc/hosts` (needs `sudo`). The line is tagged
with a trailing `# inception` comment so it can be replaced or deleted precisely rather
than by matching on the domain:

```
127.0.0.1 ghenriqu.42.fr adminer.ghenriqu.42.fr website.ghenriqu.42.fr uptime.ghenriqu.42.fr # inception
```

`make unhosts` removes it. On Fedora, if resolution still fails while `systemd-resolved` is
active, check that the `hosts:` line in `/etc/nsswitch.conf` lists `files` before `resolve`
and `dns`.

---

## 2. Building and launching

### 2.1 Targets

| Target | Effect |
|---|---|
| `make` | `check-docker check-env dirs secrets hosts up`, then prints `info` |
| `make bonus` | Same, with the `bonus` profile enabled |
| `make build` / `make build-bonus` | Build the images without starting anything |
| `make up` / `make up-bonus` | Start without re-running the host provisioning steps |
| `make stop` / `make start` / `make restart` | Container lifecycle, nothing else touched |
| `make down` | Remove the containers; volumes, data and images kept |
| `make clean` | `down -v` plus `rm -rf` of the host data directories |
| `make fclean` | `clean` plus images, secrets, `/etc/hosts` entry, dangling images and this project's build cache |
| `make re` | `clean` then `all` |
| `make ps` / `make logs` / `make info` | Inspection |
| `make prune` | Global `docker system prune -af --volumes` — every project on the machine; asks for confirmation |
| `make legacy-clean` | Removes leftovers from the old `srcs` Compose project name |

Every Compose invocation is `docker compose -p inception -f srcs/docker-compose.yml
--env-file srcs/.env`, and the teardown targets add `--profile bonus` so they also catch
bonus containers even when the stack was started without them.

The explicit project name is deliberate. Compose derives the project name from the
directory containing the file, which here would be `srcs`; that prefix ends up on every
volume, network and default container name. Pinning it to `inception` makes the names stable
and readable (`inception_wordpress_data`, `inception_inception`) regardless of what the
checkout directory is called. `make legacy-clean` exists to clean up resources created
before that was pinned.

### 2.2 What happens during `make`

1. `check-docker` — the daemon answers and the Compose v2 plugin is installed.
2. `check-env` — `srcs/.env` is present and sane (see §1.4).
3. `dirs` — the host data directories exist.
4. `secrets` — any missing secret file is generated.
5. `hosts` — the `/etc/hosts` line is refreshed.
6. `up` — `docker compose up -d --build --remove-orphans`:
   - each image is built if it does not exist or if its build context changed;
   - the bridge network `inception` is created;
   - the named volumes are created, each bind-backed by its host directory;
   - containers start in dependency order: mariadb → wordpress → nginx;
   - each entrypoint runs its first-boot logic if needed, then `exec`s its service as PID 1.
7. `info` — prints the URLs and `docker compose ps`.

A point worth internalising for the defence: `depends_on` controls **start order only**. It
does not wait for MariaDB to be ready to accept queries. That is why the WordPress
entrypoint polls with `mariadb-admin ping` in a bounded loop (30 attempts, 2 s apart) before
running WP-CLI.

### 2.3 Build cache

Docker caches every layer. Changing a file that is `COPY`ed into an image invalidates that
layer and everything after it; earlier layers are reused. This is why the `apt-get install`
lines come before the `COPY` lines in every Dockerfile — editing an entrypoint script must
not force a reinstall of the whole userland.

To force a clean rebuild:

```bash
docker compose -p inception -f srcs/docker-compose.yml --env-file srcs/.env build --no-cache
make up
```

---

## 3. Managing containers, volumes, networks and images

All commands below assume the project name `inception`. Setting a shell alias makes them
shorter:

```bash
alias dc='docker compose -p inception -f srcs/docker-compose.yml --env-file srcs/.env'
```

### Containers

```bash
dc ps                       # status
dc --profile bonus ps       # including bonus services
dc logs -f nginx            # follow one service
dc exec mariadb bash        # interactive shell
dc restart wordpress
docker stats                # live CPU / memory / network per container
docker inspect --format '{{.State.Status}} restarts={{.RestartCount}}' mariadb
```

A `RestartCount` that keeps climbing means the container is crash-looping rather than
running — the restart policy is hiding a failure. Read the logs before assuming it is
healthy just because `ps` says `Up`.

Container names are pinned with `container_name`, so `docker exec -it wordpress bash` works
directly without the Compose prefix.

### Volumes

```bash
docker volume ls | grep inception
docker volume inspect inception_wordpress_data
docker volume inspect inception_mariadb_data --format '{{ .Options.device }}'
docker volume rm inception_wordpress_data      # containers must be stopped first
```

`docker volume inspect` shows `"Mountpoint": /var/lib/docker/volumes/...` *and* the
`device` option pointing at `DATA_PATH`. The device is where the bytes actually are; the
mountpoint is only the directory Docker bind-mounts onto.

### Network

```bash
docker network ls | grep inception
docker network inspect inception_inception

# name resolution between containers
dc exec wordpress getent hosts mariadb
dc exec nginx getent hosts wordpress
```

`getent hosts` is preferable to `ping` here: the images do not ship `iputils-ping`, and
resolution is what you actually want to test.

### Images

```bash
docker images | grep inception          # mariadb:inception, wordpress:inception, ...
dc --profile bonus down --rmi all       # remove the project images
docker image prune                      # dangling layers
docker builder prune                    # build cache
```

Every image is tagged `<service>:inception` — the subject requires the image name to match
the service name, and an explicit tag avoids `latest`, which is prohibited.

---

## 4. Data storage and persistence

### Where the data lives

| Volume | Mounted at | Host directory | Contents |
|---|---|---|---|
| `inception_mariadb_data` | `/var/lib/mysql` | `${DATA_PATH}/mariadb` | InnoDB tablespaces, redo logs, system tables |
| `inception_wordpress_data` | `/var/www/html` | `${DATA_PATH}/wordpress` | WordPress core, `wp-config.php`, themes, plugins, uploads |
| `inception_uptime_kuma_data` | `/app/data` | `${DATA_PATH}/uptime-kuma` | Uptime Kuma SQLite database and its own credentials (bonus) |

`wordpress_data` is mounted in three containers: read-write in `wordpress` (PHP-FPM writes
uploads and plugin files), **read-only** in `nginx` (it only serves static assets), and
read-write in `ftp` (that is the point of the FTPS bonus).

### How the named volumes are declared

```yaml
volumes:
  wordpress_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${DATA_PATH}/wordpress
```

This satisfies both constraints of the subject at once: Docker treats these as named
volumes (they appear in `docker volume ls`, services reference them by name, their lifecycle
is independent of any container), while the bytes live under `/home/<login>/data` as
required. Bind mounts declared in a service's `volumes:` list — the `- /host/path:/container/path`
form — are not used anywhere.

The consequence to remember: `docker compose down -v` removes the *volume definition*, not
the host directory it is bound to. That asymmetry is exactly why `make clean` follows the
`down -v` with an explicit `rm -rf` of the data directories, and why the two are documented
as one operation.

### What survives what

| Event | Data | Why |
|---|---|---|
| `make stop` / `make start` | kept | Containers are paused, not removed |
| `make down` | kept | Containers removed; volumes untouched |
| `docker kill <name>` | kept | `restart: always` brings it back; volumes untouched |
| VM reboot | kept | The Docker daemon restarts the containers and remounts the volumes |
| `make clean` / `make re` | **lost** | Volumes removed *and* host directories deleted |
| `make fclean` | **lost** | Same, plus images and secrets |
| `docker compose down --rmi all` | kept | Images are rebuilt on the next `make`; volumes survive |
| Loss of the VM disk | **lost** | The volumes live on the VM filesystem — back up outside it |

### First boot vs subsequent boots

Each entrypoint detects whether initialisation already happened, so restarting never
reinstalls anything:

- **MariaDB** checks for `/var/lib/mysql/mysql`. If absent it runs `mariadb-install-db`.
  It then always writes a small `init.sql` and starts `mariadbd --init-file=...`, which is
  idempotent by construction: `ALTER USER` for root, `CREATE DATABASE IF NOT EXISTS`,
  `CREATE USER IF NOT EXISTS` plus `ALTER USER` and `GRANT` for the WordPress user. The
  init file is written with mode `600` and owned by `mysql`, because it contains the
  passwords in clear text for the duration of the startup.
- **WordPress** checks for `/var/www/html/wp-config.php`. If absent it runs `wp core
  download`, `wp config create`, `wp core install` and `wp user create`. If present it
  skips straight to PHP-FPM. The Redis block runs on every boot but is conditional on
  `getent hosts redis` succeeding, so the mandatory stack is unaffected when the bonus
  profile is off.
- **NGINX** has no volume-dependent state: the certificate is generated at build time and
  the entrypoint only verifies that the key and certificate exist before `exec`ing.

### Backup and restore

```bash
# database
docker exec mariadb mariadb-dump -u root -p"$(cat secrets/db_root_password.txt)" \
  --single-transaction wordpress > backup_db_$(date +%F).sql

# files
sudo tar -czf backup_wp_$(date +%F).tar.gz -C /home/ghenriqu/data/wordpress .

# restore the database
docker exec -i mariadb mariadb -u root -p"$(cat secrets/db_root_password.txt)" \
  wordpress < backup_db_2026-08-01.sql
```

`--single-transaction` takes a consistent snapshot of the InnoDB tables without locking
them, so the site keeps serving during the dump.

---

## 5. Adding a service

The bonus services are all built the same way; adding a sixth follows the same recipe:

1. Create `srcs/requirements/bonus/<name>/` with `Dockerfile`, `.dockerignore`, `conf/` and
   `tools/init.sh`. Copy an existing `.dockerignore` — it keeps the build context to what
   the image actually needs.
2. Base the image on `debian:bookworm`, install with `--no-install-recommends`, and finish
   with `rm -rf /var/lib/apt/lists/*` in the same `RUN` so the cache never enters a layer.
3. Write the entrypoint so it validates its inputs, performs any first-boot work, and ends
   with `exec`. The service must not daemonise.
4. Add the service to `srcs/docker-compose.yml` with `profiles: [bonus]`, `restart: always`,
   `networks: [inception]`, and `expose` rather than `ports` unless the protocol genuinely
   requires a host port.
5. If it needs a password, add a secret to the `secrets:` block, list it in the service, and
   add the filename to `SECRETS` in the `Makefile` so it is generated automatically.
6. If it needs to be reachable from a browser, add a `server` block to
   `srcs/requirements/nginx/conf/nginx.conf`, add the subdomain to the certificate's
   `subjectAltName` in the NGINX `Dockerfile`, and add it to `HOSTS_LINE` in the `Makefile`.

That last step has a subtlety worth understanding, because it is a likely defence question.
NGINX resolves upstream names at configuration-load time. If a bonus container is absent,
`fastcgi_pass adminer:9000;` makes the whole configuration fail to load — which would break
the mandatory stack. The bonus `server` blocks therefore declare
`resolver 127.0.0.11 valid=30s ipv6=off;` and pass the upstream through a variable
(`set $adminer_upstream adminer:9000; fastcgi_pass $adminer_upstream;`). A variable forces
runtime resolution: NGINX starts regardless, and only that virtual host returns `502` when
the service is missing.

---

## 6. Known constraints and pitfalls

**`server_name` is not templated.** The certificate takes `DOMAIN_NAME` as a build argument,
but `nginx.conf` contains the domain literally. If you change `DOMAIN_NAME` in `srcs/.env`,
update the four `server_name` directives too. Without that, requests still reach the first
`server` block (NGINX's default), so the site appears to work while the bonus subdomains
quietly fall through to WordPress.

**The certificate needs every subdomain in `subjectAltName`.** Modern browsers ignore the
CN entirely and validate against the SAN list. A certificate issued only for
`ghenriqu.42.fr` is rejected outright on `adminer.ghenriqu.42.fr`, with no "proceed anyway"
option in some browsers.

**The 42 header must not be the first bytes of a shell script.** The kernel reads the first
two bytes looking for `#!`; a comment block before the shebang produces `exec format
error`. Every `tools/*.sh` in this repository starts with `#!/bin/bash` and carries the
header immediately after.

**PHP-FPM must listen on TCP, not a Unix socket.** `listen = 0.0.0.0:9000` in `www.conf`.
A Unix socket only works between processes sharing a filesystem; NGINX and PHP-FPM are in
separate containers with separate mount namespaces.

**PHP package names on bookworm.** WP-CLI needs `php8.2-cli` alongside `php8.2-fpm`, and
the MySQL driver package is `php8.2-mysql` — `php8.2-mysqli` does not exist.

**Everything must run in the foreground.** `nginx -g 'daemon off;'`, `php-fpm8.2 -F`,
`vsftpd` with `background=NO`, `redis-server` with `daemonize no`. A service that forks into
the background makes the entrypoint exit and the container die.

**Third-party artefacts are pinned and verified.** Adminer and Uptime Kuma are downloaded at
a fixed version and checked against a recorded SHA-256. A new upstream release therefore
*breaks the build on purpose* until you update both the version and the digest — which is
the intended behaviour, not a bug.

**Uptime Kuma is the heaviest build.** It uses a multi-stage build with Node 22 and a
native compilation step. Under 2 GB of RAM it can be OOM-killed mid-build; the entrypoint
detects the resulting incomplete image and fails with an explicit message instead of
crash-looping.

**FTPS passive mode depends on the client's network position.** `FTP_PASV_ADDRESS` is the
address the server advertises for data connections. `127.0.0.1` works only from inside the
VM; from anywhere else it must be the VM's reachable IP, and the range 30000–30009 must be
open.
