# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Låda (`Lada`) is a native macOS SwiftUI app for managing Apple's official
[`container`](https://github.com/apple/container) runtime (v1.5.0+): containers, images, Docker Hub
library, Compose stacks, Dockerfile studio with linter, builds, networks, volumes, machines,
registries, an in-container file browser, a PTY terminal and a menu-bar popover.

## Commands

```sh
swift build
swift run Lada
swift test                 # LadaTests: Lada/Tests/{UnitTests,IntegrationTests,UIAutomationTests}
```

Also buildable from `Lada.xcodeproj`. Requires macOS 15+ and Swift 6 / Xcode 16+ (live containers
need macOS 26+ on Apple silicon and the `container` CLI in `/usr/local/bin` or
`/opt/homebrew/bin`). Without the CLI, the app's Mock Sandbox mode uses
`MockContainerRuntimeService`.

`Scripts/package-app.sh` builds a release `Lada.app`, a `.dmg` and a distribution zip in `build/`
(gitignored), and notarizes and staples them with `xcrun notarytool` (keychain profile from
`LADA_NOTARY_PROFILE`, default `MySpacesNotary`). Artifact names take the version from
`Lada/Resources/Info.plist`, so bump `CFBundleShortVersionString` (and `MARKETING_VERSION` in the
Xcode project) for a release. `Scripts/generate-app-icon.swift` regenerates `AppIcon.icns`.

## Architecture (`Lada/`)

- `App/`: `LadaApp` (@main, MenuBarExtra, shortcuts), `AppDelegate`, `AppState` (@MainActor
  coordinator, adaptive polling), `MainWindowView` (NavigationSplitView shell).
- `Runtime/`: `ContainerRuntimeService` protocol with live `ContainerCLIClient` and
  `MockContainerRuntimeService`; `CommandRunner` (actor, non-shell `Process`, streaming,
  cancellation); `OutputParsers/ContainerOutputParser`; discovery, health and capability services;
  `DockerHubService`.
- `Core/`: `Models/` (typed models and deterministic CLI argument builders), `Errors/LadaError`,
  `Utilities/` (Compose and Dockerfile parsers, port prober, `SecretRedactor`,
  `StructuredLogger`, `KeychainService`, validators), `Configuration/AppPreferences`.
- `Features/<Area>/`: one SwiftUI view module per sidebar section.
- `Shared/`: `NordicTheme` design system, custom vector icons, reusable components,
  accessibility identifiers.

## Rules

- **Never invoke a shell.** All CLI calls go through `CommandRunner` with an argument array built
  by the typed argument builders; validate names, CIDRs, MACs and ports with `ValidationUtils`.
- Every new runtime operation needs both a live (`ContainerCLIClient`) and mock implementation,
  plus parser tests against real `container` output.
- Pass anything that may contain credentials through `SecretRedactor` before logging or showing
  it as a CLI preview; store registry credentials only in the Keychain.
- Keep upstream compatibility notes (README "Upstream Runtime Compatibility") in sync when
  targeting a new `container` version.
- New UI controls get an identifier in `AccessibilityIdentifiers` for the UI automation tests.
