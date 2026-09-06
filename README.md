# Heli-Pad (Orbit Family Logistics)

[![Vercel Deployment](https://img.shields.io/badge/Deployed%20on-Vercel-black?style=flat&logo=vercel)](https://heli-pad.vercel.app)
[![Platform](https://img.shields.io/badge/Platform-Web%20%7C%20iOS%20PWA-indigo?style=flat)](#)
[![Zero Dependencies](https://img.shields.io/badge/Dependencies-Zero-emerald?style=flat)](#)

A modern, iOS-inspired mobile web application designed for stress-free family handoffs, activity relays, and parental coordination.

> **Architecture:** see [`SYSTEM.md`](./SYSTEM.md) for the system document (domain, integrations, evolution). This HTML app is the **UX / feature lab** — long-term production is not intended to remain HTML.


**Live Web App**: [https://heli-pad.vercel.app](https://heli-pad.vercel.app)

---

## Key Features

### "Next" Tab — Third Homepage Concept

An ivory and forest-green design centered on the next family handoff. Open
`index.html#next` or select **Next** in the bottom navigation.

- A trip card names the child, caregiver, origin, destination, leave-by time,
  and arrive-by time. Timing distinguishes using the buffer from arriving late.
- A daily agenda supports child filters, appointment details, editing, and
  completion. Earlier unconfirmed handoffs stay visible for review.
- "Who's got what?" shows each caregiver's handoffs and estimated driving
  minutes. Selecting a caregiver switches the agenda and trip card together.
- Driver suggestions use the existing sample scheduling logic. Changes go
  through the existing caregiver comparison and assignment dialog.
- A labeled preview clock defaults to 2:40 PM, with 3:00 PM, 3:15 PM, and live
  options. It does not change the Go or Today simulation clock.

The new design lives in `next-concept.css` and `next-concept.js`, shared by both
HTML entry points. It uses the existing local sample data; travel estimates,
calendar integration, and multi-user syncing remain prototype behavior.

### 0. "Go" Tab — At-a-Glance Departure View (Design Study)

A ground-up redesign of the Today content, built as a separate tab so the two
approaches can be compared side by side. Its premise: a parent reading this
screen is usually holding keys, so it answers one question — *do I need to move,
and when?* — and draws everything else as a mark rather than a sentence. Rebuilt
in the warm Next design language on 2026-09-05; see [`design.md`](./design.md).

- **Countdown Dial**: A live count on a forest / olive / clay tone card, drawn as a depleting SVG ring. Minutes inside the hour (`56 · min · to leave`), hours and minutes beyond it (`3h 21m`). Two channels, two facts: the card background says how urgent, the ring says how much run-up is left. It re-renders on the shared 5-second ticker.
- **Piecewise Ring**: One linear window cannot serve both "four hours out" and "eleven minutes out", so the final 60 minutes own 60% of the circle and everything earlier shares the other 40%, measured across the real gap (previous stop's end, or 6 AM). 411 min reads 90%, 56 min reads 56%, 11 min reads 11% — the arc is always moving, and it moves fastest where the decision lives.
- **One Highlight**: `#ffd36b`, reserved for `now` and `started` — leave now, or already late. The ring goes full and pulses; the colour appears nowhere else on the screen.
- **Defined State Matrix**: `later` · `ontrack` · `soon` · `now` · `started` · `nothing-left`, plus a no-travel variant that counts down to when everyone is together rather than to a departure that does not exist. Stops more than 20 minutes past their start roll off the dial and stay flagged on the rail, so a phone opened at 11 PM shows "Day is over · 3 never checked off" instead of a four-hundred-minute red alarm.
- **Two Scopes**: The dial always shows *my next departure, today* — nothing in the scope row moves it. The day strip, caregiver picker and child filter are all list controls, so looking ahead at Thursday or checking whether Dad has the 4:48 covered never costs you your countdown. The panel title names whose day is listed; the masthead keeps naming today.
- **Weather**: One ochre line icon in the masthead for today's sky — the only ambient fact on the screen. `goWeather()` is a lab stub over sample data; production reads a WeatherProvider port (WeatherKit on iOS). See `SYSTEM.md`.
- **Hero Swap**: The dial cycles through *my* stops. The dot rail under the card is the tap path; a horizontal drag is the accelerator. `Live` hands the dial back to the stop the clock actually points at.
- **Scope Swap**: One row stands in for a day strip, a crew strip, and a filter row. Each segment shows its current value as a mark plus a word and swaps the matching picker into a single drawer. It sits below the dial, so a filter never outranks leave-in.
- **Panel Swap**: The rest-of-day rail and the wheel-time chart share one slot behind a two-icon toggle, instead of stacking as two permanent modules.
- **Route Bar**: Departure and arrival as a hollow origin dot and a filled square destination, with a car marker that advances along the dashed line as the run-up elapses — the trip's shape at a glance, no prose.
- **Time Spine**: The day as a vertical rail of stops. The time column is the **arrival** — when the thing actually starts — and the derived departure rides inside the row as a `Leave 2:51 PM` line, so two different kinds of time never share one column. The title owns the whole flexible column, so activity names never truncate; only the venue may ellipsize. Children and the lead caregiver are named, not just badged — a pale disc carries the colour and the word beneath it carries the identity ("You" for your own stops, "Needs driver" when unassigned).
- **One Sheet for Add and Edit**: A sheet built from the screen's own parts — a live tone-card preview, five field rows, and the scope row's swap for the pickers. Tapping an existing stop opens the same sheet, seeded: "Edit stop", "Save changes", and a quiet "Remove this stop". Nothing is a blank field: an activity preset supplies the venue, travel mode and duration; the day comes from the list you were looking at; the driver is you; the title composes itself ("Noah Practice").
- **A ✎ Escape Hatch on Every Field**: A custom name, a custom place ("Somewhere else"), an exact time, and an exact duration — each revealed by the same ✎ affordance. Those inputs are the only things on the screen that open a keyboard.
- **No Leave-By While Composing**: The sheet shows when the stop starts and how long it runs, and says the leave-by is worked out from the rest of the day once saved. A departure needs to know where the caregiver is coming from, and at composition time the app does not — the rail is the only place that number is honest.
- **Add to Google Calendar**: A second outcome rather than a second form — it saves the stop and flags it for the calendar, showing a 📅 on the row. Calendar is read-only in v1 (`SYSTEM.md`), so the lab records the intent instead of pretending to have written; the conflict is logged as an open decision.
- **One-Tap Completion**: Tapping a stop's marker checks it off; tapping the row opens its details. Completing the dial's stop hands it back to the live one.
- **Wheel Time**: The day's driving split as one named, chart-strength bar per caregiver, sorted longest first, instead of a table of minutes.

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
