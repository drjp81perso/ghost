Here’s a clear, security-minded README you can ship with your stack. I’ve kept it practical (bullets + rationale) and added small improvements where they matter (env file, production mode, DB exposure, backups, and upgrade flow). PowerShell one-liners are included where helpful.

---

# Ghost + MariaDB (Docker Compose) — Self-Hosting README

## 1) Overview

This stack runs:

* **Ghost 6 (alpine)** — the blog engine
* **MariaDB** — the database

By default, Docker Compose creates a **user-defined bridge network** for the project. Containers can reach each other over that private network by service name (e.g., `db`), while **selected ports are published to the host** with `ports:`.

### What the current compose does

* Publishes **Ghost** on host port **2368** → container port **2368** (`2368:2368`).

* Publishes **MariaDB** on host port **3306** → container **3306** (`3306:3306`).
  ⚠️ Consequence: your database is reachable *from the host network*. This is convenient for admin tools, but it **broadens the attack surface**. If you don’t need external access, remove the `ports:` line under `db` so it’s only reachable inside the **Docker network**.

* Sets two custom **DNS resolvers** **inside** the Ghost container (`192.168.1.xxx` and `192.168.1.yyy`). This only affects how the Ghost container resolves names; it doesn’t publish DNS to others.

* Uses **bridge NAT** outbound: containers egress to the Internet via the host. Inbound traffic is only allowed on explicitly published ports (2368 and 3306 as written).

* Mounts persistent volumes:

  * `...[localstorage]/web/data/` → Ghost content (`/var/lib/ghost/content`)
  * `...[localstorage]/db/data/` → MariaDB data (`/var/lib/mysql`)

## 2) Prerequisites

* Docker Engine + Docker Compose plugin
* A domain and DNS A/AAAA records (e.g., `blog.jpsoftworks.com`) pointing to your reverse proxy or host
* Outbound SMTP creds (you’ve supplied them)

## 3) Security & Production Notes (important)

* **Database exposure:** If you do not need remote DB access, **remove** the `ports: - 3306:3306` from the `db` service. Use `docker compose exec db ...` for admin work instead.
* **Secrets:** Move passwords and API keys to a `.env` file. **Do not commit** `.env`.
* **Ghost mode:** Set `NODE_ENV=production` in production. It enables stricter behavior and correct cache/cookie settings.
* **URL correctness:** `url:` must match your public origin (scheme + host). Behind a TLS-terminating reverse proxy (nginx/Caddy/Traefik), `url` should be the **HTTPS** URL of your site.
* **MariaDB image:** The `lscr.io/linuxserver/mariadb` image supports `PUID/PGID/TZ`. Consider setting them to avoid permission anomalies.
* **Mail from:** Ghost expects a plain address or `"Name <address@domain>"`. Avoid YAML bracket syntax there.

## 4) Recommended folder layout

```
ghost-stack/
  .env
  docker-compose.yml
  backup/
```

## 5) .env (recommended)

Create `.env` alongside your compose file:

```ini
# Site
GHOST_URL=https://blog.jpsoftworks.com #shameless plug
NODE_ENV=production

# Mail
MAIL_FROM="Ghost Blog Admin <ghostsupport@drjpsoftware.com>"
MAIL_HOST=mail.drjpsoftware.com
MAIL_PORT=587
MAIL_USER=jp.lizotte@drjpsoftware.com
MAIL_PASS=REPLACE_ME

# DB
MYSQL_ROOT_PASSWORD=REPLACE_ME
MYSQL_DATABASE=ghostdb
MYSQL_USER=ghostuser
MYSQL_PASSWORD=REPLACE_ME

# Paths
GHOST_CONTENT=/absolute/path/to/localstorage/web/data
DB_DATA=/absolute/path/to/localstorage/db/data

# Optional for linuxserver/mariadb
PUID=1000
PGID=1000
TZ=America/Toronto
```


## 6) docker-compose.yml (hardened)

```yaml
services:

  ghost:
    image: ghost:6.0.9-alpine
    restart: always
    ports:
      - 2368:2368
    depends_on:
      - db
    volumes:
      - ${GHOST_CONTENT}:/var/lib/ghost/content
    environment:
      database__client: mysql
      database__connection__host: db
      database__connection__user: ${MYSQL_USER}
      database__connection__password: ${MYSQL_PASSWORD}
      database__connection__database: ${MYSQL_DATABASE}

      url: ${GHOST_URL}
      NODE_ENV: ${NODE_ENV}

      mail__transport: SMTP
      mail__from: ${MAIL_FROM}
      mail__options__host: ${MAIL_HOST}
      mail__options__port: ${MAIL_PORT}
      mail__options__auth__user: ${MAIL_USER}
      mail__options__auth__pass: ${MAIL_PASS}

    dns:
      - 192.168.1.xxx
      - 192.168.1.yyy

  db:
    image: lscr.io/linuxserver/mariadb
    container_name: mariadb
    hostname: db
    restart: always
    # Remove the next two lines unless you explicitly need external DB access
    # ports:
    #   - 3306:3306
    volumes:
      - ${DB_DATA}:/var/lib/mysql
    environment:
      - MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
      - MYSQL_DATABASE=${MYSQL_DATABASE}
      - MYSQL_USER=${MYSQL_USER}
      - MYSQL_PASSWORD=${MYSQL_PASSWORD}
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
```

> If you keep `db` un-published (recommended), Ghost still connects fine over the private bridge network using `host: db`.

