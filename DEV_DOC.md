# Inception — Developer Documentation

This document describes how a developer can set up the Inception project environment from scratch, build and launch the infrastructure, manage containers and volumes, and understand where data is stored and how it persists.

---

## Setting up the environment from scratch

### 1. Virtual machine

The project must run inside a virtual machine. Any hypervisor is acceptable (VirtualBox, VMware, UTM, QEMU/KVM). The guest operating system should be a Linux distribution with Docker support — Debian, Ubuntu, or Fedora are all valid choices.

Minimum recommended resources for the VM:

- 2 CPU cores
- 2 GB RAM (4 GB preferred — Docker builds can be memory-intensive)
- 20 GB disk space (Docker images, volumes, and build cache consume significant storage)
- Network adapter configured for NAT or bridged networking (needed for package installation during image builds)

### 2. Installing Docker and Docker Compose

On Debian/Ubuntu:

```bash
# Install prerequisites
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg

# Add Docker's official GPG key and repository
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine and Compose plugin
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Add your user to the docker group (avoids needing sudo for every docker command)
sudo usermod -aG docker $USER

# IMPORTANT: log out and log back in for the group change to take effect
# Alternatively, run: newgrp docker
```

On Fedora:

```bash
# Install from Fedora repositories
sudo dnf install -y docker docker-compose

# Start and enable the Docker daemon
sudo systemctl start docker
sudo systemctl enable docker

# Add your user to the docker group
sudo usermod -aG docker $USER

# Log out and back in, or run: newgrp docker
```

Verify the installation:

```bash
docker --version          # Should output Docker version 24.x or higher
docker compose version    # Should output Docker Compose v2.x
docker run hello-world    # Should pull and run the test image successfully
```

### 3. Configuring the domain name

Add an entry to `/etc/hosts` so that the project domain resolves to the local machine:

```bash
sudo sh -c 'echo "127.0.0.1 ghenriqu.42.fr" >> /etc/hosts'
```

Replace `ghenriqu` with your 42 username. Verify with:

```bash
ping -c 1 ghenriqu.42.fr
# Expected output: 64 bytes from 127.0.0.1 (127.0.0.1): ...
```

Edge case on Fedora: if `systemd-resolved` is active and the ping does not resolve, check `/etc/nsswitch.conf` and ensure the `hosts:` line lists `files` before `resolve` or `dns`. This guarantees that `/etc/hosts` is consulted first.

### 4. Creating the directory structure

Clone the repository and verify the structure matches the subject requirements:

```
inception/
├── Makefile
├── README.md
├── USER_DOC.md
├── DEV_DOC.md
├── secrets/
│   ├── credentials.txt          # WordPress admin password
│   ├── db_password.txt          # MariaDB WordPress user password
│   └── db_root_password.txt     # MariaDB root password
└── srcs/
    ├── .env                     # Environment variables (non-sensitive)
    ├── docker-compose.yml
    └── requirements/
        ├── mariadb/
        │   ├── Dockerfile
        │   ├── .dockerignore
        │   ├── conf/
        │   │   └── 50-server.cnf
        │   └── tools/
        │       └── entrypoint.sh
        ├── nginx/
        │   ├── Dockerfile
        │   ├── .dockerignore
        │   ├── conf/
        │   │   └── nginx.conf
        │   └── tools/
        │       └── entrypoint.sh
        ├── wordpress/
        │   ├── Dockerfile
        │   ├── .dockerignore
        │   ├── conf/
        │   │   └── www.conf
        │   └── tools/
        │       └── entrypoint.sh
        └──  bonus/
```

### 5. Creating the secret files

The secret files must be created manually on the machine and must never be committed to git. Each file contains a single password as a plain text string with no trailing newline.

```bash
mkdir -p secrets

# Generate strong passwords (or use your own)
# The openssl rand command produces cryptographically random strings
openssl rand -base64 24 | tr -d '\n' > secrets/db_root_password.txt
openssl rand -base64 24 | tr -d '\n' > secrets/db_password.txt
openssl rand -base64 24 | tr -d '\n' > secrets/credentials.txt

# Restrict file permissions — only the owner can read them
chmod 600 secrets/*.txt
```

Why `tr -d '\n'`: some tools and editors append a trailing newline to files. When the entrypoint scripts read these files with `cat`, a trailing newline becomes part of the password string. This causes authentication failures because the password stored in MariaDB does not include the newline, but the password sent by WordPress does. Stripping newlines at creation time prevents this class of bugs entirely.

### 6. Configuring the environment file

Edit `srcs/.env` and replace all placeholder values with your actual configuration:

