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

## Deploy on Railway

1. Create a new Railway service from the `backend` folder.
2. Set `JWT_SECRET`.
3. Mount a persistent volume if you want JSON file persistence to survive redeploys.
4. Start command: `npm run start`
5. Build command: `npm run build`

## Current limitation

This backend is scaffolded and functional on its own, but the iOS app is not yet wired to it. The app still uses the current on-device/CloudKit-style sync path.