# Heli-Pad — Build specification

**Status:** draft for review · written 2026-09-06 · not yet approved by Software Lead
**Audience:** a developer, or an AI agent, taking Heli-Pad from UX lab to a working product.

---

## 0. How to use this document

Three documents govern this project, and they do not overlap:

| Document | Answers | Authority |
| --- | --- | --- |
| [`SYSTEM.md`](./SYSTEM.md) | *What is this and what are the rules?* Domain model, confirmed decisions, ports, non-goals. | **System of record.** If this file and SYSTEM.md disagree, SYSTEM.md wins and this file is wrong. |
| [`design.md`](./design.md) | *What must it look and behave like?* The warm design language, the Go and Next screens, the graphic-first direction. | **Visual and interaction contract.** |
| **This file** | *How do we actually build it?* Stack, schemas, API shapes, integration mechanics, phases. | Proposal. Everything here is implementable; some of it needs a product decision first, marked **[DECIDE]**. |

The HTML in `index.html` is the **UX lab**, not the architecture. Read it for behaviour, never for structure. Where this document says "the lab does X", it means "the intended behaviour is X, and you can see it working there".

**Two surfaces are in scope, and the choice between homes is settled.** SYSTEM.md records *Primary home chrome: resolved — Go selected by product owner*. **Go** is the daily execution screen (`index.html`, the `"GO" SCREEN` block and `renderGo()`); **Plan** is its weekly companion (`plan.css`, `plan.js`, `plan-core.js`), and it already carries the week overview, the review and rebalance sheets, and a labelled local preview of two-way calendar sync. Next and Today are reference experiments and are not being ported.

**If you are an AI agent building from this file:** work in the phase order in §12. Do not start a phase before its predecessor's acceptance criteria pass. Do not invent product decisions — the items marked **[DECIDE]** are for a human. When the lab and this file disagree on behaviour, the lab is the reference implementation; when they disagree on structure, this file is.

---

## 1. What we are building

A phone app that answers one question under time pressure: **do I need to move, and when?**

The lab has established the answer's shape — a countdown to a departure that the app computes rather than the parent, a day list that can show anyone's schedule, and a create/edit flow that takes two taps. What it has not established is where any of the data comes from. Today every event, travel time, and forecast is hardcoded. This document is about replacing all of it with real sources without changing a single thing about how the screen behaves.

**The bar for "functional":**

1. A caregiver signs in, connects Google Calendar, and sees today's real schedule.
2. The leave-by time is computed from a real routing service, and is right often enough to be trusted.
3. A second caregiver in the same family sees the same schedule, and sees it when the first one reassigns a drive.
4. The phone tells you when to leave without being opened.
5. It works on the school run with one bar of signal.

Point 5 is not a nice-to-have. Every design decision in `design.md` assumes the screen is read in a hurry, and a spinner is not a countdown.

---

## 2. Target shape

```
┌───────────────────────────────────────────────────────────┐
│  iOS client (SwiftUI)                                     │
│                                                            │
│   Presentation   Go · Next · Today · Family · Settings     │
│   Use cases      hottest task · leave-by · assign · sync   │
│   Domain         Person Place Task TripPlan DayAgenda      │
│   Ports          Calendar Travel Weather Store Notifier    │
│   Adapters       ┌────────┬─────────┬────────┬─────────┐   │
│                  │SwiftData│ MapKit │Weather │ APNs    │   │
│                  └────────┴─────────┴────────┴─────────┘   │
└───────────────────────┬───────────────────────────────────┘
                        │ HTTPS (family sync + calendar)
┌───────────────────────▼───────────────────────────────────┐
│  Backend                                                   │
│   Auth · Family membership                                 │
│   Task overlays (assignee, done, buffer, notes)            │
│   Google Calendar custody: tokens, sync, webhooks           │
│   Push fan-out                                             │
└────────────────────────────────────────────────────────────┘
```

### 2.1 Client

**[DECIDE]** SYSTEM.md leaves the production client open: native SwiftUI vs a hybrid wrapping the lab.

**Recommendation: native SwiftUI.** Three of the app's defining behaviours are cheap natively and awkward otherwise — a Live Activity / Dynamic Island showing the countdown, a Watch complication, and region monitoring for arrival auto-complete (§9). The dial is already `TimelineView(.periodic)` driving a trimmed `Circle()`; the rail is a `List` with `.swipeActions`. The lab's value was never its code.

