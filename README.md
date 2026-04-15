# BarTimeTracker

macOS menu bar app. Tracks screen on/off times and project work sessions. Always running, no dock icon.

## What it does

**Screen tracking**
- Detects screen wake and sleep via macOS system notifications
- Records timestamp for every on/off event
- Shows all today's events in menu
- Calculates total screen-on time for today

**Project tracking**
- Every 15 minutes: popup asks what you're working on
- Each answer (or manual set) creates a timestamped project entry
- Skips prompt if screen is off

**Menu shows**
- Total on-time today
- First screen-on time today
- All wake/sleep events with timestamps
- Current project

## Data

All data written to:

```
~/Library/Application Support/BarTimeTracker/events.json
```

Format:

```json
{
  "screenEvents": [
    { "kind": "on",  "time": "2026-04-15T08:42:00Z" },
    { "kind": "off", "time": "2026-04-15T12:00:00Z" }
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

## Usage

| Action | Result |
|--------|--------|
| Click ⏱ icon | Show today's screen events + project |
| Set project… | Create new project entry now |
| 15-min popup → Save | Create new project entry |
| 15-min popup → Skip | No entry created |
