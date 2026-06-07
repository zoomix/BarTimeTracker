---
name: project-algorithm-spans
description: BarTimeTracker buildTimeSpans algorithm redesign — entry-driven spans, not screen-event-driven
metadata:
  type: project
---

Rewrote `buildTimeSpans` in `TimeCalculations.swift` to be **entry-driven** (project-group transitions define span boundaries) rather than screen-event-driven (merge heuristic).

**Why:** Old algorithm produced coarse/incorrect spans — wrong boundaries for May28/29 and zero-duration garbage spans from brief on/off events.

**New algorithm:**
1. Group consecutive same-project entries into runs
2. Each group → one span
3. Span start = end of previous span (or firstOnTime for first)
4. Span end = first away event (screensaverOn or off) at/after last entry, before next group
   - If that away event is screensaverOn AND a hard off follows within 30 min (still before next group) → use the hard off instead
5. Last group: use first hard off only (screensaverOn = still active → isActive = true)

**Consequence:** spanCount changed for many test days (Jun1: 20→12, Jun2: 18→9, Apr16: 5→13, Apr17: 1→7, Apr19: 2→1). workedTime and projectDurations totals are preserved because spans are contiguous. All 36 tests pass.

**How to apply:** When adding new CSV test days, expect fine-grained project-transition spans, not coarse screen-session spans. Apr17 comment "everything merges into one span" is now outdated.
