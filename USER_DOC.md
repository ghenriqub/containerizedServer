# Inception — User Documentation

This document explains how to operate the Inception infrastructure as an end user or as an
administrator: which services the stack provides, how to start and stop it, how to reach the
website and the administration panels, where the credentials live, and how to verify that
everything is healthy.

Throughout this document the domain is written as `ghenriqu.42.fr` and the data path as
`/home/ghenriqu/data`. Both come from `srcs/.env` (`DOMAIN_NAME` and `DATA_PATH`); if you
changed them, substitute your own values everywhere.

---

## Services overview

### Mandatory stack

The mandatory stack is a self-contained WordPress site served over HTTPS. It is made of
three containers on a private bridge network named `inception`.

| Service | Role | Port |
|---|---|---|
| **nginx** | TLS termination and the only entry point into the infrastructure | `443`, published on the host |
| **wordpress** | The WordPress CMS executed by PHP-FPM | `9000`, internal only |
| **mariadb** | The relational database backing WordPress | `3306`, internal only |

NGINX accepts every incoming connection on port 443, terminates TLS (TLSv1.2 and TLSv1.3
only, with a self-signed certificate), serves static assets — CSS, JavaScript, images —
directly from the WordPress volume, and forwards every request for a `.php` file to the
WordPress container over FastCGI. PHP-FPM executes the WordPress code and connects to
MariaDB using credentials read from Docker secret files at startup.

Neither PHP-FPM nor MariaDB publishes anything to the host. They are reachable only from
inside the Docker network, by service name.

### Bonus services

Five optional services are defined behind the Compose profile `bonus`. They are not started
by `make`; they require `make bonus`. When they are absent, the mandatory stack is
unaffected.

| Service | Role | Reachable at |
|---|---|---|
| **redis** | Password-protected object cache for WordPress | internal only |
| **adminer** | Web client for the database | `https://adminer.ghenriqu.42.fr` |
| **website** | Static multilingual site (HTML/CSS, no PHP) | `https://website.ghenriqu.42.fr` |
| **uptime-kuma** | Monitoring and availability dashboard | `https://uptime.ghenriqu.42.fr` |
| **ftp** | FTPS access to the WordPress volume | `ftps://ghenriqu.42.fr:21` |

Adminer, the static website and Uptime Kuma are never exposed directly: they listen on the
internal network only, and NGINX reverse-proxies them on port 443 under their own
subdomain. The FTP service is the one exception — FTPS needs its own control port (21) and
a passive data port range (30000–30009), both published on the host.

---

## Starting and stopping the project

Every operation goes through the `Makefile` at the root of the repository. Run the commands
from that directory, inside the virtual machine where Docker is installed.

### Starting

```bash
make          # mandatory stack only (nginx, wordpress, mariadb)
make bonus    # mandatory stack + the five bonus services
```

Either target performs the same preparation before starting anything: it checks that the
Docker daemon is reachable, validates `srcs/.env`, creates the host data directories under
`DATA_PATH`, generates any missing secret file, and writes the domain names into
`/etc/hosts` (this last step asks for `sudo`). Then it builds the images and starts the
containers in the background.

The first build takes several minutes — Docker downloads the Debian base image and installs
every package from scratch. Later runs reuse the build cache and take seconds.

When it finishes, `make` prints a summary of every URL, the administrator username, and the
location of the secrets and data directories. You can print that summary again at any time:

```bash
make info
```

### Stopping and cleaning

The targets form a ladder, from least to most destructive:

| Target | Containers | Docker volumes | Host data under `DATA_PATH` | Images | Secrets |
|---|---|---|---|---|---|
| `make stop` | stopped, kept | kept | kept | kept | kept |
| `make down` | removed | kept | kept | kept | kept |
| `make clean` | removed | removed | **removed** | kept | kept |
| `make fclean` | removed | removed | **removed** | removed | **removed** |

`make stop` and `make start` pause and resume the containers without touching anything
else — the fastest way to free resources temporarily. `make restart` restarts them in
place.

`make down` is the normal way to shut the project down. All content survives: the next
`make` brings the site back exactly as it was.

`make clean` destroys the data. Because the named volumes are backed by directories under
`DATA_PATH`, removing the Docker volumes alone would leave the files behind on the host, so
`clean` explicitly deletes those directories too (this needs `sudo`). `make re` is
`clean` followed by a fresh build and start.

`make fclean` is a full reset: it additionally removes the project images, the `secrets/`
directory and the `/etc/hosts` entry. Note that `fclean` deletes the data and the secrets
*together*, which is deliberate — see the warning in the credentials section below.

There is also `make prune`, which runs a global `docker system prune`. It affects **every**
Docker project on the machine, not only Inception, so it asks for confirmation and is never
called automatically.

---

## Accessing the website and the administration panel

### Name resolution

