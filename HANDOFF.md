# Handoff — in-flight work

Short-lived notes between sessions. Durable architecture lives in `CLAUDE.md`. Trim aggressively as items land.

Last touched: 2026-05-14.

## In flight

### 1. Active session in dashboard log
[Sources/DashboardView.swift](Sources/DashboardView.swift) `todayEvents` reads only completed sessions from `SessionStore`. While a focus session is in progress, it doesn't appear.

Inject a synthetic in-progress event when `timer.isActive && timer.currentPhase == .work`:
- start: `timer.sessionStartTime`
- elapsed: `timer.elapsedBeforePause + (now - timer.lastResumeTime)` (or surface a public `currentElapsedSeconds` on `TimerManager`)
- label: `timer.currentLabel`
- render with a pulsing dot or muted color so it reads as "in progress"

`TimerManager` exposes `sessionStartTime` and `elapsedBeforePause` privately — needs to either be made internal/public or wrapped in a `currentInProgressSession: WorkSession?` computed property. Latter is cleaner.

`DashboardView` would need to observe `TimerManager` (currently only observes `SessionStore`, `ProblemStore`, `AppSettings`, `DayStore`). Add `@ObservedObject var timerManager: TimerManager` and thread it through `DashboardWindowController.open(...)` from `LockInApp.PopoverContent.openDashboard`.

### 2. Liquid Glass design pass
User wants to explore Apple's Liquid Glass language. Surfaces to consider:
- Tab bar at top (segmented picker → glass capsule pills with selection blur)
- Stat cards (currently `RoundedRectangle.fill(Color.secondary.opacity(0.04))` → `.regularMaterial` / `.thinMaterial` with subtle borders)
- Buttons (chips / pickers / play button — glass hover & press states)
- Menu bar popover background (currently `Color(NSColor.windowBackgroundColor)` — could move to `.ultraThinMaterial`)
- Dashboard window chrome
- Commitment overlay

**Approach**: present 2–3 design directions before implementing. E.g.:
- **(a) Subtle**: keep current geometry, swap solid backgrounds for `.thinMaterial`, add 0.5pt hairline borders.
- **(b) Capsule-forward**: tab bar becomes glass pills, stat cards get rounder corners + heavier blur, ring controls float on glass.
- **(c) Full reskin**: dashboard adopts a translucent sidebar, popover gets a tinted glass backdrop, breaks/focus distinguished by color tint over glass.

## Done in last session — already reflected in CLAUDE.md
- Hours-based goal, day tracking, single break model, manual breaks, breaks-as-sessions, commitment-on-by-default, gutted CompletionPanel, removed flow decision, dashboard breaks in log, consistency + best-week metrics, sessions count demoted everywhere.
