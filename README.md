# Heli-Pad (Orbit Family Logistics)

[![Vercel Deployment](https://img.shields.io/badge/Deployed%20on-Vercel-black?style=flat&logo=vercel)](https://heli-pad.vercel.app)
[![Platform](https://img.shields.io/badge/Platform-Web%20%7C%20iOS%20PWA-indigo?style=flat)](#)
[![Zero Dependencies](https://img.shields.io/badge/Dependencies-Zero-emerald?style=flat)](#)

A modern, iOS-inspired mobile web application designed for stress-free family handoffs, activity relays, and parental coordination.

**Live Web App**: [https://heli-pad.vercel.app](https://heli-pad.vercel.app)

---

## Key Features

### 0. "Go" Tab — At-a-Glance Departure View (Design Study)

A ground-up redesign of the Today content, built as a separate tab so the two
approaches can be compared side by side. Its premise: a parent reading this
screen is usually holding keys, so it answers one question — *do I need to move,
and when?* — and draws everything else as a mark rather than a sentence.

- **Countdown Dial**: A depleting SVG ring carries the state through color rather than text — cool (more than an hour out, showing the clock time to leave), green (on track), amber (inside 15 minutes), red (leave now / already started). The ring is pinned full outside the 60-minute run-up so it never reads as empty-and-broken, and it re-renders on the shared 5-second ticker.
- **Defined State Matrix**: `later` · `ontrack` · `soon` · `now` · `started` · `nothing-left`. Stops more than 20 minutes past their start roll off the dial and stay flagged on the rail, so a phone opened at 11 PM shows "Nothing left to drive · 3 stops never checked off" instead of a four-hundred-minute red alarm.
- **Travel Bar**: Departure and arrival as two anchors with a car marker that advances along the line as the run-up elapses — the trip's shape at a glance, no prose.
- **Time Spine**: The day as a vertical rail of stops. The title owns the whole flexible column, so activity names never truncate; only the venue may ellipsize. Driver identity is an avatar, children are emoji, transit mode is an icon.
- **One-Tap Completion**: Tapping a stop's marker checks it off; tapping the row opens it. The dial then advances to the next departure on its own.
- **Wheel Time Bar**: The day's driving split drawn as one proportional bar of caregiver-colored segments instead of a table of minutes.
- **Single Caregiver Source**: The crew strip writes to the same `state.currentUser` as the header switcher. This screen deliberately adds no second caregiver filter of its own.

### 1. Dynamic Next Departure Hero
- **Real-Time Urgency Countdown**: Reads clock time and calculates dynamic departure alerts (`⏱ Leave in 18 min`, `⏱ Leave in 3 min` with pulse animation, and prominent `🚨 Past Departure` warnings).
- **Multi-Child Badges**: Prominently highlights which children are participating in each event with dedicated tag pills.
- **Arrive-By vs. Depart-By Grid**: Clear distinction between the activity arrival deadline and the required departure time based on travel duration from the caregiver's origin.
- **Role-Aware Personalization**: Switch the active caregiver profile (Mom, Dad, Nani, Grandma, Family) to view that caregiver's specific next departure.
- **Celebration All-Clear State**: Transforms into a cheerful completion card once all departures for the day are finished, previewing the next day's upcoming morning trip.

### 2. iOS-Native Timeline & Progressive Disclosure
- **Compact List Rows (~58px Resting Height)**: Replaces bloated cards with sleek iOS list rows displaying only the essentials at rest:
  - Leading: Clean circular completion checkbox (Things 3 / Apple Reminders style).
  - Primary Line: `Time Range` · `Activity Title`.
  - Secondary Line: `Child Badge`, `Driver Avatar + Role`, `Transit Mode`, and alert badges (`⚠ Driver Needed` or `⚠ Conflict`).
  - Trailing: Target departure time and animated disclosure chevron (`›`).
- **Progressive Disclosure Accordion Drawer**: Tapping any row smoothly expands an inline drawer revealing:
  - Route Journey Strip: `Origin ➔ Travel ETA ➔ Destination Venue`.
  - Commute buffer and slack analysis (e.g. `15 min buffer after prior drop-off`).
  - Contextual action drawer (`[✎ Edit Details]`, `[🗑 Delete]`, and `[⚡ Assign Driver]`).

### 3. iOS Swipe-to-Reveal Gestures
- **Swipe-to-Reveal Actions**: Swiping a row left (touch swipe on mobile or click-drag on desktop) shifts the row to reveal native-style `[✎ Edit]` and `[🗑 Delete]` action buttons.
- **Clean Resting State**: Destructive and secondary edit actions stay hidden at rest, keeping the timeline calm and focused on completion.

### 4. Hero & Timeline De-Duplication
- **Up Next Anchor Row**: The activity featured in the Next Departure Hero card is styled in the timeline as a streamlined anchor (`⚡ Up Next · Featured in Departure Card above`).
- Eliminates redundant 180px duplicate cards back-to-back while maintaining the chronological sequence of the day's schedule.

### 5. Two-Facet Segmented Filter (Caregiver & Child)
- **Caregiver Facet**: `All` | `Mom` | `Dad` | `Nani` | `Grandma` (with color-coded avatar pills).
- **Child Facet**: `All Kids` | `🎒 Soni` | `🎨 Maya` | `⚽ Noah`.
- **Multi-Facet Cross-Filtering**: Enables queries like *"Show Mom's rides for Maya"* or *"Show all drivers for Noah"* without messy horizontal scrolling.

### 6. Unified "Smart Dispatch" Suggestions Hub
- Merges fragmented AI banners, card driver calls, and auto-balance triggers into a single intelligent suggestions center.
- **Smart Dispatch Status**: Dynamically calculates unassigned drivers, route overlaps, and commute delays (`✦ Smart Dispatch · X Actions Available`).
- **Proximity-Aware Candidate Recommendations**: Evaluates driver origins, travel times, and existing commitments to recommend the best caregiver with delay warnings and conflict flags.
- **One-Tap Auto-Balance**: Rebalances lead drivers across the week based on proximity and equity.

### 7. Tactile Add/Edit Activity Modal
- **7-Day Date Selector**: Day pills with a `TODAY` indicator badge.
- **Quick-Set Time Presets**: Single-tap shortcuts for routine family logistics (`7:35 AM Drop-off`, `3:15 PM Pickup`, `4:30 PM Sports`, `5:30 PM Lesson`, `6:30 PM Dinner`).
- **Duration Stepper Chips**: `+30m`, `+45m`, `1 hr`, `1.5 hrs`, `2 hrs` duration chips that calculate and format end times automatically.
- **Zero-Dropdown Caregiver Grid**: Tactile button push grid for `Mom`, `Dad`, `Nani`, `Grandma`, `Family`, and `Needs Driver (TBD)`.
- **Transit Mode Pills**: `🚗 Drive`, `🚶 Walk`, `👥 Carpool`, `🚌 School Bus`, `⌂ Stay Home`.

### 8. Sunday Reset Sprint & Workload Balancing
- Weekly calibration checklist for external school calendars, sports portals, and buffer rules.
- Behind-the-wheel driving minute distribution tracker between Mom and Dad.
- Saved venue directory with parking ease ratings and loading buffers.

---

## Architectural Notes for Native iOS Port

When migrating this prototype to native Swift / SwiftUI:
1. **MapKit & MKDirections**: The prototype's static `routeMatrix` lookup table will be replaced by `MKDirections.Request` with real-time traffic ETAs and Apple Maps turn-by-turn routing.
2. **CoreLocation**: User and venue coordinates will be backed by `CLGeocoder` and live device GPS.
3. **EventKit / Reminders**: Calendar synchronization will link directly into Apple Calendar and Reminders APIs.
4. **Prototype Scaffolding**: The `.demo-sim-strip` (Live Clock and Day scrubber) is strictly marked as prototype test scaffolding and will not be carried into the native iOS shell.
5. **Go Tab Mapping**: The countdown dial is a `TimelineView(.periodic)` driving a trimmed `Circle()` stroke; the time spine is a `List` with `.swipeActions`; the whole dial is the natural source for a Live Activity / Dynamic Island and a Watch complication, since it is already reduced to one number and one color.
6. **Departure Clamping**: `calculateDayPlan` can return a negative `departBy` for an early event with a long ETA, which `minutesToTime` would wrap into a late-night time. The Go screen floors this at midnight (`goSafeDepart`); the native model should make departure a real date rather than minutes-since-midnight and drop the wrap entirely.

---

## Getting Started

### Local Development
Open `index.html` directly in any modern browser. There are no build tools, bundlers, or external dependencies required.

```bash
# Clone the repository
git clone https://github.com/onepalebluedot/heli-pad.git

# Navigate to project directory
cd heli-pad

# Open index.html in your browser or run a simple local server
python3 -m http.server 8080
```

### Production Deployment
The repository is deployed automatically to Vercel upon pushing to the `main` branch:
- Production URL: [https://heli-pad.vercel.app](https://heli-pad.vercel.app)
