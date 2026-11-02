# Changelog

All notable changes to Lada-desktop-mac are listed here, newest first.

Releases follow the project's git tags. Entries were reconstructed from the commit history.

## [Unreleased]

- Builds redesigned as a guided flow: what a build is, (1) choose the project folder (the
  Dockerfile/Containerfile is detected), (2) name the image (validated, suggested from the folder),
  (3) Build, with "step 2 of 3" progress, the BuildKit error line when it fails, and Run This Image
  when it succeeds. Everything else is under Advanced options in plain language (CLI flags in
  tooltips); the BuildKit helper VM is explained rather than managed up front (it starts by
  itself). Recent builds show image, source folder and duration and can be reused. The form and a
  running build survive leaving the screen
- Fix: the default build file was the relative path `Containerfile`, which the CLI resolves against
  Låda's own working directory, so builds used the wrong file; it is now resolved in the folder
- Each container keeps its own workspace while the app runs: its tab, a terminal shell that keeps
  running in the background (screen and scrollback intact), the Files folder, selection and
  unsaved editor text, and the Logs search/pause/boot-log settings. It all survives switching
  containers and visiting other sections. A container opened for the first time starts on the tab
  you used last; shells end when a container stops, and workspaces are dropped when it is deleted
- Graphs are more detailed: a value scale (rounded to readable steps), the time span, peak and
  average over the window, and a hover crosshair with exact values and how long ago they were
  measured. History covers 5 minutes (was ~80 s). Dashboard network/disk graphs plot real bytes per
  second (they were pre-divided to KB/s) and use the same short titles as the inspector
- Byte sizes are always numeric ("0 bytes", not "Zero KB")
- Terminal tab works like a traditional terminal: a VT100/xterm screen model (cursor movement,
  carriage-return rewrites, erase/insert/delete, scroll regions, alternate screen for `vi`/`top`,
  16/256/true colour, OSC titles ignored, cursor position reports) on a dark background with a
  block cursor and real font metrics. You type directly into it (it focuses itself); Return sends
  `\r`, Ctrl-letter, Delete, Home/End, Page Up/Down and Esc are encoded like xterm, ⌘V pastes. The
  separate command bar and quick-command chips are gone, and output is no longer re-parsed from the
  start on every chunk
- Fix: the terminal stayed connected to the previous container after selecting another one, and
  typed commands were silently dropped after switching tabs or containers (a replaced session's
  exit handler shut down the new session). The inspector rebuilds per container, keeps the
  selected tab, and connects when a container starts while its Terminal tab is open
- Fix: the Logs tab showed the previous container's logs after switching, kept stale text when
  loading failed, and never refreshed; it now clears on switch, shows load errors, and tails every
  2 s while open (the Pause control now works)
- Charts draw smooth monotone curves that never overshoot the measured values
- Redesign, step 2 (Containers): a flat list without striped filler rows, short image names
  (`nginx:1.27-alpine`), compact port mappings, and columns that fit beside the inspector;
  inspector sections are "Details", "Performance" and "Maintenance" with plain labels; chart cards
  (also on the dashboard) use sentence-case titles, numbers that roll to new values, and show
  "Collecting…" / "Not running" instead of a flat line when there is no measured data. All panels
  share one `nordicSurface()` style. The running status dot no longer pulses
- Fix: opening a container's Terminal tab crashed the app (regression from the Swift 6 switch: the
  PTY read handler, written inside a main-actor class, was treated as main-actor code and trapped
  when called on a background queue). Background callbacks (PTY, drag-and-drop loading,
  notification permission) are now explicitly `@Sendable`; terminal output also keeps multi-byte
  characters split between reads intact
- Redesign, step 1 (foundation): spacing, radius and motion tokens (`NordicTheme.Spacing`,
  `.Radius`, `.Motion`) with Reduce Motion respected; cards and panels share one style (continuous
  10 pt corners, hairline border); status badges are softer capsules and a running container's dot
  pulses; the main sidebar uses Nordic rows (accent pill, hover) instead of the translucent system
  list, and its badges only count live resources (containers as running/total)
- Security: no more well-known database passwords. Låda no longer injects
  `POSTGRES_PASSWORD=postgres` / `MYSQL_ROOT_PASSWORD=rootpassword`; presets get a fresh random
  24-character secret per deploy, the environment editor has a generate button, and creating a
  Postgres/MySQL/MariaDB container without credentials is blocked with a clear message
- Security: secret environment values are no longer passed as `-e KEY=value` (readable by any local
  user via `ps`); they go through the `container` process's environment (`-e KEY`)
- Fix: an empty environment value was sent as `-e KEY`, which copies Låda's own variable of that
  name (HOME, PATH, tokens…) into the container; it is now sent as `KEY=`
- Fix: database tweaks matched image names by substring (e.g. `postgres-exporter`); they now match
  the repository name. System notifications are only used inside a real `.app` bundle