The cost is that `design.md` must be re-implemented rather than reused. Budget for that honestly: the Go screen is roughly 900 lines of CSS worth of decisions.

### 2.2 Backend

**[DECIDE]** Firebase vs a custom service.

**Recommendation: Firebase** (Auth + Firestore + Cloud Functions + FCM/APNs). The reasons are specific, not fashion:

- Google OAuth token custody and Calendar webhooks need a server *anyway*. Cloud Functions is the least server that does it.
- Firestore's offline cache and listener model is close to what §10 needs, so we write less sync code.
- A family is 2–6 people. There is no scale problem to solve, and paying for one with operational complexity would be a mistake.

**The alternative** — Node/TypeScript + Postgres on Fly.io or Render — is better if the team is already fluent in it, or if the shared-overlay query patterns turn out to want SQL. The rest of this document is written so either works: §4 defines the API surface, and Firestore is one implementation of it.

---

## 3. Domain model

Concrete shapes. Field names are normative — the lab, this file, and the client should agree.

### 3.1 Task

The root coordination unit (confirmed in SYSTEM.md). A drive is a Task with a travel facet, not a separate type.

```ts
type TaskKind = 'drive' | 'cook' | 'lead' | 'placeholder';

interface Task {
  id: string;                    // ours, stable across calendar edits
  familyId: string;

  // ── Schedule (from Calendar when linked, else authored in-app) ──────────
  title: string;
  startsAt: string;              // RFC3339 with offset, e.g. 2026-09-06T15:20:00-04:00
  endsAt: string;
  allDay: boolean;
  timeZone: string;              // IANA, e.g. America/New_York

  source: 'google' | 'app';
  sourceCalendarId?: string;
  sourceEventId?: string;        // Google event id
  sourceRecurringEventId?: string;
  sourceEtag?: string;           // for change detection
  sourceUpdatedAt?: string;

  // ── Who and where ───────────────────────────────────────────────────────
  kind: TaskKind;
  childIds: string[];            // [] means "the whole family"
  placeId?: string;              // resolved Place
  rawLocation?: string;          // the calendar's location string, unresolved

  // ── Travel facet (present only when the kind needs it) ──────────────────
  travel?: {
    mode: 'drive' | 'walk' | 'carpool' | 'bus';
    originPlaceId?: string;      // usually derived: previous task's place, else home
  };

  // ── Overlay: ours, never Google's ───────────────────────────────────────
  assigneeId: string | null;     // null = needs a driver
  status: 'open' | 'done' | 'skipped';
  bufferMinutes: number | null;  // null = family default
  note?: string;
  calendarPush?: {               // set when a user asked for Google write-back
    requestedBy: string;
    requestedAt: string;
    state: 'queued' | 'written' | 'failed';
    writtenEventId?: string;
  };

  updatedAt: string;
  updatedBy: string;             // personId
}
```

**Why the split matters.** Everything above the overlay line is replaceable from Google on every sync. Everything below it is ours and must survive that sync. A merge that loses `assigneeId` because somebody edited the event title on their laptop is the single worst bug this app can have.

### 3.2 Person, Place, Family

```ts
interface Person {
  id: string;
  familyId: string;
  role: 'caregiver' | 'child';
  displayName: string;
  shortName: string;             // the initial or two letters on a disc
  colorToken: string;            // 'mom' | 'dad' | 'nani' | ... → design.md palette
  emoji?: string;                // children only; see design.md on identity
  userId?: string;               // caregivers who have signed in
  homePlaceId?: string;
  defaultOriginPlaceId?: string; // where they usually leave from on a weekday
}

interface Place {
  id: string;
  familyId: string;
  name: string;
  address?: string;
  lat?: number;
  lng?: number;
  kind: 'home' | 'school' | 'venue' | 'work' | 'other';
  iconToken?: string;
  aliases: string[];             // calendar location strings that map here
  parkingMinutes?: number;       // walk from car to door; folded into buffer
}

interface Family {
  id: string;
  name: string;
  memberIds: string[];
  defaultBufferMinutes: number;  // lab default: 12
  homePlaceId: string;
  timeZone: string;
}
```

### 3.3 TripPlan (derived, never stored as truth)

```ts
interface TripPlan {
  taskId: string;
  originPlaceId: string;
  departBy: string;              // RFC3339
  travelMinutes: number;
  arriveBy: string;
  bufferMinutes: number;
  urgency: 'later'|'ontrack'|'soon'|'now'|'started'|'late'|'driver-needed'|'nothing-left';
  estimatedAt: string;
  estimateSource: 'mapkit' | 'google' | 'cache' | 'fallback';
  stale: boolean;                // true when served from an expired cache
}
```

