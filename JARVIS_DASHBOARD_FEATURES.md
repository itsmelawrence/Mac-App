# JARVIS Dashboard — Complete Feature Reference

**Current version:** 0.2.29

**Platform:** macOS 14 Sonoma or newer  
**Application type:** Native, local-first macOS productivity and intelligence dashboard

## Overview

JARVIS Dashboard is a single command centre for:
- personal tasks and client projects;
- operational and website health;
- weather, Philippine earthquake activity, news, alerts, and briefings;
- the Obsidian Projects vault that its agent workflows use.

It is designed to remain useful without a cloud account. Personal records and preferences live on the Mac, and only live intelligence requests go to their providers.

The application has six main sections:

1. **Today**
2. **Tasks**
3. **Projects**
4. **Cortex**, the Projects vault, source trees, and Graphify maps
5. **Intelligence**
6. **Settings**

It also includes:
- a menu-bar command centre;
- launch-at-login support and sleep/wake monitoring;
- local notifications, local text-to-speech, and floating briefing panels;
- background vault upkeep that keeps working while the dashboard window is closed.

---

## 1. Today — Command Centre

The Today screen is a fixed-hierarchy command centre rather than a collection of unrelated widgets. It keeps the briefing and active work dominant, with weather, regional intelligence, website-check status, and momentum in a consistent secondary rail.

### Command interface

- Opens **Ask JARVIS** from the Today header or with Command-K.
- Processes commands locally; command text is not sent to an external AI provider.
- Presents the current briefing and can speak it through the configured macOS voice.
- Opens Tasks, Projects, Intelligence, weather/news signals, and Settings from plain-language commands.
- Answers task-count and project/website-health requests using current dashboard data.
- Identifies attention items, the next actionable task, blocked tasks, and projects waiting on clients.
- Reports observed weather, says "All N monitored websites are up" only when site checks have completed, and otherwise says checks have not completed yet.
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
- Monitored sites that are up
- Significant regional alerts

### System status

- Shows **Site checks: Every 5 min**, or **Paused · offline** while the Mac has no connection.
- Shows the number of monitored sites, how many are up, how many need attention, and when sites were last checked.

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
- Shows it as a highlighted "Daily resolve" banner under the greeting, with buttons to read it aloud, copy it, or show another quote without refreshing live data.
- Keeps quotes local so the Today screen does not depend on another network service.
- Ranks ongoing operations by website status, project status, priority, and recent activity.
- Shows each operation's next action, open task count, and website status.
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

- Mark tasks complete or pending. Completing a task cancels its due-date reminder; reopening it reschedules one if the due date is still ahead.
- Search task titles and notes.
- Display task priority and due date.
- Highlight overdue, incomplete tasks.
- Delete tasks from the list. Deleting a task also cancels its pending reminder.
- Persist task data locally with SwiftData.
- Assign a task to an individual project or leave it in the global inbox.
- Mark a task blocked and record the blocking reason.

### Menu-bar quick tasks

- Create a basic task without opening the main dashboard window.
- See the current pending-task count from the menu-bar panel.

---

## 3. Projects

The Projects section manages both defined-scope work and long-term client relationships.

### Operations layout

- **Operations** header with a subtitle, an attention capsule, and a **New Project** button.
- Status rail: Active, Waiting on client, Due within 7 days, Sites up (x/y), Down, and average 30-day uptime with the last check time.
- Filter chips with counts: Active, Needs attention, Waiting on client, Completed, Archived. A project needs attention when its site is Down or Slow, it is waiting on the client, its due date has passed, or it has overdue tasks.
- Sort menu: Needs attention first, Recently updated, Due date, Name. The choice is remembered.
- A **Check all sites** button and search across name, client, type, website, and tags.
- Each project is a full-width card showing:
  - site status icon, name, and client;
  - next action;
  - chips for status, priority, due date, task progress, overdue tasks, days waiting, and Ongoing;
  - a progress bar for fixed projects;
  - site status, host, and 30-day uptime on the right;
  - an **Edit** button and a **⋯** menu (open, edit, status, check site now, open website, duplicate, archive/restore, delete).