- Fix: the Xcode build compiled the new test files into the app target; all test files are now
  excluded from it
- Fix: with the inspector open, the Containers filter overlapped "Prune Stopped…" and the
  inspector title was truncated (e.g. "ng…ss"). The filter falls back to a menu, the header
  actions to icon-only buttons with tooltips, and "Unknown" is only offered when relevant
- Fix: pushing or saving a pulled image failed ("content with digest … not found") because only
  the host's platform is present locally; push and save now pass that platform. Verified with a
  local registry: tag, push, save and load round-trip
- Fix: since 1.6 the BuildKit builder VM appears in `container list`, so it showed up (and could be
  deleted) as a user container; runtime-managed containers are now hidden from the list
- Create Container: image names autocomplete as you type (local images first, then the Image
  Library catalog; after `repo:` it completes that repository's arm64 tags). ↑/↓, Return/Tab and
  Esc work from the keyboard; nothing is fetched over the network while typing. The Presets menu
  lists the whole catalog instead of the first 10
- Settings: the section list is drawn with Nordic surfaces instead of a second translucent system
  sidebar (in light mode its selected row was unreadable), and forms sit in standard Nordic panels
  instead of the system's grouped inset box. Adds a shared `nordicPanel()` modifier
- Image Library: 17 new presets (httpd, MariaDB, ClickHouse, Memcached, Valkey, NATS, PHP, Ruby,
  Eclipse Temurin, Bun, a local OCI registry, Vault dev mode, Gitea, Mailpit, Adminer, BusyBox,
  Fedora). All 35 presets were launched against container 1.6.1 and stay running
- Image Library: tags refreshed to current releases that have arm64 builds (several were years
  old; `grafana/grafana:oss` no longer exists), and stars, pulls and update dates are a real Docker
  Hub snapshot (2026-11-02) instead of invented numbers and "now minus N hours"
- Fix: the Grafana preset failed because it cannot write its root-owned named volume; it now runs
  as root
- Opt-in live tests: `LADA_LIVE_PRESETS` (launch presets) and `LADA_SNAPSHOT_DIR` (render views
  to PNG in light and dark mode)
- Fix: every Image Library launch used `run -d -i -t`, which container 1.6.1 rejects from a
  non-terminal with "Operation not supported by device". Detached runs no longer get `-i`;
  shell images (alpine, ubuntu, …) get `-t` so they keep running, and services get no terminal
  flags. Shell images are now recognised by repository name (e.g. `docker.io/library/alpine`)
- Fix: failed CLI commands showed progress output (`[0/6] [0s]`) as the error. The CLI's `Error:`
  line is shown instead, and a dropped XPC connection (for example a 1.6.1 CLI against a
  still-running 1.5.0 API server, where `run` fails but `list` works) is reported as an API server
  problem with "Restart Services" as the fix
- Fix: dashboard "Cluster CPU Load" averaged per-container percentages; it is now weighted by
  allotted vCPUs (cores in use ÷ vCPUs). System points only combine containers measured in the
  same round, and an inspector refresh no longer adds a system point mixing fresh and stale data
- CPU cards show cores in use ("0.70 of 4 vCPU busy"); the dashboard's Active Containers list is
  sorted by live CPU and shows CPU and network rates. Counter semantics were checked against a
  real 1.6.1 container (CPU time = cgroup `usage_usec`, block and network bytes exact)
- DNS aliases (container 1.6): set them in the Create Container wizard (validated against
  upstream's rules), see them in the container's Networking tab, and keep them when cloning
- Compose stacks give each service its name, plus any `networks: <net>: aliases:`, as DNS aliases
  so peers can reach it as e.g. `db`. Single-label names need a default DNS domain; without one,
  or when another container already uses a name, the alias is skipped with a note in the stack
  console. Previously stacks had no name resolution between services at all
- Read the `machine.*` system properties (default CPUs, memory, home mount, virtualization),
  show them in Settings → System & Runtime, and use them as the starting values for Create Machine
- Health check: warn when the API server runs a different release than the CLI (for example
  after upgrading to 1.6.1 without restarting services), with a "Restart Services" action in the
  Setup wizard and on the dashboard
- Health check: runtimes older than 1.6.0 are flagged for GHSA-vgrw-36j7-r93w and
  GHSA-fqxg-rrf3-358v; the recommended runtime is now 1.6.1 (Mock Sandbox reports 1.6.1 too)
- Fix: telemetry charts showed invented values. The first CPU value was derived from the raw
  counter, first network/disk rates were totals divided by 30, ten jittered seed points were
  back-filled, and CPU never went below 0.2 %. Charts now start after two real snapshots and
  show only measured rates (0 % when idle)
- Fix: missing fields were filled with invented values (DNS server 1.1.1.1, 4 cores / 8 GiB for
  machines). DNS now means "runtime default" when empty and unknown machine resources show "—";
  cloning a container no longer drops an explicit 1.1.1.1 resolver
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