```bash
# Domain
DOMAIN_NAME=ghenriqu.42.fr

# MariaDB
MYSQL_ROOT_PASSWORD_FILE=/secrets/db_root_password
MYSQL_DATABASE=wordpress
MYSQL_USER=wp_user
MYSQL_PASSWORD_FILE=/secrets/db_password

# WordPress
WP_TITLE=Inception
WP_ADMIN_USER=boss
WP_ADMIN_PASSWORD_FILE=/secrets/credentials
WP_ADMIN_EMAIL=boss@ghenriqu.42.fr
WP_USER=editor
WP_USER_EMAIL=editor@ghenriqu.42.fr
WP_USER_PASSWORD_FILE=/secrets/db_password
```

Key constraints to respect:

- `WP_ADMIN_USER` must not contain "admin", "Admin", "administrator", or "Administrator" in any form — the subject explicitly prohibits this and evaluators will check.
- Password values are not stored here — the `_FILE` suffix indicates that the variable holds a path to a Docker secret file, not the password itself.
- `MYSQL_USER` should not be "root" — root access to the database is restricted to localhost connections only (configured in the MariaDB entrypoint).

### 7. Creating the host data directories

Docker named volumes store their data at `/home/ghenriqu/data` on the host machine. These directories must exist before the first run:

```bash
sudo mkdir -p /home/ghenriqu/data/wordpress
sudo mkdir -p /home/ghenriqu/data/mariadb

# Set ownership to your user so Docker can write to them
sudo chown -R $USER:$USER /home/ghenriqu/data
```

---

## Building and launching the project

### The Makefile

The Makefile is the single entry point for all project operations. It wraps `docker compose` commands and ensures consistency.

| Target | Command executed | Effect |
|--------|-----------------|--------|
| `make` (default) | `docker compose -f srcs/docker-compose.yml up -d --build` | Builds images (if needed) and starts all containers in detached mode |
| `make down` | `docker compose -f srcs/docker-compose.yml down` | Stops and removes containers, preserves volumes |
| `make clean` | `docker compose -f srcs/docker-compose.yml down -v` | Stops containers and removes volumes (destroys all data) |
| `make re` | `make clean` then `make` | Full rebuild from scratch |

### What happens during `make`

1. Docker Compose reads `srcs/docker-compose.yml` and `srcs/.env`.
2. For each service (mariadb, wordpress, nginx), Docker builds the image from its Dockerfile if an image does not already exist or if any build context file has changed.
3. Docker creates the bridge network `inception` (if it does not exist).
4. Docker creates the two named volumes `wp_data` and `db_data` (if they do not exist), with the `local` driver configured to use `/home/ghenriqu/data/wordpress` and `/home/ghenriqu/data/mariadb` as their backing directories on the host.
5. Docker starts the containers in dependency order: MariaDB first, then WordPress (which depends on MariaDB), then NGINX (which depends on WordPress).
6. Each container runs its entrypoint script, which performs first-run initialization if the volume is empty, then `exec`s the main process as PID 1.

### Build cache and rebuilding

Docker caches each layer of the image build. If you change a file that is `COPY`ed into the image (such as an entrypoint script or a configuration file), Docker invalidates that layer and all subsequent layers, and rebuilds them. Layers before the change are served from cache.

To force a complete rebuild without cache (useful when debugging base image issues):

```bash
docker compose -f srcs/docker-compose.yml build --no-cache
docker compose -f srcs/docker-compose.yml up -d
```

---

## Managing containers and volumes

### Container commands

```bash
# List all running containers with status, ports, and names
docker compose -f srcs/docker-compose.yml ps

# View real-time logs for all services
docker compose -f srcs/docker-compose.yml logs -f

# View logs for a specific service (nginx, wordpress, or mariadb)
docker compose -f srcs/docker-compose.yml logs -f mariadb

# Open an interactive shell inside a running container
docker compose -f srcs/docker-compose.yml exec mariadb bash
docker compose -f srcs/docker-compose.yml exec wordpress bash
docker compose -f srcs/docker-compose.yml exec nginx bash

# Restart a single service without affecting others
docker compose -f srcs/docker-compose.yml restart nginx

# Stop a single service
docker compose -f srcs/docker-compose.yml stop mariadb

# View resource usage (CPU, memory, network I/O) per container
docker stats
```

### Volume commands

```bash
# List all Docker volumes
docker volume ls

# Inspect a specific volume (shows mount point, driver, options)
docker volume inspect srcs_wp_data
docker volume inspect srcs_db_data

# Remove a specific volume (container must be stopped first)
docker volume rm srcs_wp_data

# Remove all unused volumes (careful — this is destructive)
docker volume prune
```

### Network commands

```bash
# List all Docker networks
docker network ls

# Inspect the project network (shows connected containers, IP addresses, subnet)
docker network inspect srcs_inception

# Verify that containers can resolve each other by service name
docker compose -f srcs/docker-compose.yml exec wordpress ping -c 1 mariadb
docker compose -f srcs/docker-compose.yml exec nginx ping -c 1 wordpress
```

