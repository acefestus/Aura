# Aura RC Handoff

## Current release candidate

- Version: `1.1.0-rc.1`
- Marketing version: `1.1.0`
- Build number: `2`
- Git tag: `v1.1.0-rc.1`

## Completed automatically

- `./scripts/release_smoke.sh` passed
- Signing-free build passed
- Signing-free archive passed
- Changelog prepared in `CHANGELOG.md`
- Release notes draft prepared in `docs/RELEASE_NOTES_1.1.0.md`

## Archive output

Expected archive path:

- `build/Aura-1.1.0-rc1.xcarchive`

## Remaining manual gate items

- Run the functional QA sections in `docs/RELEASE_QA_CHECKLIST.md`
- Verify visual QA on target devices/simulator sizes
- Archive/sign from Xcode with the correct Development Team and provisioning
- Confirm no open release-blocking issues

## GA cut rule

Do not create final `v1.1.0` tag until the manual gate items above are complete.
