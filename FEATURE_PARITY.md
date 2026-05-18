# Mac ⇄ iPad feature parity

Last updated after parity audit.

## Both platforms have

| Feature | Mac | iPad |
|---|---|---|
| Focus timer with phases (work/break) | ✓ | ✓ |
| Presets (15 / 25 / 45 / 60) | ✓ | ✓ |
| ±5 / ±10 in-session adjust | ✓ | ✓ |
| **Take a Break** (preset + custom + kinds) | ✓ | ✓ |
| Day Start / End + commitment prompt | ✓ | ✓ |
| Tags / labels | ✓ (synced) | ✓ (synced) |
| Problem logging + categories + review queue | ✓ | ✓ |
| Homework problem logging | ✓ | ✓ |
| Scratchpad / quick-capture | ✓ | ✓ |
| Settings (daily goal, intervals, sync, etc.) | ✓ | ✓ |
| **iCloud Sync** — sessions, problems, settings, live timer | ✓ | ✓ |
| Instant timer mirroring (MultipeerConnectivity) | ✓ | ✓ |
| **Manual session log** (retroactive) | ✓ | ✓ (NEW) |
| **JSON snapshot export** | ✓ (NEW) | ✓ |
| Sync diagnostic in Settings | ✓ | ✓ |
| Local notifications on completion | ✓ | ✓ |

## Mac-only (by design — platform-specific)

- **Site blocking** — modifies `/etc/hosts` + `pf` while focused. iOS has no equivalent capability outside of Screen Time.
- **Global hotkey ⌃⌥Space** — system-wide pause / resume. iPad has no global keyboard shortcuts that work outside foreground apps.
- **Completion panel** — floating NSPanel after a session ends with "Keep going / Take break" buttons. iPad uses local notifications instead (less intrusive).
- **Onboarding tour (3-page)** — Mac shows this on first launch. iPad doesn't currently — could be added.
- **Liquid Glass UI** — Mac uses NSGlassEffect / .glassCard styling. iPad uses iOS-native materials.

## iPad-only (could be back-ported to Mac if useful)

- **3-ring "Apple Fitness" Dashboard** — focus + problems + consistency.
- **18-week heatmap** — Mac has a 14-day bar chart instead.
- **Awards screen** — 15 milestones (sessions, hours, streaks).
- **Narrative Insights screen** — "Wednesday is your power day", "down 23% vs last week", etc. Mac has a tabular Insights section with the same underlying metrics.
- **Personal-best banner** on overview when you hit a new record.
- **Today's Top 3 Priorities** on Timer screen.
- **NavigationSplitView sidebar** with 10 tabs (Mac uses 5-icon popover by space constraint).
- **Search bar** in Problems + Homework lists.
- **Quick-add problem** button on Timer screen toolbar.
- **Haptic feedback** — iPad-only (no haptic engine on Mac).

## Sync coverage

| Data type | Sync mechanism |
|---|---|
| Work sessions, problems, homework, day records, scratchpad | SwiftData + CloudKit (private DB) |
| User settings (daily goal, intervals, tags, problem goals, interview date, commitment, etc.) | iCloud Key-Value Store |
| **Live timer state** (running countdown, phase, label, break kinds) | Instant: MultipeerConnectivity over local network. Fallback: SwiftData + CloudKit. |
| Device-local (site blocking on Mac, onboarding-shown flag, cloud-sync toggle) | UserDefaults only |

## Known one-way limitations

- Manual session log on iPad inserts directly to SwiftData and propagates via CloudKit; same path as Mac.
- Timer started on one device → mirrored on the other in <1s when same wifi. ~5–30s via CloudKit if not.