- A single click opens the project. A priority accent marks the left edge, and the card has a red border when its site is down.

### Project detail

- **Back to Operations**, inline name and client editing, and Status, Priority, and Mode pickers.
- Metrics rail: Progress and Tasks done for fixed projects, or Repository health and Commits for ongoing clients; Deadline; Website; 30-day uptime.
- Main column:
  - **Website** panel: status, link, **Check Now**, last check, HTTP status, response time, uptime, a 30-day bar strip, and recent outages;
  - **Tasks**: up to 10 linked tasks, each opening its editor on click, then a link to Tasks;
  - **Local repository** (ongoing clients only);
  - **Description**.
- Side column: **Next action** and **Details** (type, mode, dates, tags, created and updated times).

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
- Optional website address for up/down checks

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

### Website checks

- Free, local up/down checks run from the Mac; no hosted service or account is involved.
- The website address is entered in the project editor's **Website** field or in the project detail **Website** panel, which also offers **Change Address** and **Stop Checking**.
- Addresses are normalised, so `example.com` becomes `https://example.com/`.
- Every 5 minutes, and about 20 seconds after wake, JARVIS sends a plain GET request to each non-archived project's website. Checks keep running while the dashboard window is closed.
- Results:
  - 2xx or 3xx is up; 401, 403, and 429 also count as up because the server answered.
  - A response slower than 3000 ms is **Slow**.
  - Any other status, a timeout, a DNS failure, or an SSL error is a failed check.
- One failed check shows **Retrying** and checks again after 60 seconds. Two failures in a row mark the site **Down**, with the outage starting at the first failure.
- States: Up, Slow, Retrying, Down, Checking…, and No website. A site needs attention when it is Down or Slow.
- When the Mac is offline, every check is discarded and checks are shown as paused; an offline Mac is never reported as a site failure.
- History is kept in `~/Library/Application Support/JARVIS Dashboard/site-checks.json`: the last 50 checks, 30 daily tallies for 30-day uptime, and the last 20 outages.
- Sends a notification when a site goes down or recovers, controlled in Settings › **Website checks**.
- Checks only read the public site; JARVIS does not change client sites or hosting.

### Project actions

- Create and edit projects.
- Open a full project detail view.
- Change status directly from a project card.
- Duplicate a project.
- Archive or restore a project.
- View archived projects through the **Archived** filter.
- Delete a project after confirmation.
  - Its tasks move to the global inbox rather than being deleted or left pointing at the missing project, so backups stay restorable.
  - A failed delete is reported instead of silently ignored.
- Automatically save detail changes locally.
- Add, change, or stop checking a project's website, and check it on demand.

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
  - Weather alerts (storm, rain, heat) are identified per location per day. A new storm tomorrow alerts again, but a reading that drifts during the day does not re-alert.
  - The last 500 delivered and spoken alert identifiers are remembered, oldest forgotten first.
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
- **Basemap picker:**
  - **Apple Maps** is the default.
  - **MapTiler preview** shows a Landscape basemap.
  - **Satellite** shows MapTiler ground imagery with NOAA/NESDIS infrared cloud tiles.
  - MapTiler modes need a MapTiler API key stored in Keychain, and the key is sent in map requests. Native animated beacons stay above either basemap, and forecast points that arrive after the map loads are added.
- **Satellite mode:**
  - Clouds show the latest available observation, independent of the forecast-hour slider (the tile service gives no observation time).
  - Ordinary weather overlays are hidden.
  - Animated thunderstorm icons appear only at the 16 sampled locations where the selected hour reports a storm.
  - This is not live radar, lightning detection, or storm coverage.
- **Personal weather dashboard:** switchable from the map. It shows a primary-location hero forecast, four independently chosen city cards, city search through Apple Maps, and an opt-in "Use Mac location". The Mac location is kept in memory for the session only and is not saved.
- Eight condition-specific native weather animations appear across the map, hero forecast, hourly strip, and city cards. With Reduce Motion, a still icon is shown instead.
- If one saved location's weather request fails, the others still update. Missing hourly precipitation values are treated as 0% rather than failing the forecast.

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

