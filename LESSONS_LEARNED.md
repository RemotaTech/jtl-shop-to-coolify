# Lessons Learned — JTL-Shop on Coolify

Running log of gotchas, root causes, and fixes from production deploys.

---

## 1. Wawi → Shop sync uses `http://` instead of `https://`

**Symptom**
- JTL Wawi `Abgleich` fails with `[DbeSClient] An error occurred while sending the request`.
- Step `DbeSArtikelBildStep` (Artikel-Bilder Senden) gets skipped after repeated failures.
- Shop access log shows `POST /dbeS/*.php` with `HTTP/1.1 200`, but Wawi still treats it as error.
- Local MAMP/XAMPP works fine over `http://`, only the Coolify deploy fails.

**Root cause**
- The Shop URL configured in Wawi was `http://shop.remotatech.com`.
- Coolify's reverse proxy (Traefik) auto-redirects `http://` → `https://` (301/302).
- Wawi's `DbeSClient` does **not** follow HTTP redirects on POST. It treats the redirect as a hard transport error and bubbles `DbeSClientSolvableException` back up the sync pipeline.
- Locally there is no redirect, so `http://` works → the bug only shows up in any TLS-terminated environment (Coolify, Cloudflare, nginx in front of Apache, etc.).

**Fix**
- In Wawi → **Einstellungen → JTL-Shop → URL**: change scheme from `http://` to `https://`.
- Make sure the cert is valid (Let's Encrypt via Coolify, not sslip.io self-cert) or Wawi rejects the TLS handshake — same end-result, different error.

**Prevention**
- Any production Shop URL in Wawi must be `https://`, full stop.
- If running behind a TLS proxy, never trust an `http://` config that "happens to work" — the proxy is silently doing the right thing locally.
- For staging on sslip.io / self-signed certs, either get a real domain + LE cert or tick `Zertifikat ignorieren` in Wawi (dev only).

**Diagnostic checklist when DbeSClient errors appear**
1. Wawi URL scheme — `http` or `https`?
2. `curl -I https://<shop>/dbeS/mytest.php` from outside — 200/405 expected.
3. Cert valid? `curl -v https://<shop>/` — look for `SSL certificate problem`.
4. Shop `access.log` shows POSTs landing → transport OK, problem is elsewhere (auth, payload).
5. Shop `error.log` + `/var/www/html/dbeS_log.txt` during the failing step.

---

## 2. PHP upload limits too low for image batches

**Symptom**
- `DbeSArtikelBildStep` fails on large image batches even when transport works.

**Root cause**
- Default PHP `upload_max_filesize=2M`, `post_max_size=8M`, Traefik `maxRequestBodyBytes` unset.

**Fix (already in repo, `docker/php/jtl.ini` + `docker-compose.yaml`)**
- PHP: `upload_max_filesize=512M`, `post_max_size=512M`, `max_execution_time=600`, `memory_limit=1024M`.
- Traefik label: `maxRequestBodyBytes=536870912` (512 MB).

---

## 3. Container rebuild wipes `config.JTL-Shop.ini.php`

**Symptom**
- After `git push` → Coolify redeploy, install wizard shows again. DB already populated → "DB exists".

**Root cause**
- JTL writes `includes/config.JTL-Shop.ini.php` post-install. It lives inside the image layer, not a volume. Every rebuild = fresh image = lost config.

**Fix (already in repo, `docker/entrypoint.sh` + `shop_persist` volume)**
- Entrypoint copies the config file to/from `/persist` (named volume) on every container start.
- First install → backed up to `/persist`.
- Future rebuilds → restored from `/persist` before Apache starts → no install wizard.

---

## 4. PHP version too low for JTL 5.7+

**Symptom**
- Install wizard 500s with: `Composer dependencies require a PHP version ">= 8.3.0". You are running 8.2.x`.

**Fix**
- `FROM php:8.3-apache` in Dockerfile. Bump again when JTL bumps requirement.

---

## 5. Source-compiling PHP extensions blows the Coolify build budget

**Symptom**
- Build hangs for minutes compiling `pdo_mysql`, `mysqli`, `mbstring`, ... then "Gracefully shutting down" (timeout or OOM).

**Fix**
- Use `mlocati/docker-php-extension-installer` (`install-php-extensions ...`) — pulls prebuilt binaries + auto-installs system deps. Build drops from ~5 min to ~30 s, RAM use way lower.

---

## 6. `docker-compose.yml` vs `docker-compose.yaml` in Coolify

**Symptom**
- Coolify deploy fails: `Docker Compose file not found at: /docker-compose.yaml (branch: main)`.

**Fix**
- Coolify expects `.yaml` by default. Either rename the file or set `Docker Compose Location` in Coolify resource settings.

---

## 7. `localhost` as DB host in install wizard

**Symptom**
- Wizard fails with `SQLSTATE[HY000] [2002] No such file or directory`.

**Root cause**
- `localhost` triggers PHP's Unix-socket lookup, which doesn't exist in the PHP container. There is no `mysqld` listening on a socket on the shop container.

**Fix**
- Use **Host: `db`** (the Docker Compose service name). Forces TCP via Docker DNS → connects to the MariaDB container.

---

## 8. `validate_timestamps=0` in OPcache breaks live template edits

**Symptom**
- Edit a `.tpl` or `.css` via SFTP / Coolify file manager → browser still serves old version after refresh.

**Root cause**
- We set `opcache.validate_timestamps=0` for production speed. OPcache never re-reads files until the container restarts.

**Fix (dev)**
- Set `validate_timestamps=1` + `revalidate_freq=2` in `docker/php/opcache.ini`.
- Or restart the shop container after each edit (slow).

**Recommendation**
- Two ini files: `opcache.ini` (prod) and `opcache.dev.ini`. Switch via build arg, env, or branch.

---

## 9. Traefik request body buffering — middleware must be referenced

**Symptom**
- Wawi sync of large image batch still fails with 413 after raising PHP limits.

**Root cause**
- Defining the Traefik middleware via labels is not enough — the router must reference it (`traefik.http.routers.shop.middlewares=shop-bodysize@docker`).

**Fix**
- Apply both labels in `docker-compose.yaml`:
  ```yaml
  - traefik.http.middlewares.shop-bodysize.buffering.maxRequestBodyBytes=536870912
  - traefik.http.routers.shop.middlewares=shop-bodysize@docker
  ```

---

## Template / theme development specific

### A. Editing templates locally vs Coolify

- Don't bind-mount the template dir over a volume that already has files baked from the image — the empty volume hides the image content on first start.
- For live editing, choose **one** workflow:
  - **Git-driven**: edit in IDE → `git push` → Coolify redeploys (auth via webhook, ~2 min).
  - **Live patch**: SFTP into Coolify container or `docker exec` + edit. Survives until next rebuild.
- Never mix: don't both volume-mount a template dir and rely on rebuild deploys for the same path. The first deploy wins and the other channel silently no-ops.

### B. Smarty cache

- Clear after every template edit if caching is on:
  ```bash
  rm -rf /var/www/html/templates_c/*
  ```
- During heavy theme work, disable Smarty cache in the JTL admin until the theme is stable, otherwise you'll chase ghost rendering bugs.

### C. Asset cache busting

- The Shop's `.htaccess` sets `Cache-Control: max-age=15552000` on images, css, js. Browsers will not pick up new versions for 6 months unless the URL changes.
- Use JTL's template asset versioning helper or append `?v=<hash>` to changed files during dev. In dev, disable the cache headers with `DevTools → Network → Disable cache`.

---

## Format for future entries

When adding a new lesson, use:

```
## N. <one-line title>

**Symptom**
- What the user saw.

**Root cause**
- Why it happened.

**Fix**
- What change resolved it.

**Prevention** (optional)
- How to avoid hitting it again.
```

Keep it short. One screen per lesson.
