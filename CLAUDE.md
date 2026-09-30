# Focus — macOS Focus Timer

macOS menu bar focus timer with day tracking, problem logging, and a standalone dashboard. SwiftUI + Swift Package Manager. Deployment target: macOS 14+.

Built for a quant + SWE interview prep workflow: focus sessions tagged by category (Quant / SWE / AI), problems logged by domain with confidence/difficulty, daily commitment + voice oath, hours-based daily goal.

## Build & install

```bash
./deploy.sh      # build → back up SwiftData store → quit → replace /Applications/Focus.app → relaunch
```

`build.sh` alone builds to `.build/app.noindex/Focus.app` (the `.noindex` keeps Spotlight from listing a duplicate). `/Applications/Focus.app` is the only copy that should exist. `deploy.sh` also deletes stale `Focus.app` / `LockIn.app` / `FocusTimer.app` bundles left in the repo root by older builds.

> **Always use `./build.sh` / `./deploy.sh`, never bare `swift build`.** Bare `swift build` only rebuilds `.build/release/Focus`, not the app bundle.

## Architecture

### Stores (ObservableObject, JSON-persisted)

| File | Role |
|------|------|
| `Sources/SessionStore.swift` | Work + break sessions (SwiftData `StoredWorkSession`). Computes today/lifetime metrics, streaks, consistency, best week, by-tag splits, daily summaries, heatmap data. |
| `Sources/DayStore.swift` | Day boundaries (`DayRecord { calendarDay, dayStart, dayEnd }`). SwiftData `StoredDayRecord`. |
| `Sources/ProblemStore.swift` | Logged problems per domain. SwiftData `StoredProblem`. |
| `Sources/ScratchStore.swift` | Scratchpad checklist items. SwiftData `StoredScratchItem`. |
| `Sources/CommitmentStore.swift` | AVFoundation voice oath recorder. Audio at `oaths/YYYY-MM-DD.m4a`. |
| `Sources/AppSettings.swift` | All settings, UserDefaults-backed. Bundle id `com.magnus.focus`. |
| `Sources/LeetCodeStore.swift` | LeetCode grind tracking derived from `ProblemStore` (every solve is a normal SWE `ProblemEntry`, matched to the catalog by URL slug, then title). Streaks, pace vs target/deadline, pattern coverage, difficulty mix vs 20/60/20 target, solve-time medians vs 15/25/40m, redo queue, milestones, Smart pick, stopwatch (persisted in UserDefaults), evening nudge notification. |
| `Sources/LeetCodeCatalog.swift` | All ~3.6k LeetCode algorithm problems from `Sources/Resources/leetcode.json` (LeetCode GraphQL + NeetCode pattern labels + Blind75/NC150/NC250/Grind75/Grind169 bitmask). One primary pattern per problem (NeetCode label, else ordered tag rules). "Update from LeetCode" refetches into `Focus/leetcode-catalog.json`; newer `generated` wins. |

### Logic / glue

| File | Role |
|------|------|
| `Sources/LockInApp.swift` | App entry (`@main FocusApp`). MenuBarExtra. `PopoverContent` wires all stores, hosts tab switcher + commitment overlay. |
| `Sources/TimerManager.swift` | Timer state machine. `Phase { work, shortBreak, longBreak }` (no rawValue — `displayName` returns "Focus" / "Break"). Phase transitions, partial-session save, manual break, pause-grace auto-finalize, crash-recovery checkpoint, site-blocking orchestration. |
| `Sources/SiteBlocker.swift` | `/etc/hosts` + `pf` firewall blocking. Requires sudo helper at `/usr/local/bin/focustimer-blocker`. Cleanup on quit + next launch after crash. |
| `Sources/GlobalHotKey.swift` | ⌃⌥Space pause/resume hotkey. |
| `Sources/CompletionPanel.swift` | Simple 2.5s success toast (`show(label:)`) shown when a focus session completes. |
| `Sources/Models.swift` | `WorkSession`, `WorkSession.SessionType` (with `isBreak`), `DailySummary`, `DayRecord`, `ProblemEntry` + enums, `ScratchItem`. |

### Views

