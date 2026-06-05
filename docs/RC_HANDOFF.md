# Aura Release Handoff

## Current release

- Version: `1.1.0`
- Marketing version: `1.1.0`
- Build number: `2`
- RC tag: `v1.1.0-rc.1`
- GA tag: `v1.1.0`

## Completed automatically

- `./scripts/release_smoke.sh` passed
- Signing-free build passed
- Signing-free archive passed
- Changelog prepared in `CHANGELOG.md`
- Release notes draft prepared in `docs/RELEASE_NOTES_1.1.0.md`
- Simulator launch smoke passed

## Archive output

Validated archive path:

- `build/Aura-1.1.0-rc1.xcarchive`

## Remaining recommended follow-up

- Run the functional QA sections in `docs/RELEASE_QA_CHECKLIST.md`
- Verify visual QA on target devices/simulator sizes
- Archive/sign from Xcode with the correct Development Team and provisioning
- Confirm no open release-blocking issues

## Release note

`v1.1.0` was cut from this machine without Apple signing identities available locally. The git/tag release is complete, but App Store/TestFlight style distribution still requires a signed archive from Xcode on a machine with a valid Apple Developer setup.
