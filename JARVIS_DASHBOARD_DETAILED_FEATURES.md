# JARVIS Dashboard — Detailed Product and Feature Specification

**Current release:** 0.2.3

**Platform:** macOS 14 Sonoma or newer  
**Application type:** Native, local-first productivity, operations, and intelligence dashboard  
**Bundle identifier:** `com.skeemadigital.jarvisdashboard`

## 1. Product vision

JARVIS Dashboard is a personal macOS command centre for daily work, client operations, website health, live regional information, and concise briefings. It is designed to answer four questions immediately:

1. What requires attention now?
2. What work should be completed next?
3. Are active projects and client websites healthy?
4. Has anything important changed locally or regionally?

The application is local-first. Tasks, projects, locations, and preferences remain on the Mac. Network requests are made only for configured live services such as weather, earthquake data, news, and the JARVIS Monitoring API.

## 2. Main application structure

The primary window uses a native macOS sidebar with five destinations:

- **Today** — daily command centre
- **Tasks** — operational mission queue
- **Projects** — project, repository, and website operations
- **Intelligence** — regional, news, and operational intelligence
- **Settings** — startup, voice, notifications, API credentials, backup, restore, and privacy

The application also includes:

- A macOS menu-bar command centre
- A floating briefing panel
- Launch-at-login support
- Sleep and wake detection
- Local notifications
- Local text-to-speech
- Secure Keychain-backed credentials

## 3. Today — Command Centre

Today is the main overview rather than a miscellaneous widget board. It uses a fixed visual hierarchy so the briefing and active work remain dominant.

### 3.1 Command header

- Greets the user based on the current time of day.
- Displays the complete date.
- Shows whether systems are nominal or how many items require attention.
- Opens **Ask JARVIS** through the header or `Command-K`.
- Refreshes weather, earthquake, and monitoring information.

### 3.2 Ask JARVIS

- Processes supported commands locally.
- Does not send command text to an external AI provider.
- Presents the current briefing.
- Speaks the briefing when requested.
- Routes the user to Tasks, Projects, Intelligence, weather/news information, or Settings.
- Answers supported questions about task counts, active projects, and monitored-site health.
- Names the next actionable task, blocked tasks, and projects waiting on clients.
- Summarises attention items and distinguishes unhealthy sites from sites awaiting checks or unavailable monitoring data.
- Reports the most recently refreshed weather for the primary location, or states when a fresh report is unavailable.
- Answers questions about a named project with a structured card covering project status, site health, last check, task counts, next action, data sources, and update time.
- Asks for a more specific project name when multiple projects match; never invents a project or a monitoring result.
- Keeps the answer visible until the user selects **View project** to open that project's detail screen.
- Explains currently supported capabilities when a request is not understood.

### 3.3 Daily briefing

The generated briefing can include:

- Pending task count
- Overdue task count
- Active project count
- Primary-location weather
- Significant Philippine-region earthquake count

The briefing can be read in place, spoken aloud, or presented in the floating briefing panel.

### 3.4 Operational status rail

The status rail summarises:

- Open tasks
- Overdue tasks
- Active operations
- Healthy monitored sites
- Regional alerts

### 3.5 Active operations

- Ranks active projects using monitoring health, project status, priority, and recent activity.
- Shows the project's next action.
- Shows the number of linked open tasks.
- Shows live website-monitoring state when available.
- Uses green only for confirmed healthy states.
- Uses orange and red only for conditions that warrant attention.
- Opens the Projects section for deeper investigation.

### 3.6 Next actions

- Displays the most relevant pending tasks.
- Prioritises overdue and higher-priority work.
- Identifies blocked work.
- Allows a task to be completed directly from Today.
- Opens the complete mission queue.

### 3.7 Weather and regional intelligence

- Displays weather for the primary saved location.
- Displays the latest significant Philippine-region earthquake signal.
- Links the user to deeper Intelligence analysis.
- Retains partial results when another provider fails.

### 3.8 Monitoring system status

