# Deploying Shareby: Supabase + your Ubuntu server

```
 Android app ─┐                     ┌─ Ubuntu server (Docker) ─────────────────┐
              ├── https://DOMAIN ──▶│ Caddy or Cloudflare Tunnel (HTTPS)        │
 Web browser ─┘                     │   └▶ web: Nginx  ── /api ──▶ api: Node.js │──▶ Supabase Postgres
                                    └───────────────────────────────────────────┘   (schema "shareby")
```

Everything the phone and browser need sits behind one HTTPS address: the web app at `/`, the
API at `/api`. Only the API talks to Supabase.

**Why the Supabase REST URL isn't used.** `https://gculrkdumuuejsiqsniq.supabase.co/rest/v1/`
is Supabase's auto-generated Data API. Shareby's sharing rules (owner / editor / viewer,
last-write-wins sync, "tags only in personal folders") live in the API, so the API connects to
the Postgres database directly instead. The tables are created in their own `shareby` schema
with Row Level Security on and no grants to Supabase's public roles, so nothing is reachable
through that REST URL even with the public anon key. Pictures are never stored in the
database: each phone keeps its own small thumbnail files.

---

## 1. Supabase

1. Open the project (ref `gculrkdumuuejsiqsniq`) → **Project Settings → Database**. If you don't
   know the database password, use **Reset database password** and save the new one.
