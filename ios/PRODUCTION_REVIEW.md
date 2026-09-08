# HeliPad iOS production review

Reviewed September 8, 2026, against the current working tree, including uncommitted files. This is a source review and build check of the native iOS app. The sibling web app was outside scope.

**I would hold a production release.** The main risks are credential exposure, destructive cloud synchronization, and incorrect time handling. Performance and energy work should follow those fixes.

## Validation and limits

- Inventoried 69 Swift files and inspected the app entry point, shared store, persistence, services, planning algorithms, feature view models, and key views.
- Release build passed for the generic iOS Simulator destination with signing disabled. Xcode reported an actor-isolation warning for the MapKit completion delegate, repeated for the two simulator architectures, and an App Intents metadata warning.
- Existing standalone countdown boundary and duration tests passed.
- The Xcode project contains one app target and no test target. The separate Swift domain test runner was inspected but not executed.
- A temporary optimized macOS benchmark ran five samples of `PlanCore.analyze` plus `PlanCore.loads`. Median results were 3.94 ms for 20 same-day events, 131.01 ms for 100, and 1181.31 ms for 500. All events used one caregiver on one day. This is a synthetic scaling check, not representative iPhone latency; the larger cases are stress cases. It excludes SwiftUI rendering.
- No app launch or cloud requests were performed. The embedded credential was not tested. No source code was changed.
- Actual battery drain, launch latency, scrolling hitches, peak memory, crash-free sessions, and accessibility behavior remain unmeasured.

P1 means fix before release. P2 means address during production hardening. All findings below are based on code; conditional outcomes are identified.

## Findings

### 1. P1: A database credential ships inside the application

[AppConfig.swift:5](</Users/johnvincent/Software Engineering/heli-pad/ios/HeliPad/HeliPad/App/AppConfig.swift:5>); [Persistence.swift:31](</Users/johnvincent/Software Engineering/heli-pad/ios/HeliPad/HeliPad/Domain/Persistence.swift:31>); [NeonDatabaseService.swift:98](</Users/johnvincent/Software Engineering/heli-pad/ios/HeliPad/HeliPad/Services/NeonDatabaseService.swift:98>)

The configuration contains a PostgreSQL connection URI with a password and an owner-named database role. The app sends that URI to Neon and persists it inside the household snapshot in UserDefaults. The snapshot is also uploaded to the database. Anyone who obtains the app binary can extract a bundled credential. Its current validity and actual grants were not tested.

Rotate or revoke the exposed credential, remove it from shipped configuration and retained artifacts, and move database access behind an authenticated service with household authorization. Store device session credentials in Keychain and exclude integration secrets from household data.

### 2. P1: Opening a fresh or stale installation can overwrite the cloud household

[AppStore.swift:439](</Users/johnvincent/Software Engineering/heli-pad/ios/HeliPad/HeliPad/Domain/AppStore.swift:439>); [AppStore.swift:509](</Users/johnvincent/Software Engineering/heli-pad/ios/HeliPad/HeliPad/Domain/AppStore.swift:509>); [NeonDatabaseService.swift:166](</Users/johnvincent/Software Engineering/heli-pad/ios/HeliPad/HeliPad/Services/NeonDatabaseService.swift:166>)

On a clean install, `restore()` enables the default cloud connection and immediately calls a push. The initial store contains sample data. Every push targets the default household ID `primary` and replaces the entire JSON document without a revision check. If the configured database is reachable, a new install can replace existing family data before onboarding; a stale device can also overwrite newer edits.

Require an authenticated household identity, distinguish initial download from upload, and use revision-checked writes with conflict handling. Never upload seed data as part of initialization.

### 3. P1: Edits made during a cloud push are dropped from that sync cycle

[AppStore.swift:379](</Users/johnvincent/Software Engineering/heli-pad/ios/HeliPad/HeliPad/Domain/AppStore.swift:379>); [AppStore.swift:514](</Users/johnvincent/Software Engineering/heli-pad/ios/HeliPad/HeliPad/Domain/AppStore.swift:514>)

A push captures a snapshot and suspends on the network. Any save while it is in flight calls `syncWithNeon()`, which returns because `isSyncingWithNeon` is true. When the first push finishes, nothing schedules the newer state. The displayed last-sync time advances even though the remote document can be stale. Local persistence keeps the edits, but cloud convergence depends on a later save or launch.

