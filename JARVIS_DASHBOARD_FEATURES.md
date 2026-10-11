# JARVIS Dashboard — Complete Feature Reference

**Current version:** 0.2.5

**Platform:** macOS 14 Sonoma or newer  
**Application type:** Native, local-first macOS productivity and intelligence dashboard

## Overview

JARVIS Dashboard is a single command centre for personal tasks, client projects, operational health, weather, Philippine earthquake activity, news, alerts, and briefings. It is designed to remain useful without a cloud account: personal records and preferences live on the Mac, while only live intelligence requests are sent to their respective providers.

The application has five main sections:

1. **Today**
2. **Tasks**
3. **Projects**
4. **Intelligence**
5. **Settings**

It also includes a menu-bar command centre, launch-at-login support, sleep/wake monitoring, local notifications, local text-to-speech, and floating briefing panels.

---

## 1. Today — Command Centre

The Today screen is a fixed-hierarchy command centre rather than a collection of unrelated widgets. It keeps the briefing and active work dominant, with weather, regional intelligence, monitoring health, and momentum in a consistent secondary rail.

### Command interface

- Opens **Ask JARVIS** from the Today header or with Command-K.
- Processes commands locally; command text is not sent to an external AI provider.
- Presents the current briefing and can speak it through the configured macOS voice.
- Opens Tasks, Projects, Intelligence, weather/news signals, and Settings from plain-language commands.
- Answers task-count and project/website-health requests using current dashboard data.
- Identifies attention items, the next actionable task, blocked tasks, and projects waiting on clients.
- Reports observed weather and refuses to label sites healthy when monitoring checks are unavailable.
- Answers named-project questions in a sourced response card with status, site check, task counts, next action, and a **View project** action.
- Provides explicit capability guidance for commands that are not yet supported.

### Daily briefing

- Generates a plain-language briefing from current dashboard data.
- Includes pending and overdue task counts.
- Includes active project count.
- Includes the primary saved location's current weather when available.
- Includes the count of significant Philippine-region earthquakes.
- Can be opened in a floating **Present** panel.
- Displays a source-refresh warning while retaining any results that loaded successfully.

### Operational status rail

- Pending tasks
- Overdue tasks
- Active operations
- Healthy monitored sites
- Significant regional alerts

### Next actions

- Displays up to five pending tasks.
- Shows due dates and highlights overdue work.
- Allows tasks to be completed directly from the dashboard.
- Shows a clear empty state when the queue is complete.

### Live intelligence summary

- Displays current weather for the primary saved location.
- Displays the latest Philippine-region earthquake report.
- Supports manual and pull-to-refresh updates.

### Active operations, daily resolve, and momentum

- Displays one locally curated philosophical quote each day, focused on discipline, endurance, and purposeful action.
- Allows another quote to be shown without refreshing live data.
- Keeps quotes local so the Today screen does not depend on another network service.
- Ranks ongoing operations by site health, status, priority, and recent activity.
- Shows each operation's next action, open task count, and monitoring state without decorative gauges.
- Uses green for healthy states and reserves orange/red for actionable conditions.
- Shows overall task completion, tasks due today, and blocked-task count in **Momentum**.

---

## 2. Tasks

The Tasks section is an operational mission queue rather than a passive checklist.

### Mission control layout

- Surfaces the highest-priority actionable task as **Priority now**.
- Shows live counts for open, due-today, overdue, blocked, and completed work.
- Filters the queue by operational state and individual project.
- Searches task titles, notes, blocking reasons, and linked project names.
- Displays completion momentum without allowing completed work to dominate the active queue.
- Uses restrained urgency colours so overdue and blocked work is immediately visible.

### Task creation

- Create a task with a title.
- Add multi-line notes.
- Assign one of four priorities:
  - Low
  - Normal
  - High
  - Critical
- Add an optional due date and time.
- Schedule a local reminder for a task that has a due date, subject to macOS notification permission.

### Task management

- Mark tasks complete or pending.
- Search task titles and notes.
- Display task priority and due date.
- Highlight overdue, incomplete tasks.
- Delete tasks from the list.
- Persist task data locally with SwiftData.
- Assign a task to an individual project or leave it in the global inbox.
- Mark a task blocked and record the blocking reason.

