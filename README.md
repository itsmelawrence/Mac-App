# JARVIS Dashboard

A local-first macOS command centre for tasks, projects, briefings, weather, news, and safety alerts.

The application icon uses the letter-free JARVIS HUD artwork in `Supporting/Brand/JarvisIconMaster.png`; the complete macOS icon set is generated under `Supporting/Assets.xcassets`.

At launch, the supplied self-contained HTML animation runs as a native full-window WebKit overlay while the dashboard refreshes beneath it. The overlay fades only after both the 3.8-second animation and the first dashboard data attempt have completed.

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

## Current foundation

- Native SwiftUI macOS application
- Today dashboard with generated briefing
- Persistent tasks and projects using SwiftData
- Project foundation with full create/edit/detail flows, status and priority tracking, due-date warnings, duplication, archiving, and confirmed deletion
- Fixed and ongoing-client project modes, with read-only local Git repository health and activity summaries for ongoing work
- Project-level website monitoring setup with platform selection, API registration, and per-project reporter tokens stored in Keychain
- Live monitoring fleet summary, health sorting/filtering, explainable site-health gauges, and per-project Security & Maintenance details
- Intelligence centre with priority alerts, Philippine conditions, editable watchlists, operational signals, change-aware briefings, and opt-in quiet-hour notifications
- Menu-bar command centre
- Launch-at-login setting using `SMAppService`
- Sleep/wake monitoring and configurable wake briefings
- Live weather forecasts from Open-Meteo
- Recent Philippine-region earthquake data from USGS
- Philippine headlines from GMA News and world headlines from BBC News
- Optional NewsAPI.org integration with the key stored in macOS Keychain
- Secure Laravel monitoring API connection with separate read, site-registration, and per-project reporter credentials in Keychain
- Local notification scheduling

Live providers are isolated behind service boundaries so they can be replaced or expanded without rewriting the interface. Apple-platform sync remains a later milestone.

## Data and permissions

Tasks, projects, locations, and preferences are stored locally. Weather requests send coordinates to Open-Meteo; earthquake and news sections read public feeds from USGS, GMA News, and BBC News. Monitoring API tokens are stored in macOS Keychain and sent only to the configured HTTPS endpoint. Launch at login and notifications are opt-in settings controlled from within the application.