Cache TripPlans, but always recompute urgency from the live clock. A cached urgency is a wrong urgency within a minute.

---

## 4. Backend API

Whatever the implementation, this is the surface the client codes against. Nine endpoints.

```
POST   /v1/auth/session              exchange an ID token for a session
GET    /v1/family                    family, people, places
PATCH  /v1/family                    buffer, home, timezone
POST   /v1/family/invite             create a join code
POST   /v1/family/join               redeem one

GET    /v1/tasks?from=&to=           tasks in a window (merged schedule + overlay)
PATCH  /v1/tasks/:id                 overlay fields only
POST   /v1/tasks                     app-authored task
DELETE /v1/tasks/:id                 app-authored only; calendar-sourced tasks hide, never delete

POST   /v1/calendar/connect          begin Google OAuth
DELETE /v1/calendar/connect          revoke and forget tokens
POST   /v1/calendar/sync             force a sync (the client should rarely need this)
POST   /v1/calendar/push/:taskId     write an app-authored task to Google  [DECIDE, §5.4]

GET    /v1/weather?date=&placeId=    forecast for a day
POST   /v1/devices                   register a push token
```

**`PATCH /v1/tasks/:id` accepts overlay fields only.** Reject `title`, `startsAt`, `sourceEventId` and friends with `409` when `source === 'google'`. This is the API-level guard behind §3.1's warning, and it should exist even though the client will not try.

Firestore implementation note: the reads become collection listeners rather than `GET`s, which is most of why Firestore is recommended. The writes stay as callable functions so the guard above lives in one place.

---

## 5. Google Calendar

### 5.1 OAuth

Scopes, minimum first:

| Scope | Why | Phase |
| --- | --- | --- |
| `.../auth/userinfo.email` | identify the account | 1 |
| `.../auth/calendar.readonly` | read events | 1 |
| `.../auth/calendar.calendarlist.readonly` | let the user pick which calendars matter | 1 |
| `.../auth/calendar.events` | write-back | only if §5.4 is approved |

Use the system browser (`ASWebAuthenticationSession`), PKCE, and offline access for the refresh token. **The refresh token never touches the device.** The client gets a session; the backend holds Google credentials, encrypted at rest, and does every Calendar call.

### 5.2 Reading

```
GET /calendar/v3/calendars/{calendarId}/events
    ?singleEvents=true          expand recurrence into instances
    &orderBy=startTime
    &timeMin=<now - 1d>
    &timeMax=<now + 14d>
    &maxResults=250
```

Then hold the returned `nextSyncToken` and use `syncToken=` on every subsequent call. Rules that matter:

- A `410 GONE` means the token expired. Drop it, drop the window's cached tasks, and do a full re-read. Do not treat it as an error the user sees.
- `status: "cancelled"` on an instance means deleted — hide the Task, keep the overlay for 30 days in case it comes back.
- `singleEvents=true` makes each instance its own event id, which is what we want: assigning Tuesday's practice to Dad must not assign every Tuesday.
- The rolling window is not the sync window. Sync ±14 days; the UI shows 7. The extra week is so "next Thursday" is instant.

### 5.3 Staying fresh

`events.watch` gives a push channel:

```
POST /calendar/v3/calendars/{calendarId}/events/watch
{ "id": "<uuid>", "type": "web_hook", "address": "https://<fn>/v1/calendar/webhook", "token": "<familyId>:<hmac>" }
```

Google then POSTs on change. It tells you *something* changed, never what — so the handler does an incremental sync and moves on. Three things that will bite:

- **Channels expire in ~7 days.** Renew on a schedule at 6, and treat a missed renewal as a fallback to polling, not an outage.
- **Verify the `token`.** The webhook URL is public.
- **Debounce.** A laptop edit spree produces a burst; coalesce per calendar with a 10-second window.

Fallback when webhooks are unavailable: poll on foreground, and every 30 minutes in the background. The app must be correct without webhooks; they are a latency optimisation.

### 5.4 Writing back **[DECIDE]**

SYSTEM.md's confirmed position is **Calendar v1 is read-only**. Two surfaces already anticipate a write path:

- Go's add sheet has an **"Add to Google Calendar"** button that records intent (`calendarPush.state = 'queued'`) and shows a mark on the row.
- Plan has a **pull/push review sheet** with a visible two-way toggle, an outgoing queue containing schedule fields only, and a success message that says explicitly that nothing was sent to Google.