### Menu-bar quick tasks

- Create a basic task without opening the main dashboard window.
- See the current pending-task count from the menu-bar panel.

---

## 3. Projects

The Projects section manages both defined-scope work and long-term client relationships.

### Project records

Each project can store:

- Project name
- Client
- Project type
- Description and context
- Status
- Priority
- Project mode
- Start date
- Due date
- Tags
- Next action
- Progress value for fixed projects
- Optional local Git repository connection for ongoing clients
- Optional monitored website URL, platform, backend site ID, and connection date

### Project statuses

- Not Started
- Active
- In Review
- On Hold
- Waiting on Client, including the number of days waiting
- Completed
- Archived

### Project priorities

- Low
- Medium
- High
- Urgent

### Fixed Project mode

- Intended for work with a defined finish.
- Displays stored completion progress.
- Displays due-date state, including **Due Soon** and **Overdue** warnings.
- Calculates completion progress from linked tasks when a project has tasks.
- Retains manual progress only for projects that do not yet have linked tasks.

### Ongoing Client mode

- Replaces potentially misleading lifetime completion percentages with operational health.
- Can connect to a local Git repository selected explicitly by the user.
- Reads repository metadata without changing repository files.
- Displays:
  - Current branch
  - Changed-file count
  - Latest commit hash and message
  - Time since the latest commit
  - Commit count during the last 30 days
  - Ahead/behind state when upstream tracking information is available
- Supports repository refresh, replacement, and disconnection.

### Repository health states

- **Healthy** — latest commit was within the last 7 days.
- **Quiet** — latest commit was 8–14 days ago.
- **Needs Attention** — the project is overdue or its latest commit is more than 14 days old.
- **Blocked** — the project is On Hold.
- **Setup Needed** — no readable repository activity is available.

Repository checks run with Git optional locks and terminal prompts disabled. JARVIS does not automatically scan folders and does not commit, pull, push, or modify a connected client repository.

### Website monitoring settings

- Lives inside each project's detail/settings view.
- Registers a new HTTPS website with the JARVIS Monitoring API.
- Accepts plain HTTPS URLs and Markdown-formatted links copied from chat or documentation.
- Attaches an already registered website through the saved read-only API connection instead of creating a duplicate.
- Supports Generic, WordPress, Laravel, Node, Static, and Custom platforms.
- Uses a separate site-registration credential with admin scope.
- Can remember that registration credential in macOS Keychain for future projects.
- Stores each returned reporter token separately in Keychain under the local project ID.
- Provides a copy action for transferring the reporter token into the website host's secret manager.
- Allows an existing monitored website's URL and platform to be corrected through project Connection Settings.
- Updates the same backend site record so its Site ID, reporter token, snapshots, incidents, and history remain intact.
- Registers the site only; it never installs reporter code or changes hosting settings without explicit approval.

### Site health and Security & Maintenance

- Fetches the monitoring fleet on entry, every 15 minutes while Projects remains active, and on manual refresh.
- Shows fleet totals and working **Needs attention** and **Sort: Site health** controls.
- Adds a semicircular site-health gauge to every project card without replacing delivery progress or repository health.
- Scores only when the backend has completed an outside reachability check; unknown, stale, offline, maintenance and disconnected states remain explicit and never masquerade as healthy.
- Uses the specified 100-point deductions for vulnerabilities, updates, unsupported PHP, expiring SSL, missing heartbeats and failed application health checks.
- Opens a dedicated **Security & Maintenance** project section containing:
  - Open vulnerabilities and reference links
  - Component updates and uncovered inventory
  - Reporter application/database/scheduler health checks
  - Environment, response, uptime, SSL and heartbeat data
  - Explainable score deductions
  - Incident history
- Animates the gauge needle unless Reduce Motion is enabled.
- Keeps health collection read-only: the Mac app reads the backend and does not contact or alter client sites. Explicit registration and settings changes update only the JARVIS Monitoring API record.

### Project actions

