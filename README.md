*This project has been created as part of the 42 curriculum by ghenriqu.*

# Inception

A containerised web infrastructure built from scratch with Docker and Docker Compose:
NGINX with TLS termination, WordPress running on PHP-FPM, and MariaDB, each in its own
container, wired together over a private bridge network.

---

## Description

The goal of this project is to build a small but complete server infrastructure using
Docker, without relying on any pre-built application image. Every image in this
repository is written from a `debian:bookworm` base and configured by hand.

The mandatory stack is made of three services:

| Service | Role | Listens on |
|---|---|---|
| **nginx** | TLS termination and the single entry point to the infrastructure | `443` (published) |
| **wordpress** | The WordPress CMS executed by PHP-FPM | `9000` (internal only) |
| **mariadb** | The relational database backing WordPress | `3306` (internal only) |

Only port 443 is reachable from outside. NGINX serves static assets directly from the
WordPress volume and forwards every PHP request to PHP-FPM over FastCGI. PHP-FPM in turn
connects to MariaDB. Neither PHP-FPM nor MariaDB is ever exposed to the host.

Five optional services are also included, isolated behind a Compose profile so their
absence never affects the mandatory stack:

| Service | Role | Reachable at |
|---|---|---|
| **redis** | Object cache for WordPress, password-protected | internal only |
| **adminer** | Web client for the database | `https://adminer.ghenriqu.42.fr` |
| **website** | Static multilingual site (HTML/CSS, no PHP) | `https://website.ghenriqu.42.fr` |
| **uptime-kuma** | Monitoring and availability dashboard | `https://uptime.ghenriqu.42.fr` |
| **ftp** | FTPS access to the WordPress volume | `ftps://ghenriqu.42.fr:21` |

Two levels of documentation accompany this README: `USER_DOC.md` for day-to-day
operation, and `DEV_DOC.md` for setting up and developing the project.

---

## Instructions

### Prerequisites

- A virtual machine running a Linux distribution with Docker Engine and the Docker
  Compose plugin installed
- `make`, `openssl` and `sudo` privileges (needed only to write `/etc/hosts`)
- Roughly 20 GB of free disk space and at least 2 GB of RAM (4 GB recommended if you
  intend to build the bonus services)

### First run

```bash
git clone https://github.com/ghenriqub/containerizedServer.git
cd containerizedServer

# Create the environment file from the template and adjust it
cp srcs/.env.example srcs/.env
$EDITOR srcs/.env          # set DOMAIN_NAME and DATA_PATH to match your login

# Build and start the mandatory stack
make
```

`make` is the single entry point. It validates the environment file, creates the host
data directories, generates any missing secret files, adds the domain names to
`/etc/hosts`, and finally builds the images and starts the containers.

The first build takes several minutes: Docker downloads the Debian base image and
installs every package from scratch. Subsequent runs reuse the build cache.

Once the containers are up, open `https://ghenriqu.42.fr` in a browser. The certificate
is self-signed, so the browser will warn you before letting you through. The
administration panel is at `https://ghenriqu.42.fr/wp-admin`, and the generated
administrator password can be read with `cat secrets/credentials.txt`.

### Available targets

| Target | Effect |
|---|---|
| `make` | Provision the host, build the images and start the mandatory stack |
| `make bonus` | Same, including the five optional services |
| `make down` | Stop and remove the containers; all data is kept |
| `make clean` | Remove the containers and the Docker volume definitions; the data on the host is kept |
| `make fclean` | Remove containers, volumes, images **and** the host data directories |
| `make re` | `clean` followed by a fresh build and start |
| `make ps` | Show the status of every container |
| `make logs` | Follow the logs of every container |

The distinction between `clean` and `fclean` matters. Because the named volumes are
backed by directories under `DATA_PATH`, `docker compose down -v` removes the volume
definitions but leaves the underlying files on the host untouched. `fclean` is the only
target that actually destroys the data.

---

## Project description

### Why Docker, and how it is used here

Each service is described by its own `Dockerfile` under
`srcs/requirements/<service>/`, following a consistent layout:

