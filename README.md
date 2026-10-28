# JARVIS Dashboard

A local-first macOS command centre for tasks, projects, briefings, weather, news, and safety alerts.

The application icon uses the letter-free JARVIS HUD artwork in `Supporting/Brand/JarvisIconMaster.png`; the complete macOS icon set is generated under `Supporting/Assets.xcassets`.

JARVIS opens directly into the native dashboard. The earlier full-window startup animation was intentionally removed so launch remains immediate and unobtrusive.

Documentation:

- [Detailed product and feature specification](JARVIS_DASHBOARD_DETAILED_FEATURES.md)
- [Complete feature reference](JARVIS_DASHBOARD_FEATURES.md)

## Requirements

- macOS 14 or newer
- Swift 6 toolchain
- Xcode for signing, entitlements, and creating a distributable `.app`

## Development

The primary project is the generated native macOS application:

```sh
xcodegen generate
open JarvisDashboard.xcodeproj
```

The Swift package remains available for command-line compilation and tests:

```sh
swift build
swift test
swift run JarvisDashboard
```

Select the `JarvisDashboard` application scheme in Xcode to run the signed app bundle. Login-item registration requires the application bundle; it is not available when launched with `swift run`.

### Releasing

Commit your changes, then run:

```sh
scripts/release.sh 0.2.29 --commit   # or --no-install to stop after packaging
```

The script stops at the first failed check:
- It requires a clean tree, a newer version, and a valid Apple Development signing identity.
- It bumps `project.yml`, runs the tests, and builds a universal Release.
- It checks the signature, both architectures, and the version, then writes `dist/JARVIS-Dashboard-<version>.zip`.
- It quits JARVIS and backs up the installed app and both SwiftData stores to `dist/install-backups/`, verified byte for byte and with SQLite `quick_check`.
- It installs, launches, and checks that JARVIS is running, with no new crash report and healthy stores.

Builds are signed with a stable Apple Development identity, so Keychain "Always Allow" grants carry over between releases. Ad-hoc signing would make each build look like a new app.

## Obsidian ICM handoff

The **Cortex** sidebar automatically discovers projects under the vault's `Work/` and `Personal/` folders when they contain a Git directory, project manifest, `PROJECT.md`, or an index file. It refreshes when opened and every 30 seconds while the overview is visible. Projects explicitly listed in `ICM/routes.json` also appear, without duplicates. If a route's folder is missing or a path is unsafe, the overview lists that route under **ICM routes need attention** and shows the other projects as normal. Discovery rules come from the vault's `ICM/discovery.json`, which the vault's `.tools/project_hubs.py` also reads; if the file is missing or malformed, JARVIS uses built-in defaults. After each scan, Cortex writes the project list to `ICM/cortex-projects.json`, only when it has changed, so the vault doctor can compare the two. A health card shows the latest `ICM/health.json` report from `.tools/vault_doctor.py` and warns when that report is more than a day old. While JARVIS is open, it runs the vault's `.tools/vault_maintenance.py` every 3 hours, starting at launch, and logs to `~/Library/Logs/vault-maintenance.log`. It also files prompts queued by the Codex and Claude Code capture hooks: every 15 seconds, only when prompts are waiting, it runs the hook's `--drain`. Both run as child processes of JARVIS because macOS doesn't let launchd jobs list `~/Documents` (and lets them read only files they created), so the jobs share JARVIS's access to the vault. While JARVIS is closed, queued prompts wait and are filed when it opens. Choose a project to browse its source tree, search folder and file paths. The **Synapse Map** embeds Graphify's own generated `graph.html` viewer, including its search, node inspector, community filters, and force-directed layout. Regenerate a project's map with the vault's `.tools/graphify_refresh.py <route>` (see `Graphify/Atlas.md`). It writes the community labels and vault-relative links JARVIS needs, and installs nothing unless validation passes. JARVIS adds subtle travelling signal pulses over Graphify's links. Selecting a source file focuses its Graphify node when one exists. The source and note links remain available below the map. JARVIS reads the Graphify export locally and does not alter project files. Generated builds, dependency folders and hidden folders are omitted from the source tree. Add an `ICM/routes.json` entry when the Ask JARVIS console should route requests to a project; discovery alone does not configure that handoff.

