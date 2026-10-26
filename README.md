# Shareby

Save links from Instagram, YouTube and TikTok into collections, and build shared boards
with friends. Mobile first (Android, then iOS), plus a web app.

```
app/                Flutter app (Android + iOS)
web/                Web app (React + Vite, installable PWA), served by Nginx
server/             Sync + sharing API (Node.js, Express, PostgreSQL / Supabase)
deploy/             Production: Docker Compose for your Ubuntu server, HTTPS, backups
docker-compose.yml  Local development stack: PostgreSQL + API + web
```

**Production:** the database is Supabase (free tier), the API and web app run on your own
Ubuntu server, sign-in is Google. Step-by-step: [deploy/DEPLOY.md](deploy/DEPLOY.md).

Phone and web speak the same sync protocol to the same API, so signing in with the same
account shows the same folders, boards and done ticks everywhere.

## Quick start: everything with Docker

```bash
docker compose up --build
```

- Web app: http://localhost:8000 (Nginx serves the app and proxies `/api` to the API)
- API: http://localhost:8080 (the phone app's default; it can also use `http://10.0.2.2:8000/api`)

## How the offline-first part works

The phone never needs the internet to save, sort, search or edit.

1. **On-device database is the source of truth.** Flutter has no browser `localStorage`;
   the mobile equivalent is SQLite (`sqflite`). Every edit is written there first.
2. **Nothing leaves the phone until you sign in.** Before sign-in the app is fully local.
3. **Signing in (Google / Apple) moves your saves to the cloud.** Everything on the phone
   is queued and uploaded, and shared boards unlock.
4. **After that, edits sync in the background.** Each edit also writes an *outbox* entry
   in the same transaction. The app pushes the outbox and pulls changes on launch, on
   resume, 2 s after an edit, and every 45 s. Offline edits simply wait in the outbox.
5. **Conflicts:** last write wins per record, using the edit time. Deletes are soft so
   other devices learn about them. IDs are UUIDs made on the phone, so offline-created
   records never clash.

The app talks to the **API**, never to PostgreSQL directly: database credentials must not
ship inside a mobile app, and the API is where sharing permissions are enforced.

Product rules enforced in both the app and the database:
tags and auto-sorting only exist in personal folders (a PostgreSQL trigger strips them from
shared-board items); viewers can't add pins; only owners can rename, delete or invite.

**Done checkmarks.** Any confirmed link can be ticked done. On a shared board the tick is
shared with everyone and shows who did it ("Done by Diana"); editors can tick anyone's pin,
viewers can't tick. Done has its own timestamp and merges separately from content edits, so
a friend ticking a pin while you retitle it offline never undoes either change. [New] links
are confirmed into a folder first, then they can be ticked.

## 1. Run the server

Needs Node 20.6+ and PostgreSQL 13+ (Docker is easiest).

```bash
cd server
docker compose up -d          # PostgreSQL on localhost:5432 (user/pass/db: shareby)
cp .env.example .env
npm install
npm run migrate               # creates tables (safe to re-run)
npm start                     # http://localhost:8080
npm test                      # 28 tests (25 end-to-end against the database)
```

`ALLOW_DEV_AUTH=true` lets the app sign in with any email. **Turn it off in production.**
Without `GOOGLE_CLIENT_ID` the apps show the test-email sign-in when the server allows it;
with it, they use Google. `GET /auth/config` tells the apps which one to show.

## 2. Run the app (Android)

Needs Flutter 3.27+ and an Android emulator or phone.

```bash
cd app
./tool/setup.sh               # generates android/ + ios/, adds the share-sheet files
flutter analyze
flutter test
flutter run
```

- **Emulator:** works as-is (`10.0.2.2` is your computer as seen from the emulator).
- **Physical phone over USB:**
  `adb reverse tcp:8080 tcp:8080` then
  `flutter run --dart-define=API_BASE_URL=http://localhost:8080`
- **Fresh install without demo data:** `--dart-define=SEED_DEMO=false`

### Try the core flows

- **Share-to-save:** in Instagram/YouTube/TikTok (or Chrome), tap Share, then Shareby.
  A small dialog appears over that app. *Save* stores the link and returns you to the app;
  *Choose collection* opens Shareby with the picker.