Track a dirty revision, serialize uploads, and repeat until the uploaded revision matches the latest local revision. Persist pending work and expose failures instead of swallowing them with `try?`.

### 4. P1: The live countdown defaults to 1:00 PM on every launch

[AppStore.swift:145](</Users/johnvincent/Software Engineering/heli-pad/ios/HeliPad/HeliPad/Domain/AppStore.swift:145>); [GoViewModel.swift:35](</Users/johnvincent/Software Engineering/heli-pad/ios/HeliPad/HeliPad/Features/Go/GoViewModel.swift:35>)

`mockTime` defaults to `"13:00"`. The clock uses the device time only when that value is empty. No production assignment clears it, and restore does not replace it. Consequently hero selection, lateness, and countdowns run against 1:00 PM regardless of the actual time.

Use a real clock by default. Inject a test clock explicitly for previews and tests.

### 5. P1: Week rollover changes existing event dates

[AppStore.swift:12](</Users/johnvincent/Software Engineering/heli-pad/ios/HeliPad/HeliPad/Domain/AppStore.swift:12>); [AppStore.swift:256](</Users/johnvincent/Software Engineering/heli-pad/ios/HeliPad/HeliPad/Domain/AppStore.swift:256>); [AppStore.swift:312](</Users/johnvincent/Software Engineering/heli-pad/ios/HeliPad/HeliPad/Domain/AppStore.swift:312>)

`BASE_WEEK` is computed from the current date, while `eventsByDay` persists only weekday buckets. Both `records()` and `reconcile()` replace each event's date with the current week's date. After Monday, a one-off event from last week appears in this week, including its old completion state. Future records are not promoted into the buckets used by Go.

Persist absolute event dates or a stable bucket-week anchor. Expand explicit recurring rules separately and reconcile week transitions without rewriting historical events.

### 6. P1: Departure reminders use arrival time and lose timezone information

[NotificationService.swift:89](</Users/johnvincent/Software Engineering/heli-pad/ios/HeliPad/HeliPad/Services/NotificationService.swift:89>); [NotificationService.swift:105](</Users/johnvincent/Software Engineering/heli-pad/ios/HeliPad/HeliPad/Services/NotificationService.swift:105>); [NotificationService.swift:131](</Users/johnvincent/Software Engineering/heli-pad/ios/HeliPad/HeliPad/Services/NotificationService.swift:131>)

The scheduler fires ten minutes before the event start and says “Leave in 10 minutes.” It never subtracts travel or buffer and includes non-travel events. For a 3:00 PM stop with 30 minutes of driving and a 12-minute buffer, departure is 2:18 PM and a ten-minute advance reminder belongs at 2:08 PM. The current reminder is 2:50 PM.

It also extracts year/month/day/hour/minute from the household calendar without retaining the timezone in the notification's DateComponents. A different device timezone can shift delivery.

Share the departure calculation with Go, filter reminder types, and preserve the intended timezone. Add tests for travel, no-travel events, timezone differences, and DST.

### 7. P1: An ETA can belong to the wrong event or remain based on the launch location

[GoView.swift:82](</Users/johnvincent/Software Engineering/heli-pad/ios/HeliPad/HeliPad/Features/Go/GoView.swift:82>); [AppStore.swift:541](</Users/johnvincent/Software Engineering/heli-pad/ios/HeliPad/HeliPad/Domain/AppStore.swift:541>); [GoDialCardView.swift:42](</Users/johnvincent/Software Engineering/heli-pad/ios/HeliPad/HeliPad/Features/Go/Views/GoDialCardView.swift:42>)

Go calculates an ETA on appearance and when the hero ID changes. It does not refresh when the first GPS fix arrives, the same event's destination changes, or the cached estimate ages. All results write to one unkeyed `realTimeDeviceEta`. It is not cleared before a new route lookup; overlapping tasks can complete out of order and overwrite the current event's estimate.

Represent ETA with destination identity, origin, timestamp, and provenance. Cancel superseded requests, reject stale results, and refresh after an acceptable location fix or meaningful movement.

### 8. P1: Failed geocoding produces apparently valid coordinates