The **Ask JARVIS** console can route work requests through a local Obsidian vault. In Settings, choose the `Projects` vault containing `CONTEXT.md` and `ICM/routes.json` (the default location is `~/Documents/Main/Projects`). For a prompt such as “Update the JARVIS UI”, JARVIS selects the configured project, checks its context note, suggests a few Graphify notes, and offers a short handoff to copy into Codex or Claude. It saves every submitted console prompt locally under `Memory/01_intake/`; unmatched prompts go into `_unrouted/`. Matched work requests also create a dated, append-only activity note under `Notes/Projects/<project path>/Activities/` following PARA. The handoff asks the agent to fill in work performed, files, verification, and outcome in that note.

Routing is deterministic and does not call an AI service. The agent must still inspect current source and local project instructions. The route file is the place to add further projects; the currently configured pilot routes are JARVIS and LawrencePortfolio.

## Current foundation

- Native SwiftUI macOS application
- Command-centre Today dashboard with live operational hierarchy, monitoring health, fixed-grid intelligence, and a local Ask JARVIS console
- Persistent Tasks Mission Queue and project operations using SwiftData
- Versioned local-data schema with daily backups, secret-free JSON export, previewed merge/replace restore, and configurable rotation
- Project foundation with full create/edit/detail flows, status and priority tracking, due-date warnings, duplication, archiving, and confirmed deletion
- Fixed and ongoing-client project modes, with read-only local Git repository health and activity summaries for ongoing work
- Project-level website monitoring setup with platform selection, API registration, editable site details, and per-project reporter tokens stored in Keychain
- Live monitoring fleet summary, health sorting/filtering, explainable site-health gauges, and per-project Security & Maintenance details
- Intelligence Matrix with priority alerts, Philippine conditions, editable watchlists, operational signals, change-aware briefings, and opt-in quiet-hour notifications
- Local configurable JARVIS text-to-speech using installed macOS voices
- Menu-bar command centre
- Launch-at-login setting using `SMAppService`
- Sleep/wake monitoring and configurable wake briefings
- Live weather forecasts from Open-Meteo
- Switchable Philippine weather map and personal weather dashboard, with a primary-location hero forecast, four independently chosen city cards, city search, and opt-in Mac location
- Optional MapTiler Landscape basemap preview for the Philippine map; Apple Maps remains the default and native animated weather beacons remain above either basemap
- Satellite mode using MapTiler ground imagery with NOAA infrared cloud tiles on top. The clouds show the latest available observation, independent of the forecast-hour slider; the tile service does not supply an observation time. Ordinary weather overlays are hidden, with animated thunderstorm icons only at sampled forecast locations where the selected hour reports a storm. This is not live radar, lightning detection, or a storm-coverage map.
- Eight native condition-specific weather animations across the map, hero forecast, hourly strip, and city cards; Reduce Motion keeps a still condition icon
- Recent Philippine-region earthquake data from USGS
- Philippine headlines from GMA News and world headlines from BBC News
- Optional NewsAPI.org integration with the key stored in macOS Keychain
- Secure Laravel monitoring API connection with separate read, site-registration, and per-project reporter credentials in Keychain
- Local notification scheduling

Live providers are isolated behind service boundaries so they can be replaced or expanded without rewriting the interface. Apple-platform sync remains a later milestone.

## Data and permissions

Tasks, projects, saved locations, and preferences are stored locally. Weather requests send coordinates to Open-Meteo; city search uses Apple Maps. Mac location is requested only when you press “Use Mac location” and is kept in memory for that session, not added to saved locations. The optional MapTiler Landscape and Satellite modes load MapTiler's SDK and map tiles while visible; the API key is stored in macOS Keychain, not in the repository, but is necessarily sent in map requests. Satellite mode also requests public infrared cloud tiles from NOAA/NESDIS. Paste only the MapTiler key in Settings, then select **MapTiler preview** or **Satellite** in the Philippine map's **Basemap** picker. Satellite thunderstorm icons represent forecasts at 16 sampled locations, not live radar or storm coverage. MapTiler usage counts towards the account's quota. Earthquake and news sections read public feeds from USGS, GMA News, and BBC News. Monitoring API tokens are stored in macOS Keychain and sent only to the configured HTTPS endpoint. Launch at login and notifications are opt-in settings controlled from within the application.
