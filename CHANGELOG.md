# Changelog

All notable changes to Lada-desktop-mac are listed here, newest first.

From 1.6.0 every commit bumps the version (`Scripts/bump-version.sh`); entries up to 1.5.0 were reconstructed from the commit history.

## [Unreleased]

## [1.7.1] - 2026-11-03

- Release packaging uses the notarytool keychain profile `LadaNotary` by default (was
  `MySpacesNotary`, left over from another project); override with `LADA_NOTARY_PROFILE`

## [1.7.0] - 2026-11-02

- Compose `mem_limit:` and `cpus:` are honoured (and written back by the stack builder); before,
  every stack service got the default memory and CPUs. Metabase gets 2 GB, which its JVM needs
- New templates were run on container 1.6.1. Without a default DNS domain, services can't find
  each other by name: LAMP, Drupal, Matomo, MediaWiki, Uptime Kuma, RabbitMQ and Caddy keep
  running, while apps that exit when their database is unreachable (Ghost, Directus, Keycloak,
  n8n, Nextcloud, Joomla, Odoo, Metabase, Mongo Express) stop until a DNS domain is set
- Live stack test cleans up by container name (a successful start clears the Stacks screen, so
  it used to leave the started stacks behind)

- Stacks: 16 more templates for popular web stacks: LAMP (PHP + MariaDB + phpMyAdmin), MongoDB
  + Mongo Express, Ghost + MySQL, Nextcloud + PostgreSQL + Redis, Drupal, Joomla, Directus,
  n8n, Keycloak, Matomo, Metabase, Odoo, MediaWiki, Uptime Kuma, RabbitMQ and Caddy reverse
  proxy. Every image is pinned to a version with an arm64 build (checked against the
  registries); Prometheus and Grafana are pinned instead of `:latest`
- Compose `command:` now follows Compose: it replaces the image's CMD and keeps its ENTRYPOINT
  (init scripts run), and is split like a shell (quotes group words; list form supported).
  Before, the first word replaced the entrypoint and quoted arguments were split apart
- Dockerfile Editor IntelliSense: the completion list has a reference pane for the highlighted
  suggestion: what the instruction does, how it works, syntax, every parameter and flag (the
  one being completed is highlighted) and an example
- Node Graph is faster and easier to use: the graph is built once per inventory change instead
  of on every hover or drag frame, chips redraw only when their own state changes and no longer
  use a blur and shadow each, and the layouts use spatial grids (Fruchterman–Reingold's grid
  variant for force-directed). Build plus all five layouts for 332 nodes went from 3.7 s to
  0.76 s (debug build). Clicking empty space, Esc or the selection chip's ✕ now deselects
- Info tips open at once (no popover animation) in a lighter, more see-through frosted card

## [1.6.0] - 2026-11-02

- Node Graph (Infrastructure): every resource as a node (stacks, containers, machines, images,
  networks, IP addresses, subnets, volumes, Mac folders, ports, registries) with its own icon,
  linked by relationship (runs, attached to, has address, in subnet, mounts, publishes, member
  of, pulled from) and similarity (same image repository). Drag nodes, pan and zoom, hide types,
  and re-arrange with Force-Directed, Hierarchy, Radial, Circular or By Type layouts; hover for
  a node's configuration, double-click to open it
- Machines: a Containers-style inspector (Overview with live charts, Terminal with the machine's
  real login shell, Files, Logs, Settings with save-and-restart, Inspect), Open in Terminal.app,
  and state kept per machine. Machine data now comes from `machine inspect` (container ID,
  image, home mount, user), which `machine list` doesn't report; home mount was always shown
  as read-write before
- Universal search in the toolbar: finds containers, stacks, images, machines, volumes,
  networks, registries, Image Library presets and pages, with type, location and state, in a
  frosted panel (↑↓, Return, Esc). The old per-list filtering is gone
- Toolbar: New Container, Pull Image and Build Image removed (⌘N, ⇧⌘N and the menus remain).
  Refresh waits for a poll in progress and also reloads open logs, folders and stack logs
- Create Network, Create Volume, Create Machine and Log In to Registry redesigned on one sheet
  layout: icon header, sections, hints and ⓘ tips, live validation in the footer (duplicate
  names, overlapping subnets, sizes), command preview with Copy, and the new item selected
  afterwards. Network suggests a free subnet; Volume shows sizes against the Mac's free space;
  Machine offers common images and disables nested virtualization where unsupported;
  Registry explains where to get a token for well-known registries and warns about HTTP
- ⓘ info tips with hover cards on section headers, Settings controls, machine settings and
  sheets
- Dockerfile completion list is a frosted-glass panel with roomier rows and type labels
- Accent palette: seven new themes (Frost Cyan, Aurora Green, Aurora Violet, Lingonberry,
  Cloudberry, Birch Gold, Midnight Indigo), chosen from colour swatches. The accent now applies
  everywhere; several components always used Fjord Blue before
- Interface Density works: Compact uses smaller controls, tighter panels, shorter rows and a
  denser sidebar. Settings changes now update the whole window at once