- Shows whether the Monitoring API is online.
- Displays monitored-site totals.
- Displays healthy and attention-required counts.
- Never labels unknown or unavailable data as healthy.

### 3.9 Momentum and daily resolve

- Shows completed-task momentum.
- Shows due-today and blocked-task counts.
- Displays a locally stored motivational or philosophical quote.
- Selects a stable quote for the day.
- Allows another quote to be shown without refreshing network data.

## 4. Tasks — Mission Queue

Tasks is designed as an operational queue rather than a passive checklist.

### 4.1 Mission Queue header

- Shows the number of items requiring attention.
- Provides a prominent **New Mission** action.
- Displays live counts for:
  - Open
  - Due today
  - Overdue
  - Blocked
  - Completed

### 4.2 Priority Now

- Automatically selects the most important actionable task.
- Prefers overdue work over future work.
- Prefers higher-priority work when urgency is otherwise equal.
- Prefers actionable work over blocked work.
- Falls back to blocked work when no actionable task exists.
- Shows its linked project or global Inbox status.
- Shows its deadline and priority.
- Allows immediate completion.

### 4.3 Queue filtering

The mission queue can be filtered by:

- Open tasks
- Tasks due today
- Overdue tasks
- Blocked tasks
- Completed tasks
- Individual project

Search covers:

- Task title
- Notes
- Blocking reason
- Linked project name

### 4.4 Task creation

Each task supports:

- Required title
- Multi-line notes
- Optional project assignment
- Optional due date and time
- Optional blocked state and blocking reason
- Priority levels:
  - Low
  - Normal
  - High
  - Critical

When a due date is set, JARVIS can schedule a local reminder subject to macOS notification permission.

### 4.5 Task management

- Mark complete or return to pending.
- Mark blocked or unblock from the context menu.
- Display overdue deadlines in red.
- Display priority using restrained urgency colours.
- Delete only after confirmation.
- Persist changes locally with SwiftData.
- Calculate overall completion momentum.

### 4.6 Project-to-task behaviour

- A task may belong to a specific project or the global Inbox.
- Project cards can show linked task totals.
- Fixed-project completion is calculated automatically when linked tasks exist.
- Manual progress remains available when a fixed project has no linked tasks.
- Blocked and waiting-on-client states remain distinct: blocked applies to a task; waiting on client applies to a project.

## 5. Projects — Operations and Client Work

Projects supports both defined deliverables and continuing client relationships.

### 5.1 Project record

Each project can store:

- Project name
- Client name
- Project type
- Summary and context
- Status
- Priority
- Project mode
- Start date
- Due date
- Tags
- Next action
- Manual progress where applicable
- Local Git repository connection
- Monitoring website URL
- Monitoring platform
- Monitoring Site ID
- Monitoring connection date

### 5.2 Project statuses

- Not Started
- Active
- In Review
- On Hold
- Waiting on Client
- Completed
- Archived

Waiting-on-client projects display the number of days spent in that state.

### 5.3 Project priorities

- Low
- Medium
- High
- Urgent

### 5.4 Fixed Project mode

- Intended for work with a defined completion point.
- Shows due-soon and overdue conditions.
- Uses linked-task completion when tasks are assigned.
- Uses manual progress only when no linked tasks exist.

### 5.5 Ongoing Client mode

- Avoids misleading lifetime completion percentages.
- Uses operational health, current activity, repository status, and website health instead.
- Supports long-running retainers, maintenance relationships, and continuing client work.

### 5.6 Project actions

- Create and edit a project.
- Open project details.
- Change status directly from the card.
- Duplicate a project.
- Archive and restore a project.
- Show or hide archived projects.
- Delete after confirmation.
- Sort and filter the project fleet.
- Show only projects needing attention.

## 6. Local Git Repository Intelligence

An ongoing project can be connected to a local Git repository chosen explicitly by the user.

JARVIS reads:

- Current branch
- Changed-file count
- Latest commit hash
- Latest commit message
- Time since the latest commit
- Commit count during the previous 30 days
- Ahead/behind state when an upstream branch is available

Repository health states are:

- **Healthy** — latest commit within seven days
- **Quiet** — latest commit eight to fourteen days ago
- **Needs Attention** — overdue project or latest commit more than fourteen days ago
- **Blocked** — project is On Hold
- **Setup Needed** — no readable repository activity

Repository inspection safeguards:

- Read-only Git commands
- Git optional locks disabled
- Terminal prompting disabled
- No automatic folder scanning
- No commits, pulls, pushes, checkouts, or file changes
- Repository connection can be refreshed, replaced, or disconnected

## 7. Website Monitoring

Website monitoring is configured from the individual project's settings.

### 7.1 Supported website platforms

- Generic
- WordPress
- Laravel
- Node
- Static
- Custom

### 7.2 Site registration and attachment

- Accepts normal HTTPS URLs.
- Accepts Markdown-formatted links copied from chat or documentation.
- Normalises URLs before registration.
- Registers a new site through the Laravel Monitoring API.
- Detects and attaches an already registered website through the saved read-only connection.
- Avoids creating duplicate monitoring records.
- Allows the URL and platform to be corrected later.
- Preserves the Site ID, reporter access, snapshots, findings, incidents, and historical data when details change.

### 7.3 Credential separation

JARVIS uses three distinct monitoring credential types:

1. **Read token** — loads monitoring summaries and details.
2. **Site-registration/admin token** — creates sites, edits site settings, updates findings, and rotates reporter credentials.
3. **Reporter token** — belongs to one monitored website and allows that website to submit telemetry.

All credentials are stored in macOS Keychain. Reporter tokens are stored separately using the local project ID.

### 7.4 Reporter-token workflow

- The Monitoring API returns a dedicated reporter token when a site is registered.
- JARVIS stores the token locally in Keychain.
- **Copy Reporter Token** transfers it for placement in the website host's secret manager or environment configuration.
- **Rotate Reporter Token** revokes the previous token and stores the replacement.
- JARVIS warns that the website must be updated before its next heartbeat after rotation.
- The Mac application never installs reporter code or changes hosting configuration automatically.

### 7.5 Universal reporter concept

The monitoring design is platform-flexible:

- WordPress can use the universal must-use plugin reporter.
- Laravel, Node, static, and custom applications can submit the same telemetry through their own scheduled code.
- A reporter can send heartbeat, environment, dependency inventory, update state, and application-health information.
- A real server cron or scheduler should run the reporter; the site does not need a human visitor to trigger monitoring.

### 7.6 Site-health states and score

- A score appears only after the backend completes an outside reachability check.
- Unknown, stale, disconnected, offline, or awaiting-check states remain explicit.
- A missing signal never becomes a fabricated score of 100.
- The score begins at 100 and applies explainable deductions.

Potential deductions include:

- Open vulnerabilities
- Available component updates
- Unsupported PHP version
- SSL certificate expiring within fourteen days
- Missing reporter heartbeat
- Failed application or database health checks

### 7.7 Project health card

- Shows a semicircular site-health gauge.
- Displays score and health label.
- Displays update and vulnerability totals.
- Shows the last observation time.
- Keeps project delivery progress and repository health separate from site health.
- Animates the gauge unless Reduce Motion is enabled.

### 7.8 Security and Maintenance view

The detailed monitoring view contains:

- Open vulnerability findings
- Severity and affected component
- Fixed-in version where supplied
- External reference links
- Mark-as-handled action
- Ignore action
- Plugin, theme, core, and dependency updates
- Covered and not-covered component inventory
- Reporter application checks
- Database and scheduler checks
- HTTP status and response time
- 30-day uptime
- PHP version
- SSL expiry date
- Last heartbeat
- Application name and deployment version
- Explainable score deductions
- Incident history

### 7.9 Monitoring refresh behaviour

- Loads the fleet when Projects opens.
- Refreshes every fifteen minutes while Projects remains active.
- Supports manual refresh.
- Shows cached project connections when the API is unavailable.
- Never substitutes a fake healthy state for missing API data.

## 8. Monitoring Backend and Hardening

