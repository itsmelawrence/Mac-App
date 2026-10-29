# JARVIS Dashboard — Detailed Product and Feature Specification

**Current release:** 0.2.29

**Platform:** macOS 14 Sonoma or newer  
**Application type:** Native, local-first productivity, operations, and intelligence dashboard  
**Bundle identifier:** `com.skeemadigital.jarvisdashboard`

## 1. Product vision

JARVIS Dashboard is a personal macOS command centre for daily work, client operations, website health, live regional information, and concise briefings. It is designed to answer four questions immediately:

1. What requires attention now?
2. What work should be completed next?
3. Are active projects and client websites healthy?
4. Has anything important changed locally or regionally?

The application is local-first. Tasks, projects, locations, and preferences remain on the Mac. Network requests are made only for configured live services such as weather, earthquake data, news, and map tiles, plus plain up/down checks sent from the Mac to each project's website.

JARVIS is also the always-on local host for the Obsidian **Projects vault** that agent tools (Codex, Claude Code) use:
- it routes work requests to projects and records the work;
- it browses project source and Graphify maps in Cortex;
- it keeps the vault healthy in the background.

The longer-term direction, a local AI assistant acting through JARVIS's tools, is tracked in the vault at `Notes/Projects/Personal/Mac App/ROADMAP.md`.

## 2. Main application structure

The primary window uses a native macOS sidebar with six destinations:

- **Today** — daily command centre
- **Tasks** — operational mission queue
- **Projects** — project, repository, and website operations
- **Cortex** — the Projects vault: every project, its source tree, context notes, Graphify maps, and vault health
- **Intelligence** — regional, news, and operational intelligence
- **Settings** — startup, voice, notifications, API credentials, map and vault configuration, backup, restore, and privacy

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
- Refreshes weather and earthquake information.

### 3.2 Ask JARVIS

- Processes supported commands locally.
- Does not send command text to an external AI provider.
- Presents the current briefing.
- Speaks the briefing when requested.
- Routes the user to Tasks, Projects, Intelligence, weather/news information, or Settings.
- Answers supported questions about task counts, active projects, and monitored-site health.
- Names the next actionable task, blocked tasks, and projects waiting on clients.
- Summarises attention items and distinguishes sites needing attention from sites awaiting checks.
- Answers "All N monitored websites are up" only when checks have completed; otherwise says site checks have not completed yet.
- Reports the most recently refreshed weather for the primary location, or states when a fresh report is unavailable.
- Answers questions about a named project with a structured card covering project status, site health, last check, task counts, next action, data sources, and update time.
- Asks for a more specific project name when multiple projects match; never invents a project or a site-check result.
- Keeps the answer visible until the user selects **View project** to open that project's detail screen.
- Explains currently supported capabilities when a request is not understood.
- Turns a work request into an agent handoff through the Obsidian vault; see section 10.1.

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
- Monitored sites that are up
- Regional alerts

### 3.5 Active operations

- Ranks active projects using site status, project status, priority, and recent activity.
- Shows the project's next action.
- Shows the number of linked open tasks.
- Shows the latest website-check state when the project has a website.
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

### 3.8 System status

- Shows **Site checks: Every 5 min**, or **Paused · offline** while the Mac has no connection.
- Displays the number of monitored sites.
- Displays Up and attention-required counts.
- Shows when sites were last checked.
- Never labels unchecked sites as up.

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

- Mark complete or return to pending. Completing cancels the task's due-date reminder; returning to pending reschedules it if the due date is still ahead.
- Mark blocked or unblock from the context menu.
- Display overdue deadlines in red.
- Display priority using restrained urgency colours.
- Delete only after confirmation. Deleting cancels the task's pending reminder.
- Persist changes locally with SwiftData.
- Calculate overall completion momentum.
- Task changes go through a tested `TaskStore`, so reminders always follow the task's state.

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
- Website address for up/down checks (stored in `monitoringWebsiteURL`)

The legacy `monitoringSiteID`, platform, and connection-date fields remain in the model only so older stores and backups still load; the app no longer uses them.

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
- Uses operational health, current activity, repository status, and website status instead.
- Supports long-running retainers, maintenance relationships, and continuing client work.

### 5.6 Operations board

The Projects section uses the same layout language as Tasks.

