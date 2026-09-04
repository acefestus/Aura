# Aura Family Backend

Railway-ready backend scaffold for Aura family accounts and household sync.

## What it provides

- Email/password registration and login
- Household creation and join by code
- Authenticated household snapshot sync for events, lists, activities, and steps
- Postgres persistence in production (falls back to a local JSON file when `DATABASE_URL` is unset, for local dev)

## Why Railway

Railway is the better fit here than Vercel for this backend stage because Aura needs:

- a long-running API process
- persistent server-side data storage
- a simple path to background/realtime expansion later

## Run locally

```bash
cd backend
npm install
cp .env.example .env
npm run dev
```

To make your account the admin/owner, set one of these in `.env`:

```bash
ADMIN_EMAIL=you@example.com
# or
ADMIN_EMAILS=you@example.com,coowner@example.com
```

Any configured admin email is treated as an Owner membership automatically.

## Deploy on Railway

1. Create a new Railway service from the `backend` folder.
2. Add a Railway Postgres service to the project. Railway injects `DATABASE_URL` into the backend service automatically when they're linked; the server uses Postgres whenever `DATABASE_URL` is set.
3. Set `JWT_SECRET`.
4. Set `ADMIN_EMAIL` (or `ADMIN_EMAILS`) to your account email.
5. Start command: `npm run start`
6. Build command: `npm run build`
7. If you have existing data in `backend/data/db.json`, run `npm run migrate:pg` once (with `DATABASE_URL` set) to import it into Postgres.

Without `DATABASE_URL`, the server falls back to the local JSON file — fine for local dev, but on Railway that file lives on an ephemeral filesystem and is wiped on every redeploy, so production should always have `DATABASE_URL` set.

## Security hardening

Set these for production:

```bash
# Required
JWT_SECRET=<random-32-plus-char-secret>

# Recommended JWT policy
JWT_ISSUER=aura-family-backend
JWT_AUDIENCE=aura-family-clients

# Browser CORS allowlist (comma-separated)
CORS_ALLOWED_ORIGINS=https://your-frontend-domain.example
CORS_DISABLE_ORIGIN_CHECK=false

# Rate limits
RATE_LIMIT_AUTH_WINDOW_MS=900000
RATE_LIMIT_AUTH_MAX=10
RATE_LIMIT_WRITE_WINDOW_MS=60000
RATE_LIMIT_WRITE_MAX=120
RATE_LIMIT_ADMIN_WINDOW_MS=60000
RATE_LIMIT_ADMIN_MAX=60
```

Notes:

- If `CORS_DISABLE_ORIGIN_CHECK=false`, `CORS_ALLOWED_ORIGINS` must be configured.
- Native iOS requests do not send browser origins, so CORS checks mainly protect browser clients.

## Current limitation

The iOS app is already wired to this backend for account auth, household linking, sync snapshots, and owner admin actions.

## Web PWA on the same domain

This backend now serves an installable web app at the root URL:

- `https://aura-family-backend-production.up.railway.app/`

Capabilities in the web app:

- Register and login
- Update profile and password
- Create or join household
- Load and save household sync snapshot JSON

Install to home screen:

- iPhone/iPad (Safari): Share -> Add to Home Screen
- Android (Chrome): use the browser install prompt or the in-app Install button

Persistence: Postgres in production (set `DATABASE_URL`), JSON file for local dev.