The companion Laravel Monitoring API is responsible for server-side collection and scheduling.

Current system responsibilities include:

- Public reachability checks
- Reporter heartbeat ingestion
- Snapshot storage
- Application-health storage
- Incident tracking
- SSL-expiry checks
- Vulnerability matching through Wordfence Intelligence data
- Finding status updates
- Reporter-token rotation
- Snapshot and alert retention/pruning
- Scheduler heartbeat monitoring through an external dead-man's switch

The macOS app remains a read-focused command console. It changes backend state only through explicit registration, settings, token-rotation, or finding-status actions.

### Laravel Cloud cost guard

- Settings explains that JARVIS will not invent estimated cloud costs.
- Laravel Cloud's native billing alert remains the authoritative spending threshold.
- JARVIS provides a direct link to Laravel Cloud.
- If Laravel Cloud introduces a documented billing API, live cost telemetry can be added later.

## 9. Intelligence Matrix

The Intelligence Matrix combines live external information with local operational data.

### 9.1 Persistent intelligence telemetry

The status rail shows:

- Priority signals
- Significant regional events
- Watchlist matches
- Overdue operations
- Loaded live sources

The five intelligence modes are:

- **Now**
- **Philippines**
- **Watchlist**
- **Operations**
- **Briefings**

### 9.2 Now

- Displays alerts ordered by severity and recency.
- Places the priority feed beside a stable situation brief.
- Shows primary-location weather.
- Shows critical and warning totals.
- Shows significant regional-event count.
- Shows overdue-operation count.
- Shows what changed since the previous successful refresh.
- Retains available results when an individual source fails.

### 9.3 Alert generation

Signals can be generated from:

- Thunderstorm weather codes
- Rain probability crossing the configured threshold
- Apparent temperature of 42°C or higher
- Earthquakes crossing the configured magnitude threshold
- Philippine headlines containing hazard terms such as typhoon, cyclone, flood, landslide, tsunami, volcanic activity, or earthquake

Severity levels:

- Information
- Advisory
- Warning
- Critical

Earthquakes at magnitude 6.0 or above are classified as critical. News-derived hazard signals are advisory until verified through an official authority.

### 9.4 Alert policy

- Earthquake threshold adjustable from magnitude 3.0 to 7.0.
- Rain threshold adjustable from 40% to 100%.
- Optional warning and critical notifications.
- Configurable quiet hours.
- Duplicate-notification suppression.
- Maximum of three new notifications per delivery cycle.

### 9.5 Saved locations

- Manila is created automatically when no location exists.
- Add Philippine location presets.
- Mark a location as primary.
- Remove saved locations.
- Display temperature, apparent temperature, condition, and weather icon.

Preset locations include Baguio, Manila, Legazpi, Puerto Princesa, Cebu, Iloilo, Tacloban, Davao, Cagayan de Oro, and Zamboanga.

### 9.6 Philippines

- Native MapKit view with 16 sampled Philippine forecast locations and seven selectable forecast layers.
- Seven days of hourly forecast navigation, next-24-hour detail, and seven daily summaries for a selected location.
- Sampled values are explicitly distinguished from continuous map tiles, radar, and official weather warnings.
- Displays representative conditions across Luzon, Visayas, and Mindanao.
- Includes temperature, condition, and precipitation probability.
- Lists recent Philippine-region earthquakes.
- Shows magnitude, location, and relative time.
- Links to the source event page.
- Displays Philippine news with source and publication time.

### 9.7 Watchlist and news management

- Accepts comma-separated watched subjects.
- Checks Philippine and world headlines.
- Uses whole-word matching for single terms.
- Uses phrase matching for multi-word terms.
- Deduplicates similar headlines.
- Tracks read and unread stories.
- Saves stories with bookmarks.
- Dismisses stories locally.
- Restores dismissed stories.
- Switches the complete feed between Philippines and World.

Default watchlist terms are AI, WordPress, technology, and business.

### 9.8 Operations intelligence