[GoogleMapsService.swift:377](</Users/johnvincent/Software Engineering/heli-pad/ios/HeliPad/HeliPad/Services/GoogleMapsService.swift:377>); [GoogleMapsService.swift:433](</Users/johnvincent/Software Engineering/heli-pad/ios/HeliPad/HeliPad/Services/GoogleMapsService.swift:433>); [AppStore.swift:553](</Users/johnvincent/Software Engineering/heli-pad/ios/HeliPad/HeliPad/Domain/AppStore.swift:553>)

When place resolution fails, the service returns a successful PlaceDetail containing the default Ann Arbor coordinate. Missing destination coordinates also become that coordinate in drive-time calculation. These values can be saved and used for navigation even though the requested address was never resolved.

Keep coordinates absent on failure and expose an unresolved state. Require successful resolution before offering coordinate-based routing. The straight-line, assumed-speed route fallback should likewise be labeled as an estimate rather than passed through as a live route.

### 9. P2: Location acquisition runs continuously without a matching consumer

[GoView.swift:82](</Users/johnvincent/Software Engineering/heli-pad/ios/HeliPad/HeliPad/Features/Go/GoView.swift:82>); [LocationService.swift:33](</Users/johnvincent/Software Engineering/heli-pad/ios/HeliPad/HeliPad/Services/LocationService.swift:33>); [SettingsView.swift:668](</Users/johnvincent/Software Engineering/heli-pad/ios/HeliPad/HeliPad/Features/Settings/SettingsView.swift:668>)

Opening Go starts continuous location updates until that view disappears, even with no travel event. Most updates do not trigger an ETA refresh. The Settings “Verify GPS Access” action can also start updates without a corresponding stop in that sheet.