| File | Role |
|------|------|
| `Sources/TimerView.swift` | Main timer UI. Day status row (Start/End Day), phase label, category chips, presets, ring (outer = goal progress in hours, inner = session progress), controls, ±5/±10 adjustment, Take a Break button + sheet, today's stats footer. |
| `Sources/CommitmentView.swift` | Daily commitment overlay (written text + optional voice oath). Triggered by Start Day. |
| `Sources/StatsView.swift` | Popover stats tab. Today card, 7-day card, focus split, 18-week heatmap, lifetime row. |
| `Sources/ProblemsView.swift` / `ProblemDetailView.swift` | Problem logging + review queue. SWE log sheet searches/browses `FocusCore/Grind75Catalog.swift` (8-week schedule) and prefills title/URL/difficulty/categories; progress matched by LeetCode URL slug, then title. |
| `Sources/ScratchpadView.swift` | Quick checklist. |
| `Sources/SettingsView.swift` | All settings UI. |
| `Sources/BlockedSitesView.swift` | Domain list editor for site blocking. |
| `Sources/LeetCodeView.swift` | Standalone LeetCode window (`LeetCodeWindowController`), opened from the popover's LeetCode button. Left: searchable/filterable browser. Right: Grind tab (today ring, stopwatch, problem card + attempt history, Smart/Random pick, redo queue, pace) and Stats tab (28-day chart, pattern grid, mix, speed, quality, lists, milestones). |
| `Sources/DashboardView.swift` | Standalone NSWindow. Left: today's log (focus + breaks + problems, newest-first, click focus/problem rows to edit). Right: stat cards, problem progress, 14-day chart, focus split, insights, weak areas, lifetime row. `DashboardWindowController.open(...)` opens/refocuses. |

## Data model

### `WorkSession`
- `id: UUID`, `startTime: Date`, `durationMinutes: Double`, `type: SessionType`, `var label: String?`
- `SessionType`: `.work | .shortBreak | .longBreak` — `var isBreak: Bool` returns `type != .work`. Old `.shortBreak`/`.longBreak` data still decodes; new code writes only `.shortBreak` for breaks.

### `DayRecord`
- `id: UUID`, `calendarDay: Date` (start of day), `var dayStart: Date?`, `var dayEnd: Date?`
- `DayStore.todayRecord`, `isDayStarted` (started but not ended), `isDayEnded`.

### `ProblemEntry`
- `domain: ProblemDomain` (Quant / SWE), `categories: [String]`, `var difficulty: ProblemDifficulty`, `var confidence: Confidence`, `var needsReview`, `var notes`, `var url`, etc. Spaced-repetition `reviewDueDate` derived from confidence + needsReview.

### Storage paths
- `~/Library/Application Support/default.store` — SwiftData (SQLite) store for sessions, day records, problems, scratch, practice/mastery, timer state. Mirrored to CloudKit. Count sessions: `sqlite3 -readonly ~/Library/Application\ Support/default.store 'select count(*) from ZSTOREDWORKSESSION'`
- `~/Library/Application Support/Focus/backups/default-YYYY-MM-DD.store` — daily single-file snapshots (`FocusCore/StoreBackup.swift`), 14 kept. Restore = quit app, copy over `default.store`, delete its `-wal`/`-shm`.
- The old `*.json` files were migrated in May 2026 and survive only as `*.pre-swiftdata.bak`. `zetamac.json` and `sync.log` in `~/Library/Application Support/Focus/` are still live.
- `~/Library/Application Support/Focus/oaths/YYYY-MM-DD.m4a`
- UserDefaults `com.magnus.focus` (settings, commitment timestamp, timer crash checkpoint)

## Key behaviours

### Timer
- **Phases**: focus → break → focus. No long-break cycle anymore (single break duration in settings, default 10m).
- **Auto-break**: when a focus session naturally completes, a break timer auto-starts if `settings.autoBreakEnabled` (default true). Otherwise returns to idle.
- **Manual break**: "Take a Break" button (idle on work phase) opens a sheet — 30 / 60 / 120 min / custom (5m steps, 5–480m). Saves any in-progress focus first.
- **Stop / skip**: stop button mid-session saves partial work if ≥ 1 min; skip during a break saves break if ≥ 5 min, then returns to work.
- **Pause grace**: pausing arms an auto-finalize that saves + ends the session after `pauseGraceMinutes` (default 10). Bathroom-break safe; longer absences auto-end.
- **Crash recovery**: timer state checkpointed every 30s during work; on next launch the partial session is recovered into the store.
- **In-session adjustment**: ±5 / ±10 min chips during active work.
- **Quick presets**: 15 / 25 / 45 / 60m chips when idle on work.

