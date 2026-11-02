# Changelog

All notable changes to Lada-desktop-mac are listed here, newest first.

Releases follow the project's git tags. Entries were reconstructed from the commit history.

## [Unreleased]

- Build the SwiftPM targets in Swift 6 language mode (matching the Xcode project); fix the
  resulting strict-concurrency errors in `CommandRunner`, the Dockerfile completion catalog and
  a UI workflow test
- Add parser tests against real `container` 1.6.1 output, and `CommandRunner` tests (stdout,
  stdin, exit status, timeout termination)
- `Scripts/package-app.sh` names the dmg and zip after the version in `Info.plist` instead of a
  hardcoded 1.5.0
- Correct CLAUDE.md: the packaging script is in the repo
- Bump `actions/checkout` from 4 to 7
- Add CHANGELOG.md
- Ignore macOS, Claude Code and secret files
- Add CLAUDE.md with project guidance for Claude Code
- Add CI workflow, Dependabot config, security policy

## [1.5.0] - 2026-10-19

- Initial release of Låda v1.5.0 — Native macOS GUI for Apple Containers
- Use ASCII 'Lada' for all filenames, bundle paths, CLI output, and scripts
- Package distribution zips with --norsrc --noextattr and notarize/staple builds
