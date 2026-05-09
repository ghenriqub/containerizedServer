# Inception — User Documentation

This document explains how to use the Inception infrastructure as an end user or system administrator. It covers what services are available, how to start and stop the project, how to access the website, where credentials are stored, and how to verify that everything is running correctly.

---

## Services overview

The Inception stack provides a fully self-contained WordPress website running over HTTPS. It is composed of three services, each isolated in its own Docker container:

**NGINX** serves as the web server and the sole entry point to the infrastructure. It handles all incoming HTTPS connections on port 443, terminates TLS encryption (using a self-signed certificate with TLSv1.2 or TLSv1.3), and routes requests to the appropriate backend. Static files such as images, CSS stylesheets, and JavaScript files are served directly by NGINX without involving PHP. Requests for dynamic content (any PHP page) are forwarded internally to the WordPress container using the FastCGI protocol.

**WordPress with PHP-FPM** is the application layer. It runs the WordPress CMS — a content management system that allows you to create and manage a website through a graphical administration panel in the browser. PHP-FPM (FastCGI Process Manager) is the PHP runtime that executes the WordPress code. It listens internally on port 9000, which is only accessible within the Docker network and never exposed to the outside world.

**MariaDB** is the database server. It stores all WordPress data: posts, pages, user accounts, site settings, theme and plugin configurations, comments, and media metadata. It listens internally on port 3306, again only within the Docker network. WordPress connects to it automatically using credentials read from Docker secret files at startup.

---

## Starting and stopping the project

All operations are performed from the root directory of the project repository, where the `Makefile` is located. You must run these commands inside the virtual machine where Docker is installed.

### Starting the infrastructure

```bash
make
```

This single command builds all three Docker images from their respective Dockerfiles (if not already built), creates the Docker network and named volumes (if they do not already exist), and starts all containers. The first run takes longer because Docker needs to download the Debian base image and install all packages. Subsequent runs are much faster thanks to Docker's build cache.

Once the command completes and all containers are running, the website is accessible at `https://ghenriqu.42.fr` (replace `ghenriqu` with the 42 username configured for this project).

### Stopping the infrastructure

```bash
make down
```

This stops all running containers and removes them, but preserves the Docker volumes. Your WordPress content, database, uploaded media, and all user data remain intact. The next time you run `make`, the infrastructure comes back up with all data preserved.

### Full cleanup (destroys data)

```bash
make clean
```

This stops all containers, removes them, and also removes the Docker named volumes. All WordPress content and the entire database are permanently deleted. Use this only if you want a completely fresh start.

### Rebuilding from scratch

```bash
make re
```

This performs a full cleanup followed by a fresh build and start. It is equivalent to running `make clean` followed by `make`. Every container image is rebuilt, volumes are recreated, and the WordPress installation process runs again from the beginning.

---

## Accessing the website and administration panel

### Prerequisites

Before accessing the site, ensure that the domain name `ghenriqu.42.fr` resolves to your local machine. This is configured by adding an entry to the `/etc/hosts` file on the machine where you open the browser:

```
127.0.0.1    ghenriqu.42.fr
```

If you are accessing the website from inside the VM itself, this entry should already be present. If you are accessing it from the host machine that runs the VM, you need to add this entry to the host's `/etc/hosts` and point it to the VM's IP address instead of `127.0.0.1`.

### Accessing the website

Open a browser and navigate to:

```
https://ghenriqu.42.fr
```

Important: use `https://`, not `http://`. The infrastructure only accepts connections over HTTPS on port 443. There is no HTTP server listening on port 80.

The browser will display a security warning because the TLS certificate is self-signed (it was not issued by a trusted Certificate Authority). This is expected for a local development project. In most browsers:

- **Firefox:** click "Advanced" → "Accept the Risk and Continue"
- **Chrome/Chromium:** click "Advanced" → "Proceed to ghenriqu.42.fr (unsafe)"
- **Safari:** click "Show Details" → "visit this website"

The encryption is real and functional — the warning only means the certificate was not verified by a third party.

### Accessing the WordPress administration panel

The administration panel is located at:

```
https://ghenriqu.42.fr/wp-admin
```

Log in with the administrator credentials (see the credentials section below). From this panel you can create and edit posts, manage pages, install themes and plugins, moderate comments, create additional user accounts, and configure all aspects of the website.

### WordPress users

The installation creates two users:

1. **Administrator** — has full access to all WordPress features, including installing plugins, changing themes, managing other users, and modifying site settings. The username is defined by the `WP_ADMIN_USER` variable in the `.env` file (it cannot contain "admin" or any variation of it).

2. **Editor** — has the WordPress "editor" role, which allows creating, editing, and publishing posts and pages, as well as managing other users' posts. The editor cannot install plugins, change themes, or modify site-wide settings. The username is defined by the `WP_USER` variable in the `.env` file.

---

## Locating and managing credentials

### Where credentials are stored

Credentials are stored in two places, both outside of version control:

**Docker secret files** are plain text files in the `secrets/` directory at the root of the project. Each file contains a single password with no trailing newline. These files are mounted as read-only inside the containers at `/run/secrets/` and are stored in memory (tmpfs), never written to the container's filesystem layer.

| File | Purpose |
|------|---------|
| `secrets/db_root_password.txt` | MariaDB root user password |
| `secrets/db_password.txt` | MariaDB WordPress user password (also used as the WordPress editor password) |
| `secrets/credentials.txt` | WordPress administrator password |

**Environment variables** are stored in `srcs/.env`. This file contains non-sensitive configuration (domain name, database name, usernames, email addresses) and references to the secret file paths. It does not contain any actual passwords.

### Changing passwords

To change a password:

1. Stop the infrastructure: `make down`
2. Edit the appropriate file in the `secrets/` directory with the new password
3. For database passwords: you must also update the password inside MariaDB. The simplest approach is to perform a full rebuild: `make re`. Note that this destroys and recreates all data.
4. For the WordPress admin password only (without touching the database): you can change it through the WordPress admin panel at `https://ghenriqu.42.fr/wp-admin/profile.php` while the infrastructure is running, but the secret file should also be updated to match (in case the containers are rebuilt).

### Security notes

The `secrets/` directory and `srcs/.env` are listed in `.gitignore` and must never be committed to the git repository. The project subject states explicitly that credentials found in the repository will result in automatic project failure.

Do not share the secret files over insecure channels (email, chat, unencrypted messaging). If you need to back them up, use a password manager or an encrypted storage medium.

---

## Checking that services are running correctly

### Quick health check

Run the following command to see the status of all containers:

```bash
docker compose -f srcs/docker-compose.yml ps
```

All three services (nginx, wordpress, mariadb) should show a status of `Up`. If any container shows `Restarting`, it is likely crashing on startup — check its logs for the error.

### Viewing container logs

To inspect the logs of a specific service:

```bash
# NGINX logs (access and error logs)
docker compose -f srcs/docker-compose.yml logs nginx

# WordPress / PHP-FPM logs
docker compose -f srcs/docker-compose.yml logs wordpress

# MariaDB logs
docker compose -f srcs/docker-compose.yml logs mariadb

# Follow logs in real time (like tail -f)
docker compose -f srcs/docker-compose.yml logs -f

# Follow a specific service
docker compose -f srcs/docker-compose.yml logs -f nginx
```

### Verifying HTTPS and TLS

From inside the VM, test the TLS connection:

```bash
# Verify that the certificate is served and TLS is functional
# -k skips certificate verification (expected for self-signed)
curl -kI https://ghenriqu.42.fr
```

You should see an HTTP response with status `200 OK` or `301/302` (redirect). If you get `connection refused`, the NGINX container is not running or port 443 is not published.

To verify the TLS protocol version:

```bash
openssl s_client -connect ghenriqu.42.fr:443 -tls1_2 </dev/null 2>/dev/null | grep "Protocol"
openssl s_client -connect ghenriqu.42.fr:443 -tls1_3 </dev/null 2>/dev/null | grep "Protocol"
```

At least one of these should output `Protocol  : TLSv1.2` or `Protocol  : TLSv1.3`. You can also verify that older protocols are rejected:

```bash
# This should FAIL (connection refused or handshake error)
openssl s_client -connect ghenriqu.42.fr:443 -tls1 </dev/null 2>&1 | grep -i "error\|alert"
```

### Verifying database connectivity

To confirm that WordPress can reach MariaDB:

```bash
# Open a shell inside the WordPress container
docker compose -f srcs/docker-compose.yml exec wordpress bash

# From inside the container, test the database connection
# (mysql/mariadb client may need to be installed separately)
php -r "
\$db = new mysqli('mariadb', getenv('MYSQL_USER'), trim(file_get_contents(getenv('MYSQL_PASSWORD_FILE'))), getenv('MYSQL_DATABASE'));
echo \$db->connect_error ? 'FAIL: '.\$db->connect_error : 'OK: connected to MariaDB';
echo PHP_EOL;
"
```

### Verifying data persistence

To confirm that data survives container restarts:

1. Create a test post through the WordPress admin panel
2. Stop and remove the containers: `make down`
3. Start the infrastructure again: `make`
4. Navigate to the website — the test post should still be there

If the post disappears, the named volumes are not configured correctly or were accidentally removed.

### Verifying crash recovery

The subject requires that containers restart automatically after a crash:

```bash
# Get the container ID for MariaDB
docker compose -f srcs/docker-compose.yml ps -q mariadb

# Force-kill the container (simulates a crash)
docker kill $(docker compose -f srcs/docker-compose.yml ps -q mariadb)

# Wait a few seconds, then check if it restarted
sleep 5
docker compose -f srcs/docker-compose.yml ps mariadb
```

The container should show status `Up` with a recent start time. Repeat for `nginx` and `wordpress` to verify all three services have the restart policy configured.