- **Paste:** copy a link, tap *Paste link* on Home. Only real links are pasted.
- **Auto-sort:** links saved with "Sort it for me" show as *New* with a suggested folder.
  If you don't confirm, they're filed automatically after being shown twice.
- **Done:** tap the circle on the right of a link. It moves into the folder's Done section
  (collapsible), and the snackbar offers Undo.
- **Two friends:** run two emulators, sign in on each with different emails (dev sign-in),
  create a board on one, invite the other's email, pull to refresh on the second.

## 3. Run the web app

### Development

```bash
cd web
npm install
npm run dev        # http://localhost:5173, proxies /api to the API on :8080
npm test           # unit tests: categorizer, link helpers, IndexedDB outbox
npm run build      # type-check + production build into dist/
```

### Production (Nginx)

`web/Dockerfile` builds the app and serves `dist/` with Nginx using
`web/nginx/default.conf.template`, which:

- proxies `/api/*` to the API (`API_UPSTREAM`, default `http://api:8080`), same origin, so no CORS
- serves `index.html` for app routes (`/folders/<id>`, `/share?...`) so deep links and reloads work
- caches hashed `/assets/` for a year, and never caches `index.html`, `sw.js` or the manifest,
  so updates actually reach people
- gzips text assets and sends security headers (CSP, nosniff, frame-deny) from a snippet that
  every location includes. A bare `add_header` inside a location would silently drop them.

**Serve it over HTTPS.** Browsers only run service workers (offline mode, install, share
target) on HTTPS or `localhost`. Put TLS in front, for example Caddy, Certbot, or your
host's load balancer, and enable the HSTS line in `nginx/security-headers.conf`.

### How offline works on the web

- **Data:** IndexedDB (via `idb`) holds folders, links and the outbox, with the same design as the
  phone's SQLite. `localStorage` holds only small values: session, sync cursor, flags.
  localStorage alone would cap out around 5 MB and block the page on every write.
- **App shell:** a service worker (Workbox via `vite-plugin-pwa`) precaches the app, so it opens
  and works with no connection. Thumbnails you've seen are cached for 30 days.
- **Reconnect:** the browser's `online` event triggers a sync immediately. Sync also runs on
  load, when the tab becomes visible, 2 s after an edit, and every 45 s.
- **Auto-filing [New] links:** a browser reloads far more than an app launches, so visits under
  10 minutes apart count as one showing.

### Web-only conveniences

- **Share from Android apps:** install Shareby from Chrome (menu, then *Install app*). It then
  appears in the share sheet, via the Web Share Target API in the manifest.
- **Desktop:** press Ctrl/Cmd+V anywhere with a link copied, or drag a link onto the page.
- Right-click a link (or use the ⋯ button) for its actions.

### End-to-end test

`web/e2e/smoke.cjs` drives the running stack in a real browser. It covers paste-to-save,
done/undo, Back, reloading while offline, sign-in upload, two friends sharing a board, the
share target, and global paste.

```bash
cd web && npm i -D playwright && npx playwright install chromium
BASE_URL=http://localhost:8000 node e2e/smoke.cjs
```

## Online services