The browser must resolve `ghenriqu.42.fr` to the machine running the containers. `make`
handles this automatically by appending a line to `/etc/hosts`, tagged so it can be
replaced or removed cleanly:

```
127.0.0.1 ghenriqu.42.fr adminer.ghenriqu.42.fr website.ghenriqu.42.fr uptime.ghenriqu.42.fr # inception
```

`make unhosts` removes it again.

If you browse from the VM itself, nothing more is needed. If you browse from the physical
host that runs the VM, add the same names to the *host's* `/etc/hosts`, pointing at the
VM's IP address instead of `127.0.0.1`, and make sure port 443 is forwarded or the VM is
bridged.

### The website

Open:

```
https://ghenriqu.42.fr
```

Use `https://`, not `http://` — nothing listens on port 80.

The browser will show a security warning, because the certificate is self-signed rather
than issued by a trusted authority. This is expected. The encryption itself is real; only
the identity verification is missing.

- **Firefox** — Advanced → Accept the Risk and Continue
- **Chrome / Chromium** — Advanced → Proceed to ghenriqu.42.fr (unsafe)
- **Safari** — Show Details → visit this website

The certificate is issued for `ghenriqu.42.fr` and carries the three bonus subdomains in
its `subjectAltName` extension, so the same certificate covers all four names. You will be
asked to accept it once per subdomain.

### The administration panel

```
https://ghenriqu.42.fr/wp-admin
```

Two WordPress accounts are created during the first installation:

| Account | Role | Username from | Password from |
|---|---|---|---|
| Administrator | full control: plugins, themes, users, settings | `WP_ADMIN_USER` in `srcs/.env` (default `boss`) | `secrets/credentials.txt` |
| Editor | create, edit and publish posts and pages; no plugin, theme or site settings access | `WP_USER` in `srcs/.env` (default `editor`) | `secrets/wp_user_password.txt` |

The subject forbids an administrator name containing "admin" in any form; `make` refuses to
start if `WP_ADMIN_USER` violates that rule.

Read the administrator password with:

```bash
cat secrets/credentials.txt
```

### Bonus services

**Adminer** — `https://adminer.ghenriqu.42.fr`. Log in with:

| Field | Value |
|---|---|
| System | MySQL |
| Server | `mariadb` |
| Username | the value of `MYSQL_USER` (default `wp_user`) |
| Password | `cat secrets/db_password.txt` |
| Database | the value of `MYSQL_DATABASE` (default `wordpress`) |

The server field is the *service name*, not an IP address — Docker's embedded DNS resolves
it on the internal network. The MariaDB `root` account will not work here: it is restricted
to local connections inside the database container, which is intentional.

**Static website** — `https://website.ghenriqu.42.fr`. A small multilingual showcase site
in plain HTML and CSS, with Portuguese and French versions under `/pt/` and `/fr/`. It has
no database and no PHP.

**Uptime Kuma** — `https://uptime.ghenriqu.42.fr`. On the very first visit it shows a setup
wizard asking you to create an administrator account. That account is *not* one of the
generated secrets: you choose it yourself, and it is stored in the `uptime_kuma_data`
volume. From there you can add monitors for the other services — for example an HTTPS
monitor on `https://nginx:443` with certificate verification disabled, or a TCP monitor on
`mariadb:3306`.

**FTPS** — `ftps://ghenriqu.42.fr:21`, with the username from `FTP_USER` in `srcs/.env`
(default `ftpuser`) and the password in `secrets/ftp_password.txt`. Plain FTP is refused:
the server requires explicit TLS for both the control and the data channel. In a client
such as FileZilla, choose "Require explicit FTP over TLS" and accept the self-signed
certificate. The session is chrooted to `/var/www`, so the WordPress files appear under
`html/`.

If transfers hang after a successful login, the passive-mode address is wrong. The client
must be able to reach the address advertised in `FTP_PASV_ADDRESS`; set it to the VM's IP
when connecting from another machine, and make sure ports 30000–30009 are reachable.

---

## Locating and managing credentials

### Where the credentials live

Nothing sensitive is stored in git. Passwords live in files, configuration lives in
environment variables, and both are excluded by `.gitignore`.

**Secret files** — the `secrets/` directory at the root of the repository. Each file holds
one password as plain text with no trailing newline. Docker mounts them read-only inside
the containers that declare them, under `/run/secrets/<name>`, on a `tmpfs` — they exist in
memory only and never end up in an image layer.

| File | Used by | Purpose |
|---|---|---|
| `secrets/db_root_password.txt` | mariadb | MariaDB `root` password |
| `secrets/db_password.txt` | mariadb, wordpress | Password of the WordPress database user |
| `secrets/credentials.txt` | wordpress | WordPress administrator password |
| `secrets/wp_user_password.txt` | wordpress | WordPress editor password |
| `secrets/redis_password.txt` | redis, wordpress | Redis authentication password (bonus) |
| `secrets/ftp_password.txt` | ftp | FTPS account password (bonus) |