Both are deliberate placeholders that stop short of writing, which is the right call for a lab — but the product now has two entry points for a feature its architecture says does not exist. That needs resolving before either ships.

Three ways out, in order of preference:

1. **A dedicated secondary calendar.** On connect, create "Heli-Pad" in the user's account and write only there. Nothing we write can corrupt a school or team calendar, the user can hide or delete it wholesale, and revocation is one click. Needs `calendar.events` and `calendar` (for `calendars.insert`).
2. **Defer.** Remove the button until there is a reason to write. Cheapest, and honest.
3. **Write into the primary calendar.** Do not. The blast radius of a sync bug is somebody's real life.

If (1) is chosen: write with `extendedProperties.private = { heliPadTaskId }` so the event round-trips back to its own Task instead of arriving as a duplicate on the next read.

---

## 6. Travel estimation

The leave-by time is the product. If it is wrong twice, the app is decoration.

```
departBy = startsAt − travelMinutes − buffer − parkingMinutes
buffer   = task.bufferMinutes ?? family.defaultBufferMinutes
```

**[DECIDE]** MapKit vs Google Routes.

**Recommendation: MapKit on-device, with a server-side Google fallback for scheduling.** `MKDirections` is free, needs no key, and is accurate enough for a 20-minute suburban drive. The problem is that notifications must be scheduled when the app is closed, and the server cannot call MapKit. So:

- **Foreground / UI:** `MKDirections` with `departureDate` set to the estimated departure, so traffic is priced at the right hour.
- **Server / scheduling:** Google Routes API `computeRoutes` with `routingPreference: TRAFFIC_AWARE`, used only to decide *when* to fire a notification.
- Both write into the same cache with `estimateSource` recorded, so a mismatch is visible in support rather than mysterious.

**Cache** keyed `originPlaceId:destPlaceId:dayOfWeek:hourBucket`, TTL 6 hours off-peak and 45 minutes inside 07:00–09:30 and 14:30–18:30. Invalidate on any place edit. Never let a cache miss block a render — draw the dial from the last known estimate marked `stale: true` and refresh underneath.

**Origin.** The lab hardcodes `parentLocations`. Production derives it: the previous task's place if it ends within 90 minutes, else the assignee's `defaultOriginPlaceId`, else home. This is the single biggest accuracy win available, because a leave-by from the wrong side of town is worse than no leave-by.

---

## 7. Weather

Ambient only. It changes what you put on the child, never the plan.

**Recommendation: WeatherKit.** On iOS the framework handles auth; the backend, if it ever needs a forecast, uses the REST endpoint with a JWT signed by a WeatherKit key. **Attribution is required** — Apple's logo and the legal link must appear, most naturally in Settings.

Map Apple's `conditionCode` to the five tokens `design.md` draws, and keep the mapping in one function:

| Token | conditionCode |
| --- | --- |
| `sun` | clear, mostlyClear, hot |
| `partly` | partlyCloudy, mostlyCloudy, breezy, windy |
| `cloud` | cloudy, foggy, haze, smoky |
| `rain` | rain, drizzle, sleet, hail, and every snow case |
| `storm` | thunderstorms, tropicalStorm, hurricane, blizzard |

Return `{ sky, label, tempHigh, tempLow }`, cache per `place + date` for 3 hours, and render nothing rather than a placeholder if it is missing. A missing icon is invisible; a wrong one is a wet child.

The client-side stub to replace is `goWeather(dayIdx)` in `index.html`. Its return shape is already the shape above, minus temperatures.

---

## 8. Notifications

| Notification | Fires | To | Source |
| --- | --- | --- | --- |
| Leave now | at `departBy` | assignee | local, scheduled on device |
| Leave in 15 | `departBy − 15m` | assignee | local |
| Driver needed | 12h before an unassigned drive | all caregivers | server push |
| Reassigned to you | on overlay change | new assignee | server push |
| Crew informed | on "Tell the crew" | other caregivers | server push |
| Plan changed | calendar edit inside 3h of a stop | assignee | server push |

**Leave-by is local, not push.** It has to fire on time with no network, and it needs to be cancelled the instant the task is completed. Reschedule the next 24 hours of local notifications on every foreground, every sync, and every overlay change; cancel and rebuild rather than diffing.