- **Database: Supabase.** Tables live in a private `shareby` schema (Row Level Security on, no
  grants to Supabase's public API roles), reached through the session pooler with SSL.
  Kept lean for the free tier: no session table (sign-in tokens are HMAC-signed), accepted
  invitations are deleted, deleted links and folders are purged after 60 days by a daily job,
  and pictures stay on devices (only the short image address syncs, so friends' phones can
  download the same picture without scraping Instagram again). A device away longer than 60
  days gets a full resync (`full: true` from `/sync/pull`) so it can't keep purged items.
- **Google sign-in.** Android: `google_sign_in` (Credential Manager) returns an ID token for
  the server's Web client ID; the API verifies it. Web: Google Identity Services button, loaded
  only on the sign-in sheet. The session token is kept in Android Keystore / iOS Keychain
  (`flutter_secure_storage`). Set up in [deploy/DEPLOY.md](deploy/DEPLOY.md#2-google-sign-in-google-cloud-console).
- **Account deletion** (required by Google Play): Profile → *Delete account*, phone and web
  (`DELETE /account`). Personal saves stay on the device, like signing out.
- **Languages and regions.** First launch asks for your region, which picks the language
  (Indonesia → Bahasa Indonesia, elsewhere → English; changeable) and switches on the sources
  people there use most. Every app text is written in English and wrapped in `tr()`; the
  Indonesian table is `app/lib/l10n/strings_id.dart`, and `test/l10n_test.dart` fails when a
  text has no translation. The Android share popup follows the same setting.
- **Sources.** Profile → Sources switches built-in sources on or off (what the search filter
  lists) and adds your own from a name and an example link. Custom sources stay on the device
  and are recognised from the link address, so other devices are unaffected. Sorting uses
  sources too: a folder that is mostly one source (all Spotify links in Music) attracts new
  links from it, and auto-sorting understands English and Indonesian titles.
- **Refresh.** Pull-to-refresh returns at once and works behind a thin bar at the top: rules,
  sync, and links still missing a preview (six lookups at a time). Re-checking every link is
  Profile → Refresh all previews.

## iOS (phase 2)

The app itself runs on iOS today. Share-to-save needs a native **Share Extension**:

1. Xcode: *File > New > Target > Share Extension*. Add an **App Group** (e.g.
   `group.com.shareby.shareby`) to both the app and the extension.
2. In the extension, read the shared URL and append `{url, text, choose}` to a JSON array
   in `UserDefaults(suiteName: "group.com.shareby.shareby")`, the same shape Android uses.
3. In `AppDelegate`, register the `shareby/share_intake` method channel with
   `drainPending`, returning and clearing that array. No Dart changes are needed.
4. For the local dev server, add `NSAppTransportSecurity > NSAllowsLocalNetworking = YES`
   to `ios/Runner/Info.plist`.
5. Sign-in on iOS: add the iOS OAuth client ID to `GOOGLE_CLIENT_ID` (after the web one) and
   to `Info.plist` (`GIDClientID` + its reversed URL scheme). The App Store requires *Sign in
   with Apple* next to Google: add `sign_in_with_apple`, call `api.appleLogin(...)` (the
   server's `/auth/apple` is ready), and set `APPLE_CLIENT_ID` to the bundle ID.

## Where things are

| Piece | File |
| --- | --- |
| Local database + outbox | `app/lib/data/local_db.dart` |
| All edits (offline-first) | `app/lib/data/repository.dart` |
| Push / pull / thumbnails | `app/lib/data/sync_service.dart` |
| Auto-sorting | `app/lib/data/categorizer.dart` (keyword scorer behind an interface; swap in an on-device MiniLM embedding model later) |
| App state for the UI | `app/lib/state/app_state.dart` |
| Android share dialog | `app/platform_overlay/android/.../ShareReceiverActivity.kt` |
| Web: IndexedDB + outbox | `web/src/data/localDb.ts` |
| Web: edits, sync, state | `web/src/data/repository.ts`, `sync.ts`, `web/src/state/store.ts` |
| Web: Nginx | `web/nginx/default.conf.template`, `security-headers.conf` |
| API | `server/src/sync.js`, `auth.js`, `tokens.js`, `folders.js`, `maintenance.js`, `preview.js` |
| Sign-in (phone) | `app/lib/data/auth_service.dart`, `session_store.dart` |
| Sign-in (web) | `web/src/data/googleIdentity.ts`, `web/src/ui/sheets/SignInSheet.tsx` |
| Production | `deploy/docker-compose.yml`, `deploy/DEPLOY.md` |
| Schema | `server/schema.sql` |

## Notes

- Card images: YouTube thumbnails come straight from the link; others are looked up from
  the page's Open Graph image during sync (Instagram often blocks this). When there's no
  image, or you're offline, cards show a placeholder in the folder's color with the
  source icon.
- Last-write-wins uses phone clocks; a phone with a badly wrong clock can lose a
  conflict it should win. Fine for an MVP; move to server-assigned versions later.
- If `flutter pub get` fails because a newer Flutter needs newer packages, run
  `flutter pub upgrade --major-versions`.
- The Flutter code was syntax-checked and the Kotlin compiled against API stubs, but the
  app was **not built or run** in the environment it was written in. Run
  `flutter analyze` first and fix anything it reports. The web app and server were built
  and tested end to end through Nginx.
