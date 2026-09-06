# Heli-Pad — System Document

**Status:** living draft (Task model confirmed 2026-09-05)  
**Product:** Orbit Family Logistics (heli-pad)  
**Live UX lab:** https://heli-pad.vercel.app  
**Repo:** `onepalebluedot/heli-pad`

## 1. Intent

Heli-Pad helps caregivers run the day: who has which kids, when to leave, and which Task is hottest right now.

**Long-term target**

- **iOS app first**, mobile only (phone layouts, not desktop)
- **Google Calendar** as the source of scheduled events (what / when / where)
- **Maps / routing** to estimate real driving distance and travel time between places
- Not a long-lived HTML production app

**Near-term approach**

- The current **HTML / CSS / JS prototype** is the **UX and feature lab**: fast iteration on screens, copy, urgency states, and flows
- System design and domain model live in this doc and guide whatever replaces HTML later
- Do not treat the monolith as the production architecture

## 2. Problem frame

Parents and caregivers need answers under time pressure:

1. What is my **hottest** Task right now (any kind — not only the next drive)?
2. **When do I leave**, given travel time and buffer?
3. **Who is driving**, and who else could cover?
4. What else is on the **day’s agenda**, filterable by caregiver and child?

The prototype already explores these questions; production must answer them with live calendar data and live travel estimates.

## 3. Current prototype (as of this draft)

| Asset | Role |
| --- | --- |
| `index.html` / `Orbit_Family_Logistics_Rebuilt.html` | Shell + Today / Go concepts (large single-file UI) |
| `next-concept.css` / `next-concept.js` | “Next” tab: trip card, agenda, crew, preview clock |
| Sample in-memory events | Mock family, places, ETAs — not synced |
| Vercel static deploy | Shareable UI demos |

**UI experiments (not yet frozen)**

- **Today** — list / progressive disclosure / swipe actions
- **Go** — countdown dial, travel bar, time spine (“do I need to move?”)
- **Next** — ivory / forest trip card + daily agenda + “who’s got what?”

Home-tab choice is still open; the lab may keep more than one concept until product picks a primary home.

**Prototype limits (known)**

- Hardcoded / sample travel minutes
- No Google Calendar sync
- No multi-user auth or shared family state
- No real geocoding or routing
- Preview clock is design-only and not persisted

## 4. Target product architecture

### 4.1 Principles

1. **Domain first** — UI shells change; handoff / trip / place semantics stay stable
2. **Calendar owns schedule** — logistics metadata (driver, done, buffer) is app-owned overlay
3. **Travel is computed** — never hardcode ETAs in production paths
4. **Offline-tolerant** — last-known agenda and ETAs work without network for the next few hours
5. **Mobile-only** — design and QA for phone; no desktop product commitment
6. **Honor the contract** — lab/ports implement design’s feature contracts or escalate; never silently approximate unsupported behavior

### 4.2 Logical layers

```
┌─────────────────────────────────────────┐
│  Presentation (SwiftUI or future shell) │  Next/Go/Today, agenda, family, settings
├─────────────────────────────────────────┤
│  Application / use cases                │  next handoff, leave-by, filters, assign
├─────────────────────────────────────────┤
│  Domain                                 │  Person, Place, Task, TripPlan, DayAgenda
├─────────────────────────────────────────┤
│  Ports                                  │  CalendarProvider, TravelEstimator, MapsLauncher, Store
├─────────────────────────────────────────┤
│  Adapters                               │  Google Calendar API, MapKit/Directions, SwiftData, …
└─────────────────────────────────────────┘
```

HTML lab today collapses most of this into one file; the layers above are the migration target, not a description of the current code.

### 4.3 Domain model

**Person**

- Caregiver or child
- Display name, role, optional avatar / color

**Active viewer** (first-class facet — hard boundary)

- The caregiver whose day the UI is computing: agenda, hottest Task, glanceables, and notify state are **per viewer**, never a household mash with a swapped label
- **Production:** viewer is sticky (mom stays mom for that install/session identity)
- **Lab:** viewer is switchable (mom / dad / …) so each caregiver’s unique aspects can be tested independently
- Filters (child facet, etc.) apply *within* the active viewer’s frame; they do not merge other caregivers’ chrome into the hero
- Sync / overlays / push key off viewer + assignee the same way (no leaking mom’s chrome into dad’s view)

**Place**

- Stable id, display name
- Address and/or lat/lng
- Kind: home, school, activity venue, other
- Owned or shared within a family

**Task** (confirmed root coordination unit — v1)