- **Operations** header with a subtitle, an attention capsule, and a **New Project** button.
- Status rail: Active, Waiting on client, Due within 7 days, Sites up (x/y), Down, and average 30-day uptime with the last check time.
- Filter chips with counts: Active, Needs attention, Waiting on client, Completed, Archived.
- A project needs attention when its site is Down or Slow, it is waiting on the client, its due date has passed, or it has overdue tasks.
- Sort menu: Needs attention first, Recently updated, Due date, Name. The choice is remembered as `projects.sort`.
- A **Check all sites** button.
- Search covers name, client, type, website, and tags.

Each project appears as a full-width card with:

- a site status icon, the project name, and the client;
- the next action;
- chips for status, priority, due date, task progress, overdue tasks, days waiting, and Ongoing;
- a progress bar for fixed projects;
- site status, host, and 30-day uptime on the right;
- an **Edit** button and a **⋯** menu: open, edit, status, check site now, open website, duplicate, archive/restore, delete;
- a priority accent on the left edge and a red border when the site is down.

A single click opens the project.

### 5.7 Project detail

- **Back to Operations** link, inline name and client editing, and Status, Priority, and Mode pickers.
- Metrics rail: Progress and Tasks done for fixed projects, or Repository health and Commits for ongoing clients; Deadline; Website; 30-day uptime.
- Main column:
  - **Website** panel: status, link, **Check Now**, last check, HTTP status, response time, uptime, a 30-day bar strip, and recent outages;
  - **Tasks**: up to 10 linked tasks, each opening its editor on click, then a link to Tasks;
  - **Local repository**, for ongoing clients only;
  - **Description**.
- Side column: **Next action** and **Details** (type, mode, dates, tags, created and updated times).

### 5.8 Project actions

- Create and edit a project.
- Open project details.
- Change status from the card's menu.
- Duplicate a project.
- Archive and restore a project; archived projects appear under the **Archived** filter.
- Delete after confirmation, through `ProjectStore`:
  - linked tasks move to the Inbox rather than keeping a dangling project link, which would make later backups fail to import;
  - a failed save is reported in an alert.
- Check a project's site on demand or open its website.

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

## 7. Website Checks

JARVIS runs free, local up/down checks from the Mac. No hosted service, account, or credential is involved.

### 7.1 Website address

- Entered in the project editor sheet's **Website** field or in the project detail **Website** panel.
- Normalised before saving: `example.com` becomes `https://example.com/`. Only http and https addresses with a dotted host are accepted.
- The Website panel offers **Change Address** and **Stop Checking**.
- Stored in the existing `monitoringWebsiteURL` project field.

### 7.2 Check schedule

- `SiteMonitor` lives for the whole app session, so checks continue while the dashboard window is closed.
- Every 5 minutes, and about 20 seconds after wake, it sends a plain GET request to each non-archived project's website.
- **Check Now**, **Check Site Now**, and **Check all sites** run a check on demand.

### 7.3 Result classification

- 2xx and 3xx responses are up.
- 401, 403, and 429 also count as up, because the server answered.
- A response slower than 3000 ms is **Slow**.
- Any other status, a timeout, a DNS failure, or an SSL error is a failed check.
- If the Mac itself is offline, every check is discarded and checks are shown as paused. An offline Mac is never reported as a site failure.

### 7.4 Retries, outages, and states

- One failed check shows **Retrying** and checks again after 60 seconds.
- Two failures in a row mark the site **Down**. The outage is recorded as starting at the first failure.
- States: Up, Slow, Retrying, Down, Checking…, and No website.
- A site needs attention when it is Down or Slow.

### 7.5 History

Stored locally in `~/Library/Application Support/JARVIS Dashboard/site-checks.json`:

- The last 50 checks
- 30 daily tallies, used for 30-day uptime
- The last 20 outages

### 7.6 Notifications

- JARVIS notifies when a site goes down and when it recovers.
- The toggle is in Settings › **Website checks** (preference `sites.notifyOnChange`, included in backups).

## 8. Assistant State Snapshot

JARVIS writes `~/Library/Application Support/JARVIS Dashboard/state.json` (schema version 1) for the assistant's read-only tools.

Each item in its `sites` section contains:

- `site_id` (the project UUID), `name`, `url`, `project_id`, and `project`
- `state` and `needs_attention`
- `last_check`, `status_code`, `response_ms`, and `error`
- `down_since` and `uptime_percent`

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
- Duplicate-notification suppression:
  - Weather alerts (storm, rain, heat) are identified per location per day. A new storm the next day alerts again, while a reading drifting within the day does not re-alert.
  - The last 500 notified and spoken alert identifiers are kept in order and the oldest are forgotten first.
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
- Compact weather beacons with rain-probability rings, condition glyphs, annotation-attached labels that follow panning and zooming, collision-tested placement, a fitted/resettable camera, and a selectable wettest-location list. The detail metric picker does not change the rain-chance ring.
- A legend and on-map provenance distinguish point forecasts from radar or area-wide rain coverage.
- Seven days of hourly forecast navigation, next-24-hour detail, and seven daily summaries for a selected location.
- Sampled values are explicitly distinguished from continuous map tiles, radar, and official weather warnings.
- **Basemap picker.** **Apple Maps** is the default. **MapTiler preview** shows a Landscape basemap. **Satellite** shows MapTiler ground imagery under NOAA/NESDIS infrared cloud tiles: the latest available observation, independent of the forecast-hour slider. Ordinary overlays are hidden in Satellite mode, and animated thunderstorm icons appear only at sampled locations where the selected hour reports a storm. This is not live radar or lightning detection.
- MapTiler modes need a MapTiler key (Keychain) and count towards the account's quota. Forecast points arriving after the map page loads are pushed to the map.
- **Personal weather dashboard.** Switchable from the map. It shows a primary-location hero forecast, four independently chosen city cards, Apple Maps city search, and an opt-in "Use Mac location" kept in memory for the session only.
- Eight condition-specific native weather animations across the map, hero forecast, hourly strip, and city cards. With Reduce Motion, a still icon is shown instead.
- One failed location no longer discards the others' weather. Missing (null) hourly precipitation is read as 0%.
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
- **GMA News** — Philippine headlines. The feed URL currently serves an HTML list, which is read through the HTML fallback.
- **BBC News RSS** — world headlines. CDATA titles are read as-is; bare `&` repair applies only outside CDATA.
- **NewsAPI.org** — optional news enrichment:
  - Philippines requests use `country=ph`; World requests use `category=general&language=en`, because NewsAPI requires a filter.
  - Errors such as an invalid key or quota are shown on the Intelligence screen.
  - Malformed or `[Removed]` articles are skipped, not fatal.
- **MapTiler** and **NOAA/NESDIS** — map and cloud tiles, only while those basemaps are visible.

Weather, earthquake, Philippine news, world news, and regional weather requests run concurrently. RSS remains the fallback when NewsAPI is unavailable or not configured.

### 9.11 Safety boundaries

- Open-Meteo is informational; PAGASA remains the official Philippine weather authority.
- USGS reports may be preliminary; significant local events should be confirmed with PHIVOLCS.
- Headline matching is an early signal, not an emergency instruction.
- Evacuation and safety decisions must be confirmed with the appropriate authorities.

## 10. Cortex, Vault, and Agent Handoff

JARVIS works with a local Obsidian **Projects vault** (default `~/Documents/Main/Projects`, chosen in Settings → ICM · Obsidian vault). The vault is shared with Codex and Claude Code. All vault reads and writes are local; no AI service is called.

### 10.1 Ask JARVIS work handoff

- A work request is matched to a project through `ICM/routes.json`, using fixed rules.
- JARVIS verifies the project folder and context note, suggests relevant Graphify notes, and prepares a handoff for an agent.
- Every submitted console prompt is saved under `Memory/01_intake/<project>/` (unmatched prompts go to `_unrouted/`).
- Matched requests get a dated activity note under `Notes/Projects/<project path>/Activities/` for the agent to complete.
- Routing never edits project source; the agent must still inspect current source and local instructions.

### 10.2 Cortex workspace map

- **Discovery:** lists all vault projects under `Work/` and `Personal/`, combining ICM routes with projects found by marker files (Git, manifests, `PROJECT.md`, index files), without duplicates. The rules live in `ICM/discovery.json`, shared with the vault's `.tools/project_hubs.py`, with built-in defaults if the file is missing or malformed.
- **Refresh:** on open and every 30 seconds on the overview. The scan, search, and file reads run off the main thread, and a refresh is skipped while one is still running.
- **Scan record:** the scanned list is written to `ICM/cortex-projects.json`, only when it changes, so the vault doctor can check that JARVIS and the vault tools agree.
- **Route problems:** a missing or unsafe route appears under **ICM routes need attention** without hiding other projects.
- **Per project:** browse the source tree (generated, dependency, and hidden folders omitted), search paths, and open the context note and Graphify connection notes.

### 10.3 Vault health