Server pushes carry `content-available` so the client can refresh silently, plus a visible alert. Respect Focus modes — the leave-by notification is a **time-sensitive** interruption level and should be declared as such; nothing else is.

---

## 9. Arrival auto-completes a stop

Recorded in SYSTEM.md as `ArrivalDetector`, not yet built. It is the highest-value feature in this document that nobody has asked for, because completion is exactly the action a caregiver will not perform: they are at the field, holding a bag, with a child.

- Register a `CLCircularRegion` (150 m) around the destination of the assignee's next few travel tasks — iOS allows 20 monitored regions per app, so budget them.
- On entry, if `now` is within `[startsAt − 30m, endsAt]`, mark the Task done and sync the overlay.
- Attribute it: `updatedBy = assigneeId`, and record that it was automatic so the UI can say "checked off on arrival" rather than implying a tap.
- **The manual tap never goes away.** A handoff can happen without the assignee's phone arriving — grandma drove, the phone was dead, the region did not fire.
- Requires `whenInUse` at minimum and `always` for background regions. Ask for it in context, after the user has seen the app work, and explain the trade in one sentence.

---

## 10. Offline, sync, and conflicts

The app must open to a correct-looking day with no network, because that is a school car park.

- **Read path:** local store first, always. Render, then refresh. Never gate the dial on a fetch.
- **Write path:** apply locally, enqueue, retry with backoff. The checkbox must feel instant.
- **Overlay conflicts:** last-write-wins per field, using `updatedAt` and `updatedBy`. Per *field*, not per document — two caregivers editing different fields of the same task must both survive.
- **`status` is idempotent.** Two people marking the same stop done is agreement, not a conflict.
- **Schedule conflicts do not exist.** Google wins on schedule fields, unconditionally. The only question is whether the overlay follows, which it does by `sourceEventId`.
- **Deleted-then-restored events** are why overlays are kept for 30 days after a `cancelled`.

---

## 11. Security and privacy

This app knows where children are and when they are alone. Treat it accordingly.

- Google refresh tokens live server-side, encrypted with a KMS key, never logged, never returned by any endpoint.
- Family membership is the only authorisation boundary. Every read and write checks it; there is no admin surface that bypasses it.
- Firestore rules (or the SQL equivalent) must enforce it independently of the client, and there should be a test that a member of family A cannot read family B.
- Children are data subjects, not users. No child accounts, no child-facing surface, no analytics keyed to a child.
- Location is used for two things — travel estimation and arrival detection — and stored for neither. No location history.
- Deleting a family deletes its tasks, places, and calendar links within 30 days, and revokes the Google grant immediately.
- Crash and analytics reporting must not carry titles, place names, or people's names. A stop called "Custody exchange" is not a debug string.

---

## 12. Build phases

Each phase ships something usable. Do not start one before the previous one's criteria pass.

### Phase 1 — Skeleton with fakes
Domain types (§3), ports, and in-memory adapters seeded from the lab's sample data. The Go screen rebuilt in SwiftUI against `design.md`.
**Done when:** the Go screen matches the lab's behaviour on the dial state matrix, the two scopes, all three swaps, and the add/edit sheet — with no network anywhere.

### Phase 2 — Identity and family
Sign-in, family creation, invite/join, people and places CRUD, backend deployed.
**Done when:** two devices sign in to one family and see the same people and places.

### Phase 3 — Calendar in
OAuth, calendar picker, incremental sync, place resolution, webhooks.
**Done when:** an event created on a laptop appears within 60 seconds, and a title edited there does not disturb its assignee or done state.

### Phase 4 — Travel and the countdown
MapKit estimates, origin derivation, cache, TripPlan, real urgency.
**Done when:** the leave-by is within ±3 minutes of Apple Maps for the same trip at the same hour, and the dial is correct across `later → started` against a mocked clock.

### Phase 5 — Shared overlays
Assign, complete, buffer, notes, offline queue, conflict rules.
**Done when:** two caregivers reassign the same drive in airplane mode and both converge on one answer with no lost data.

### Phase 6 — Notifications
Local leave-by scheduling, server pushes, Focus behaviour.
**Done when:** the phone, untouched and locked since morning, says "leave now" at the right minute.

### Phase 7 — Weather and polish
WeatherKit, attribution, the load gauge against real data, empty and error states.
**Done when:** every state in `design.md` has been seen with real data, including the ones nobody wants to look at.

