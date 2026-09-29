# Handoff — in-flight work

Short-lived notes between sessions. Durable architecture lives in `CLAUDE.md`. Trim aggressively as items land.

Last touched: 2026-09-27.

## In flight

_(nothing in flight right now)_

## Future / nice-to-have

_(nothing queued)_

## Done in last session — already reflected in CLAUDE.md
- Hours-based goal, day tracking, single break model, manual breaks, breaks-as-sessions, commitment-on-by-default, gutted CompletionPanel, removed flow decision, dashboard breaks in log, consistency + best-week metrics, sessions count demoted everywhere.
- Active in-progress focus session shown in DashboardView's today log (synthetic event with pulsing dot via `TimerManager.currentInProgressSession`).
- TimerView goal redesign: removed redundant outer goal ring + goal stat tile; goal now shown as a single slim progress bar above the stat trio. Streak tile is always present.
- Liquid Glass-flavored material pass: `Sources/GlassEffects.swift` (`glassCard` / `glassChrome`) applied to menu bar popover, dashboard window chrome, and all stat-card surfaces across DashboardView + StatsView.