- Create and edit projects.
- Open a full project detail view.
- Change status directly from a project card.
- Duplicate a project.
- Archive or restore a project.
- Show or hide archived projects.
- Delete a project after confirmation.
- Automatically save detail changes locally.
- Connect a website to monitoring from its individual project settings.
- Correct a connected website's URL without creating a duplicate monitoring identity.

---

## 4. Intelligence

The Intelligence centre combines live external information with local tasks and projects. It contains five pages: **Now**, **Philippines**, **Watchlist**, **Operations**, and **Briefings**.

### Intelligence matrix layout

- Presents a persistent status rail for priority signals, regional events, watchlist matches, overdue operations, and loaded sources.
- Uses a dedicated navigation strip for **Now**, **Philippines**, **Watchlist**, **Operations**, and **Briefings**.
- Places the priority signal feed beside a compact situation brief instead of mixing every source into one card grid.
- Shows critical and warning counts, primary-location weather, change detection, and alert thresholds in one stable analysis column.
- Keeps live refresh prominent while retaining available results when individual providers fail.

### 4.1 Now

#### Priority alerts

JARVIS analyses current feeds and orders signals by severity and recency.

Alert sources and conditions include:

- Thunderstorms at saved locations
- Rain probability crossing the configured threshold
- Apparent temperature of 42°C or higher
- Philippine-region earthquakes crossing the configured magnitude threshold
- Philippine news headlines containing hazard subjects such as typhoons, tropical cyclones, storm signals, floods, landslides, tsunamis, volcanic activity, or earthquakes

Alert severity levels are:

- Information
- Advisory
- Warning
- Critical

Earthquakes of magnitude 6.0 or above are treated as critical signals. News-based hazard signals are advisories and must be verified against official bulletins.

#### Alert policy

- Adjustable earthquake threshold from magnitude 3.0 to 7.0.
- Adjustable rain-probability threshold from 40% to 100%.
- Optional notifications for new warning and critical signals.
- Configurable quiet-hour start and end times.
- Duplicate notification suppression using previously delivered alert identifiers.
- A maximum of three new alerts is delivered per notification cycle.

#### Saved locations

- Manila is created automatically when no saved location exists.
- Add locations from Philippine presets.
- Mark any saved location as primary.
- Remove saved locations.
- Display current temperature, apparent temperature, conditions, and weather icon.

Available presets currently include:

- Baguio
- Manila
- Legazpi
- Puerto Princesa
- Cebu
- Iloilo
- Tacloban
- Davao
- Cagayan de Oro
- Zamboanga

### 4.2 Philippines

#### Weather map

- Native interactive map centred on the Philippines with 16 representative forecast locations.
- Compact, selectable point beacons use weather glyphs and rain-probability rings. Each label travels with its beacon while panning and zooming; a tested placer chooses its side and hides crowded labels.
- The camera fits all 16 locations, a Reset view control restores that framing, and the map expands to use available window width.
- Selected-location detail, wettest-location list, forecast provenance, and a rain-ring legend make the point-based data easier to interpret.
- Seven selectable detail metrics: temperature, rain chance, rainfall, wind, cloud cover, humidity, and sea-level pressure. The beacon ring always represents rain chance.
- Hourly timeline across seven forecast days, with location details, the next 24 hours, and daily summaries.
- Forecast samples are not continuous raster overlays or live radar. Open-Meteo is credited; PAGASA remains the authority for official warnings.

#### Situation overview

- Shows representative current conditions across Luzon, Visayas, and Mindanao.
- Covers Baguio, Manila, Legazpi, Cebu, Iloilo, Davao, Cagayan de Oro, and Zamboanga.
- Displays temperature, condition, and precipitation probability.

#### Earthquake activity

- Displays Philippine-region events reported during the USGS all-day feed window.
- Shows magnitude, location, and relative occurrence time.
- Highlights events that cross the user's threshold.
- Links to the source detail page when available.
- Displays up to 15 recent events.

#### Philippine news

- Loads Philippine headlines from the configured feed.
- Displays source and publication time when available.
- Opens the original article.
- Supports read/unread, save, dismiss, and restore-dismissed controls.