### Phase 8 — Plan
Port the weekly companion: week overview, readiness from real events, review and rebalance sheets, priorities. `plan-core.js` is pure logic (`analyze`, `summary`, `loads`, `proposals`, `occurrences`, `pull`) and should port almost verbatim — it is the one part of the lab written as a module rather than a screen.
**Done when:** readiness, conflict flags, and rebalance proposals agree with the lab given the same events, and an empty week reads 0 / 0.

### Phase 9 — Beyond
Live Activity, Watch complication, arrival auto-complete (§9), calendar write-back if §5.4 is approved.

---

## 13. What must not drift

`design.md` is a contract, not a mood board. These are the decisions most likely to be quietly lost in a port, and each exists for a reason recorded there:

1. **The dial shows my next departure, today.** No filter, day picker, or caregiver selector moves it. Only the profile switcher does — and Plan's caregiver filter must leave Go's viewer and countdown alone.
2. **The countdown counts.** Minutes inside the hour, hours and minutes beyond it, and a ring that is always moving — never a clock face, never a bar pinned full.
3. **One highlight colour** (`#ffd36b`) means *act now*, and appears nowhere else.
4. **A mark plus a name.** People are never reduced to an initial or an emoji alone.
5. **Arrival in the time column, departure inside the row.** Two kinds of time never share a column.
6. **No leave-by while composing.** The create sheet shows start and end only, because the app does not yet know where the caregiver will be coming from.
7. **Two taps to add.** Every field pre-filled; the keyboard opens only for a custom name, place, or exact time.
8. **Swipe accelerates, never hides.** Every gesture has a visible tap path first — see `design-lab/SWIPE-TAP-MAP-v1.md`.
9. **Line work, not clip art.** Icons are drawn in the app's palette. Children's emoji are the exception, because there the emoji is the identity.
10. **Readiness is computed, never claimed.** Plan's ready fraction comes from the events themselves, saving a review records only that somebody looked, and an empty week reads 0 / 0 — never 100%.
11. **Unknown stays unknown.** A route with no estimate is shown as unknown rather than given a plausible number.

---

## 14. Open decisions

| # | Decision | Blocks | Owner |
| --- | --- | --- | --- |
| 1 | Native SwiftUI vs hybrid (§2.1) | Phase 1 | Software Lead + John |
| 2 | Firebase vs custom backend (§2.2) | Phase 2 | Software Lead |
| 3 | Calendar write-back, and how (§5.4) | Phase 8, and the "Add to Google Calendar" button shipped in the lab | Product |
| 4 | MapKit vs Google Routes (§6) | Phase 4 | Product — do we need ETAs that match the Maps app users already trust? |
| 5 | Whose phone gets the leave-by (§8) | Phase 6 | Product — assignee only, or every caregiver? |
| 6 | Location permission tier for §9 | Phase 8 | Product + Legal |
| 7 | Does Plan's rebalance stay deterministic, or become a service? | Phase 8 | Product — today it is schedule rules and sample routes, with unknown ETAs left unknown. That honesty is worth keeping |

Everything in §3–§11 is surface-agnostic and holds for Go and Plan alike. The home-screen question that once sat here is **closed**: Go was selected by the product owner, with Plan as its weekly companion.

---

## 15. Mapping the lab to production

For whoever ports the behaviour. Everything in the left column is in `index.html`.

| Lab | Production |
| --- | --- |
| `state.eventsByDay` | `GET /v1/tasks` → local store |
| `calculateDayPlan()` | `DayAgenda` use case + `TripPlan` derivation |
| `routeMatrix` / `travelMinutes()` | `TravelEstimator` port → MapKit / Routes |
| `goWeather()` / `GO_WEATHER` | `WeatherProvider` port → WeatherKit |
| `goRingFraction()` | port verbatim — the piecewise curve is a design decision, not an implementation detail |
| `goWeekLoads()` | same, against real tasks; the peak-relative scale is deliberate |
| `state.currentUser` | the signed-in `Person`, sticky across cold start |
| `state.goCrewFilter` | a view filter, never a viewer switch |
| `goToggleDone()` | overlay `PATCH`, optimistic, queued offline |
| `saveState()` / `localStorage` | `Store` port → SwiftData + sync queue |
| Preview clock (`mockTime`) | test-only clock injection; never ships |
| `plan-core.js` — `analyze`, `summary`, `loads`, `proposals`, `occurrences`, `pull` | port near-verbatim; it is already a pure module with no DOM |
| Plan's calendar pull/push preview | the real adapter behind §5.4, once that decision lands |