- Kinds include at least: `drive` · `cook` · `lead` · `placeholder` (and related caregiver coordination)
- Links to external calendar event id(s) when the schedule came from Calendar (optional)
- Title, start/end (or soft window for placeholders)
- Children / people involved as needed
- **Overlays** (app + shared backend): assignee, done/confirm, buffer, notes — not stored in Google Calendar for v1
- Optional **travel facet**: origin Place → destination Place, mode (drive, walk, home/no-travel, …)
- Travel / TripPlan apply only when the kind (or facet) needs them — e.g. cook/lead may have none

**Handoff** (view, not a separate root)

- Drive-shaped projection of a `Task` with a travel facet: used by leave-by, urgency, and TripPlan inputs
- Prefer speaking “drive task” in APIs; “handoff” remains valid UX language from the lab

**TripPlan** (derived)

- `departBy`, `travelMinutes`, `arriveBy`
- Buffer vs late margin
- Urgency tone: e.g. `later` · `ontrack` · `soon` · `now` · `started` · `nothing-left` · `late` · `driver-needed`
- Inputs: wall clock (or lab preview clock), Task (+ travel facet), TravelEstimator result
- Only computed when the Task needs travel

**DayAgenda**

- Ordered Tasks for a calendar day **for the active viewer** (all kinds in their frame)
- Filters: caregiver facet, child facet
- Includes unconfirmed / past-due items the UX chooses to keep visible

**Family**

- Membership of people and shared places
- Shared backend is source of truth for Task overlays and multi-caregiver “keep each other informed” (v1)
- Invites / fine-grained permissions: evolve after first sync path works

### 4.4 Core use cases

| Use case | Behavior |
| --- | --- |
| Sync day | Pull Google Calendar events; upsert Tasks (preserve overlays); sync overlays via shared backend |
| Resolve places | Map event / task locations to Places (geocode / user pick); remember mappings |
| Estimate travel | When Task has a travel facet: origin → destination minutes for assignee context |
| Compute hottest | Given **active viewer** + filters + clock, pick that viewer’s **hottest Task** of any kind for the home hero (+ TripPlan if travel) |
| Suggest assignee | Rank available caregivers (lab heuristics → production rules); drive tasks emphasize drivers |
| Assign | Write Task overlay (shared backend); Calendar stays read-only in v1 |
| Complete / confirm | Mark Task done or needs follow-up (synced overlay) |
| Leave reminder | For travel Tasks: local + shared-aware departBy notifications, scoped to the relevant viewer/assignee |

### 4.5 Integration ports

**CalendarProvider (Google Calendar)**

- OAuth for the signing-in caregiver (v1: one account; later: family-linked calendars)
- Read events in a rolling window (e.g. today ± N days)
- Optional later: write annotations / secondary logistics calendar
- v1: Calendar is **read-only**; assignee / done / buffer live on Task overlays in the shared backend (no Calendar writeback required for first ship)

**TravelEstimator**

- Input: origin + destination coordinates (or Place ids), departure time if needed
- Output: duration (+ optional distance, traffic-aware when available)
- Preferred on-device path for iOS: MapKit / Apple Directions where it meets accuracy needs
- Alternate: Google Directions API if product requires Google-consistent ETAs
- Cache results with TTL; invalidate on place or schedule change

**MapsLauncher**

- Deep-link to Apple Maps and/or Google Maps for turn-by-turn
- Pass origin, destination, transport mode
- Estimation stays in-app; navigation may leave the app

**Store**

- Local persistence of People, Places, Tasks (+ overlays cache), cached TripPlans; shared backend is multi-caregiver source of truth for overlays
- Survive offline / cold start

**WeatherProvider**

- Input: date + the family's home (or destination) coordinates
- Output: one condition token (`sun` · `partly` · `cloud` · `rain` · `storm` · …) plus a human label and temperature
- Preferred on-device path for iOS: WeatherKit
- Cache with a TTL and refresh on the same cadence as the day sync; a stale icon is acceptable, a missing one is fine
- Ambient only — it never changes a plan, a departure, or an assignment. Go renders it as a single masthead icon (`goWeather()` is the lab stub)

**ArrivalDetector** (not built — recorded for a later pass)

- Input: the destination Place for an active Task + the device's location
- Output: an arrival signal that **auto-completes the Task** instead of waiting for a tap
- Rationale: completion is the action a caregiver is least likely to perform — they are at the field, with a child, and the phone is in a pocket
- Preferred iOS path: region monitoring / significant-location change (background-friendly, low power); not continuous GPS
- Requires an explicit, revocable permission; the manual tap stays as the fallback, since a handoff can happen without the assignee's phone arriving
- Interacts with the shared overlay: an auto-complete is still a synced overlay write, and other caregivers should see who/what completed it

**Notifier**

- Local notifications for leave-by and driver-needed
- Respect iOS permission and focus modes

## 5. Information flow (happy path)