- Cortex shows a health card from `ICM/health.json`, written by the vault doctor (`.tools/vault_doctor.py`).
- The card gives the error and warning counts, the top issues, and an **Open report** button for `Notes/Resources/Vault health.md`. It warns when the report is more than a day old.
- The doctor checks routes, project hubs (including moved projects, detected through stable hub IDs), wikilinks in curated notes, Graphify coverage, activity-note status, stray intake folders, and Cortex-versus-tools discovery parity.

### 10.4 Synapse Map (Graphify)

- Embeds Graphify's own `graph.html`, with search, node inspector, community filters, and force-directed layout. JARVIS inlines the pinned vis-network 9.1.6 library and adds signal pulses.
- Selecting a source file focuses its node. The viewer is prepared off the main thread and reloads when `graph.html` changes.
- Maps are regenerated with `.tools/graphify_refresh.py <route>`, which validates code coverage, the HTML, and inbound links before installing.

### 10.5 Background vault upkeep

`AppCoordinator` runs these for the app's lifetime, with or without the dashboard window. Each runs as a time-limited child process of JARVIS. They can't run as launchd jobs: macOS doesn't let those list `~/Documents`, and they can read only files they created.

- **Vault maintenance:** at launch and then every 3 hours, `.tools/vault_maintenance.py --vault <configured vault>` refreshes project hubs and runs the doctor. It logs to `~/Library/Logs/vault-maintenance.log`.
- **Prompt capture filing:** every 15 seconds, when prompts are queued, JARVIS files prompts captured by the Codex and Claude Code `UserPromptSubmit` hooks:
  - one activity note per agent session, project, and day;
  - Codex's automatic "suggestions" prompts are skipped;
  - prompts queued while JARVIS is closed are filed when it opens.

## 11. JARVIS Voice

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

## 12. Briefing Panel

- Compact floating native macOS panel.
- Can appear above other workspaces and alongside full-screen applications.
- Displays complete briefing text without truncating it.
- Opens from Today, Intelligence, Settings, the menu bar, and wake events.
- Requests are handled by the app-lifetime `AppCoordinator`, not the dashboard window. Menu-bar and wake briefings work with the window closed, and each request is presented exactly once.
- Can be dismissed with its close action or Escape. Closing by any route, including the title-bar button, stops speech.
- Opening animation has been removed to keep startup immediate and restrained.

## 13. Startup, Login, Sleep, and Wake

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
- Wake detection requires JARVIS to remain running, but not its dashboard window. It is started once at launch by `AppCoordinator`.

## 14. Menu-Bar Command Centre

- Shows the current pending-task count.
- Adds a quick Inbox task.
- Opens the main dashboard window.
- Presents a briefing.
- Quits JARVIS.

## 15. Settings

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

### Philippines map · MapTiler preview

- Saves or removes a MapTiler API key in Keychain. Without a key, Apple Maps remains available.

### ICM · Obsidian vault

- Shows and changes the Projects vault used for routing, capture, Cortex, and maintenance.

### Website checks

- Turns notifications on or off for when a site goes down or recovers.

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

### Data and privacy

- Explains which data is local and which services receive requests.
- Explains that website checks are plain requests sent from this Mac to each project's site.

## 16. Local Storage and Credential Security

### SwiftData

Stored locally:

- Tasks
- Projects
- Saved weather locations
- A formal versioned schema and migration plan protect future model changes.

### Application preferences

Stored locally in preferences:

- Selected views and filters
- Project sort order (`projects.sort`)
- Watchlist terms
- Alert thresholds
- Quiet hours
- Read, saved, and dismissed story identifiers
- Intelligence comparison baseline
- Wake-briefing settings
- Voice settings
- Website-check notifications (`sites.notifyOnChange`)

### Application Support files

- `JARVIS Dashboard/site-checks.json`: website-check history (see section 7.5)
- `JARVIS Dashboard/state.json`: the assistant state snapshot (see section 8)

### macOS Keychain

Stored securely:

- NewsAPI.org key
- MapTiler API key

`KeychainCache` reads each item at most once per launch. Saves and deletes keep the cache current; a cancelled password prompt is not cached.

JARVIS is signed with a stable Apple Development identity (team `TRM376DDJX`). Its designated requirement, the bundle identifier plus that certificate, stays the same across builds, so Keychain **Always Allow** grants persist through updates. Ad-hoc signing would make every build a new app.

### Data store safety

