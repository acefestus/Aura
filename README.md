# Aura Family Hub

Aura is a SwiftUI iOS family planner with events, shared lists, family activities, visibility controls, and account-backed sync.

## Project layout

- `Aura/` iOS app source
- `AuraWidget/` widget target
- `Aura.xcodeproj/` Xcode project
- `backend/` Railway-ready Node/TypeScript API

## Current status

Implemented:
- Premium app UI polish and interaction upgrades
- Family model: members, shared lists, activities, step snapshots
- Visibility scopes: Personal, Family, Custom
- Event assignees and conflict detection
- Local household sync path and server-backed account/snapshot sync path

Still to complete in later chunks:
- Realtime server push updates
- Role-based permissions and invites
- Rich routines/chore automation modules

## Chunked implementation roadmap

### Chunk 1 (done)
- Backend scaffold (auth + household + snapshot endpoints)
- iOS account wiring for register/login/create household/join household
- Server snapshot sync integrated into app settings flow

### Chunk 2 (next)
- Add signed-in session refresh on app launch and token expiry handling
- Add server sync conflict resolution UX (remote/local merge prompts)
- Add account profile editing and password reset endpoints

### Chunk 3
- Add realtime updates for household changes (SSE/WebSocket)
- Add per-member permissions (owner/admin/member)
- Add audit timeline for server-origin changes

### Chunk 4
- Expand product modules (routines/chore templates, meal planner, family inbox)
- Analytics and reliability hardening
- CI checks and release pipeline

## Run iOS app

```bash
xcodebuild -project Aura.xcodeproj -scheme Aura -destination 'platform=iOS Simulator,id=4E9EEC6D-D75C-4158-9D4E-5005E512FE49' -configuration Debug build
```

## Run backend locally

```bash
cd backend
npm install
cp .env.example .env
npm run dev
```

## Railway deployment

1. Create or login to Railway CLI.
2. From `backend/`, run `railway up`.
3. Set environment variable `JWT_SECRET`.
4. Keep a persistent volume for `backend/data` if you want file persistence.
5. Copy generated domain URL and set it in the app Settings under Account & Server.

## Public GitHub publication

After local git initialization, run:

```bash
gh repo create Aura --public --source=. --remote=origin --push
```

If the repository name already exists, use a unique name like `Aura-family-hub`.

## Final release prep

Run automated smoke checks:

```bash
./scripts/release_smoke.sh
```

Run manual release checklist:

- `docs/RELEASE_QA_CHECKLIST.md`

Notes:

- The smoke script uses `CODE_SIGNING_ALLOWED=NO` so iOS compile checks can run without a configured development team.
- For an actual distributable build/archive, set the development team in Xcode for both app and widget targets.