Use one-shot location acquisition for one-time estimates, or a bounded stream while an active travel feature needs updates. Tie service lifetime to foreground scene state and reject stale or invalid fixes. Hundred-meter accuracy and the existing distance filter are sensible, but do not eliminate unnecessary acquisition. This is an energy-risk finding, not a measured drain percentage. [Apple's location efficiency guidance](https://developer.apple.com/documentation/xcode/accessing-the-device-s-location-efficiently)

### 10. P2: A five-second timer repeatedly runs expensive planning work on the UI path

[GoViewModel.swift:25](</Users/johnvincent/Software Engineering/heli-pad/ios/HeliPad/HeliPad/Features/Go/GoViewModel.swift:25>); [GoView.swift:12](</Users/johnvincent/Software Engineering/heli-pad/ios/HeliPad/HeliPad/Features/Go/GoView.swift:12>); [PlanCore.swift:161](</Users/johnvincent/Software Engineering/heli-pad/ios/HeliPad/HeliPad/Domain/PlanCore.swift:161>)

The timer publishes `nowMinutes` every five seconds even when unchanged. Go's body then calls `computeView`, which analyzes events and calculates workloads. Each analysis calls `candidate` for each event; candidate repeatedly filters and sorts other events. Loads repeats candidate calculations. The synthetic benchmark above demonstrates the scaling cost.

Publish only when the minute changes, pause the ticker outside the active scene, and cache schedule analysis by relevant data revision. Index events by date and caregiver. Keep countdown presentation separate from schedule recomputation. Profile on the oldest supported iPhone before setting a supported schedule-size limit.

### 11. P2: Local persistence rewrites the household synchronously and deletes unreadable data

[AppStore.swift:379](</Users/johnvincent/Software Engineering/heli-pad/ios/HeliPad/HeliPad/Domain/AppStore.swift:379>); [Persistence.swift:42](</Users/johnvincent/Software Engineering/heli-pad/ios/HeliPad/HeliPad/Domain/Persistence.swift:42>)

Each save normalizes the entire store and synchronously JSON-encodes the full household into UserDefaults. Go's multi-stop save loop repeats this work per stop. Cloud pushes also execute schema creation and send a full pretty-printed snapshot. This creates avoidable CPU, storage, and network work as schedules grow.

Separately, a decode failure removes the only stored blob, and a version mismatch silently falls back to initial state. A model change can therefore lose the user's recoverable data.

Use batched mutations and a serialized persistence layer with atomic writes, backups, and explicit migrations. Preserve an unreadable snapshot for recovery. Move schema creation to deployment and coalesce uploads after local edits.

### 12. P1: The target is missing a privacy manifest for UserDefaults access

[Persistence.swift:42](</Users/johnvincent/Software Engineering/heli-pad/ios/HeliPad/HeliPad/Domain/Persistence.swift:42>)

No `PrivacyInfo.xcprivacy` exists in the inspected iOS project, while persistence uses UserDefaults. Declare the applicable required-reason API use and verify that the file is packaged in the archive. A successful simulator build does not validate App Store submission requirements. [Apple's required-reason API policy](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api), [API categories and approved reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)

### 13. P2: Fixed typography does not provide Dynamic Type scaling

[HeliTypography.swift:5](</Users/johnvincent/Software Engineering/heli-pad/ios/HeliPad/HeliPad/Core/Theme/HeliTypography.swift:5>); [ContentView.swift:130](</Users/johnvincent/Software Engineering/heli-pad/ios/HeliPad/HeliPad/App/ContentView.swift:130>); [GoDialCardView.swift:396](</Users/johnvincent/Software Engineering/heli-pad/ios/HeliPad/HeliPad/Features/Go/Views/GoDialCardView.swift:396>)

The typography helpers use explicit point sizes throughout, including 9.5–12 point operational labels. Critical icon buttons and inactive custom tabs lack explicit action labels or selection semantics. These need device verification with VoiceOver and accessibility text sizes.

Use semantic fonts or scaled metrics, permit layouts to reflow, and label actions such as marking a stop complete. Test the dial, navigation, forms, and sheets at accessibility sizes.

### 14. P2: Network failure is shown as fabricated weather

[WeatherService.swift:64](</Users/johnvincent/Software Engineering/heli-pad/ios/HeliPad/HeliPad/Services/WeatherService.swift:64>); [WeatherService.swift:140](</Users/johnvincent/Software Engineering/heli-pad/ios/HeliPad/HeliPad/Services/WeatherService.swift:140>)

Any fetch failure produces “Sunny · 58°–78°” without an error or stale indication, even if a previously fetched value exists. The one-hour cache has no coordinate key, so moving to another location can reuse the previous location's weather.

Model weather as loading, current, stale, or unavailable. Key the cache by approximate coordinate and retain the last known successful result with its timestamp.

## Structure and production gaps

Feature folders, extracted view components, and pure PlanCore/FamilyCore functions provide a useful starting point. Local reminders, route caching, and weather caching are also reasonable choices.

The 983-line AppStore currently owns domain mutations, navigation filters, normalization, persistence, onboarding, location integration, and synchronization. Views observe that whole object, so unrelated published changes invalidate broad portions of the UI. The older Today feature uses a separate TaskItem/TaskStore model and is not reachable through ContentView. Retaining both models increases maintenance and testing work.

Separate household state and use cases from view state and integration services. Add explicit actor ownership to the UI store and mutable service caches. The compiler already flags MapKitCompleterService's delegate conformance as crossing actor isolation; it becomes an error in Swift 6 mode. Resolve that conformance and enable strict concurrency checking incrementally.

Add an XCTest target and CI before relying on the current manual checks. Prioritize sync interleavings, migrations, week rollover, notification timing, and route cancellation. Add privacy-preserving error reporting and performance signposts so field failures and regressions are observable. The current review cannot establish a crash-free rate or memory-leak rate.

## Device measurements to collect

| Metric | Scenario | Evidence needed |
|---|---|---|
| Launch latency | Cold and warm launch with a large saved household | Median and p95 time to an interactive Go screen |
| UI responsiveness | Go countdown, Plan navigation, batch edits | Main-thread stalls, hitch rate, and analysis duration |
| Energy | Ten minutes idle on Go, active travel, and backgrounding | Location duration, timer activity, CPU and network use |
| Memory | Repeated tab changes, searches, and route lookups | Peak footprint and whether allocations settle |
| Network efficiency | Rapid edits, offline edits, reconnect, two devices | Requests and bytes per logical edit, convergence and conflicts |
| Reliability | Decode failure, interrupted save, schema upgrade | Recovery without data loss |
| Accessibility | VoiceOver, large text, Reduce Motion | Completion of core tasks without clipped or unlabeled controls |

Fix credentials and sync behavior first, then clock/date/reminder correctness. Follow with ETA ownership, bounded location use, and cached planning calculations. Collect device baselines after those changes so optimization targets reflect the intended production behavior.