- Settings → About: version, the runtime and this Mac, Copy Version Info, links and licences
- Versioning: `Scripts/bump-version.sh` updates Info.plist, the Xcode project, `AppVersion` and
  this changelog together; a test checks they agree
- Security: the Terminal.app launcher quotes every argument, so container or machine names and
  a custom CLI path can't inject shell commands

- Translucent window: the desktop and windows behind Låda show through, blurred, under a lighter
  Nordic tint; panels use a thinner glass so the frost is visible (Reduce Transparency makes both
  solid). Sections no longer stack extra copies of the backdrop
- Container inspector: a disk donut per container showing what its root filesystem image uses on
  this Mac and how much it can still grow (measured from the sparse `rootfs.ext4`, so it works
  for stopped containers)
- Dockerfile Editor: code completion while typing (instructions, then each instruction's
  arguments: images, build stages for `COPY --from=`, `ARG`/`ENV` variables, flags, ports,
  signals, earlier WORKDIRs and USERs, OCI labels), brighter text, and the code on the same glass
  as other panels instead of an opaque slab; header and inspector restyled to match Stacks
- Dashboard: Quick Actions removed; Active Containers, disk usage and recent operations pack into
  columns without gaps (masonry layout) and reflow to one column when narrow
- Performance: one 2-second poll loop feeds every chart (the dashboard and inspector no longer
  run their own stats loops); poll results only publish when they changed, `isRefreshing` no
  longer re-renders the window, telemetry history is published once per poll, and the drag-and-
  drop helper walks the view tree only when the section changes
- Files tab: fits the inspector at the default window size (it overflowed and clipped both
  edges), toolbar buttons fall back to icons when narrow, and the cached listing stays visible
  while it refreshes
- README: new screenshots and feature descriptions checked against the code (8-tab inspector,
  actual linter rules and templates, no Builds page or terminal quick-command bar)

- Dashboard: a hollow pie (donut) of the drive that holds the runtime's data, split into images,
  containers, volumes, other files and free space, with the free space in the middle
- Every panel uses the same frosted glass (Image Library cards and filter bar, menu-bar rows, drop
  overlays, chart hover readouts); small chips use one translucent chip style instead of opaque
  fills
- All tables share the Containers table design: transparent, no stripes, icon + semibold name,
  12 pt secondary columns, plain column titles. The Files tab is now such a table (Name, Size,
  Modified, Permissions, Owner) with double-click to open
- The code surface and backdrop are cool Nordic tones instead of warm beige, and the Dockerfile
  Editor highlights with a Nordic palette chosen for contrast in each appearance (re-applied when
  you switch light/dark)
- Stacks starts empty with two ways in: build your own (name it, then Add Service) or pick one of
  the template cards. The stack name is editable in the header. After a stack starts successfully
  (every service running) the window clears and shows a confirmation with Show in Containers; the
  compose file is remembered so Open in Stacks on the stack's group in Containers can reopen it. If
  any service fails, nothing is cleared
- Frosted-glass look: one calm Nordic backdrop (a soft fjord-to-sand gradient) behind every
  section, panels and cards in frosted material with a fine light edge and soft shadow, toolbars
  and headers in bar material, and a translucent sidebar. Terminal, code editors and logs stay solid
  for contrast; with Reduce Transparency the system makes the materials opaque
- Stacks is a stack builder: Add Service (and Edit/Remove on each service) opens a form for name,
  image (autocomplete or an Image Library preset with generated secrets), ports, settings, storage,
  start order and command, with a preview; saving writes only that service's block into the compose
  file (other text and comments are kept), and services typed in the Compose File tab appear under
  Services. Starting a stack keeps running if you leave the screen
- Containers groups each started stack under one collapsible row named after the stack (members by
  service name, "2/3 running", start/stop all); selecting it shows a stack summary. Collapsed groups
  are remembered
- Stack templates: added PostgreSQL + Adminer, Gitea + PostgreSQL, NATS + Valkey, Mailpit + private
  registry and Vault (dev mode); updated tags; passwords are generated each time a template is used
  (shared ones stay consistent). Templates & Files has New Empty Stack, Open Recent, Save and Save As
  and opens any `.yml`/`.yaml` compose file
- Fix: the WordPress template ran nginx instead of WordPress and pointed at the database by
  container name; it now runs `wordpress:php8.4-apache` against the `mysql` service
- Removed the Builds page; build images in the Dockerfile Editor (the toolbar's Build Image and the
  dashboard action open it)
- Stacks redesigned for clarity: a one-line explanation, the stack's state in words ("2 of 3
  services running"), Start / Stop / Remove next to it, and Services, Compose File and Logs tabs.
  Services is the default, with a three-step "How it works" guide until the stack is started
  (including whether services can reach each other by name) and cards that show the short image,
  start order, what each service waits for and its localhost ports
- Fix: the compose editor reset to the first template whenever you left Stacks, losing edits, and a
  file opened from the Dockerfile Editor was re-applied on every return; the compose file, tab and
  activity are now kept in `AppState` and a handed-over draft is applied once
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
