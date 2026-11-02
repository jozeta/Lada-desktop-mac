# Changelog

All notable changes to Lada-desktop-mac are listed here, newest first.

Releases follow the project's git tags. Entries were reconstructed from the commit history.

## [Unreleased]

- Files tab moves data with `container copy` instead of base64 through `sh -c`: binary-exact
  transfers with no size cap (the old path hit Linux's 128 KiB per-argument limit), and no shell inside the
  container for listing, mkdir or delete
- Fix: the file editor truncated files over 128 KiB on save. It now loads whole files and refuses
  files over 1 MiB or binary files (use Download…) instead of cutting them short
- Fix: saving a file reset its permissions and owner (for example scripts lost their execute bit);
  the original mode and owner are now restored
- Fix: a failed download wrote a corrupt file; make-folder and delete reported success even when
  they failed. Errors are now shown
- Fix: device files (`/dev`) showed garbled names in the Files tab
- Fix: command output was dropped when a multi-byte character (å, ä, ö, emoji) was split between
  two pipe reads, and streamed build/pull lines could be split in two
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
