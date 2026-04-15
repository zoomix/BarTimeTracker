# BarTimeTracker

macOS menu bar app. Tracks screen activity and project work sessions. Always running, no dock icon.

## What it does

**Screen tracking**
- Detects screen wake, sleep, screensaver start/stop via macOS system notifications
- Records timestamp for every event
- Calculates total active screen time for today (screensaver = away)

**Project tracking**
- Periodic popup asks what you're working on (configurable: 5 / 15 / 30 / 60 min)
- Each answer creates a timestamped project entry — including every check-in, not just changes
- Popup skips if screen is off, screensaver is running, or Focus/DND is active
- Prompts chain: next fires only after current is dismissed — no stacking after long absence
- Window appears without stealing keyboard focus

**Menu shows**
- Total active time today
- First screen-on time today
- All screen events with timestamps (▶ on / ■ off / ← left)
  - `← left HH:MM` = computed time user left (screensaver start - timeout from system settings)
  - Reads screensaver idle time from `com.apple.screensaver` ByHost prefs (`idleTime` or `lastDelayTime`)
- Current project
- Last check (time ago) + next check (time until + clock time)
- Interval selector submenu

## Data

All data written to:

```
~/Library/Application Support/BarTimeTracker/events.json
```

Format:

```json
{
  "screenEvents": [
    { "kind": "on",           "time": "2026-04-15T08:42:00Z" },
    { "kind": "screensaverOn","time": "2026-04-15T11:00:00Z" },
    { "kind": "screensaverOff","time": "2026-04-15T11:05:00Z" },
    { "kind": "off",          "time": "2026-04-15T18:00:00Z" }
  ],
  "projectEntries": [
    { "project": "ClientWork", "time": "2026-04-15T09:00:00Z" },
    { "project": "ClientWork", "time": "2026-04-15T09:15:00Z" }
  ]
}
```

Accumulates across days. Never truncated. Designed for report generation.

## Build & run

Requires macOS with Swift toolchain (`xcode-select --install`).

```bash
cd BarTimeTracker
./build.sh
open BarTimeTracker.app
```

**Auto-launch on login:** System Settings → General → Login Items → add `BarTimeTracker.app`.

## Menu example

```
Total on today: 7h 24m
First on: 8:42 AM
──────────────────
▶ on    8:42 AM
← left  10:40 AM     (screensaver started 11:00, timeout=20m)
▶ on    11:05 AM
■ off   6:00 PM
──────────────────
Project: ClientWork
Last check: 3 min ago
Next check: in 12 min (2:47 PM)
Check every… ▶  5 min
                15 min ✓
                30 min
                60 min
──────────────────
Quit
```

## Usage

| Action | Result |
|--------|--------|
| Click ⏱ icon | Open menu with today's events + project status |
| Set project… | Create new project entry now |
| Check every… | Set prompt interval (5 / 15 / 30 / 60 min) — persists across restarts |
| Popup → Save | Create timestamped project entry |
| Popup → Skip | No entry, next prompt scheduled |
| Popup → Esc | Same as Skip |
| Click in popup | Focus window to type / use dropdown |