- Shows overdue-task count.
- Shows active-project count.
- Shows repository-connected project count.
- Lists overdue tasks with priority and due time.
- Shows project status, repository health, branch, progress, and overdue state.

### 9.9 Intelligence briefings

- Generates the current briefing from task, project, weather, and earthquake data.
- Presents the briefing in the floating panel.
- Records the latest refresh time.
- Compares alert, overdue-task, and news totals with the previous successful baseline.

### 9.10 Live providers

- **Open-Meteo** — current weather and precipitation probability
- **USGS** — Philippine-region earthquake feed
- **GMA News RSS** — Philippine headlines
- **BBC News RSS** — world headlines
- **NewsAPI.org** — optional news enrichment

Weather, earthquake, Philippine news, world news, and regional weather requests run concurrently. RSS remains the fallback when NewsAPI is unavailable or not configured.

### 9.11 Safety boundaries

- Open-Meteo is informational; PAGASA remains the official Philippine weather authority.
- USGS reports may be preliminary; significant local events should be confirmed with PHIVOLCS.
- Headline matching is an early signal, not an emergency instruction.
- Evacuation and safety decisions must be confirmed with the appropriate authorities.

## 10. JARVIS Voice

Text-to-speech uses macOS speech synthesis and runs locally.

Voice controls include:

- Enable or disable speech.
- Select from installed macOS voices.
- British English macOS default option.
- Adjust speaking rate.
- Adjust pitch.
- Adjust volume.
- Preview the selected voice.
- Stop current speech.
- Speak wake briefings automatically.
- Speak new critical intelligence alerts.
- Respect configurable overnight quiet hours.

The application does not contain or distribute the copyrighted cinematic JARVIS voice.

## 11. Briefing Panel

- Compact floating native macOS panel.
- Can appear above other workspaces and alongside full-screen applications.
- Displays complete briefing text without truncating it.
- Opens from Today, Intelligence, Settings, the menu bar, and wake events.
- Can be dismissed with its close action or Escape.
- Opening animation has been removed to keep startup immediate and restrained.

## 12. Startup, Login, Sleep, and Wake

### Launch at login

- Uses macOS `SMAppService`.
- Can be enabled or disabled in Settings.
- Explains when macOS requires manual Login Items approval.
- Opens the appropriate System Settings page when necessary.
- Launch occurs after macOS user login, not before the user session exists.

### Sleep and wake

- Observes macOS workspace sleep and wake notifications.
- Records sleep duration.
- Optionally presents a wake briefing.
- Supports minimum sleep thresholds of 5, 15, or 30 minutes, or 1 hour.
- Wake detection requires JARVIS to remain running.

## 13. Menu-Bar Command Centre

- Shows the current pending-task count.
- Adds a quick Inbox task.
- Opens the main dashboard window.
- Presents a briefing.
- Quits JARVIS.

## 14. Settings

### Startup

- Launch-at-login toggle.
- Login Items approval guidance.

### Wake briefing

- Enable or disable wake briefings.
- Select sleep-duration threshold.
- Preview the briefing panel.

### Voice

- All voice, rate, pitch, volume, alert-speech, and quiet-hour controls.

### Notifications

- Displays current macOS notification status.
- Requests notification permission.
- Supports task reminders and intelligence alerts.

### News API

- Securely saves a NewsAPI.org key.
- Reports whether a key exists.
- Removes the key.
- Continues with RSS feeds when no key is present.

### Monitoring API

- Configures the HTTPS API base URL.
- Stores the read token in Keychain.
- Tests authenticated access.
- Reports site, incident, and security-finding totals after a successful test.
- Replaces or removes the saved token.

### Data, backup, and restore

- Exports tasks, projects, saved locations, and an explicit allow-list of non-secret preferences to a versioned JSON backup.
- Shows new, updated, and skipped record counts before importing.
- Merges by stable identifiers without creating duplicates.
- Replaces all local records only after the user types `REPLACE` and JARVIS creates a safety backup.
- Rejects malformed files and backups from a newer schema without changing local data.
- Creates an automatic snapshot when due and checks again every six hours while the app remains open.
- Creates a raw store backup before opening a newly versioned SwiftData schema.
- Uses Application Support by default or a user-chosen backup folder.
- Retains the newest configured number of snapshots; the default is 14.
- Shows the last backup time and provides Back Up Now, Choose Folder, Reveal in Finder, and guided Restore controls.
- Explains that Keychain credentials are excluded and must be entered again on a new Mac.