## 7) First run

```bash
docker compose up -d
docker compose ps
```

Ghost will be at `http://<HOST-IP>:2368` (or through your reverse proxy at `https://blog.jpsoftworks.com`).

## 8) Initialize the database (SQL)


```bash
docker compose exec db mariadb -e \
"CREATE DATABASE IF NOT EXISTS ghostdb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'ghostuser'@'%' IDENTIFIED BY 'mystrongpassword';
ALTER USER 'ghostuser'@'%' IDENTIFIED BY 'mystrongpassword';
GRANT ALL PRIVILEGES ON ghostdb.* TO 'ghostuser'@'%';
FLUSH PRIVILEGES;"
```

### Notes and a safer variant

* Inside `db`, the `mariadb` client may still require credentials. Use root auth explicitly and pull values from **.env**:

```bash
docker compose exec db bash -lc \
"mariadb -uroot -p\"\$MYSQL_ROOT_PASSWORD\" -e \"
CREATE DATABASE IF NOT EXISTS \\\`$MYSQL_DATABASE\\\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$MYSQL_USER'@'%' IDENTIFIED BY '$MYSQL_PASSWORD';
ALTER USER '$MYSQL_USER'@'%' IDENTIFIED BY '$MYSQL_PASSWORD';
GRANT ALL PRIVILEGES ON \\\`$MYSQL_DATABASE\\\`.* TO '$MYSQL_USER'@'%';
FLUSH PRIVILEGES;\""
```

* If `db` is **not** published on 3306 (recommended), this still works because the command runs **inside** the container.

## 9) Reverse proxy (nginx) — minimal TLS termination

Point your public DNS (`blog.jpsoftworks.com`) to your proxy. Example nginx server block:

```nginx
server {
    listen 80;
    server_name blog.jpsoftworks.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name blog.jpsoftworks.com;

    # ssl_certificate /etc/letsencrypt/live/blog.jpsoftworks.com/fullchain.pem;
    # ssl_certificate_key /etc/letsencrypt/live/blog.jpsoftworks.com/privkey.pem;

    location / {
        proxy_pass http://HOST-IP:2368;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port 443;
    }
}
```

* Keep `url: https://blog.jpsoftworks.com` in Ghost.
* If you’re using Certbot, it will amend SSL directives for you.

## 10) Backups

### One-shot backup (PowerShell on the host)

```powershell
$ts = Get-Date -Format "yyyyMMdd-HHmmss"
$bk = "backup\$ts"
New-Item -ItemType Directory -Force -Path $bk | Out-Null

# DB dump
docker compose exec db bash -lc "mysqldump -u$MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE" `
  | Out-File -FilePath "$bk\db-$ts.sql" -Encoding ascii

# Ghost content
Compress-Archive -Path (Resolve-Path $Env:GHOST_CONTENT\*) -DestinationPath "$bk\ghost-content-$ts.zip"

Write-Host "Backup created in $bk"
```

### One-shot backup (bash)

```bash
ts=$(date +%Y%m%d-%H%M%S)
mkdir -p backup/$ts

docker compose exec db bash -lc \
  "mysqldump -u\$MYSQL_USER -p\"\$MYSQL_PASSWORD\" \$MYSQL_DATABASE" \
  > backup/$ts/db-$ts.sql

(cd "$(dirname "$GHOST_CONTENT")" && zip -r "../backup/$ts/ghost-content-$ts.zip" "$(basename "$GHOST_CONTENT")")
```

## 11) Upgrades

```bash
docker compose pull
docker compose up -d
docker compose logs -f --tail=100
```

> Always take a backup before upgrading.

## 12) Troubleshooting

* **Ghost shows wrong URLs**
  Ensure `GHOST_URL` is the public HTTPS origin and your reverse proxy sets `X-Forwarded-Proto https`.

* **Can’t send email**
  Check `MAIL_HOST/PORT/USER/PASS`, and that the SMTP provider allows the from-address domain. In Ghost Admin, go to **Settings → Email newsletter** to verify configuration.

* **DB permission or init issues**
  Confirm the DB exists and the user has privileges. Re-run the SQL snippet with root auth. Check `docker compose logs db`.

* **Port conflicts**
  If host ports 2368 or 3306 are taken, change the **left-hand** side (e.g., `8080:2368`).

* **Permissions on volumes**
  On Linux, ensure the mapped directories are writable by the container’s user. With linuxserver/mariadb, set `PUID/PGID` to your host user (commonly 1000/1000).

## 13) Optional hardening

* Remove `db` port publishing.
* Add a firewall rule to restrict inbound 2368 to your reverse proxy only.
* Use **fail2ban**/**WAF** on the proxy.
* Configure automatic backups + off-host storage (e.g., nightly cron to S3/Backblaze).
* Rotate SMTP and DB passwords periodically.

---

## Appendix A — Your original DB init (kept verbatim)

```bash
docker compose exec db mariadb -e \
"CREATE DATABASE IF NOT EXISTS ghostdb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'ghostuser'@'%' IDENTIFIED BY 'mystrongpassword';
ALTER USER 'ghostuser'@'%' IDENTIFIED BY 'mystrongpassword';
GRANT ALL PRIVILEGES ON ghostdb.* TO 'ghostuser'@'%';
FLUSH PRIVILEGES;"
```

> If it fails with auth errors, use the “safer variant” in section 8 that supplies `-uroot -p$MYSQL_ROOT_PASSWORD`.


