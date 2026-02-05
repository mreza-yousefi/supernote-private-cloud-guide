# Supernote Private Cloud — Setup & Security Guide

A concise, opinionated guide for self-hosting the Supernote Private Cloud using Docker Compose. Covers deployment, email setup, backups, upgrades, and optional HTTPS for remote access with security hardening.

The [official documentation](https://support.supernote.com) is thorough but spread across a long PDF. This guide distills it into what you actually need.

## Prerequisites

- Linux server (tested on Ubuntu 24.04). **ARM is not supported** (no Raspberry Pi)
- At least **50 GB** of free disk space (Supernote recommendation)
- Docker and Docker Compose installed
- An email account with SMTP access (e.g., Gmail with [App Password](https://support.google.com/accounts/answer/185833))

## Deployment

### 1. Create the project directory and download the database schema

```bash
mkdir -p ~/supernote && cd ~/supernote
curl -O https://supernote-private-cloud.supernote.com/cloud/supernotedb.sql
```

### 2. Create environment files

Create `.env`:

```env
# Database
MYSQL_ROOT_PASSWORD=CHANGE_ME
MYSQL_DATABASE=supernotedb
MYSQL_USER=supernote
MYSQL_PASSWORD=CHANGE_ME

# Redis
REDIS_PASSWORD=CHANGE_ME

# Ports
FRONTEND_PORT=19072
```

Create `.dbenv` (values must match `.env`):

```env
DB_HOSTNAME=mariadb
MYSQL_DATABASE=supernotedb
MYSQL_USER=supernote
MYSQL_PASSWORD=CHANGE_ME
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=CHANGE_ME
```

> Use strong random passwords. Generate with: `openssl rand -base64 16`

### 3. Create docker-compose.yml

Use the template in [configs/docker-compose.yml](configs/docker-compose.yml), or download the official one from Supernote and adjust the image tags to the latest versions from [Docker Hub](https://hub.docker.com/u/supernote).

### 4. Start the stack

```bash
docker compose up -d
```

Wait ~30 seconds for MariaDB to initialize, then verify:

```bash
docker compose ps
```

All four containers should be running:

| Container          | Purpose                        | Host Port |
|--------------------|--------------------------------|-----------|
| mariadb            | Database (MariaDB 10.6)        | —         |
| redis              | Session cache (Redis 7.4)      | —         |
| notelib            | Note format conversion         | —         |
| supernote-service  | Web UI + API + sync            | 19072     |

### 5. Access and register

Open `http://your-server-ip:19072` in a browser. Register an account (requires email verification — see next section).

### 6. Configure your Supernote device

> ⚠️ **Important:** Test everything (registration, login, file sync) in a browser **before** connecting your Supernote device. Current firmware versions require a **factory reset** to switch between cloud providers. Don't point your tablet at a setup that isn't fully working yet.

On your tablet: **Settings → Account → Private Cloud** → enter `http://your-server-ip:19072`

## Port Reference

The supernote-service container exposes several ports internally:

| Container Port | Host Default | Purpose |
|---------------|-------------|---------|
| 8080          | 19072       | Web UI + API (HTTP). Main access point for browsers and devices |
| 443           | 19443       | Built-in HTTPS with self-signed cert (browser will warn) |
| 18072         | 18072       | Auto-sync between devices via WebSocket. Optional — remove from compose if unused |
| 19071         | 19071       | Backend API. Not needed for normal use |

For most setups, only port **19072** needs to be exposed.

## Email (SMTP) Setup

Email is required for account registration and password recovery. Configure it through the web admin panel, or directly in the `u_email_config` database table.

**Gmail example:**

| Setting    | Value                |
|------------|----------------------|
| SMTP server| `smtp.gmail.com`     |
| Port       | `587`                |
| Encryption | TLS                  |
| Username   | your Gmail address   |
| Password   | Gmail App Password   |

> Do **not** use your regular Gmail password. Create an [App Password](https://support.google.com/accounts/answer/185833).

## Backups

Private Cloud sync provides redundancy between devices, but it is **not** a backup. Deleted files are gone. Back up regularly.

**Quick backup:**

```bash
# User files
tar -czf supernote-files-backup.tar.gz supernote_data/

# Database
docker exec mariadb mysqldump -u root -p"YOUR_ROOT_PASSWORD" supernotedb > supernotedb-backup.sql
```

**Automated backup to NAS/external storage** (via cron):

```bash
#!/bin/bash
# cloud-backup.sh — run via cron, e.g.: 0 3 * * * /path/to/cloud-backup.sh

BACKUP_DIR="/mnt/your-nas/supernote-backup"
INSTALL_DIR="/path/to/supernote"

# Database dump with timestamp
docker exec mariadb mysqldump -u root -p"YOUR_ROOT_PASSWORD" supernotedb \
  > "$INSTALL_DIR/db_backup/supernotedb-$(date +%Y%m%d).sql"

# Sync files (preserves deletions on source)
rsync -a "$INSTALL_DIR/supernote_data/" "$BACKUP_DIR/files/"
rsync -a "$INSTALL_DIR/db_backup/" "$BACKUP_DIR/db_backup/"
```

A sample backup script is also available at [configs/cloud-backup.sh](configs/cloud-backup.sh).

## Upgrading

**Supernote service and notelib:**

```bash
# Update image tags in docker-compose.yml to latest versions, then:
docker compose pull
docker compose up -d
```

Check [Docker Hub](https://hub.docker.com/u/supernote) for the latest tags.

**Database schema:** When a new `supernotedb.sql` is released:

```bash
# Download the new schema
curl -O https://supernote-private-cloud.supernote.com/cloud/supernotedb.sql

# Apply it (uses CREATE TABLE IF NOT EXISTS, safe to re-run)
docker restart mariadb
docker exec -i mariadb mysql -u root -p"YOUR_ROOT_PASSWORD" supernotedb < supernotedb.sql
```

**MariaDB version:** Don't upgrade the MariaDB version unless Supernote explicitly confirms compatibility.

## Coexistence with Other Docker Services

If you run other services (Home Assistant, Zigbee2MQTT, Portainer, etc.), verify:

- **No port conflicts** — Supernote uses 19071, 18072, 19072 (and optionally 19443)
- **No container name conflicts** — `mariadb`, `redis`, `notelib`, `supernote-service` must be unique
- **Host network mode** — other containers using `network_mode: host` could conflict with any port

---

## Optional: HTTPS for Remote Access

The steps below let you access your cloud securely from outside your local network.

### What you need

- A domain pointing to your public IP (e.g., [DuckDNS](https://www.duckdns.org/), [No-IP](https://www.noip.com/), or any DDNS provider)
- nginx and certbot installed on the host
- A port forwarded on your router

> **Why not use the built-in HTTPS?** The container includes HTTPS on port 443 (host 19443) with a self-signed certificate. This works but your browser and apps will show security warnings. Using nginx + Let's Encrypt gives you a trusted certificate.

### Setup

```bash
# Install
sudo apt install nginx certbot python3-certbot-nginx

# Get certificate (port 80 must be forwarded on your router)
sudo certbot --nginx -d your-domain.example.com

# Verify auto-renewal
sudo certbot renew --dry-run
```

Copy [configs/nginx-supernote.conf](configs/nginx-supernote.conf) to `/etc/nginx/sites-available/supernote`. Update the domain and cert paths, then enable:

```bash
sudo ln -s /etc/nginx/sites-available/supernote /etc/nginx/sites-enabled/supernote
sudo nginx -t && sudo systemctl reload nginx
```

### Router port forwarding

Use a **non-standard port** like **8443**. Some routers reserve port 443 for their own admin interface.

Forward external TCP port 8443 to your server's internal IP, port 8443. Refer to your router's documentation for the exact steps.

Access remotely at: `https://your-domain.example.com:8443`

### Block public registration

By default, anyone who discovers your URL can register an account. Block this from the internet by adding these lines to the nginx config **above** the `location /` block:

```nginx
location /api/user/register {
    return 403 '{"success":false,"errorMsg":"Registration disabled"}';
}
location /api/user/mail/validcode {
    return 403 '{"success":false,"errorMsg":"Registration disabled"}';
}
```

Registration still works on the local network via `http://server-ip:19072`.

### Important nginx settings

The nginx config includes two critical directives:

- **`client_max_body_size 0`** — Removes the default 1MB upload limit. Without this, file uploads and device sync through HTTPS will fail with "413 Request Entity Too Large".
- **`proxy_set_header Host $http_host`** — Passes the original `Host` header including the port (e.g., `your-domain:8443`). Using `$host` (without port) causes the app to generate download URLs with its internal port 8080, breaking file downloads in the web UI.

### Security findings

| Finding | Severity | Notes |
|---------|----------|-------|
| Passwords stored as MD5 (32-char hash) | High | Built into the app. Use a strong unique password |
| `Access-Control-Allow-Origin: *` | Medium | All API responses allow any origin |
| Swagger UI + API docs on port 19071 | Medium | Never forward port 19071 to the internet |
| Open user registration | Medium | Mitigated by nginx block above |
| Account lockout after 6 failed attempts | Good | |
| Email verification for registration | Good | |
| CAPTCHA on login | Good | |

### NAT hairpinning (slow local HTTPS)

Using the HTTPS URL from inside your LAN may be ~10x slower than direct HTTP, because traffic hairpins through the router. This is a router limitation.

**Workarounds:**
- **Accept it** — 10 MB/s is fine for syncing notes
- **Split DNS** — run dnsmasq to resolve your domain to the local IP on your LAN (eliminates hairpinning)

> Some routers have DNS rebind protection that blocks external domains resolving to internal IPs. You may need to add an exception for your domain. This alone does not solve hairpinning — you still need a local DNS override.

## License

This guide is provided as-is. Supernote Private Cloud is property of Ratta / Supernote.

---

Built with ❤️ by [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (Anthropic's AI coding agent)