### 4.3 Watchlist

- Accepts a comma-separated list of watched subjects.
- Checks both Philippine and world headlines.
- Uses whole-word matching for a single term such as `AI` to reduce false positives.
- Uses phrase matching for multi-word subjects.
- Deduplicates similar headlines.
- Provides separate lists for watchlist matches and saved stories.
- Allows switching the complete news list between **Philippines** and **World**.
- Tracks read, saved, and dismissed state locally.

The initial watchlist is:

- AI
- WordPress
- technology
- business

### 4.4 Operations

- Shows counts for overdue tasks, active projects, and repository-connected projects.
- Lists up to ten overdue tasks with priority and due time.
- Monitors active project status.
- Shows repository health and branch information for ongoing clients.
- Shows completion progress for fixed projects.
- Highlights overdue project dates.

### 4.5 Briefings

- Generates a current briefing from task, project, weather, and earthquake data.
- Opens the briefing in a floating presentation panel.
- Records the time of the latest refresh.
- Compares the current successful refresh with the previous baseline.
- Reports changes in:
  - Priority alert count
  - Overdue task count
  - News-story count
- Displays totals for priority alerts, watchlist matches, and saved stories.

### Intelligence refresh behaviour

- Weather, regional weather, earthquake, Philippine news, and world news requests run concurrently.
- Successful sources update even if another source fails.
- RSS news is the core fallback and does not require an API key.
- When a NewsAPI.org key exists, NewsAPI enrichment runs separately after the core refresh so Keychain access does not block the interface.
- The interface retains available results and reports partial refresh failures.

---

## 5. News and Information Providers

### Default providers

- **Open-Meteo** — current temperature, apparent temperature, condition codes, and precipitation probability.
- **USGS** — recent earthquake feed filtered to latitude 4–22 and longitude 115–130 for the Philippine region.
- **GMA News RSS** — default Philippine breaking-news feed.
- **BBC News RSS** — default world-news feed.

### Optional NewsAPI.org integration

- A NewsAPI.org key can be pasted in Settings.
- The key is stored in macOS Keychain rather than the application database.
- The key can be removed at any time.
- RSS feeds remain available when no key is stored or NewsAPI enrichment is unavailable.

### Safety and source boundaries

- Open-Meteo data is informational; PAGASA remains the authority for official Philippine weather warnings.
- USGS data may be preliminary; significant Philippine events should be confirmed with PHIVOLCS.
- News-based hazard detection is a headline signal, not an official disaster instruction.
- Evacuation, safety, and emergency decisions should be confirmed with PAGASA, PHIVOLCS, and relevant local authorities.

---

## 6. Briefing System

- Displays briefings in a compact floating macOS panel.
- The panel can appear over other workspaces and alongside full-screen applications.
- Supports manual briefings from Today, Intelligence, Settings, and the menu bar.
- Supports automatic wake briefings when the configured sleep-duration threshold is met.
- Uses a specific wake message when no detailed dashboard briefing is supplied.
- Can be dismissed with the button or Escape keyboard action.

---

## 7. Startup and Wake Behaviour

### Launch at login

- Optional **Launch JARVIS when I log in** setting using macOS `SMAppService`.
- If macOS requires approval, JARVIS explains the requirement and can open the Login Items settings page.
- This covers logging in after startup; macOS launches the application after the user session begins.

### Sleep and wake

- Monitors macOS sleep and wake events while JARVIS is running.
- Records how long the Mac was asleep.
- Optionally presents a wake briefing after the configured minimum sleep duration.
- Available thresholds are 5 minutes, 15 minutes, 30 minutes, and 1 hour.
- Wake briefings can be disabled.

---

## 8. Menu-Bar Command Centre

JARVIS remains accessible from the macOS menu bar.

- Shows the pending-task count.
- Adds a quick task.
- Opens the main Command Centre window.
- Presents a briefing.
- Quits JARVIS.

---

## 9. Settings and Permissions

### Startup

- Enable or disable launch at login.
- Open macOS Login Items settings when manual approval is required.

### Wake briefing

- Enable or disable wake briefings.
- Select the minimum sleep duration.
- Preview the briefing panel.