Note: volume and network names are prefixed with the Compose project name (derived from the directory name, typically `srcs_`). If you set `COMPOSE_PROJECT_NAME` in the environment or in the compose file, the prefix changes accordingly.

### Image commands

```bash
# List all images built by this project
docker images | egrep "srcs[-_](nginx|wordpress|mariadb)"

# Remove all project images (forces rebuild on next make)
docker compose -f srcs/docker-compose.yml down --rmi all

# Remove dangling images (leftover layers from previous builds)
docker image prune

# Full system cleanup — removes all unused images, containers, networks, and build cache
# WARNING: this affects ALL Docker projects on the machine, not just Inception
docker system prune -a
```

---

## Data storage and persistence

### Where data lives

Data persists across container lifecycle events (stop, start, restart, remove + recreate) through two Docker named volumes:

| Volume | Container mount point | Host path | Contents |
|--------|----------------------|-----------|----------|
| `wp_data` | `/var/www/html` | `/home/ghenriqu/data/wordpress` | WordPress PHP files, themes, plugins, uploaded media (images, documents) |
| `db_data` | `/var/lib/mysql` | `/home/ghenriqu/data/mariadb` | MariaDB data files (InnoDB tablespace, transaction logs, system tables) |

The NGINX container also mounts the `wp_data` volume at `/var/www/html` in read-only mode. This is necessary because NGINX serves static files (CSS, JS, images) directly from the WordPress file tree without involving PHP-FPM.

### How named volumes work

Docker named volumes are managed by the Docker engine. Unlike bind mounts (which map a host path directly), named volumes are abstracted — Docker controls their lifecycle, and they can be listed, inspected, and backed up with Docker commands.

In this project, the named volumes use the `local` driver with the `bind` mount type and a `device` pointing to the host directory. This satisfies the subject requirement: named volumes (not bind mounts) are used, but their backing storage is at `/home/ghenriqu/data`. The configuration in `docker-compose.yml` looks like:

```yaml
volumes:
  wp_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /home/ghenriqu/data/wordpress
  db_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /home/ghenriqu/data/mariadb
```

### What survives what

| Event | Data preserved? | Explanation |
|-------|----------------|-------------|
| `docker compose stop` / `start` | Yes | Containers are paused and resumed; volumes are untouched |
| `docker compose down` | Yes | Containers are removed but volumes persist |
| `docker compose down -v` | No | The `-v` flag explicitly removes named volumes |
| `docker kill <container>` | Yes | Container is force-stopped; the restart policy brings it back automatically; volumes are untouched |
| `docker compose down --rmi all` | Yes (data), No (images) | Volumes persist, but images are deleted and must be rebuilt |
| Host machine reboot | Yes | Docker daemon restarts containers (due to restart policy) and remounts volumes |
| VM disk corruption | No | Volumes are stored on the VM's filesystem — if the disk fails, data is lost |

### Backing up data

To back up the WordPress database:

```bash
docker compose -f srcs/docker-compose.yml exec mariadb \
  mysqldump -u root --password="$(cat secrets/db_root_password.txt)" wordpress \
  > backup_wordpress_$(date +%Y%m%d).sql
```

To back up WordPress files:

```bash
tar -czf backup_wp_files_$(date +%Y%m%d).tar.gz -C /home/ghenriqu/data/wordpress .
```

To restore a database backup:

```bash
docker compose -f srcs/docker-compose.yml exec -i mariadb \
  mysql -u root --password="$(cat secrets/db_root_password.txt)" wordpress \
  < backup_wordpress_20260509.sql
```

### First-run initialization vs subsequent runs

Each entrypoint script checks whether its volume already contains data before performing initialization:

**MariaDB:** checks if `/var/lib/mysql/mysql` directory exists. If it does not, the entrypoint runs `mysql_install_db` to create the system tables, then starts a temporary `mysqld` instance (without networking) to create the WordPress database and users. If the directory already exists, it skips initialization entirely and goes straight to `exec mysqld`.

**WordPress:** checks if `/var/www/html/wp-config.php` exists. If it does not, the entrypoint downloads WordPress core files using WP-CLI, generates `wp-config.php` from environment variables and secrets, and runs the WordPress installation (creating the admin user, setting the site title, etc.). If the file already exists, it skips all of this and goes straight to `exec php-fpm`.

**NGINX:** generates the self-signed TLS certificate at build time (in the Dockerfile) or at startup if it does not exist. No volume-dependent initialization is needed because NGINX's configuration is baked into the image.

This idempotent design means you can safely restart the infrastructure at any time without triggering a reinstallation or losing data.