- Generates a current briefing from task, project, website, weather, and earthquake data, naming any site that is down or slow.
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

## 5. Cortex, Vault, and Agent Handoff

JARVIS connects to a local Obsidian **Projects vault** (default `~/Documents/Main/Projects`, chosen in Settings → ICM · Obsidian vault). The vault is shared with agent tools such as Codex and Claude Code. Everything is read and written locally; no AI service is called.

### Ask JARVIS work handoff

- A work request such as "Update the JARVIS UI" is matched to a project through `ICM/routes.json`, using fixed rules.
- JARVIS checks the project's context note, suggests a few Graphify notes, and prepares a short handoff to copy into Codex or Claude.
- Every submitted console prompt is saved under `Memory/01_intake/`; unmatched prompts go to `_unrouted/`.
- Matched requests also create a dated activity note under `Notes/Projects/<project path>/Activities/` for the agent to complete.

### Cortex

- **Overview:** lists every project in the vault's `Work/` and `Personal/` folders, combining ICM routes with automatically discovered projects. Discovery rules come from `ICM/discovery.json`, shared with the vault's `.tools/project_hubs.py`; built-in defaults are used if the file is missing or malformed.
- **Refresh and responsiveness:** the scan refreshes on open and every 30 seconds while the overview is visible, and runs in the background so a large vault doesn't freeze the app. Each scan's project list is written to `ICM/cortex-projects.json` (only when it changes) for the vault doctor's comparison.
- **Route problems:** a route with a missing folder or unsafe path appears under **ICM routes need attention**; the other projects still show.
- **Vault health card:** shows the latest report from the vault doctor (`ICM/health.json`), with error and warning counts, the top issues, and **Open report**. It warns when the report is more than a day old.
- **Per project:** browse the source tree (generated, dependency, and hidden folders omitted), search paths, and open the project's context note and Graphify connection notes.

### Synapse Map

- Embeds Graphify's own generated `graph.html` viewer, with its search, node inspector, community filters, and force-directed layout. JARVIS adds travelling signal pulses.
- Selecting a source file focuses its node. The viewer is prepared in the background and reloads automatically when `graph.html` is regenerated.
- Maps are regenerated with the vault's `.tools/graphify_refresh.py <route>`, which validates before installing.

### Background vault upkeep

These run for the app's whole lifetime, with or without the dashboard window, as child processes of JARVIS so they share its vault access (macOS doesn't let launchd jobs list `~/Documents`).

- **Vault maintenance:** every 3 hours from launch, `.tools/vault_maintenance.py` refreshes project hubs and runs the vault doctor. It logs to `~/Library/Logs/vault-maintenance.log`.
- **Prompt capture filing:** every 15 seconds, and only when prompts are queued, JARVIS files prompts captured by the Codex and Claude Code hooks into the vault, one activity note per agent session. While JARVIS is closed, prompts wait in the queue.
- Each run has a time limit, so a stuck script cannot block later runs.

---

## 6. News and Information Providers

### Default providers

- **Open-Meteo** — current temperature, apparent temperature, condition codes, and precipitation probability.
- **USGS** — recent earthquake feed filtered to latitude 4–22 and longitude 115–130 for the Philippine region.
- **GMA News** — default Philippine breaking news. The feed address currently serves an HTML list, which JARVIS reads through its HTML fallback.
- **BBC News RSS** — default world-news feed. RSS titles and links in CDATA are read as-is; bare `&` characters are repaired only outside CDATA.

### Optional NewsAPI.org integration

- A NewsAPI.org key can be pasted in Settings.
- The key is stored in macOS Keychain rather than the application database.
- The key can be removed at any time.
- Philippines requests use `country=ph`. World requests use `category=general&language=en`, because NewsAPI needs at least one filter.
- NewsAPI failures, such as an invalid key, used-up quota, or bad request, appear on the Intelligence screen with NewsAPI's own message.
- An article with a missing title or link, or marked `[Removed]`, is skipped rather than failing the whole response.
- RSS feeds remain available when no key is stored or NewsAPI enrichment is unavailable.

### Safety and source boundaries