2. Click **Connect** (top bar) → **Session pooler** → copy the URI. It looks like
   `postgresql://postgres.gculrkdumuuejsiqsniq:[YOUR-PASSWORD]@aws-0-<region>.pooler.supabase.com:5432/postgres`.
   Use the **session** pooler (port 5432): it works over IPv4 (the "direct connection" host is
   IPv6-only on the free plan, which most home connections and many VPSs can't reach).
3. Optional but recommended: **Project Settings → Data API** → turn the Data API off, since
   Shareby doesn't use it.

You don't run any SQL by hand: the API container applies `server/schema.sql` on every start
(it is idempotent).

Free-plan facts worth knowing:

- **500 MB database.** Shareby stores links as short text rows, so this is tens of thousands of
  saves. Deleted links are purged after `TOMBSTONE_DAYS` (60) and stale invites after
  `INVITE_DAYS` (60) by a daily job in the API.
- **Projects pause after about a week with no activity.** The API's daily housekeeping query
  touches the database once a day, which is usually enough; if the project ever does pause,
  click **Restore** in the dashboard.
- **No downloadable backups** on the free plan: `deploy/backup.sh` (step 5) makes nightly dumps.
- **Latency:** if the project's region is far from Indonesia (e.g. US), each sync is slower.
  Singapore (`ap-southeast-1`) is the closest region; the region can only be chosen when a
  project is created.

## 2. Google sign-in (Google Cloud console)

Do this once you know your domain (step 3), e.g. `shareby.example.com`.

1. <https://console.cloud.google.com> → create a project → **APIs & Services → OAuth consent
   screen** (Google Auth Platform): app name *Shareby*, support email, audience **External**.
   While it is in *Testing*, only the test users you add can sign in; click **Publish app**
   when you're ready for everyone (basic sign-in needs no Google review).
2. **Credentials → Create credentials → OAuth client ID → Web application**
   - Authorized JavaScript origins: `https://shareby.example.com`
     (add `http://localhost:5173` and `http://localhost` for local development).
   - No redirect URIs are needed.
   - This **Web client ID** goes first in `GOOGLE_CLIENT_ID`. The web app uses it directly, and
     the Android app asks Google for a token addressed to it.
3. **Create credentials → OAuth client ID → Android**, package name `com.shareby.shareby`, and
   the **SHA-1** of the key that signs the app. Create one Android client per key:
   - Debug builds (`flutter run`):
     `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android`
   - Release builds: your upload key (see step 4). If you publish on Google Play with Play App
     Signing, also add the **App signing key** SHA-1 from Play Console → *Test and release →
     App integrity*.
   The Android client ID is not put anywhere; Google matches the app by package + SHA-1.
4. (Later, iOS) an **iOS** client: add its ID after the web one in `GOOGLE_CLIENT_ID`.

## 3. The Ubuntu server

### 3.1 Install Docker

```bash
sudo apt update && sudo apt install -y ca-certificates curl git
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER    # log out and back in once
docker compose version           # should print v2.x
```

### 3.2 Get the code and configure it

```bash
sudo mkdir -p /opt/shareby && sudo chown $USER /opt/shareby
git clone https://github.com/miguelrolandjo-ops/shareby.git /opt/shareby
cd /opt/shareby/deploy
cp .env.example .env
openssl rand -hex 32             # paste as SESSION_SECRET
nano .env                        # DATABASE_URL, SESSION_SECRET, GOOGLE_CLIENT_ID, SHAREBY_DOMAIN
chmod 600 .env
```

### 3.3 Make it reachable over HTTPS: pick ONE

Google sign-in, the installable web app and Android's network rules all require HTTPS.

**Option A: the server has a public IP** (VPS, or home internet with a real public IP and port
forwarding). Point a DNS **A record** for `shareby.example.com` at the server's IP, forward/open
TCP 80 and 443, then:

```bash
sudo ufw allow OpenSSH && sudo ufw allow 80,443/tcp && sudo ufw enable
docker compose --profile caddy up -d --build
```

Caddy gets the certificate automatically within a minute.

**Option B: home server without a public IP** (CGNAT is common on Indonesian home internet:
if your router's WAN IP differs from what <https://ifconfig.me> shows, you're behind CGNAT).
Use a free Cloudflare Tunnel; no router ports are opened:

1. Add your domain to Cloudflare (free plan) and switch its nameservers as instructed.
2. Cloudflare dashboard → **Zero Trust → Networks → Tunnels → Create a tunnel →
   Cloudflared** → name it `shareby` → copy the **token** into `CLOUDFLARE_TUNNEL_TOKEN`.
3. In the tunnel's **Public hostname** tab: hostname `shareby.example.com`, service
   **HTTP** `web:80`.
4. Start it:

```bash
docker compose --profile tunnel up -d --build
```

### 3.4 Check it

```bash
docker compose ps                               # api "healthy", web "running"
docker compose logs -f api                      # expect "Schema applied" and "listening"
curl -s https://shareby.example.com/api/health  # {"ok":true}
curl -s https://shareby.example.com/api/auth/config
```

`/auth/config` should show your web client ID and `"dev":false`. Then open
`https://shareby.example.com`, go to **Friends → Continue with Google**.

In Supabase → **Table Editor**, switch the schema dropdown to `shareby` to see the tables.

## 4. Build the Android app for your server

```bash
cd app
./tool/setup.sh                                   # first time only
flutter pub get
flutter run --dart-define=API_BASE_URL=https://shareby.example.com/api --dart-define=SEED_DEMO=false
```

For a release build, create an upload key once and tell Gradle about it:

```bash
keytool -genkey -v -keystore ~/shareby-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
keytool -list -v -keystore ~/shareby-upload.jks -alias upload   # SHA-1 -> Android OAuth client (step 2.3)
```

`app/android/key.properties` (never commit it; it's already git-ignored):

```
storeFile=/home/you/shareby-upload.jks
storePassword=...
keyAlias=upload
keyPassword=...
```

```bash
flutter build appbundle --release \
  --dart-define=API_BASE_URL=https://shareby.example.com/api --dart-define=SEED_DEMO=false
# or: flutter build apk --release ... for sideloading
```

If Google's sheet says the app isn't configured, the SHA-1 of the key that signed this build
is missing from the Android OAuth clients, or the package name differs.

Google Play needs a **privacy policy URL** and an **account deletion** path. Account deletion
is built in (Profile → *Delete account*, in the app and on the web); point Play's
"delete account URL" at `https://shareby.example.com/profile` (sign in, then *Delete account*).

## 5. Running it

```bash
cd /opt/shareby
git pull && cd deploy && docker compose --profile caddy up -d --build   # update (or --profile tunnel)
docker compose logs --since 1h api                                       # logs
docker image prune -f                                                    # reclaim disk after updates
```

Nightly backup of the `shareby` schema (keeps 14 days):

```bash
sudo mkdir -p /var/backups/shareby && sudo chown $USER /var/backups/shareby
crontab -e
# 30 3 * * * /opt/shareby/deploy/backup.sh >> /var/backups/shareby/backup.log 2>&1
```

Containers restart on reboot by themselves (`restart: unless-stopped`; Docker starts at boot).

## Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| API logs `ENETUNREACH` or timeout to `db.<ref>.supabase.co` | You used the direct connection string. Use the **Session pooler** one. |
| API logs `password authentication failed` | Wrong password, or the user isn't `postgres.gculrkdumuuejsiqsniq` (the pooler needs the project ref in the user name). |
| API logs `self-signed certificate in certificate chain` | `DATABASE_CA_CERT` points to the wrong file; remove it to use encrypted-without-verification, or download the CA from Project Settings → Database. |
| API exits with `SESSION_SECRET must be set` | Fill `SESSION_SECRET` in `deploy/.env` (32+ characters). |
| Web: Google button missing | `GOOGLE_CLIENT_ID` empty, or the page isn't served from an origin listed in the Web client. |
| Web: "origin is not allowed" | Add the exact `https://` origin to the Web client's JavaScript origins (can take a few minutes). |
| Android: "Google sign-in is not set up for this app build" | SHA-1 / package missing from an Android OAuth client in the **same** Google Cloud project as the Web client. |
| Everyone got signed out | `SESSION_SECRET` changed. Keep it stable. |
| App says offline though the site works | The build's `API_BASE_URL` must end in `/api` and use `https://`. |