- The SwiftData store is at `~/Library/Application Support/default.store`, SwiftData's shared default path. Moving it to an app-specific path is deferred, with a migration plan in the vault audit note.
- A store or migration failure opens a recovery screen instead of crashing. It explains the error, opens the backups folder or shows the store, and changes nothing.

### Versioned backups

- Backup schema version, application version, and export timestamp
- Every persisted task and project field, including task-to-project identifiers
- Saved locations and non-secret preferences
- Repository bookmarks for same-Mac recovery; macOS may require repository access to be granted again on another Mac
- No NewsAPI or MapTiler key
- `projects.sort` and `sites.notifyOnChange` are included; `projects.sort` replaced the former `projects.showArchived`
- Automatic rotation to the configured retention count

### External request boundaries

- Location coordinates are sent to Open-Meteo.
- Public earthquake data is requested from USGS.
- Public news is requested from configured providers.
- NewsAPI category requests occur only when a key is configured.
- MapTiler and NOAA/NESDIS tiles load only while those basemaps are visible; the MapTiler key is sent in map requests.
- City search uses Apple Maps; Mac location is requested only on "Use Mac location".
- Git inspection remains entirely local.
- Website checks send a plain GET request from the Mac to each non-archived project's website, with no credentials.
- The Obsidian vault is read and written locally only.

## 17. Native macOS Experience

- SwiftUI interface.
- SwiftData persistence.
- AppKit floating panels and workspace event monitoring.
- Native sidebar, forms, menus, links, alerts, search, and keyboard shortcuts.
- Dark command-centre visual system.
- Letter-free JARVIS HUD application icon.
- Minimum main-window size of 900 × 600.
- Default main-window size of approximately 1180 × 760.
- Universal Intel and Apple Silicon release build.

## 18. Technical Foundation

- Swift 6 toolchain (`swift-tools-version: 6.0`) in the Swift 5 language mode
- SwiftUI
- SwiftData
- AppKit
- URLSession and Swift concurrency
- UserNotifications
- AVFoundation/macOS speech synthesis
- ServiceManagement
- Security framework and macOS Keychain
- Local `/usr/bin/git` inspection
- WebKit for the Synapse Map and MapTiler basemaps
- `/usr/bin/python3` child processes (time-limited) for vault maintenance and prompt-capture filing
- XcodeGen project generation
- Unit tests using Swift Testing (112 tests in 28 suites at 0.2.29)
- `scripts/release.sh` for gated releases

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
- Website-check classification, URL normalisation, retry and outage logic, 30-day uptime, and history persistence
- Speech settings logic
- Backup round trips, secret exclusion, validation, idempotent merge, replace safeguards, rotation, and migration from the 0.1.18 unversioned store
- Task and project stores: reminder lifecycle, and project deletion that keeps backups restorable (with a contrast test showing a raw delete breaks them)
- Alert identity and ordered dedupe memory
- Malformed-input tolerance for NewsAPI, RSS (CDATA and bare ampersands), and weather
- Cortex discovery rules, route problems, scan recording, and vault-health decoding
- App coordinator briefing delivery, Keychain cache, prompt-capture queue detection, and process timeouts

## 19. Product Boundaries

The current release intentionally does not provide:

- Cross-device sync
- An iPhone application
- Apple Reminders import
- Calendar integration
- Email or messaging integration
- Automatic Git commits, pulls, pushes, or deployments
- Changes to client websites or hosting
- Website security, update, or certificate-expiry monitoring; website checks report reachability and response time only
- Official emergency-alert authority
- An external generative-AI command backend. A local assistant acting through JARVIS's tools is a roadmap goal, not a current feature.
- Vault upkeep or prompt filing while JARVIS is not running; prompts wait in temporary storage until it opens

An iOS application is planned but is not part of the current macOS release.

## 20. Installation and Release Artifact

Current distributable archive:

`dist/JARVIS-Dashboard-0.2.29.zip`

Installed application location:

`/Applications/JARVIS Dashboard.app`

The release is built as a universal macOS application for Apple Silicon and Intel Macs, signed with the Apple Development identity.

Releases are made only with `scripts/release.sh X.Y.Z --commit`, which stops at the first failed check:
1. Preconditions: clean tree, newer version, valid signing identity.
2. Tests, then a universal build.
3. Signature, architecture, and version checks, then the zip.
4. A graceful quit, then byte-verified backups of the app and both stores with SQLite `quick_check`, in `dist/install-backups/pre-<version>-<date>/`.
5. Install, binary compare, then launch, crash, and store checks.

On success it prints the rollback command.
