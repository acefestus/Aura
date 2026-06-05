# Aura Family Backend

Railway-ready backend scaffold for Aura family accounts and household sync.

## What it provides

- Email/password registration and login
- Household creation and join by code
- Authenticated household snapshot sync for events, lists, activities, and steps
- Simple JSON persistence for early-stage deployment

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
2. Set `JWT_SECRET`.
3. Set `ADMIN_EMAIL` (or `ADMIN_EMAILS`) to your account email.
4. Mount a persistent volume if you want JSON file persistence to survive redeploys.
5. Start command: `npm run start`
6. Build command: `npm run build`

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

Remaining limitation: persistence is JSON-file based and best for early-stage deployment. For production scale, migrate to a managed database with proper backups and migration flow.