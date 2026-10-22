# Deploying to a Vultr VM (Docker + nginx + MySQL)

```
Phones (APK) ─┐                    ┌─ /api, /files ──▶ api (Node, :8080) ──▶ MySQL (on the VM)
              ├─ HTTPS ─▶ nginx ───┤                         │
Admin browser ┘   :443             └─ /  (admin panel)       └─ ./data/uploads (selfies)
```

Everything runs on one VM. nginx terminates HTTPS (Let's Encrypt) and serves
the admin panel; the API container talks to the MySQL server already on the VM.

You need: a domain or subdomain (e.g. `attendance.example.com`), SSH access,
and MySQL **8.0.13 or newer**.

## 1. Point the domain at the VM

At your DNS provider, add an **A record** `attendance.example.com → <VM public IP>`.
Check with `ping attendance.example.com` before continuing.

## 2. Prepare the VM (Ubuntu)

```bash
# Docker Engine + Compose plugin
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER && newgrp docker

# Firewall: SSH and web only. MySQL stays private.
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

Also allow 22/80/443 (and nothing else) in the **Vultr firewall group** if you use one.

## 3. Create the database and user

The API container reaches the VM's MySQL through Docker's bridge
(`host.docker.internal`, usually `172.17.0.1`), so MySQL must listen there.

In `/etc/mysql/mysql.conf.d/mysqld.cnf` set:

```ini
bind-address = 127.0.0.1,172.17.0.1
```

(MySQL 8.0.13+ accepts several addresses. Docker must be installed first so
`172.17.0.1` exists.) Then `sudo systemctl restart mysql`, and in `sudo mysql`:

```sql
CREATE DATABASE smart_attendance CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'attendance'@'172.%' IDENTIFIED BY 'a-long-random-password';
GRANT ALL PRIVILEGES ON smart_attendance.* TO 'attendance'@'172.%';
FLUSH PRIVILEGES;
```

`ufw` already blocks port 3306 from the internet; keep it that way.

## 4. Copy the project and configure

```bash
git clone <your repo> smart_attendance   # or scp/rsync the folder
cd smart_attendance

cp server/.env.example server/.env
nano server/.env        # DB_PASSWORD, JWT_SECRET, PUBLIC_URL, APP_TIMEZONE

cp deploy/.env.example deploy/.env
nano deploy/.env        # DOMAIN=attendance.example.com

mkdir -p deploy/data/uploads deploy/web deploy/certbot/conf deploy/certbot/www
sudo chown -R 1000:1000 deploy/data/uploads   # the API runs as uid 1000
```

Generate `JWT_SECRET` with `openssl rand -hex 32`. Changing it later signs
everyone out.

## 5. Get the HTTPS certificate (first time only)

Port 80 must be free (nothing else running on it):

```bash
cd deploy
docker compose run --rm -p 80:80 --entrypoint certbot certbot certonly \
  --standalone -d attendance.example.com \
  --email you@example.com --agree-tos --no-eff-email
```

The `certbot` service renews it automatically afterwards.

## 6. Build the admin panel

On your PC (needs Flutter), from the project root:

```bash
flutter build web --release -t lib/main_admin.dart
scp -r build/web/* user@VM:~/smart_attendance/deploy/web/
```

The panel calls the API on the same domain, so no `API_URL` is needed for web.

## 7. Start everything

```bash
cd ~/smart_attendance/deploy
docker compose up -d --build
docker compose logs -f api      # "Applying 001_init.sql" then "listening on :8080"
curl https://attendance.example.com/api/health    # {"ok":true}
```

Database tables are created automatically on start.

## 8. Create the first admin

```bash
docker compose exec api npm run create-admin -- --email you@example.com --name "Your Name"
```

It asks for a password (8+ characters). Sign in at `https://attendance.example.com`.
Everything else (more admins, employees, sites, shifts) is done from the panel.

## 9. Build the Android app for this server

```bash
flutter build apk --release -t lib/main_employee.dart \
  --dart-define=API_URL=https://attendance.example.com
```

The APK is `build/app/outputs/flutter-apk/app-release.apk`. Release builds
only talk HTTPS.

## Updating

```bash
cd ~/smart_attendance && git pull
cd deploy && docker compose up -d --build      # migrations run on start
```

For a new admin panel, rebuild it (step 6) and copy it into `deploy/web/`.

## Backups

Two things hold data: the MySQL database and `deploy/data/uploads/`.

```bash
# nightly, e.g. from cron
mysqldump --single-transaction smart_attendance | gzip > ~/backup/db-$(date +%F).sql.gz
tar czf ~/backup/uploads-$(date +%F).tgz -C ~/smart_attendance/deploy/data uploads
```

Copy them off the VM (Vultr Object Storage, another server, …). Vultr
automatic snapshots are a good extra layer.

## Troubleshooting

| Symptom | Check |
|---|---|
| API logs `ECONNREFUSED 172.17.0.1:3306` | MySQL `bind-address` (step 3) and `sudo systemctl restart mysql` |
| `Access denied for user 'attendance'@'172.18.0.x'` | The user must be `'attendance'@'172.%'` |
| nginx exits: `cannot load certificate` | Step 5 was not done, or `DOMAIN` in `deploy/.env` differs from the certificate |
| Phone: "Could not reach the server" | APK built without `--dart-define=API_URL=…`, or DNS/firewall |
| Punches land on the wrong day | `APP_TIMEZONE` in `server/.env`, then `docker compose up -d` |
