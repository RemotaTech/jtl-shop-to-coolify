# jtl-shop-coolify

JTL-Shop 5 on Coolify via Docker Compose. Drop ZIP, deploy.

## What you do

1. Download JTL-Shop 5 ZIP from https://www.jtl-software.com/ (customer account).
2. Drop ZIP file into `shop/` folder — any filename (e.g. `shop/JTL-Shop-5.x.x.zip`).
3. Commit + push. Coolify build will auto-extract on `docker build`.

Dockerfile finds first `*.zip` in `shop/`, unzips it, and handles both layouts:
- ZIP with `index.php` at root
- ZIP with single wrapper folder containing `index.php`

## Structure

```
jtl-shop-coolify/
├── Dockerfile               ← auto-unzips shop/*.zip into image
├── docker-compose.yml
├── .env.example
├── .gitignore
├── .gitattributes           ← Git LFS for shop/*.zip
├── docker/
│   └── php/
│       ├── jtl.ini
│       └── opcache.ini
└── shop/
    └── <your-jtl-shop.zip>  ← place here
```

## Git LFS (required if ZIP > 100MB)

GitHub rejects files >100MB. JTL ZIP often >100MB. Install LFS once:

```bash
brew install git-lfs
git lfs install
```

`.gitattributes` already tracks `shop/*.zip` via LFS.

## Deploy

```bash
cp .env.example .env       # edit passwords
git init
git add .
git commit -m "Initial JTL Shop Coolify setup"
git branch -M main
git remote add origin https://github.com/abdullahIbdah/jtl-shop-coolify.git
git push -u origin main
```

In Coolify:
1. New Resource → Docker Compose → connect repo
2. Branch: `main`, compose file: `docker-compose.yml`
3. Environment variables: paste from `.env`
4. Domains: set `shop.yourdomain.com` (auto SSL via Let's Encrypt)
5. Deploy

## First-run install wizard

Visit `https://<your-domain>/install`:
- DB host: `db`
- DB name / user / password: from `.env`
- Grants needed: SELECT, CREATE, ALTER, INSERT, UPDATE, DELETE, INDEX, DROP

After install: delete `/install` directory inside container (or via Coolify file manager) — JTL security requirement.

## Persistent data

Volumes survive redeploy:
- `shop_bilder` → `/var/www/html/bilder` (product images)
- `shop_files` → `/var/www/html/files`
- `shop_export` → `/var/www/html/export`
- `shop_mediafiles` → `/var/www/html/mediafiles`
- `shop_templates_c` → `/var/www/html/templates_c` (Smarty cache)
- `db_data` → MariaDB data

## Cron

`cron` service hits `jtl_cron.php` every 5 min. Adjust interval in `docker-compose.yml` if needed.