### Day tracking
- **Start Day** button at top of TimerView. Records `dayStart` and (if commitment enabled) shows the commitment overlay.
- **End Day** button replaces it once started. Records `dayEnd`.
- App relaunch mid-day: if day is already started and commitment not done today, the overlay shows automatically.

### Commitment
- ON by default. Written commitment (required) + optional voice oath (AVFoundation, requires mic permission).
- Tracked via `lastCommitmentDateEpoch` in UserDefaults. `needsCommitmentToday` checks if it's a different calendar day than the last commitment.

### Goal
- Daily goal is **hours** (not sessions). Settings shows "Daily Target ... 4 h". Stored under UserDefaults key `dailyGoalHours`.
- Goal progress shown as outer ring (TimerView), `Xh / Yh` bar (StatsView), and `N% of Yh goal` card (Dashboard).

### Stats
- **Consistency** (`consistencyScore(days:)`): % of last N days with any work session. Surfaced in StatsView 7-day card and Dashboard insights.
- **Best week** (`bestWeekMinutes`): max hours in any rolling 7-day window. In lifetime row + Dashboard insights.
- **Streak**: consecutive days with a work session. Today counts only if logged.
- **By-tag splits**: 7-day and lifetime breakdowns.

### Site blocking
Requires admin password on first setup. Sets up sudoers entry + helper script. Modifies `/etc/hosts` + `pf` firewall while a focus session is active. Cleanup runs on quit and on next launch after a crash via `SiteBlocker.cleanupIfNeeded()`.

### LeetCode tracker
- Daily goal = `settings.sweGoal` (falls back to 3). Target/deadline: `leetCodeTarget`, `leetCodeDeadline` (falls back to `interviewDate`).
- Solve confidence drives the existing spaced repetition (`ProblemEntry.reviewDueDate`); "needed hints/AI" → `needsReview`. Redo queue uses each problem's latest attempt.
- `CommitmentReminder` is the app's only `UNUserNotificationCenterDelegate`; non-commitment taps go to `onOtherTap(identifier)` (LeetCode nudge opens the LeetCode window).
- Regenerating `leetcode.json`: page LeetCode GraphQL `questionList` 100 at a time (limit is capped at 100), keep `categoryTitle == "Algorithms"`.

### Menu bar
- Idle: `scope` SF Symbol.
- Active: countdown `MM:SS`, prefixed with `⏸` when paused.

## Conventions

- **No comments in code unless WHY is non-obvious.** The user reads the diff; obvious comments are noise.
- **No "what changed" recap summaries** at end of responses — keep responses tight.
- **Edit existing files over creating new ones.**
- Install with `./deploy.sh` (never bare `swift build`).

## Roadmap status

### Done
- [x] Hours-based daily goal (was sessions)
- [x] Day boundaries (Start/End Day)
- [x] Single break duration + auto-break toggle
- [x] Manual breaks with presets, tracked as sessions
- [x] Daily written commitment + voice oath
- [x] Standalone dashboard window with editable log
- [x] Newest-first log ordering
- [x] Consistency score + best-week metric
- [x] Crash-recovery for partial sessions
- [x] Pause auto-finalize (bathroom-break safe)
- [x] In-session duration adjustment
- [x] Spaced-repetition review queue for problems
- [x] 18-week heatmap
- [x] In-progress focus session in dashboard log
- [x] Material-based glass pass (`GlassEffects.swift`)
- [x] CloudKit mirror health (`FocusCore/CloudSyncMonitor.swift`) in Settings + popover warning when failing/stale
- [x] Daily store backups

- [x] Native Liquid Glass on macOS 26 (`glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass/.glassProminent)` on timer controls, tinted glass on selected chips); material fallback on 14–15
- [x] Grind 75 picker in Log Problem

### In flight (see HANDOFF.md)
_(none)_

### Future ideas (not started)
- Multi-day visual timeline (horizontal blocks for past days)
- Pace-toward-interview indicator (problems remaining ÷ days left)
- Weekly goal in addition to daily
- Editable break sessions (set label like "Lunch", "Gym")
- Notification quick-action to extend +5 min
- Sound customization
