# Heli-Pad — System Document

**Status:** living draft  
**Product:** Orbit Family Logistics (heli-pad)  
**Live UX lab:** https://heli-pad.vercel.app  
**Repo:** `onepalebluedot/heli-pad`

## 1. Intent

Heli-Pad helps caregivers run the day: who has which kids, when to leave, and whether the next handoff is still on track.

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

1. What is my **next** handoff?
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

### 4.2 Logical layers

```
┌─────────────────────────────────────────┐
│  Presentation (SwiftUI or future shell) │  Next/Go/Today, agenda, family, settings
├─────────────────────────────────────────┤
│  Application / use cases                │  next handoff, leave-by, filters, assign
├─────────────────────────────────────────┤
│  Domain                                 │  Person, Place, Handoff, TripPlan, DayAgenda
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
- Caregivers can be “active viewer” (whose day am I looking at?)

**Place**

- Stable id, display name
- Address and/or lat/lng
- Kind: home, school, activity venue, other
- Owned or shared within a family

**Handoff** (logistics view of a calendar event)

- Links to external calendar event id(s)
- Title, start/end (arrive-by typically = event start for activities)
- Children involved
- Assigned driver (caregiver) or `TBD`
- Origin place → destination place
- Mode: drive, walk, home/no-travel, …
- Completion / confirmation state (app overlay)

**TripPlan** (derived)

- `departBy`, `travelMinutes`, `arriveBy`
- Buffer vs late margin
- Urgency tone: e.g. `later` · `ontrack` · `soon` · `now` · `started` · `nothing-left` · `late` · `driver-needed`
- Inputs: wall clock (or lab preview clock), Handoff, TravelEstimator result

**DayAgenda**

- Ordered handoffs for a calendar day
- Filters: caregiver facet, child facet
- Includes unconfirmed / past-due items the UX chooses to keep visible

**Family**

- Membership of people and shared places
- Future: invites, roles, permissions (out of scope for first ship)

### 4.4 Core use cases

| Use case | Behavior |
| --- | --- |
| Sync day | Pull Google Calendar events for the family calendars; upsert Handoffs; preserve local overlays |
| Resolve places | Map event locations to Places (geocode / user pick); remember mappings |
| Estimate travel | Origin → destination travel minutes for the assigned (or suggested) driver context |
| Compute next | Given viewer + filters + clock, pick next actionable handoff + TripPlan |
| Suggest driver | Rank available caregivers (existing prototype heuristics → production rules) |
| Assign driver | Write overlay; optionally write back a Calendar annotation later |
| Complete / confirm | Mark handoff done or needs follow-up |
| Leave reminder | Schedule local notification at departBy − ε |

### 4.5 Integration ports

**CalendarProvider (Google Calendar)**

- OAuth for the signing-in caregiver (v1: one account; later: family-linked calendars)
- Read events in a rolling window (e.g. today ± N days)
- Optional later: write annotations / secondary logistics calendar
- App never treats Calendar as the store for driver assignment or completion unless we explicitly design that writeback

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

- Local persistence of People, Places, Handoff overlays, cached TripPlans
- Survive offline / cold start

**Notifier**

- Local notifications for leave-by and driver-needed
- Respect iOS permission and focus modes

## 5. Information flow (happy path)

1. User opens app → Store shows last synced DayAgenda immediately
2. CalendarProvider refreshes → Handoffs updated
3. Missing Place coords → geocode / prompt
4. TravelEstimator fills travel minutes for upcoming drive handoffs
5. Use cases recompute TripPlans and urgency
6. Home UI renders next handoff + agenda
7. User taps navigate → MapsLauncher
8. User marks complete → Store overlay; UI advances to next

## 6. Non-goals (near term)

- Android / web production clients
- Full multi-family SaaS backend (unless sync requirements force a thin API later)
- Replacing Google Calendar as the scheduling UI for creating school/activity events
- Desktop layouts
- Shipping all three home concepts as equal product surfaces

## 7. Open decisions

| Decision | Options | Notes |
| --- | --- | --- |
| Production client | Native SwiftUI vs hybrid (Capacitor) wrapping lab | Native favored for Calendar, background alerts, maps; lab stays HTML either way |
| Primary home | Next vs Go vs Today | Keep others as lab tabs until frozen |
| Travel provider | MapKit vs Google Directions | Product may want Google ETAs to match Maps app choice |
| Family sync | On-device only vs shared backend | Multi-caregiver truth needs a sync story beyond one Google account |
| Calendar writeback | Read-only vs write driver/notes | Start read-only + local overlay |

## 8. Evolution path

1. **Lab** — continue HTML for UX/feature discovery (current repo)
2. **System doc** — this file; update when domain or integrations change
3. **Freeze** — one home concept + native-vs-hybrid call
4. **Skeleton app** — domain + fake CalendarProvider + fake TravelEstimator driving SwiftUI (or chosen shell)
5. **Live adapters** — Google Calendar OAuth + real routing
6. **Hardening** — notifications, offline, place mapping UX, multi-caregiver sync

## 9. Doc ownership

- Software Lead maintains this document
- Escalate to Engineering Manager on scope/timeline tradeoffs (client stack, sync backend, home freeze)
- Prototype README remains the lab feature narrative; this doc is the system of record for architecture