### Notifications

- Display the current macOS notification-authorisation state.
- Request notification permission.
- Task reminders and Intelligence alerts respect macOS notification permission.

### News API

- Securely save a NewsAPI.org key.
- Report whether a key is stored.
- Remove the stored key.
- Continue with RSS fallback feeds without a key.

### Monitoring API

- Configure the Laravel Cloud API base URL.
- Store the bearer token in macOS Keychain.
- Test authenticated access against the live monitoring summary.
- Report site, incident, and security-finding totals on a successful test.
- Remove or replace the stored token.

### Data and privacy notice

- Exports and restores a versioned JSON backup of tasks, projects, saved locations, and non-secret preferences.
- Previews new, updated, and skipped records before Merge or confirmed Replace.
- Creates daily and pre-migration backups, retains the configured number, and supports a user-chosen folder.
- Explains that tasks and projects are stored locally.
- Explains that NewsAPI.org and monitoring API credentials are stored in Keychain and excluded from every backup.
- Notes that live services receive only the information required for their requests.

---

## 10. Data Storage and Privacy

### Stored locally with SwiftData

- Tasks
- Projects
- Saved weather locations

### Stored in application preferences

- Interface selections
- Project archive visibility
- Watchlist terms
- Alert thresholds
- Quiet hours
- Read, saved, and dismissed news identifiers
- Intelligence comparison baselines
- Wake briefing preferences
- Monitoring API base URL

### Stored in macOS Keychain

- NewsAPI.org API key
- Laravel monitoring API read token
- Laravel monitoring API site-registration token
- Dedicated reporter tokens stored separately per connected project

### External requests

- Saved-location coordinates are sent to Open-Meteo for weather requests.
- Public earthquake data is requested from USGS.
- Public news feeds are requested from GMA News and BBC News.
- NewsAPI.org receives category requests only when an API key is configured.
- Connected Git repositories are inspected locally.
- The configured Laravel monitoring API receives an authenticated summary request when the connection is tested.

---

## 11. Visual Identity and Native Experience

- Native SwiftUI interface designed for macOS.
- Letter-free JARVIS HUD application icon.
- Dark command-centre visual system with stable screen hierarchies.
- Responsive native layouts for varying window widths.
- Native materials, panels, forms, menus, search, links, and keyboard shortcuts.
- Minimum main-window size of 900 × 600 and default size of 1180 × 760.
- Dedicated menu-bar extra.

---

## 12. Technical Foundation

- SwiftUI for the interface.
- SwiftData for local task, project, and location persistence.
- AppKit for the floating briefing panel and workspace events.
- AVFoundation and macOS speech synthesis for local text-to-speech.
- URLSession with Swift concurrency for live providers.
- UserNotifications for reminders and Intelligence alerts.
- ServiceManagement for launch-at-login registration.
- Security framework/Keychain for NewsAPI.org and monitoring API credentials.
- Local `/usr/bin/git` commands for read-only repository inspection.
- XcodeGen configuration for generating the Xcode project.
- Unit coverage for briefing composition, task prioritisation, weather mapping, news parsing, NewsAPI parsing, project behaviour, Git health, monitoring health, Intelligence rules, and speech preferences.

---

## 13. Current Product Boundaries

The following distinctions are important when interpreting the dashboard:

- Tasks may remain global or be linked to a project. Fixed-project progress uses linked task completion when available.
- Ongoing-client health describes recent operational activity, not percentage completion.
- Repository intelligence reads local Git metadata only; it does not inspect GitHub issues, pull requests, CI, deployments, or client communications.
- Launch at login occurs after macOS login, not before a user session exists.
- Wake detection works while JARVIS remains running.
- Weather, earthquake, and news features require an internet connection for fresh data.
- There is currently no cross-device sync, Apple Reminders import, Calendar integration, or cloud account.
- Alerts are decision-support signals and do not replace official emergency advisories.

---

## 14. Installation Artifact

The current distributable build is:

`dist/JARVIS-Dashboard-0.2.5.zip`

The installed application is expected at:

`/Applications/JARVIS Dashboard.app`
