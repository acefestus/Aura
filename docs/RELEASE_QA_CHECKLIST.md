# Aura Release QA Checklist

This checklist is for final release validation before publishing a build.

## 1) Preflight

- Pull latest `main` and verify clean working tree (`git status --short` is empty).
- Confirm backend URL is set for server-sync testing.
- Confirm at least two family members exist for shared/collaboration checks.

## 2) Automated Smoke

Run:

```bash
./scripts/release_smoke.sh
```

Expected:

- iOS signing-free build succeeds.
- Backend TypeScript build succeeds.
- Required release files exist.

## 3) Functional QA (Critical)

- Launch path:
- Splash -> onboarding -> auth gateway -> app shell works without dead-end state.

- Auth and account:
- Create account, sign in, sign out, sign in again.
- Update display name.
- Change password.

- Household sync:
- Create household and join from a second device/account.
- Create event/list/activity on device A and confirm sync on device B.
- Trigger `Sync Now` in Settings and verify status updates.

- Events and scheduling:
- Add/edit/delete event.
- Conflict warning appears for overlapping assigned members.
- Smart scheduling `Find Next Free Family Slot` resolves collision.
- Recurrence options save and persist correctly.

- Notifications:
- Trigger test reminder event in near future.
- Confirm actionable reminder appears.
- Confirm Snooze action schedules follow-up.
- Use `Rebuild Event Notifications` and verify reminders still fire.

- Collaboration:
- Share event link, import on receiver side.
- Verify shared permission toggles (View/Edit) are enforced.
- Verify conflict filter and auto-resolution in shared manager.
- Verify shared activity log records invite and resolution actions.

- Planning and insights:
- `Plan My Week` generates drafts, supports deselect/regenerate/apply.
- Applied drafts appear on Home/Agenda and avoid collisions.
- Home insights (balance/streak/recommendations) render and update after data changes.

## 4) Visual and UX QA

- Verify no clipped text on iPhone SE-sized and large-screen devices.
- Verify dark/light/system appearance transitions.
- Verify custom theme selection updates app accent and persists after relaunch.
- Verify family hero assets render without stretching artifacts.

## 5) Data Integrity and Recovery

- Run `Run Integrity Sweep` in Settings and ensure completion message is shown.
- Corrupt-state resilience check:
- Delete one category used by old events and verify fallback category assignment remains stable.
- Confirm app does not crash after relaunch with recovered data.

## 6) Release Notes Draft (App Store style)

Suggested summary for this release:

- New premium Home dashboard with proactive family insights.
- Smart scheduling assistant with conflict-aware slot suggestions.
- Guided `Plan My Week` flow with selectable draft events.
- Collaboration upgrades: richer share audit and shared conflict tools.
- Reliability upgrades: data integrity sweep and notification rebuild utilities.

## 7) Ship Gate

Only mark release ready when all are true:

- Automated smoke passes.
- Critical functional QA passes.
- No P0/P1 bugs open.
- Release notes finalized.
- Build archived/signed from Xcode organizer with correct team and bundle settings.