1. User opens app → Store shows last synced DayAgenda immediately
2. CalendarProvider refreshes → schedule-backed Tasks upserted; shared backend refreshes overlays
3. Missing Place coords → geocode / prompt
4. TravelEstimator fills travel minutes for Tasks with a travel facet
5. Use cases recompute urgency (+ TripPlans when needed)
6. Home UI (Today playground first) renders **active viewer**’s hottest Task hero (any kind) + that viewer’s agenda
7. User taps navigate → MapsLauncher (travel Tasks)
8. User marks complete / reassigns → shared backend overlay; UI advances

## 6. Non-goals (near term)

- Android / web production clients
- Broad multi-family SaaS beyond the shared Task-overlay backend needed for multi-caregiver sync
- Replacing Google Calendar as the scheduling UI for creating school/activity events
- Desktop layouts
- Shipping all three home concepts as equal product surfaces

## 7. Decisions & open items

### Confirmed (2026-09-05)

| Decision | Call |
| --- | --- |
| Root model | Broader **`Task`** with kinds `drive` · `cook` · `lead` · `placeholder` · …; travel is an **optional facet** |
| Handoff | Drive-shaped view / TripPlan input — not a separate root entity |
| Sync | **Shared backend** for multi-caregiver overlays + informed state; not on-device-only |
| Calendar v1 | **Read-only**; Task overlays sync via backend |
| Home hero | **Hottest Task** (any kind) — not “next drive/handoff” only |
| Active viewer | First-class facet: sticky in production, switchable in lab; agenda / hero / notify are per caregiver, not label-swapped household chrome |
| Design ↔ eng contract | Today ports must honor: hottest Task hero, shared overlays/notify, per-viewer chrome, travel only when needed — escalate gaps to Software Lead; do not silently approximate |
| Phone input | Swipe where it fits with **tap primary** for critical actions — not tap-only, not swipe-only |
| Near-term UX priority | **Home tab first** — Today as playground; Go/Next as controls until Lena’s test wins |
| Out of scope now | AI recommendations/automation; side surfaces; chrome freeze before Lena |

### Today gesture contract (Lena amend — Samira pressure-test)

Gate Avery’s Today port against this map; escalate gaps — do not approximate.

| Gesture / layout | Rule |
| --- | --- |
| Critical actions | **Tap remains primary** (complete/done, Send on Tell-the-crew, etc.) |
| Tell-the-crew swipe-down | Returns to **Edit only** — never skip Send, never silent discard |
| Snooze ≥ 10 min | Still routes through **Tell-the-crew** (crew must be informed) |
| Week / filters | Must **not** sit above the leave-in dial |
| Other swipes | done, snooze, lab viewer switch, dismiss notify, agenda peek — where they fit, with tap fallbacks |

### Still open

| Decision | Options | Notes |
| --- | --- | --- |
| Production client | Native SwiftUI vs hybrid (Capacitor) wrapping lab | Lab stays HTML either way; freeze waits on Lena + John |
| Primary home chrome | Today playground vs winning Go/Next control | Implement against Today first; no merge of chrome until Lena |
| Travel provider | MapKit vs Google Directions | Product may want Google ETAs to match Maps app choice |
| Depart-by audience | Assignee-only vs every caregiver | Avery to spike with shared push once sync shape lands |
| Exact Task kind enum | Final set / naming beyond the confirmed list | Keep extensible; ship drive-shaped UX first while model stays broad |
| Weather provider | WeatherKit vs a web forecast API | Ambient icon only for now; picking a provider can wait until after the home freeze |
| **Calendar write-back** | Keep v1 read-only vs add a write path | **Conflict to resolve.** Go's new-stop sheet now offers "Add to Google Calendar", which the confirmed "Calendar v1: read-only" decision does not support. The lab records the intent on the Task overlay (`gcal: true`) and shows it on the row rather than approximating a write. Product must either grant v1 a write path (scoped to a Heli-Pad secondary calendar), defer the button, or re-label it as a queued intent |
| Arrival auto-complete | Region monitoring vs manual only | Needs a location permission and a story for handoffs where the assignee's phone does not arrive; manual tap stays regardless |

## 8. Evolution path

1. **Lab** — continue HTML for UX/feature discovery (current repo)
2. **System doc** — this file; update when domain or integrations change
3. **Home-tab lab** — Today playground; Go/Next as controls; no chrome freeze until Lena
4. **Shared sync spike** — Task overlays + push; Calendar read-only
5. **Skeleton app** — Task domain + fake CalendarProvider / TravelEstimator / SyncStore
6. **Live adapters** — Google Calendar OAuth + real routing + shared backend
7. **Hardening** — notifications, offline TTL, place mapping, kind coverage beyond drive UX

## 9. Doc ownership

- Software Lead maintains this document
- Escalate to Marcus Hale (EM) on scope/timeline tradeoffs (client stack, sync scope eating home-tab week, home freeze)
- Prototype README remains the lab feature narrative; this doc is the system of record for architecture