```
srcs/requirements/<service>/
├── Dockerfile          # image definition
├── .dockerignore       # keeps build contexts minimal
├── conf/               # configuration files copied into the image
└── tools/              # entrypoint script
```

`srcs/docker-compose.yml` declares the services, the private network, the named volumes
and the secrets. The `Makefile` at the root drives everything and is the only interface
a user is expected to touch.

The main design choices are the following.

**One process per container.** Every image runs exactly one service. This keeps images
small, makes failures easy to attribute, and lets each service be restarted
independently.

**The entrypoint always ends in `exec`.** Each entrypoint script performs its
initialisation and then replaces itself with the service process via `exec`, so that
process becomes PID 1. This matters because PID 1 receives the signals Docker sends: a
`docker stop` delivers `SIGTERM` to PID 1, and only a real service process will shut down
cleanly. If the shell script stayed as PID 1, signals would be swallowed and containers
would be killed abruptly after the grace period. For the same reason NGINX runs with
`daemon off`, PHP-FPM with `-F` and vsftpd with `background=NO`: none of them may fork
into the background.

**Initialisation is idempotent.** MariaDB checks whether its system tables already exist
before running `mariadb-install-db`; WordPress checks whether it has already been
installed before downloading and configuring it. Restarting the stack therefore never
reinstalls anything or destroys existing data.

**Readiness is probed, not assumed.** Compose's `depends_on` only controls the order in
which containers are *started*, not whether the service inside is ready to accept
connections. The WordPress entrypoint therefore polls MariaDB with `mariadb-admin ping`
in a bounded loop before continuing.

**Bonus services are behind a Compose profile.** They only exist when `make bonus` is
used, and the NGINX configuration resolves their addresses through runtime variables so
that the reverse proxy still loads when they are absent.

**Third-party downloads are pinned and verified.** Adminer and Uptime Kuma are fetched at
build time at a fixed version and checked against a recorded SHA-256 digest, so a build
either produces exactly the expected artefact or fails.

### Virtual Machines vs Docker

A virtual machine emulates a complete computer: the hypervisor provides virtual hardware,
and a full guest kernel and operating system are installed on top of it. A container
shares the host kernel and isolates only the process's view of the system, using kernel
namespaces (PID, network, mount, UTS, IPC, user) for visibility and cgroups for resource
limits.

The practical consequences are size and speed. A VM image carries an entire OS and boots
in tens of seconds; a container image carries only the userland files a service needs and
starts in milliseconds. Running the three services of this project as three VMs would
mean three kernels and several gigabytes of RAM; as containers they share one kernel and
a few hundred megabytes.

The trade-off is the strength of the isolation boundary. A VM is separated from the host
by the hypervisor, so a kernel vulnerability in the guest stays in the guest. Containers
share the host kernel, so a kernel-level escape affects the host directly. Containers are
an excellent isolation mechanism between cooperating services, and a weaker one against
genuinely hostile workloads. That is why this project runs the whole stack inside a
virtual machine: the VM is the security boundary, and the containers are the service
boundary inside it.

### Secrets vs Environment Variables

Environment variables are convenient but leak easily. They are inherited by every child
process, they are visible through `docker inspect` and in `/proc/<pid>/environ`, they are
frequently written to logs and crash reports, and if they are set in the `Dockerfile` they
are baked permanently into the image layers, where anyone who pulls the image can read
them.

Docker secrets are mounted as files under `/run/secrets/` on a `tmpfs`, meaning they exist
only in memory, never touch the image layers, and are readable only inside the containers
that explicitly declare them.

This project applies the distinction strictly:

- `srcs/.env` holds only non-sensitive configuration: the domain name, the data path, the
  database name, usernames, email addresses. Never a password.
- `secrets/*.txt` holds every password, generated locally by the `Makefile` with
  `openssl rand`, permissions `600`, and excluded from git through `.gitignore`.

Seven secrets are used: `db_root_password`, `db_password`, `credentials` (the WordPress
administrator password), `wp_user_password`, `redis_password`, `ftp_password` and
`kuma_password` (the Uptime Kuma administrator password). Every entrypoint reads them
directly from the mounted file under `/run/secrets/<name>`; none of them is ever passed
as an environment variable.

### Docker Network vs Host Network

