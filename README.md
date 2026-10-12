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
- Eight native condition-specific weather animations across the map, hero forecast, hourly strip, and city cards; Reduce Motion keeps a still condition icon
- Recent Philippine-region earthquake data from USGS
- Philippine headlines from GMA News and world headlines from BBC News
- Optional NewsAPI.org integration with the key stored in macOS Keychain
- Secure Laravel monitoring API connection with separate read, site-registration, and per-project reporter credentials in Keychain
- Local notification scheduling

Live providers are isolated behind service boundaries so they can be replaced or expanded without rewriting the interface. Apple-platform sync remains a later milestone.

## Data and permissions

Tasks, projects, saved locations, and preferences are stored locally. Weather requests send coordinates to Open-Meteo; city search uses Apple Maps. Mac location is requested only when you press “Use Mac location” and is kept in memory for that session, not added to saved locations. Earthquake and news sections read public feeds from USGS, GMA News, and BBC News. Monitoring API tokens are stored in macOS Keychain and sent only to the configured HTTPS endpoint. Launch at login and notifications are opt-in settings controlled from within the application.