They are generated automatically by `make` with `openssl rand -base64 24`, the directory is
`chmod 700` and each file `chmod 600`. Existing files are never overwritten, so your
passwords survive a rebuild.

**Environment variables** — `srcs/.env`. This file holds only non-sensitive configuration:
the domain name, the data path, the database name, the usernames, the email addresses, the
FTP user and its passive address. It contains no passwords, and `srcs/.env.example` is the
committed template it is copied from.

### Changing a password

> **Read this first.** The secret files and the database contents must stay in sync.
> MariaDB stores the passwords it was given on first initialisation *inside its data
> directory*. Deleting `secrets/` while keeping the data — or the reverse — produces a
> stack that builds fine and then fails authentication. This is why `make fclean` removes
> both at once, and why `make clean` removes neither.

To rotate the **WordPress administrator or editor password**, change it in the WordPress
admin panel (`https://ghenriqu.42.fr/wp-admin/profile.php`) and update the matching secret
file so the two agree. Nothing needs to be restarted.

To rotate a **database or Redis password**, the honest options are:

1. Change it in place — connect to the service, change the password there, then update the
   secret file. For MariaDB that means `ALTER USER` plus updating `wp-config.php` inside
   the WordPress container.
2. Or start over: `make fclean && make`. Everything is regenerated consistently, and all
   content is lost.

For a school project the second option is usually the right one; the first is what you
would do in production.

### Backing up the secrets

Because they are excluded from git, the secret files exist only on this machine. If you
need a copy, use a password manager (Bitwarden, KeePassXC) or an encrypted volume. Never
email them, paste them into a chat, or commit them "just temporarily" — credentials found
in the repository mean automatic failure of the project.

---

## Checking that the services are running correctly

### Status at a glance

```bash
make ps      # status of every container, bonus included
make info    # the same, plus every URL and where the files are
```

Every service should be `Up`. A container stuck in `Restarting` is crashing at startup —
read its logs.

### Logs

```bash
make logs                                     # follow everything

# a single service
docker compose -p inception -f srcs/docker-compose.yml logs -f mariadb
docker compose -p inception -f srcs/docker-compose.yml logs -f wordpress
docker compose -p inception -f srcs/docker-compose.yml logs -f nginx
```

Each entrypoint prints a clear line before handing over to its service — for example
`[mariadb] Starting mariadbd (PID 1)...` or `TLS material OK. Starting nginx...`. Seeing
that line means initialisation succeeded.

### HTTPS and TLS

```bash
# -k skips certificate verification, expected with a self-signed certificate
curl -kI https://ghenriqu.42.fr
```

A `200`, `301` or `302` means NGINX is answering. `Connection refused` means the container
is not running or port 443 is not published.

Check the negotiated protocol:

```bash
openssl s_client -connect ghenriqu.42.fr:443 -tls1_2 </dev/null 2>/dev/null | grep Protocol
openssl s_client -connect ghenriqu.42.fr:443 -tls1_3 </dev/null 2>/dev/null | grep Protocol
```

Both should succeed. Older protocols must fail — this is a requirement of the subject, and
evaluators do test it:

```bash
# expected to fail with a handshake error
openssl s_client -connect ghenriqu.42.fr:443 -tls1_1 </dev/null 2>&1 | grep -i "alert\|error"
```

Confirm that nothing else is exposed:

```bash
docker ps --format '{{.Names}}\t{{.Ports}}'
```

Only `nginx` should map a host port (443), plus `ftp` (21 and 30000–30009) when the bonus
profile is running.

### Database connectivity

```bash
docker exec -it mariadb mariadb -u root -p"$(cat secrets/db_root_password.txt)" \
  -e "SHOW DATABASES; SELECT User, Host FROM mysql.user;"
```

You should see the `wordpress` database and the WordPress user allowed from `%`, while
`root` exists only for `localhost`.

From the application side:

```bash
docker exec -it wordpress wp db check --allow-root
```

### Redis cache (bonus)

```bash
docker exec -it wordpress wp redis status --allow-root
```

The status should be `Connected`. The WordPress entrypoint enables the object cache only
when Redis actually answers, so if Redis is down the site still works — just without the
cache.

### Data persistence

1. Publish a test post in the admin panel.
2. `make down`
3. `make`
4. Reload the site — the post must still be there.

If it disappears, the volumes were not reused. Confirm they exist and where they point:

```bash
docker volume ls | grep inception
docker volume inspect inception_wordpress_data
ls -la /home/ghenriqu/data/wordpress
```

### Crash recovery

Every service is declared with `restart: always`, so Docker must bring it back after a
crash:

```bash
docker kill mariadb
sleep 10
make ps
```

MariaDB should be `Up` again with a fresh start time. Repeat with `wordpress` and `nginx`.