With `network_mode: host` a container shares the host's network namespace directly: it has
no network isolation, it binds to the host's interfaces, and every port it opens is
immediately exposed. That would break the central requirement of this project, since
MariaDB on 3306 and PHP-FPM on 9000 would become reachable from outside.

This project uses a user-defined bridge network, `inception`. It provides a private
subnet, and Docker runs an embedded DNS resolver at `127.0.0.11` so containers reach each
other by service name: NGINX connects to `wordpress:9000`, WordPress to `mariadb:3306`.
No IP address is ever hard-coded, which means containers can be recreated with new
addresses without any configuration change.

Only NGINX publishes a port to the host, and only 443. Every other service uses `expose`,
which documents the port and makes it reachable on the internal network without opening
anything on the host. The legacy `--link` mechanism is not used: it is deprecated, it does
not survive container recreation, and it injects the linked container's environment
variables — including any secret — into the linking container.

### Docker Volumes vs Bind Mounts

A bind mount maps an arbitrary host path into a container. It is simple, but the container
inherits whatever ownership and permissions that path already has, and the configuration
is tied to the host's filesystem layout.

A named volume is managed by Docker: it has a name in the Docker namespace, it can be
listed, inspected, backed up and pruned with the Docker CLI, its lifecycle is independent
of any container, and its driver is pluggable — the same declaration can be backed by a
local directory or by network storage.

The subject requires named volumes whose data nonetheless lives under `/home/login/data`.
Both constraints are satisfied by declaring named volumes with the `local` driver and a
bind-type device:

```yaml
volumes:
  wordpress_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${DATA_PATH}/wordpress
```

These are named volumes as far as Docker is concerned — `docker volume ls` lists them and
the services reference them by name — while their backing storage is exactly where the
subject requires it. One consequence is worth knowing: `docker compose down -v` removes
the volume definitions but not the files under `DATA_PATH`, which is why this repository
distinguishes `make clean` from `make fclean`.

Two volumes are used, `wordpress_data` mounted at `/var/www/html` and `mariadb_data`
mounted at `/var/lib/mysql`, plus `uptime_kuma_data` for the bonus monitoring service.
NGINX mounts `wordpress_data` read-only, since it only ever needs to read static files
from it.

---

## Resources

### Documentation

- [Docker documentation](https://docs.docker.com/) — engine, build and CLI reference
- [Docker Compose file reference](https://docs.docker.com/reference/compose-file/) — services, networks, volumes, secrets, profiles
- [Dockerfile best practices](https://docs.docker.com/build/building/best-practices/)
- [NGINX documentation](https://nginx.org/en/docs/) — `http`, `ssl` and `fastcgi` modules
- [PHP-FPM configuration](https://www.php.net/manual/en/install.fpm.configuration.php)
- [MariaDB Knowledge Base](https://mariadb.com/kb/en/)
- [WP-CLI handbook](https://make.wordpress.org/cli/handbook/)
- [Debian packages](https://packages.debian.org/bookworm/) — verifying package names and contents for bookworm

### Articles and references

- [Docker and the PID 1 zombie reaping problem](https://blog.phusion.nl/2015/01/20/docker-and-the-pid-1-zombie-reaping-problem/)
- [Mozilla SSL Configuration Generator](https://ssl-config.mozilla.org/) — TLS protocol and cipher baselines
- [`namespaces(7)`](https://man7.org/linux/man-pages/man7/namespaces.7.html) and [`cgroups(7)`](https://man7.org/linux/man-pages/man7/cgroups.7.html) — the kernel features containers are built on
- [vsftpd.conf(5)](https://security.appspot.com/vsftpd/vsftpd_conf.html) — FTPS and passive mode configuration

### Use of AI

AI (Claude) was used as a technical review and rubber-duck partner, not as a code
generator. Concretely:

- **Concept clarification before writing code.**
- **Code review of files already written.**
- **Debugging assistance.**
- **Verifying assumptions against primary sources.**
- **Documentation drafting.**

Every suggestion was tested locally before being kept, and several were rejected or
corrected after testing. The reasoning behind each configuration choice in this
repository is documented in the inline comments of the files themselves.