### Cost guard and privacy

- Links to Laravel Cloud billing controls.
- Refuses to fabricate unavailable spend information.
- Explains which data is local and which services receive requests.

## 15. Local Storage and Credential Security

### SwiftData

Stored locally:

- Tasks
- Projects
- Saved weather locations
- A formal versioned schema and migration plan protect future model changes.

### Application preferences

Stored locally in preferences:

- Selected views and filters
- Archive visibility
- Watchlist terms
- Alert thresholds
- Quiet hours
- Read, saved, and dismissed story identifiers
- Intelligence comparison baseline
- Wake-briefing settings
- Voice settings
- Monitoring API base URL

### macOS Keychain

Stored securely:

- NewsAPI.org key
- Monitoring read token
- Monitoring site-registration/admin token
- Per-project reporter tokens

### Versioned backups

- Backup schema version, application version, and export timestamp
- Every persisted task and project field, including task-to-project identifiers
- Saved locations and non-secret preferences
- Repository bookmarks for same-Mac recovery; macOS may require repository access to be granted again on another Mac
- No NewsAPI key, monitoring token, site-registration token, or reporter token
- Automatic rotation to the configured retention count

### External request boundaries

- Location coordinates are sent to Open-Meteo.
- Public earthquake data is requested from USGS.
- Public news is requested from configured providers.
- NewsAPI category requests occur only when a key is configured.
- Git inspection remains entirely local.
- Monitoring requests go only to the configured HTTPS API endpoint.

## 16. Native macOS Experience

- SwiftUI interface.
- SwiftData persistence.
- AppKit floating panels and workspace event monitoring.
- Native sidebar, forms, menus, links, alerts, search, and keyboard shortcuts.
- Dark command-centre visual system.
- Letter-free JARVIS HUD application icon.
- Minimum main-window size of 900 × 600.
- Default main-window size of approximately 1180 × 760.
- Reduced-motion support for animated monitoring gauges.
- Universal Intel and Apple Silicon release build.

## 17. Technical Foundation

- Swift 5
- SwiftUI
- SwiftData
- AppKit
- URLSession and Swift concurrency
- UserNotifications
- AVFoundation/macOS speech synthesis
- ServiceManagement
- Security framework and macOS Keychain
- Local `/usr/bin/git` inspection
- XcodeGen project generation
- Unit tests using Swift Testing

Current automated coverage includes:

- Briefing composition
- Task queue ordering and filtering
- Project persistence and status behaviour
- Git parsing and repository-health evaluation
- Weather-code mapping
- RSS and NewsAPI parsing
- Intelligence alert generation
- Watchlist deduplication and matching
- Quiet-hour logic
- Monitoring request construction and response parsing
- Monitoring-health scoring
- Speech settings logic
- Backup round trips, secret exclusion, validation, idempotent merge, replace safeguards, rotation, and migration from the 0.1.18 unversioned store

## 18. Product Boundaries

The current release intentionally does not provide:

- Cross-device sync
- An iPhone application
- Apple Reminders import
- Calendar integration
- Email or messaging integration
- Automatic Git commits, pulls, pushes, or deployments
- Automatic website code installation
- Direct cloud-billing telemetry without a documented provider API
- Official emergency-alert authority
- An external generative-AI command backend

The planned iOS application can reuse the Laravel Monitoring API later, but it is not part of the current macOS release.

## 19. Installation and Release Artifact

Current distributable archive:

`dist/JARVIS-Dashboard-0.2.3.zip`

Installed application location:

`/Applications/JARVIS Dashboard.app`

The release is built as a universal macOS application for Apple Silicon and Intel Macs.
