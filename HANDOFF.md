# Handoff — in-flight work

Short-lived notes between sessions. Durable architecture lives in `CLAUDE.md`. Trim aggressively as items land.

Last touched: 2026-05-14.

## In flight

_(nothing in flight right now)_

## Future / nice-to-have

### Liquid Glass — true APIs once Xcode is updated
Current pass uses `.thinMaterial` / `.regularMaterial` via `Sources/GlassEffects.swift` (`glassCard`, `glassChrome`). This works on macOS 14+ and the system renders these materials with the Liquid Glass aesthetic automatically on macOS 26.

To adopt the real APIs (`glassEffect(in:)`, `GlassEffectContainer`, `.buttonStyle(.glass)`, `.buttonStyle(.glassProminent)`), bump to Xcode 17+ / macOS 26 SDK and update `GlassEffects.swift` to switch on `#available(macOS 26, *)`. Likely surfaces:
- Tab picker → `TabView` with native glass tab bar.
- Play button → `.buttonStyle(.glassProminent)`; stop/skip → `.buttonStyle(.glass)`.
- Preset/category chips → wrap in `GlassEffectContainer` for morph/blend on selection.

## Done in last session — already reflected in CLAUDE.md
- Hours-based goal, day tracking, single break model, manual breaks, breaks-as-sessions, commitment-on-by-default, gutted CompletionPanel, removed flow decision, dashboard breaks in log, consistency + best-week metrics, sessions count demoted everywhere.
- Active in-progress focus session shown in DashboardView's today log (synthetic event with pulsing dot via `TimerManager.currentInProgressSession`).
- TimerView goal redesign: removed redundant outer goal ring + goal stat tile; goal now shown as a single slim progress bar above the stat trio. Streak tile is always present.
- Liquid Glass-flavored material pass: `Sources/GlassEffects.swift` (`glassCard` / `glassChrome`) applied to menu bar popover, dashboard window chrome, and all stat-card surfaces across DashboardView + StatsView.