- Open-Meteo data is informational; PAGASA remains the authority for official Philippine weather warnings.
- USGS data may be preliminary; significant Philippine events should be confirmed with PHIVOLCS.
- News-based hazard detection is a headline signal, not an official disaster instruction.
- Evacuation, safety, and emergency decisions should be confirmed with PAGASA, PHIVOLCS, and relevant local authorities.

---

## 7. Briefing System

- Displays briefings in a compact floating macOS panel.
- The panel can appear over other workspaces and alongside full-screen applications.
- Supports manual briefings from Today, Intelligence, Settings, and the menu bar.
- Supports automatic wake briefings when the configured sleep-duration threshold is met.
- Uses a specific wake message when no detailed dashboard briefing is supplied.
- Can be dismissed with the button or Escape keyboard action. Closing the panel by any route, including its title-bar close button, also stops speech.
- Briefing requests are handled for the app's whole lifetime, not by the dashboard window. "Present Briefing" from the menu bar and wake briefings work with the window closed, and each request is shown once even with two dashboard windows open.

---

## 8. Startup and Wake Behaviour

### Launch at login

- Optional **Launch JARVIS when I log in** setting using macOS `SMAppService`.
- If macOS requires approval, JARVIS explains the requirement and can open the Login Items settings page.
- This covers logging in after startup; macOS launches the application after the user session begins.

### Sleep and wake

- Monitors macOS sleep and wake events while JARVIS is running, including when it runs only from the menu bar with the dashboard window closed.
- Records how long the Mac was asleep.
- Optionally presents a wake briefing after the configured minimum sleep duration.
- Available thresholds are 5 minutes, 15 minutes, 30 minutes, and 1 hour.
- Wake briefings can be disabled.

---

## 9. Menu-Bar Command Centre

JARVIS remains accessible from the macOS menu bar.

- Shows the pending-task count.
- Adds a quick task.
- Opens the main Command Centre window.
- Presents a briefing.
- Quits JARVIS.

---

## 10. Settings and Permissions

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

### Philippines map · MapTiler preview

- Save or remove a MapTiler API key (stored in Keychain). Without a key, Apple Maps remains available.
- The MapTiler and Satellite basemaps count towards the MapTiler account's quota.

### ICM · Obsidian vault

- Shows the Projects vault in use and lets you choose a different one.
- JARVIS reads `CONTEXT.md` and `ICM/routes.json` to route work requests and saves submitted prompts under `Memory/01_intake`.

### Website checks

- Turn notifications on or off for when a site goes down or recovers.

### Data and privacy notice

- Exports and restores a versioned JSON backup of tasks, projects, saved locations, and non-secret preferences.
- Previews new, updated, and skipped records before Merge or confirmed Replace.
- Creates daily and pre-migration backups, retains the configured number, and supports a user-chosen folder.
- Explains that tasks and projects are stored locally.
- Explains that NewsAPI.org and MapTiler keys are stored in Keychain and excluded from every backup.
- Explains that website checks are plain requests sent from this Mac to each project's site.
- Notes that live services receive only the information required for their requests.

---

## 11. Data Storage and Privacy

### Stored locally with SwiftData

- Tasks
- Projects
- Saved weather locations

### Stored in application preferences

- Interface selections
- Project sort order
- Watchlist terms
- Alert thresholds
- Quiet hours
- Read, saved, and dismissed news identifiers
- Intelligence comparison baselines
- Wake briefing preferences
- Website-check notification preference

### Stored in Application Support

- Website-check history in `~/Library/Application Support/JARVIS Dashboard/site-checks.json`

### Stored in macOS Keychain

- NewsAPI.org API key
- MapTiler API key

Each Keychain item is read at most once per launch and then served from memory. Saves and deletes keep that memory current; a cancelled password prompt is not remembered, so it can be retried.

JARVIS is signed with a stable Apple Development identity. macOS therefore sees every update as the same app, and a Keychain **Always Allow** grant carries over between releases.

### Data store safety

- The SwiftData store is at `~/Library/Application Support/default.store`.
- If the store or a migration cannot open, JARVIS shows a recovery screen instead of crashing. The screen explains the error, can open the backups folder or show the store file, and changes nothing.

### External requests

