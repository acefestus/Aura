# Aura Signed Distribution Handoff

Use this after the GA tag is in place and you have access to a Mac with a valid Apple Developer signing setup.

## Goal

Produce a signed archive from Xcode Organizer for App Store Connect or TestFlight distribution.

## Xcode steps

1. Open `Aura.xcodeproj` in Xcode.
2. Select the `Aura` scheme and a generic iOS device destination.
3. Open the app target settings and confirm the correct Development Team is selected.
4. Confirm the bundle identifier remains `com.personal.aura`.
5. Choose Product > Archive.
6. When the archive finishes, open Window > Organizer and select the new archive.
7. Click Distribute App.
8. Choose App Store Connect or TestFlight.
9. Follow the signing prompts and export the archive.

## Pre-export checks

- App version should be `1.1.0`.
- Build number should remain `2` unless you intentionally increment it.
- Release smoke should have passed.
- Manual QA should be complete on at least one real device.

## If export fails

- Recheck the selected Development Team.
- Recheck provisioning profiles and certificate status in Xcode.
- Make sure the archive was created from the release scheme, not a debug-only run.
- If the Distribute App flow is unavailable, confirm the archive is selected inside Organizer and not an older entry.