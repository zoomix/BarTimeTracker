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

**Time spans**
- Raw on/off events collapsed into continuous work spans (e.g. `9:00 AM – 12:30 PM  (3h 30m)`)
- Gaps under 3 minutes merged (handles screen flicker / rapid lock-unlock)
- Each span is hoverable — submenu shows projects worked during that span with duration
- Duration attributed backwards: check-in at T claims `[prev check-in, T]` for its project
- Most recent check-in also claims forward to span end (still working on it)
- `diff  Xm` shown at bottom of submenu if span has unaccounted time

**Break handling**
- Popup → Break: marks the interval since last check-in as a break
- Break time is subtracted from **Worked today** total
- Deduction = only screen-on time overlapping the break claim (prevents over-subtraction when screen was already off during that period)
- Break entries appear in span submenu so you can see where time went

**End of day**
- "Log out for the day" stops all prompts, records a logout marker
- Persists across restarts — resets automatically next calendar day
- "Resume tracking" re-enables prompts and restarts the timer

**Menu shows**
- Worked today (screen on-time minus breaks)
- Work spans with per-project durations and diff markers
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
    { "project": "ClientWork", "time": "2026-04-15T09:15:00Z" },
    { "project": "Break",      "time": "2026-04-15T14:00:00Z" },
    { "project": "~logged out~","time": "2026-04-15T17:30:00Z" }
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
Worked today: 7h 24m
──────────────────
8:42 AM – 11:00 AM  (2h 18m)  ▶   ClientWork  2h 18m
11:05 AM – 6:00 PM  (6h 55m)  ▶   ClientWork  5h 10m
                                   Break       45m
                                   ───
                                   diff        1h 0m
──────────────────
Project: ClientWork
Last check: 3 min ago
Next check: in 12 min (2:47 PM)
Set project…
Check every… ▶
──────────────────
Log out for the day
──────────────────
Quit
```

Sentinel entries stored in JSON but never shown in menu: `~logged out~`, `~resumed~`.

## Usage

| Action | Result |
|--------|--------|
| Click ⏱ icon | Open menu with work spans + project status |
| Hover span | See per-project durations + any diff |
| Set project… | Create new project entry now |
| Check every… | Set prompt interval (5 / 15 / 30 / 60 min) — persists across restarts |
| Popup → Save | Log project; that interval attributed to it |
| Popup → Break | Mark interval as break; excluded from worked total |
| Popup → Skip | No entry, next prompt scheduled |
| Popup → Esc | Same as Skip |
| Log out for the day | Stop prompts for today; auto-resets next day |
| Resume tracking | Re-enable prompts mid-day |