- Saved-location coordinates are sent to Open-Meteo for weather requests.
- Public earthquake data is requested from USGS.
- Public news feeds are requested from GMA News and BBC News.
- NewsAPI.org receives category requests only when an API key is configured.
- MapTiler and NOAA/NESDIS tiles are requested only while a MapTiler or Satellite basemap is visible.
- City search uses Apple Maps; Mac location is requested only when you choose "Use Mac location".
- Connected Git repositories are inspected locally.
- Each non-archived project's website receives a plain GET request from the Mac every 5 minutes; no credentials are sent.
- The Obsidian vault is read and written locally; nothing about it leaves the Mac.

---

## 12. Visual Identity and Native Experience

- Native SwiftUI interface designed for macOS.
- Letter-free JARVIS HUD application icon.
- Dark command-centre visual system with stable screen hierarchies.
- Responsive native layouts for varying window widths.
- Native materials, panels, forms, menus, search, links, and keyboard shortcuts.
- Minimum main-window size of 900 × 600 and default size of 1180 × 760.
- Dedicated menu-bar extra.

---

## 13. Technical Foundation

- SwiftUI for the interface.
- SwiftData for local task, project, and location persistence.
- AppKit for the floating briefing panel and workspace events.
- AVFoundation and macOS speech synthesis for local text-to-speech.
- URLSession with Swift concurrency for live providers.
- UserNotifications for reminders and Intelligence alerts.
- ServiceManagement for launch-at-login registration.
- Security framework/Keychain for NewsAPI.org and MapTiler keys.
- Local `/usr/bin/git` commands for read-only repository inspection.
- WebKit for the Synapse Map (Graphify) and the MapTiler basemaps.
- `/usr/bin/python3` child processes for the vault's maintenance and prompt-capture tools.
- Swift 6 toolchain (`swift-tools-version: 6.0`) compiling in the Swift 5 language mode.
- XcodeGen configuration for generating the Xcode project.
- 112 unit tests (Swift Testing) covering:
  - briefing composition, task prioritisation, and project behaviour;
  - task and project stores, including reminders and backup-safe deletion;
  - alert reliability and Intelligence rules;
  - website-check classification, URL normalisation, retry and outage logic, uptime, and history persistence;
  - weather, news, NewsAPI, and RSS parsing, including malformed input;
  - Git health and speech preferences;
  - backups and migration;
  - Cortex discovery and vault health;
  - the app coordinator, Keychain caching, and process timeouts.
- `scripts/release.sh` builds, verifies, backs up, and installs each release, stopping at the first failed check.

---

## 14. Current Product Boundaries

The following distinctions are important when interpreting the dashboard:

- Tasks may remain global or be linked to a project. Fixed-project progress uses linked task completion when available.
- Ongoing-client health describes recent operational activity, not percentage completion.
- Repository intelligence reads local Git metadata only; it does not inspect GitHub issues, pull requests, CI, deployments, or client communications.
- Launch at login occurs after macOS login, not before a user session exists.
- Wake detection works while JARVIS remains running.
- Website checks run from this Mac while JARVIS is running. They report reachability and response time only, not security, updates, or certificate expiry.
- Weather, earthquake, and news features require an internet connection for fresh data.
- There is currently no cross-device sync, Apple Reminders import, Calendar integration, or cloud account.
- Alerts are decision-support signals and do not replace official emergency advisories.
- Ask JARVIS routing uses fixed rules and calls no AI service; the agent receiving a handoff must still inspect current source.
- Vault upkeep and prompt filing run only while JARVIS is running. Queued prompts wait in temporary storage, and a restart before JARVIS opens could discard them.
- Graphify maps are navigation aids, regenerated on demand; they can lag behind the code until refreshed.

---

## 15. Installation Artifact

The current distributable build is:

`dist/JARVIS-Dashboard-0.2.29.zip`

The installed application is expected at:

`/Applications/JARVIS Dashboard.app`

Releases are made with `scripts/release.sh X.Y.Z --commit`. Each release backs up the previous app and both data stores to `dist/install-backups/pre-<version>-<date>/` and prints the rollback command. The build is universal (Apple Silicon and Intel).
