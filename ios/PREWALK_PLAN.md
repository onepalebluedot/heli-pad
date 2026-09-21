# HeliPad prewalk: remaining work, performance, to-dos, and groceries

Reviewed September 11, 2026. Originally a planning deliverable with no
application source changed.

**Updated September 12, 2026, after the lists and performance review.** Read the
current backlog below first. It supersedes the status of the historical
checkboxes later in this document. The earlier plan remains as implementation
context, not a list of features to rebuild. Assistant integration exists, but
production service, integration, and verification work remains.

**Navigation clarified September 13, 2026; Lists home revised September 20, 2026:**
Settings stays in the top-right gear and opens its existing sheet. The fifth
bottom destination is Lists. Use `Go | Plan | Assistant | Family | Lists`.

**Lists home contract (September 20, 2026):** the Lists destination opens two
large horizontally swipeable cards, **To-do** and **Grocery**, one visible at a
time. Each centers the supplied illustration above its title and remaining
count, with an **Open list** action, and opens that household's default list in
one tap. Accessible page controls also switch cards, and the chosen card is
preserved on return. Nothing else is on the home screen: **two lists only**, so
there is no custom-list row, no category switcher, and no list-chip strip.
Sections inside each list are how the household organises its work. This
replaces the segmented-control description previously carried in L01/N01, and it
replaces the earlier proposal to put Settings in the bottom navigation.

**Lists work order:** `LISTS_IMPLEMENTATION_PLAN.md` (full-app hybrid navigation
and household collaboration) is the authoritative Lists specification; the
L01–L10 checklist below is its backlog summary. `ListsLab/` is an experiment
kept for interaction and test references only — its sample data, private-link
sharing, Mac service, and separate navigation shell are not shipped, and its
passing tests are **not** evidence that any production acceptance criterion
below has passed.

## Current review scope and results

This review covers the working tree, including existing uncommitted changes,
across Go, Plan, Family, Settings, Onboarding, Assistant, persistence, cloud
merge, calendars, location, routing, and notifications. Only this plan was
edited. No application implementation was requested or performed.

Verification on September 12, 2026:

- `bash scripts/test-production.sh` passed. Its checks cover credentials, sync races and convergence, rollover, clock/analysis caching, solo events, calendar adapter behavior, statistics, and event provenance. Compilation emitted existing MapKit/geocoding deprecation and isolation warnings.
- `swift test --package-path AssistantLab` passed: 168 tests, zero failures.
- These are local tests. This review did not launch the simulator, build the full iOS target, profile a device, contact a production household, or exercise authenticated calendar/AI services. Performance items below describe source-supported opportunities, not measured speedups. UI lifecycle failures are identified as risks where runtime confirmation is still needed.

Paths in the current backlog are relative to the repository root. P0 means
data integrity or household isolation; P1 means a requested feature or a
material correctness/performance issue; P2 means a follow-up improvement.

### Reconcile the historical checklist before implementation

| Earlier work | Current source status | Remaining work |
| --- | --- | --- |
| U01, U02, U03, U09, U10, U11 | Canonical planning/settings mutations, place CRUD, setup prefill, name/error handling, and the Plan shortcut action now have implementations. | Retain regression and UI verification; do not implement the old fixes wholesale. |
| U04 | Editor address invalidation and resolution tokens exist. | Background geocoding still needs stale-result checks; see F04. |
| U05, U06 | Go preserves unfinished work and carries assigned, known-route, and unknown-route counts. | Verify large-text and long/all-day-event presentation; route result correctness remains in F04/F05. |
| U07 | EventKit import and Google authentication/import/create/update/delete paths exist. | Complete imports, durable external writes, provider concurrency, and recurrence round trips remain; see F01/F02. |
| U08, U13 | Local driver-needed reminders, explicit trigger timezone, eligible-fire-time sorting, and scheduling error reporting exist. Reassignment alerts are explicitly unavailable. | Queue rebuilding and reminder scope/wording remain; see PF02/F05. Authenticated APNs delivery remains under historical U08/A01. |
| R01–R05 | Series definitions, exceptions, finite recurrence controls, store commands, shortcut defaults, and onboarding propagation exist. | R06/V02 device, DST, two-device, and external-calendar verification remains. Preserve existing identities and exceptions. |
| A03–A06 | Assistant tools, proposals, transcript, trends, and native tab exist. | Navigation, session lifecycle, common metric definitions, and deployed-service checks remain; see F07/F08 and A01/A02. |
| Smart Suggestions | Provenance, tolerance-based grouping, per-session caches, snoozing, local fallback, and draft review now exist. | Fix integration and async invalidation gaps in F06; do not replace the detector with another implementation. |
| N01/N02/N03 | Four destinations and a Settings sheet are implemented. | N01 now adds Lists as the fifth destination and keeps the top-right Settings gear. L01 defines the swipeable two-card Lists home and the sectioned list detail. Accessibility and navigation verification remain. Liquid Glass is optional follow-up work after functional delivery. |

## Lists: hybrid navigation and household collaboration

The requested addition is an undated to-do list and a grocery list users can
check off. Neither requires children, a driver, a place, a start time, or a
recurrence rule. There are currently no corresponding models or screens;
`TaskRecord` in `HeliPad/HeliPad/Domain/Models.swift` represents a scheduled
event and requires a date and time.

Full specification: `LISTS_IMPLEMENTATION_PLAN.md`. That document is the
authoritative navigation, sharing, and verification contract for this section;
L00–L10 below are its backlog summary.

Product decisions:

- **Hybrid navigation.** Lists is the fifth destination, and it is two lists:
  **To-do** and **Grocery**. The home shows two large horizontally swipeable
  cards, one visible at a time, each centering the supplied artwork above the
  list name, its remaining count, and an **Open list** action. Accessible page
  controls switch cards; the chosen card is preserved on return. Nothing else is
  on the home screen — no custom-list row, no category switcher, no chip strip.
- **Fixed defaults.** Two deterministic list identities per household, one per
  kind, with fixed names and positions. They cannot be created or deleted, so
  there is no list-creation path anywhere. Every list has a stable default
  **General** section. New households receive empty lists, never lab samples.
- **Sections are the structure.** list → section → item → optional to-do steps.
  No separate folder entity, no nested sections.
- **Household-wide sharing** once household sync is configured. Without a
  connection, lists stay usable locally with truthful status. Per-participant
  permissions and external invitations are deferred.
- **Audit metadata, not due dates.** Creation/completion timestamps are audit
  metadata. Defer due dates, child links, assignments, reminders, recipes,
  pantry inventory, prices, and AI categorization.
- **ListsLab is a reference.** It supplies useful interactions and test cases.
  Its sample data, private-link sharing, Mac service, and separate navigation
  shell are not shipped, and its tests are not production acceptance evidence.

- [x] **L00 / P1: Reconcile the agent backlog.** *(Done September 20, 2026.)* The navigation contract above replaces the segmented-control description, the deferred "multiple custom lists" line is removed, L02 and L05 now name the separate storage and cloud contracts, L07–L10 are added, and execution order, the navigation status table, and the historical navigation text agree with `LISTS_IMPLEMENTATION_PLAN.md`.

- [ ] **L01 / P1: Add a Lists destination with a swipeable two-card home.**
  - Target: `HeliPad/HeliPad/App/ContentView.swift`, `MainTab.lists`, and a new `Features/Lists/` area. Order: `Go | Plan | Assistant | Family | Lists`; Settings stays in the top-right gear and opens its existing sheet. Implement the shared navigation change once under N01 and validate all five destinations on compact phones.
  - Lists home: two large horizontally swipeable cards (To-do, Grocery), one visible at a time, each centering the supplied artwork above the list name, its remaining count, and an **Open list** action. Accessible page controls switch cards, tapping a card opens that list, and the chosen card is preserved on return. Nothing else is on the home screen — no custom-list row, no category switcher, no chip strip.
  - List detail: Back to Lists, title, remaining count, compact sync status, sectioned items, the section-management row, and the bottom quick-add.
  - Keep capture quick: a visible text field, keyboard submit/Add, and a checkbox per row, with the checkbox on the same line as the item's name. Provide empty states, remaining counts, accessible actions, and useful error feedback. Core/caregiver filters must not hide shared list items.
  - Store navigation, drafts, expanded sections, completed-section visibility, and scroll anchors per household and list ID outside transient detail views; returning from another main tab restores the previous Lists position, and switching household clears that state.
  - Acceptance: each list is one tap from Lists home and there is no second navigation step; Settings stays reachable from every destination; drafts and scroll positions survive navigation; every row is reachable with the keyboard and the bottom bar visible; VoiceOver announces item text, checked state, list name, remaining count, and the page position; hit targets are at least 44 points.

- [ ] **L02 / P1: Introduce independent list records, commands, and local storage.**
  - Targets: new list domain types under the full app's `Domain` area, `AppStore`, `Persistence`, Xcode source registration, and test compilation inputs where needed. Do not fabricate dated `TaskRecord` rows or expand the scheduling model with dummy dates.
  - Types: `HouseholdList` (identity, kind, name, ordering, creation/update metadata), `HouseholdListGroup` (list identity, name, ordering), `HouseholdListItem` (list/section identity, text, optional quantity and note, completion, ordering, activity/review metadata), `ListSubtask` (parent item identity, text, completion, ordering; to-dos), plus a versioned list snapshot carrying deletion records and sync metadata.
  - Defaults: two deterministic list identities per household, one per kind, with fixed names and positions and no deletion. Every list has a stable default "General" section. New households receive empty lists, never lab samples.
  - Ordering: stable integer ordering ranks with record-ID tie-breaking; reorder commands update the affected sibling ranks atomically. Array position and item text are never identity. Persist explicit `setCompleted(id:to:)`; replaying a toggle must not reverse the requested final state.
  - Commands: an observable `HouseholdListsStore` owned by `AppStore` centralizes list/group/item/subtask creation, editing, movement, ordering, explicit completion, deletion, purchased-item clearing, review snoozing, and Undo. UI bindings must not bypass commands.
  - Storage: a versioned, atomic archive scoped to household and connection identity, kept **separate** from the legacy household snapshot so an older app cannot discard unfamiliar list fields when saving. Preserve archives across household changes; never automatically upload the previous household's lists into a newly selected household. Use an ordered persistence writer, report local-save failures, protect corrupt or unsupported archives from replacement with a recovery path, and preserve lists across schedule resets, setup reruns, and week rollover.
  - Invalidation: list mutations publish a dedicated list revision. They must not call the existing schedule-wide save path, rebuild reminders, rehash events, rewrite unchanged credentials, or trigger calendar, routing, or suggestion work — see PF01.
  - Acceptance: every command survives offline relaunch; failed persistence is visible; old household data loads unchanged; schedule operations preserve lists; completion, edits, and deletions never affect Go/Plan, calendar export, suggestions, notifications, child statistics, or driving totals. Full detail in `LISTS_IMPLEMENTATION_PLAN.md` §2.

- [ ] **L03 / P1: Deliver the to-do workflow.**
  - Support quick add, inline editing or a lightweight detail editor, completion/reopening, manual ordering, movement to another group, and removal with Undo. Keep active items in user order and completed items in a collapsible section. Do not automatically delete completed items at midnight or during week rollover.
  - The capture bar must identify its target group explicitly: default to General, remember the last selected group per list, let the user change it, and let a group's "Add item" action preselect that group. Expanding a group must never silently redirect quick-add.
  - To-dos carry notes and collapsible steps. Completing every step does not automatically complete the parent, and checking the parent preserves its step states for reopening.
  - Acceptance: add "Replace furnace filter" with text alone; edit it; complete, reopen, reorder, and delete/undo it. No date picker, child selector, caregiver assignment, or event editor appears. Rapid keyboard submission does not duplicate one submission or drop another. Full detail in `LISTS_IMPLEMENTATION_PLAN.md` §5.

- [ ] **L04 / P1: Deliver the grocery workflow.**
  - Support item name, optional quantity such as "2 cartons", optional note, quick add, check/uncheck, edit, movement to another group, and delete/Undo. Preserve active-item order; move checked items into a collapsible Purchased section without disturbing the current tap or scroll position.
  - Detecting a duplicate normalizes whitespace and case within the current list and offers **Edit existing** or **Add another**. Never silently combine quantities, brands, or units. Reopening a purchased item restores its group and ordering and preserves its quantity and note. Keep reuse simple; do not add an inferred shopping schedule.
  - **Clear purchased** carries a batch Undo that targets exactly the purchased IDs shown when it was invoked; it must not clear items another device added or checked in the meantime.
  - Undo is one persistent, household-scoped batch for the latest destructive action. Preserve its saved contents across navigation and relaunch until it is undone or replaced by the next destructive action. Persist Undo locally only.
  - Acceptance: "Milk · 2 cartons" can be checked with one tap and reopened. Checking ten rows quickly loses no changes. Clearing purchased leaves active and concurrently added items untouched, and Undo cannot overwrite newer edits made by another device. Full detail in `LISTS_IMPLEMENTATION_PLAN.md` §5.

- [ ] **L05 / P0 prerequisite for shared lists: Add live household synchronization.**
  - Evidence: current snapshot, fingerprints, stamp tracking, and `merge` enumerate events/people/templates/places explicitly (`AppStore.swift:516,621,653,866`). Simply adding an array to the UI or snapshot does not make lists sync. Existing ordinary tombstones expire after 30 days (`AppStore.swift:463,961`).
  - Contract: extend the existing Neon integration with a `HouseholdListsCloudService` exposing `fetchListsRevision`, `pullLists`, and `pushLists` (requiring an expected remote revision). Store the versioned list snapshot in a **separate** `helipad_household_lists` record keyed by household ID, using compare-and-swap writes with pull/merge/retry on revision conflict. Older clients keep writing the existing household record without erasing lists; that is why lists must not ride the household snapshot (see L02).
  - Lifecycle: coordinate list sync through the app's foreground sync lifecycle with independent list revisions, pending state, and errors, so a schedule-sync failure cannot block lists. Two-second active cadence only while Lists is visible, bounded idle/error backoff, no polling in the background, refresh on foregrounding and after local changes.
  - Merge: reuse `RecordStamp` ordering with independent stamps for editable fields, completion, placement/order, and review snoozing; merge by identity, never array position or text. Different-field edits survive together; simultaneous edits to the same field resolve deterministically by stamp. Detail editors carry expected field stamps and preserve stale drafts for review instead of overwriting incoming changes.
  - Deletion: keep list-specific deletion records **without time-based expiry** in this release. Deletion wins for the deleted identity, including edits arriving after long offline periods. Deleting a list suppresses its descendants. Undo restores fresh identities; it never removes a deletion record or overwrites a remotely edited record.
  - Session: capture household identity and connection generation for all async work; discard responses from an obsolete session and clear visible drafts, navigation, and Undo state on household change. Switching caregiver within one household retains shared lists.
  - Status: show **On this device**, **Waiting to sync**, or **Up to date** truthfully, and persist local edits before claiming they are saved. Do not claim participant-based authorization or expose invitations the app cannot support.
  - Acceptance: two devices converge after concurrent additions, edits, checks, reorders, and reconnects; deleted content does not resurrect; old-client household uploads leave lists intact; switching households shows only that household's lists and rejects late responses from the prior household. Full detail in `LISTS_IMPLEMENTATION_PLAN.md` §3.

- [ ] **L06 / P2, after manual lists work: Extend the assistant to list operations.**
  - Add typed queries and reviewed proposals for "Add milk to groceries", "Add replace the filter to my to-dos", and explicit completion/removal requests. Route them through L02 commands, with resolved list/item IDs and the existing proposal validation. Listing items is read-only.
  - "Add milk to groceries" targets the Groceries list, and a to-do request targets the To-dos list. There are only two lists, so an unnamed target is never ambiguous; a request that names a list the household does not have is a clarification, not a guess.
  - Extend the assistant boundary and receipt types with list/item identities and accurate local-versus-synced outcomes. Require current household identity and expected record revisions at confirmation; repeated confirmation is idempotent. Update the data-disclosure text to cover list information actually sent, and fetch only the lists needed for the request.
  - Section administration, and the two fixed lists themselves, remain manual in this release.
  - Acceptance: these requests never create calendar events or ask for a child/date. Confirm once creates or updates exactly the reviewed items; cancellation and duplicate confirmation are harmless. Report local save versus cloud sync accurately. Stale proposals cannot alter another household or overwrite newer edits. Keep manual lists independent of the assistant service. Full detail in `LISTS_IMPLEMENTATION_PLAN.md` §8.

- [ ] **L07 / P1: Add manageable sections.**
  - Under the sections, one row: an **Add section** button, plus two icon-only buttons that put the sections into a mode.
  - **Edit** turns each section header into an editable name field, committed when the field is submitted or the mode is left; a blank name is refused rather than renaming a section to nothing. General offers no removal; every other section does, and removing it moves its rows into General with their wording intact.
  - **Rearrange** gives each section a grip; dragging a section onto another puts it in that position, and the sections animate into their new places.
  - Acceptance: both lists behave identically; General cannot be removed; removing a section never deletes tasks or groceries; a reorder survives relaunch and merge. Full detail in `LISTS_IMPLEMENTATION_PLAN.md` §6.

- [ ] **L08 / P1: Keep nesting shallow and lists fixed.**
  - Keep nesting at list → section → item → optional to-do steps. No separate folder entity and no nested sections.
  - The two lists are derived from the household id and are never created, renamed or deleted, so no screen may offer list creation.
  - Acceptance: nothing in the app offers to create a list or a nested section. Full detail in `LISTS_IMPLEMENTATION_PLAN.md` §6.

- [ ] **L09 / P1: Add advisory cleanup.**
  - Deterministic inactivity rules: groceries 14 days, to-dos 45 days, completed items excluded, and **Keep for now** suppressing that item's suggestion household-wide for 30 days.
  - Meaningful item edits, step changes, and reopening restart inactivity; viewing, reordering, and syncing do not, so a placement-only update must preserve activity metadata (see L02).
  - Show a compact **Still need these?** entry within the affected list; its review screen offers Keep and Remove with Undo. Evaluate when opening or foregrounding a list and when relevant data changes. No scheduled AI request and no automatic deletion.
  - Acceptance: both devices respect Keep; old unfinished items become eligible; completed items are excluded; removal always follows an explicit action.

- [ ] **L10 / P1: Verify and gate the release.**
  - Tests: empty initialization, deterministic default identities, legacy household loading, corrupt-list recovery, and household/connection switching; durable commands, explicit completion, duplicate handling, ordering, subtasks, group removal, batch deletion, and Undo after relaunch; two independent clients covering offline additions, different-field edits, same-field conflicts, simultaneous reorders, delete-versus-edit, retained deletion records, replay, and edits made during an in-flight upload; older household clients writing while list sync continues; failed list uploads retaining local pending changes; cleanup thresholds and household-wide snooze; and no schedule revision, calendar write, route request, credential rewrite, or reminder rebuild from list edits.
  - Register new sources in the full iOS target and production test inputs. Run `bash scripts/test-production.sh`, the AssistantLab tests when its interfaces change, and a full HeliPad build.
  - Verify the real app on compact iPhones with large Dynamic Type, VoiceOver, Reduce Motion, keyboard presentation, five-tab navigation, and household changes. Exercise two-device collaboration across separate networks using a test household.
  - Profile 500 groceries and 500 to-dos alongside representative event history. Target p95 visible check-off response under 100 ms and healthy active-list propagation within roughly five seconds. Record measured results rather than inferring performance from code.
  - Gate: complete the manual feature only when L01–L05 and L07–L10 pass. L06 follows as a separate assistant increment.

## Performance opportunities

- [ ] **PF01 / P1: Reduce work per save before adding rapid check-offs.**
  - Evidence: `AppStore.save` calls `reconcile`, stamps the full household, increments revisions, persists, and refreshes reminders (`AppStore.swift:691`). Reconciliation enumerates every series' dates and normalizes all records; stamping serializes every record; `persist` writes three Keychain values and a full JSON snapshot (`AppStore.swift:345,653,764`; `Persistence.swift:118`). These operations are synchronous on normal UI mutation paths.
  - Change: measure those stages, then separate schedule/list/settings invalidation. A grocery completion must not regenerate series date sets, recompute schedule suggestions, write unchanged secrets, or rebuild reminders. Track changed entities through domain commands; serialize immutable snapshots with ordered completion so an older async write cannot replace a newer one. Keep reliable local durability while coalescing cloud uploads.
  - Acceptance: instrument 100, 1,000, and 10,000 stored events plus 500 grocery and 500 to-do items. Record p50/p95 input-to-checkbox latency, main-thread time, encoding time, and writes per action on a physical supported phone. Proposed interaction target: p95 visible check-off feedback under 100 ms. A burst of 20 list changes causes no route/AI requests or notification rebuilds and remains intact after relaunch.

- [ ] **PF02 / P1: Bound routing work and update the reminder queue incrementally.**
  - Evidence: `NotificationService.applySchedule` removes all owned requests before calculating replacements, awaits routing for every future eligible event, and only then takes 48 candidates (`NotificationService.swift:96,137,168`). Every GPS update in `ContentView.swift:117` requests another rebuild. A 30-week schedule can therefore route hundreds of events for a queue of at most 48, and cancellation can leave the old queue already removed.
  - Change: prepare candidates before replacing requests, diff stable IDs, preserve unaffected requests, and serialize generations so a canceled run cannot overwrite a newer queue. Bound route lookups by an explicit reminder horizon and safe eligibility rules; do not restore the old bug of truncating raw events before fire-time eligibility. Replenish through foreground/schedule changes. Coalesce GPS changes, share in-flight route requests, and evict expired/least-used route cache entries. Current route caches have a TTL but no eviction (`GoogleMapsService.swift:97,450,487`).
  - Acceptance: a 30-week household has a documented upper bound on route requests per refresh, shared queue capacity, and correct nearest eligible reminders. Repeated saves/GPS updates neither empty the queue nor duplicate requests. Cancellation and route failures preserve valid previously scheduled reminders. F05 defines unknown-route behavior.

- [ ] **PF03 / P2: Reuse date and series projections across Plan and Family.**
  - Evidence: `AppStore.records()` flattens and sorts all history on every call (`AppStore.swift:285`). `PlanView.body` calls `summary` and `decisionQueue`, which calls `summary` again; `PlanScheduleView` separately computes day loads. `PlanViewModel.routineGroups` filters all records for every visible series. Family calculates caregiver loads twice for the workload card. Go already caches its analysis and its clock wakes once per minute; preserve these improvements.
  - Change: build a shared per-revision event/date/series index and one week analysis that supplies counts, decisions, day indicators, and routines. Cache only against relevant input revisions, including settings, locations, reviews, and remote merges. Reuse date formatting safely after profiling; avoid turning unrelated list updates into schedule invalidations.
  - Acceptance: diagnostics show one analysis per unchanged week/options revision across its consumers. Lists and clock ticks do not recompute Plan analysis. Editing a route/rule/event or receiving a remote merge invalidates the correct result. Week 30 browsing stays responsive in the PF01 fixture.

- [ ] **PF04 / P2: Reduce idle network and location activity.**
  - Evidence: foreground cloud polling runs every four seconds (`AppStore.swift:1135`) even while the user reads Family or Assistant. It already fetches only the revision when clean. Location updates run throughout foreground app use (`ContentView.swift:103`; `LocationService.swift:20`).
  - Change: measure requests and energy, retain prompt propagation while someone actively shops, and apply bounded backoff/jitter to idle or repeatedly failing polling. Keep an explicit sync action and immediate foreground/local-change refresh. Request sustained location only while a route/departure use case needs it; Lists should work without location permission. Avoid adding new server infrastructure solely as a speculative performance fix.
  - Acceptance: document freshness targets and idle/active request counts; no polling or GPS loop continues in the background. A revoked/failed connection does not retry every four seconds indefinitely. Grocery collaboration remains responsive and offline actions remain usable.

- [ ] **PF05 / P2: Profile view invalidation and large collections.**
  - Evidence: many screens observe the entire `AppStore`; save/reconcile publishes changes to broad collections. Plan and Family use eager stacks. The assistant has already isolated composer input from transcript publication; do not undo that optimization.
  - Change: use Instruments/SwiftUI profiling to identify actual redraw and allocation costs. Give list screens focused observable state, stable row IDs, and lazy/native list rendering. Cache expensive derived values only where measured; avoid a blanket framework rewrite. Review existing concurrency-isolation warnings before moving shared mutable state off the main actor.
  - Acceptance: 1,000 list rows scroll smoothly; typing an item does not rebuild calendar analysis or the entire list. Capture before/after traces, memory, frame hitches, and the device/build configuration. No performance claim is complete based on source inspection alone.

## Remaining functionality and correctness

- [ ] **F01 / P0: Make calendar imports complete before treating absence as deletion.**
  - Evidence: `GoogleCalendarService.fetchEvents` requests 250 items, never follows pagination, continues on HTTP failure, and decodes failure as an empty item array (`Services/GoogleCalendarService.swift:489`). `AppStore.mergeGoogleCalendarEvents` removes existing selected-calendar events absent from that response (`AppStore.swift:1690`). This path can interpret incomplete or failed retrieval as a remote deletion.
  - Change: fetch every page, preserve provider status/cursors, and return an explicit completeness result per calendar and time window. Reconcile deletions only after the relevant scope completed successfully; surface partial failures and preserve existing records. Scope token/cursor recovery and account switching explicitly. Keep bounded full import as a fallback if incremental sync is deferred.
  - Acceptance: more than 250 events import completely; a page-two timeout, 401/403, malformed response, or one failing calendar never deletes previously imported events. An actual remote cancellation is removed once a complete authoritative result confirms it. Extend service/transport tests, not only tests that feed arrays directly into merge.

- [ ] **F02 / P0: Make calendar writes durable and safe across retries and local edits.**
  - Evidence: the event editor exports in an untracked task with `try?` (`GoAddEditStopSheet.swift:1361`); exports replace the whole captured record or append it after the network await (`AppStore.swift:1757`), so an edit/deletion during export can be overwritten or resurrected. Provider creation uses a POST without a stable supplied event identity. Import does not persist each event's ETag into the export metadata, so a first update of an imported event can omit `If-Match`. Delete failures are swallowed (`AppStore.swift:1820`).
  - Change: persist an operation/outbox with stable idempotency identity, household/account, local revision, provider identity/ETag, and pending/failed/confirmed state. Revalidate context on completion and attach external metadata to the current record without replacing newer fields or reviving deleted rows. Make failed writes retryable and visible. Preserve reviewed export intent on edits.
  - Complete historical U07 recurrence mapping: current export loops materialized occurrences and `taskToEventPayload` has no recurrence rule. Decide and document provider-series mapping, one-occurrence exceptions, range changes, and explicit local-only deletion versus provider deletion. This needs a contract, not hundreds of silent single-event writes.
  - Acceptance: timeout after remote creation does not duplicate on retry; editing/deleting locally while export runs preserves the latest intent; switching households/accounts discards stale completion; a provider edit returns a conflict; partial series export can resume. Imported ETags, overnight/all-day boundaries, recurrence rules, and moved/deleted exceptions round-trip in a test account. Never describe a pending local save as exported.

- [ ] **F03 / P1: Preserve navigation state and make event links open the actual event.**
  - Evidence: `ContentView.swift:53` conditionally instantiates destination views whose Plan/Family view models are local `StateObject`s. Tab-state preservation therefore needs runtime verification. Assistant `onOpenEvent` ignores the event ID, silently returns for dates outside the current week, and sets `store.activeDay` before showing Plan (`ContentView.swift:268`), while Plan uses its own `currentWeek`/`selectedDay`.
  - Change: give destinations durable navigation/draft state and an explicit event route containing event ID/date. Select the correct week/day and open or highlight the actual record; explain deleted/inaccessible targets. Coordinate sheet transitions through dismissal completion rather than fixed 0.2-second delays. Add manual bounded event search as a P2 follow-up so finding history does not require AI or paging every week.
  - Acceptance: Plan week/day, Family segment, Assistant composer draft, and both new list drafts survive tab switches. Assistant links work for today, next month, and history. Review-to-editor/assignment opens exactly one sheet and retains edits. Verify behavior in the running iOS app.

- [ ] **F04 / P1: Bind route and geocoding results to the request that produced them.**
  - Evidence: hero routing writes one unkeyed `realTimeDeviceEta` after awaiting (`AppStore.swift:1242`). `GoView.swift:85` launches tasks on appearance, hero-ID changes, and GPS updates, but has no request generation check; editing the destination of the same event does not change its ID. `resolveMissingPlaceCoordinates` re-finds by name and checks only missing latitude after geocoding (`AppStore.swift:1190`), not unchanged address/household.
  - Change: key and validate async results by household, event/place identity, destination revision, origin, and request generation. Cancel obsolete requests, clear the prior hero's ETA immediately, refresh on relevant field changes, and attach geocoded coordinates only to the address that was resolved. Validate fix age/accuracy before labeling GPS live.
  - Acceptance: slow route A cannot replace route B after a hero switch; changing the same event's destination refreshes ETA; a failed request cannot leave another stop's time displayed. Changing/deleting an address or switching households during geocoding cannot attach stale coordinates.

- [ ] **F05 / P1: Show truthful travel/weather/reminder states.**
  - Evidence: `GoogleMapsService.calculateDriveTime` returns and caches a straight-line/30-mph fallback with the same shape as a provider result (`GoogleMapsService.swift:450`). `WeatherService` returns fixed sunny 78-degree data on failure and uses a cache unkeyed by location. `NotificationService.swift:144,174` converts unknown travel to zero and labels even non-travel events "Leave in 10 minutes". Reminder selection does not receive an active-caregiver/recipient scope.
  - Change: carry estimate provenance/freshness and an explicit unavailable state. Retain genuine cached weather with its timestamp, key it by location, and refresh when stale on foreground. Do not present sample weather or guessed travel as live. Distinguish an appointment reminder from a departure reminder, state what happens when travel is unknown, and define whose assigned/Family/TBD events trigger this device's alerts.
  - Acceptance: failed providers show last-known/estimated/unavailable truthfully; household/location changes do not reuse another place's weather. A home activity gets an activity reminder. A failed route does not silently claim an accurate leave time. Switching caregiver preferences reschedules only the intended device reminders, and lists never produce departure/driver alerts.

- [ ] **F06 / P0 for session isolation, P1 for UI: Finish Smart Suggestions integration.**
  - Evidence: `FamilyView.swift:90` sets `editingTemplateIsNew`, but the editor call still uses `editingTemplate == nil` (`FamilyView.swift:149`); a prefilled suggestion therefore appears as an existing shortcut with a delete action. `refreshLocally` only filters cached suggestions, so newly eligible candidates do not appear during that pass. AI refresh runs on the session task rather than a candidate revision (`FamilyView.swift:216`). Remote `AppStore.merge/apply` do not bump `contentRevision`. `AssistantSuggestionStore.swift:114` publishes results after await without validating the saved session/candidate revision; `loadedKey` is assigned but not used to reject stale results.
  - Change: wire the explicit draft state into the editor, publish new deterministic local candidates on relevant changes, and refresh ranking using changed candidates plus the existing cadence/backoff. Propagate remote event/shortcut changes to invalidation. Cancel/discard stale async results before storage or display and permit the new session to refresh. Gate background model requests on the app's data-disclosure choice while retaining local suggestions. Distinguish a valid empty AI ranking, malformed response, offline fallback, and successful model ranking in cache policy.
  - Acceptance: opening a suggestion shows New Shortcut with no deletion control; cancel is read-only and save creates once. A third qualifying event appears without leaving Family; a remotely created equivalent shortcut removes the card. An old household's delayed response never appears in the new one. Configuring AI after a local fallback permits ranking without a false 14-day successful-model cache. Tests must exercise the app store/UI integration, not only the pure policy structs.

- [ ] **F07 / P1: Correct assistant session and conversation lifecycle.**
  - Evidence: `AssistantHost.reset()` clears every transcript file, and `ContentView` calls it on caregiver changes and when closing Settings from Assistant (`AssistantHost.swift:133`; `ContentView.swift:76,98`). Host identity includes user/household but not changing date/timezone or service configuration, and there is no direct household-ID observer in the shell. `AssistantChatModel` captures its session when initialized.
  - Change: separate service reconfiguration, session switching, cancellation, explicit Clear conversation, and sign-out. Keep stored conversations scoped and only delete them through the appropriate explicit action. Refresh date/week/timezone context before a turn. Invalidate pending proposals and async work immediately when identity changes, and rebuild the visible assistant without requiring another tab switch.
  - Acceptance: opening/closing unchanged Settings does not erase history; returning to a caregiver restores their conversation; explicit clear affects the specified scope. Midnight/timezone changes resolve "today" correctly. Household switches during an active request neither display old results nor permit stale proposal confirmation. Historical A01 production authentication and Keychain token migration remain prerequisites for release.

- [ ] **F08 / P1: Complete accessibility, metric consistency, and recovery.**
  - Accessibility: `Core/Theme/HeliTypography.swift` uses fixed point sizes throughout. Adopt scalable text styles and adaptable layouts across existing screens and Lists; verify VoiceOver labels, checked state, contrast, Reduce Motion, and keyboard/safe-area behavior. Treat Liquid Glass as separate P2 polish, not a dependency of Lists.
  - Metrics (P2): Family's category fallback uses shortcut titles, while Assistant trends use `event.kind.category` (`Features/Family/FamilyViewModel.swift`; `AssistantLab/Sources/AssistantKit/Trends/TrendService.swift:97`). Share event metric/category definitions and explicit date ranges. Verify that "needs a driver" excludes activities that do not require transport, or relabel it as needing a caregiver. A household with no children should get a useful empty state. List items must stay excluded from these metrics.
  - Recovery: `HeliPersistence.load` quarantines decode failures and returns nil; unsupported versions return nil; save encoding errors are discarded (`Domain/Persistence.swift:101,118`). Add a visible recoverable-data state, backup/recovery route, explicit save failures, and a safe unsupported-version path before extending the snapshot. Never silently replace an unreadable household with sample data and then overwrite the recovery copy.
  - Acceptance: accessibility sizes remain usable on compact phones; equivalent periods produce matching Family/Assistant numbers; corrupted/unsupported snapshots retain recoverable bytes and show a useful action; failed persistence does not report a successful save. Cover lists in backup, restore, and explicit household reset behavior.

### Execution order and release evidence

1. **Complete L00 first:** this backlog and `LISTS_IMPLEMENTATION_PLAN.md` must agree before list code is written. Then fix F01/F02 calendar data risks and F06 session invalidation. Preserve the existing uncommitted feature work; inspect current references before modifying shared files.
2. Establish the L02 storage and L05 sharing contracts, then implement L01 (swipeable two-card home, list detail, navigation), L03/L04 (item workflows), L07/L08 (sections and fixed lists), and L09 (cleanup). Apply the PF01 separation of side effects alongside these commands. A local-only first milestone may ship before L05 synchronization, but it must say that edits are device-local until L05 passes. L10 gates the manual feature.
3. Address PF02 and F03/F04/F05 correctness, then profile PF03–PF05 with representative data. L06 assistant support follows working manual lists and only after L01–L05 and L07–L10 pass. A01/A02 and APNs delivery remain separate production-service work.
4. Run targeted migration, list-command, merge, async-race, and provider-failure tests, then the existing suites. Build the full iOS target and verify the real UI on an available iOS 17-compatible target and iOS 26+ where available. Report unavailable runtimes/credentials rather than substituting mock success.
5. Record device performance traces and two-device offline/online list scenarios. Require zero dropped rapid check-offs, zero cross-household results, no calendar/statistics/reminder changes from list edits, and successful old-snapshot recovery. Mark an item complete only with the evidence its acceptance criteria require.

## Historical plan and evidence

The material below preserves earlier decisions and observations. Its old line
numbers and unchecked boxes are historical; use the current status table and
backlog above when choosing implementation work. Prior claims about deployed
models, device verification, or missing integrations are not new verification
from this review.

## Scope and evidence

- Reviewed the reachable native Go, Plan, Family, Settings, and Onboarding surfaces and their store/service paths. The sibling web prototype is not an implementation target.
- Findings are source-verified unless explicitly labeled otherwise. No simulator UI walkthrough, production database access, or authenticated OpenAI request was performed. Simulator tooling is installed, but no simulator was booted at review time.
- Compiled the actual `Models.swift` and `PlanCore.swift` with a temporary command-line probe. For a September 14, 2026 start and Monday/Wednesday weekdays, `PlanCore.occurrences` produced:

  | Calendar weeks | Occurrences | First | Last |
  | --- | --- | --- | --- |
  | 1 | 2 | 2026-09-14 | 2026-09-16 |
  | 20 | 40 | 2026-09-14 | 2027-01-27 |
  | 30 | 60 | 2026-09-14 | 2027-04-07 |

  Compile and execution exited successfully. Temporary source and executable were removed. This verifies existing core capacity, not end-to-end editor behavior.
- OpenAI's official model documentation lists **GPT-5.6 Luna**, API ID **`gpt-5.6-luna`**, with Responses API, function calling, structured outputs, and streaming support. Deployment-account access remains an implementation-time check; do not silently substitute another model.
- The app currently targets iOS 17. Use availability-gated native Liquid Glass on iOS 26+ and an accessible material fallback on older supported OS versions.
- `PRODUCTION_REVIEW.md` and `README.md` contain historical observations. Current source already has absolute-date storage, real-clock defaults, Keychain integration secrets, revision-checked cloud writes, and per-record merge. Do not reintroduce or redo those fixes based on stale documentation.

Historical paths below are relative to `HeliPad/HeliPad/` unless prefixed otherwise. Priorities: **P0** data integrity/security prerequisite; **P1** requested feature or materially misleading behavior; **P2** smaller interaction/confidence patch. The current status table above supersedes these original unchecked boxes.

## V1 — what shipped, and where it diverges from this plan

Updated 12 September 2026. Section C is built and integrated; the navigation is
in the app.

**V1 is the direction currently in the code. The original direction in this
document is preserved below, unchanged, as the alternative.** Each divergence
below names the item it departs from and what reverting costs, so switching
back is a decision rather than an excavation.

### V1-a. The assistant is a fourth tab, not a raised centre launcher

*Diverges from: product decisions 5 and 7, and N01.*

Shipped: `Go | Plan | Assistant | Family` as four equal destinations, styled
like the existing tabs. Settings stayed as the top-right gear. The assistant is
a destination, not a presentation action.

Why: requested directly after the five-slot version was built and seen on
device. It also satisfies one of N01's own acceptance points better than the
original — a destination keeps its scroll position and unsent draft across tab
switches, where a sheet resets both.

September 13 clarification: retain this ordinary Assistant destination and the
top-right Settings gear. Add Lists as the fifth destination under N01/L01.
The previous alternative with Settings in the bottom bar and a raised
Assistant launcher is no longer an implementation option in this plan.

### V1-b. The assistant writes its own replies, grounded rather than templated

*Diverges from: A03's "do not directly render arbitrary model prose".*

Shipped: the model writes the sentence above the cards. Before it is displayed,
`ProseValidator` extracts every number in it and requires each to appear in the
output of an operation that actually ran that turn; a figure from nowhere
rejects the message and an app-owned sentence is shown instead. On a
conversational turn, where nothing was looked up, no figure is permitted at
all. A claimed result with no operation behind it is still refused.

Why: requested. The templated version was safe and read like a form letter.

What this keeps: the tool allowlist, argument validation, household-scoped id
resolution, and the typed cards. Off-topic requests are stopped by the
allowlist, not by templating, so that protection is unchanged.

**What this gives up, stated plainly:** grounding catches fabricated figures.
It does not catch a fabricated qualitative claim — "your week looks quiet" is
not checkable and the model can say it. A number written as a word slips
through. A03 as originally written promised more than the code now delivers.

Reverting: drop `message` from `FinalDecision` and have `AssistantEngine`
always render the template. One file each side.

### V1-c. Development plaintext to local hosts

*Not in the original plan.* `HeliPad/Info.plist` sets `NSAllowsLocalNetworking`
so the app can reach a relay on a developer's machine over `http://localhost`.
Internet destinations still require HTTPS. Remove it once A01 is deployed and
nobody needs a local relay.

### Status against the original checklist

- **A01** — not done. `tools/dev-relay/relay.py` in the assistant package is a
  laptop prototype that proves the shape (it authenticates, pins the model,
  refuses hosted tools and off-allowlist functions, and holds the key
  server-side) and has served real traffic from the simulator. No identity
  provider, no per-household limits, no TLS, no deployment. The session token
  is in UserDefaults and **must move to Keychain** as part of this.
- **A02** — partly. A real `gpt-5.6-luna` request succeeded from the deployment
  account; strict tool schemas, the structured-output format and `store: false`
  were all accepted. Per-household usage limits are not implemented anywhere.
- **A03** — done except as amended by V1-b.
- **A04** — done. Chat writes go through `AppStore.saveEvent(draft:recurrence:)`
  and `AppStore.assignEvents(_:)`, the same entry points the manual editors
  use.
- **A05** — done, with the metric definitions living in the assistant package
  rather than shared with Family yet.
- **A06** — done, as a tab rather than a sheet.
- **N01** — revised September 13 to add Lists as the fifth destination while retaining the top-right Settings gear, then revised September 20 to replace the segmented-control home first with a two-tile home and then with the swipeable two-card home, and to settle Lists as two fixed lists with no custom lists (`LISTS_IMPLEMENTATION_PLAN.md`). **N02** (Liquid Glass) — not started.
  **N03** — partly; sheet routing is now a single enum, but the Plan Review →
  editor transition named in N03 has not been exercised.

### Carried over, not addressed here

**Dynamic Type does not work anywhere in the app.** At the largest
accessibility text size the UI is pixel-identical to the default, because every
helper in `Core/Theme/HeliTypography.swift` returns a hard-coded
`Font.system(size:)`. Verified on device 12 September 2026. This predates the
assistant work and is tracked separately; it is an app-wide change and should
not be made piecemeal.

## Product decisions for implementation

1. **Finite weekly recurrence:** explicit Does not repeat / Weekly; select weekdays and either a number of calendar weeks or an inclusive end date. Offer convenient 20- and 30-week presets plus a custom count. No automatic 30-week default for old events, no infinite/background recurrence engine.
2. **Reuse materialized records:** keep `TaskRecord` occurrences and the existing absolute-date partitioning. Extend `PlanCore.occurrences`; remove the sheet's competing generation loop. Store the rule separately so a deleted last occurrence cannot change the apparent intended end date.
3. **Strictly app-scoped assistant:** Luna interprets natural-language requests into allowlisted app operations. Code controls authorization, validation, calculations, confirmation, and displayed result types. A prompt alone cannot guarantee app-only behavior.
4. **No silent AI writes:** event creation and assignment produce a review card; the user confirms exact changes. Manual and chat actions use the same domain mutation path.
5. **Bottom layout (September 13 direction; Lists home revised September 20):** `Go | Plan | Assistant | Family | Lists`. Preserve the four existing destinations and add Lists as the fifth button. The Lists home is two large horizontally swipeable cards, To-do and Grocery, one at a time, each centering the supplied artwork above the list name, its remaining count and an Open list action; the chosen card is preserved on return and there is nothing else on the screen. Settings remains the top-right gear and opens its existing sheet; it does not move into the bottom navigation or an overflow menu. Assistant remains an ordinary destination.
6. **Icons:** retain the existing Assistant speech bubble. Use a legible checklist symbol for Lists with the visible/accessibility label "Lists". Keep To-do and Grocery as the two named cards on the Lists home, with no custom-list row, no category switcher and no chip strip.
7. **Native appearance:** use five ordinary destination buttons with accessible hit targets and safe-area placement. No raised center launcher is required. N02 remains optional Liquid Glass polish with supported-version and accessibility fallbacks; it must not block Lists or relocate Settings.
8. **Calendar direction:** `../SYSTEM.md:313–319` supersedes the earlier read-only direction with reviewed pull/push. Existing Settings copy still says read-only. Implement real reviewed Google export for the current “Add to Google Calendar” promise; do not mistake `gcal = true` for a successful write. Apple Calendar connection can remain read-only as advertised. Chat-created events default to app-local unless external export is explicitly selected and authorized.

## A. Patch existing UI behavior

- [ ] **U01 — P0: Make Planning Rules save real settings.**
  - Evidence: `Features/Plan/Sheets/PlanPrioritiesSheet.swift:76–98` updates aliases in a copied dictionary; `Domain/AppStore.swift:85–127` prefers the unchanged canonical keys. Dinner time and notes have no effective save path. Roster and planner display/use different dinner defaults.
  - Change: use canonical typed mutations and one save. Connect dinner target to the existing `WeekPriority`/planning contract. Define notes as weekly planning notes and persist them with the selected week. Make Settings, Roster, and planning read the same values; migrate affected callers, not another alias layer.
  - Acceptance: change every field, save, reopen and relaunch; values agree across screens and change relevant planning results. Cancel leaves the store unchanged.

- [ ] **U02 — P0: Persist every durable visible edit.**
  - Evidence: direct bindings in `Features/Settings/SettingsView.swift:435–441,471–505`, suggestion adoption in `Features/Family/FamilyView.swift:71–74`, and place mutations in `FamilyLocationSheet.swift:191–240` bypass explicit save behavior. `AppStore` does not globally autosave `@Published` assignments.
  - Change: route durable settings, active-caregiver selection, adopted shortcuts, and place create/edit/delete through existing store mutation/save conventions. Keep screen filters transient. Do not add a parallel global autosave system.
  - Acceptance: with cloud disabled and no unrelated later edit, each action survives close/relaunch. Changing travel settings refreshes relevant reminders immediately.

- [ ] **U03 — P0: Use existing place integrity safeguards.**
  - Evidence: `Features/Family/Sheets/FamilyLocationSheet.swift:171–240` duplicates CRUD and bypasses `Domain/AppStore.swift:1440–1502` validation, home/base rename handling, and protected deletion checks.
  - Change: use `updateLocation`/`removeLocation`; preserve identity, references, Home, and caregiver origins. Surface actionable errors. Do not silently remove an in-use place or relocate Home to the first remaining entry.
  - Acceptance: reject duplicate names and invalid addresses; block deletion of Home/base/referenced venues. Renaming preserves all event/template/base references and persists.

- [ ] **U04 — P0: Invalidate stale address coordinates.**
  - Evidence: `SettingsView.swift:196–225,305–325`, `FamilyLocationSheet.swift:137–147,199–207`, and `AppStore.swift:1398–1421` retain old coordinates after address edits. Event coordinates take precedence over shared-place coordinates at `AppStore.swift:1130–1143`.
  - Change: bind verification and coordinates/place ID to the resolved address. Manual address edits clear stale metadata through an explicit store operation. Reject obsolete async selection results. Define propagation to events referencing the changed venue without rewriting explicit event-specific destinations.
  - Acceptance: select address A, type B, save: A's coordinates and “verified” badge cannot remain. A late response for A cannot replace B. Failed geocoding remains explicitly unresolved.

- [ ] **U05 — P1: Stop reporting overdue unfinished work as complete.**
  - Evidence: `Features/Go/GoViewModel.swift:133–158` excludes undone events 20 minutes after start; `GoDialCardView.swift:197–214` renders “Every handoff done” when there is no hero. Computed `looseEnds` is not surfaced.
  - Change: distinguish upcoming, ongoing/overdue unfinished, empty, and genuinely complete states. Keep outstanding tasks actionable; respect event duration and viewer scope.
  - Acceptance: an unfinished 15:00 event at 15:21 is not “all done.” Completing the last outstanding task transitions correctly. Long-running and all-day events have appropriate states.

- [ ] **U06 — P1: Distinguish unknown travel from zero driving.**
  - Evidence: `GoViewModel.swift:86–88` sums missing ETAs as zero; `GoWheelTimeView.swift:13–19` hides zero totals and reports no assigned driving.
  - Change: carry assigned-stop counts and known/unknown route counts alongside estimated minutes. Label partial totals; preserve Family's already-correct stop-count behavior.
  - Acceptance: assigned stops with unknown routes remain visible. Mixed known/unknown routes show a partial estimate, not a complete total or empty schedule.

- [ ] **U07 — P1: Deliver real calendar connections and reviewed export.**
  - Evidence: `SettingsView.swift:429–442` only changes booleans; `GoAddEditStopSheet.swift:220–224` offers “Add to Google Calendar” but saves only `gcal`. No native EventKit or Google Calendar provider implementation was found. Currently unreachable `PlanCalendarReviewSheet.swift:5–6,106–133` uses fabricated status/sample import/label-only push.
  - Change: implement EventKit permission plus selected-calendar import, Google OAuth with PKCE/authorized calendar selection, stable provider event/occurrence identity, incremental import and deletion handling, and preservation of app-owned overlays. Implement reviewed Google writes with provider version/conflict handling and recurrence mapping. A user must see pending/failed/confirmed external status separately from local save. Replace demo review code before making it reachable; reconcile stale read-only copy with current product direction.
  - Acceptance: denied/revoked permissions show disconnected state. Repeated imports do not duplicate records or erase assignments/completion/notes. “Added to Google Calendar” appears only after a real successful provider write. Exported recurrence/end dates and one-occurrence exceptions round-trip correctly. Cancellation and conflict do not silently overwrite remote events.
  - Dependencies: recurrence identity contract R01; real OAuth configuration. Temporary unavailable states are acceptable during rollout, but hiding switches alone does not complete this task.

- [ ] **U08 — P1: Implement driver-needed and reassignment alerts.**
  - Evidence: `SettingsView.swift:471–472` exposes both; only leave-by scheduling is connected at `AppStore.swift:663–675` and `Services/NotificationService.swift`.
  - Change: schedule/cancel the 12-hour unassigned warning and implement recipient-specific reassignment delivery via authenticated household/device membership and APNs. Respect alert preferences, permission, and assignment changes; do not equate data sync with notification delivery or promise delivery through Focus settings.
  - Acceptance: one eligible TBD event produces one warning; assignment/deletion cancels it. Confirmed reassignment targets the intended caregiver device(s), avoids duplicate notifications, and reports truthful delivery state. Disabled preferences prevent new alerts.
  - Dependencies: authenticated household boundary A01 for cross-device reassignment alerts.

- [ ] **U09 — P1: Make setup reruns use the current household.**
  - Evidence: `AppStore.swift:1235–1237` prefers historical `savedOnboardingDraft`; completion replaces household data at `1203–1217`.
  - Change: prefill from current people, places, shortcuts, and series, deliberately merging setup-only answers. Preserve explicit replacement review, cancellation, and warning about affected existing/future events.
  - Acceptance: after renaming a person, moving Home, and adding a shortcut/place, rerun shows current data. Cancel changes nothing; Finish applies exactly the reviewed replacement, not stale answers.

- [ ] **U10 — P2: Show Settings errors and explicit name-save behavior.**
  - Evidence: `SettingsView.swift:11,331,365,405` writes an unpresented error state; names commit only on keyboard submit at `349–408`.
  - Change: display validation failures and retain draft input. Provide explicit Save/Cancel for name changes; route through existing name validation/cascades.
  - Acceptance: duplicate/reserved names show a useful error without modifying valid data. Save persists; Cancel/back behavior does not silently pretend the edit was committed.

- [ ] **U11 — P2: Connect the Plan Shortcuts button.**
  - Evidence: `Features/Plan/PlanView.swift:49–51` supplies an empty callback to the haptic-enabled Shortcuts button.
  - Change: scroll/focus the existing shortcut section or navigate to existing Family Templates. Do not create another shortcut manager.
  - Acceptance: tapping reveals actionable shortcut content; zero shortcuts leads to its existing create/empty state.

- [ ] **U12 — P2: Make place confidence badges truthful.**
  - Evidence: `FamilyPlacesView.swift:121–122` treats a `routeKey` as “Calibrated”; `OnboardingBuild.swift:111–164` assigns keys to manual/estimated routes.
  - Change: distinguish manually supplied estimates, resolved coordinates, and measured routing. A lookup key is not evidence of calibration.
  - Acceptance: manually entered places never claim measured/calibrated travel; actual results display only supported provenance. Keep useful manual estimates, clearly labeled.

- [ ] **U13 — P1: Preserve reminder timezone and bounded queue correctness.**
  - Evidence: `NotificationService.swift:97–148` resolves dates with a household calendar, but constructs trigger components without carrying its timezone; the nearest-record limit is applied before all fire-time eligibility checks. Scheduling errors are discarded with `try?`.
  - Change: preserve intended timezone in notification triggers; select the nearest eligible fire times, share queue capacity with new alert types, and surface actionable scheduling failure. Replenish the bounded queue through existing save/foreground/rollover paths. Do not promise all 30 weeks are simultaneously queued or that iOS always runs background refresh.
  - Acceptance: household/device timezone disagreement and DST produce the intended reminder instant. Skipped/ineligible records do not crowd out later eligible reminders. Stable IDs prevent duplicates; unrelated notification identifiers are untouched.

## B. Add complete multiweek recurrence

- [ ] **R01 — P0: Add durable recurrence identity and migration.**
  - Targets: `Domain/Models.swift`, `Domain/Persistence.swift`, `Domain/AppStore.swift` fingerprint/stamp/merge paths.
  - Contract: independently stamped series definition keyed by `seriesId`, containing start date, household timezone, normalized weekdays, and a typed `weekCount` OR inclusive `throughDate` end condition. Add optional original-occurrence date/key and explicit override information to occurrences. Keep durable per-slot exclusions and whole-series deletion state; existing 30-day event tombstones alone are insufficient for 30-week schedules.
  - Keep finite materialized `TaskRecord` rows, existing IDs, absolute dates, and per-record state. Introduce additive decoding or an explicit old-version migration; the existing loader accepts version 1 only. Never infer series membership from title/location/kids.
  - Legacy series remain bounded to their existing members. Preserve holes, old IDs, and historical dates; never infer an intended 30-week extension. Optional template/onboarding defaults preserve old bounded behavior.
  - Acceptance: old snapshots decode without loss; round-trip and merge preserve new metadata and old records. Deletion survives beyond 30 days and stale-device sync. Define deterministic conflict precedence for series rules, per-slot exclusions/overrides, and series deletion; repeated merges converge without duplicate or resurrected slots.

- [ ] **R02 — P1: Extend the existing recurrence generator.**
  - Target: `Domain/PlanCore.swift:443–500` (`occurrences`, not `buildSeries`).
  - Change: use typed None/Weekly and end conditions. None produces exactly one selected date. Weekly enumerates valid weekdays on/after start through the inclusive end. Retain calendar-day arithmetic; never add fixed 604800-second intervals to local dates. Enumeration must not reuse one draft ID as the identity of every new row.
  - Count semantics: retain 1–52 Monday–Sunday calendar-week buckets, including the partial starting week. Label “For N calendar weeks, including the starting week” and always show actual first/last dates and occurrence count. End-date mode supports the requested 20–30-week range and longer valid ranges; any safety bound must be explicit validation, never silent truncation or a hidden 30-week cap.
  - Acceptance: Monday start Mon/Wed ×20 gives 40; Wednesday start Mon/Wed ×20 gives 39; Wednesday start Monday-only ×1 gives a useful no-occurrences error. Include a matching end date; reject end before start and invalid/empty weekdays; deduplicate weekdays. Cover leap day/year rollover and DST wall times, including documented nonexistent/repeated-time behavior.

- [ ] **R03 — P1: Add repeat duration controls and accurate previews.**
  - Target: `Features/Go/Sheets/GoAddEditStopSheet.swift:42–45,277–289,909–1011,1152–1280`.
  - Change: explicit repeat mode independent of weekday count; start date, weekdays, “For weeks”/“Until date,” presets 20/30, custom count, end-date picker, and generated summary. Load saved rule when reopening. Remove the manual one-week loop and emit one validated batch command.
  - Acceptance: a single Tuesday can repeat for 30 weeks; “Does not repeat” remains exactly one event. No occurrence precedes selected start. Preview count/range equals saved records and survives reopen. Invalid input stays in the sheet with a clear error.

- [ ] **R04 — P0: Make occurrence and whole-series actions safe.**
  - Targets: `AppStore`, `GoView`, `PlanView`, `PlanViewModel`, `PlanRoutinesView`, `PlanAssignSheet`.
  - Change: central store commands for create/edit/delete/assign. Resolve entire-series membership globally by `seriesId`, not current-week group. Separate weekly display rows from action scope. Show once-weekly series and unique weekday badges plus range/count; do not render one badge for every materialized event.
  - Scope: offer “This occurrence” and “Entire series.” Entire-series confirmation names total and historical affected counts; it is not silently week-only. Preserve done/locked/tentative/notes/calendar/buffer/location fields unless the chosen action explicitly changes them. Unrelated edits preserve mixed-driver assignments and occurrence overrides. Single edits retain series/original-slot identity; a weekday count of one never means detach or convert to one-off.
  - New slots use collision-free stable series/original-date identity; migrated slots keep existing IDs. Range shrink/extend changes only intended slots. Deleted/moved exceptions must not regenerate. No generation on read/clock rollover.
  - Acceptance: Mon/Wed → Wed preserves Wednesday's original ID/state. An edited/moved/deleted exception survives extension, relaunch and two-device sync. Lookalike one-offs remain untouched. “All occurrences” actually reaches all explicitly confirmed weeks. Simultaneous range change versus occurrence exception/deletion converges; one local save alone is not proof of atomic remote series behavior.

- [ ] **R05 — P1: Carry recurrence through shortcuts and onboarding.**
  - Targets: `GoAddEditStopSheet` shortcut writer, `FamilyCore`, `FamilyTemplateSheet`, `PlanView`, `OnboardingDraft`, `OnboardingBuild`, `OnboardingActivitiesStep`, `OnboardingReviewStep`, `AppStore.applyOnboarding`.
  - Change: preserve existing `TemplateItem.weekdays` at every writer/normalizer; the Go shortcut writer and onboarding currently omit them. Reuse the same duration controls and generator in setup. Prefer relative week-count presets for reusable shortcuts rather than stale absolute end dates. Selecting a shortcut opens a draft; editing a shortcut does not rewrite scheduled events.
  - Extend onboarding result to carry absolute/off-week records; currently `applyOnboarding` resets `plan` and the builder only returns week buckets. Replace weekday-only IDs with date-unique stable occurrence identities.
  - Acceptance: a 30-week setup survives Finish/relaunch with unique records across the entire range. Shortcut weekdays/duration defaults survive save/reopen. Old templates retain their existing bounded behavior until changed. Review count equals generated occurrences.

- [ ] **R06 — P1: Prove recurrence works across all consumers.**
  - Targets: Plan week browsing/assignment, Go rollover, Family weekly statistics, reminder scheduler, persistence/cloud merge, calendar adapter, assistant tool adapter.
  - Acceptance: browsing week 20/30 and advancing the app clock exposes the correct stored events without redating history. Family's current-week numbers do not count all future occurrences. Reminder limits/exceptions remain correct. Manual editor, onboarding, and assistant create the same recurrence for the same inputs. Imported provider recurrence uses provider identity, not guessed local lookalike groups.

## C. Add the app-only GPT-5.6 Luna assistant

- [ ] **A01 — P0: Establish the authenticated server boundary.**
  - Evidence: `Services/NeonDatabaseService.swift:89–95,106–156,184–248` is direct device-to-database HTTP SQL with user-supplied connection credentials. `AppConfig.swift` now has empty defaults; do not misreport a currently bundled database secret. No app AI gateway or authenticated household API was found in the inspected repository.
  - Change: add one deployable authenticated service for OpenAI requests and household-authorized cloud access. Keep OpenAI/database credentials server-side, session tokens in Keychain, and server-derived user/household membership on every request. The local caregiver picker is not authentication. Reuse the current `HouseholdCloudService` abstraction and preserve revision checks/per-record merge while replacing its production direct-SQL transport; no model-generated SQL or general-purpose query endpoint.
  - Preserve local/offline scheduling. Adapt the existing Swift domain for validated queries/proposals/mutations; do not build a second JS implementation of recurrence/planning or let chat independently replace the cloud household document.
  - Acceptance: another household's IDs/records and forged caregiver values cannot grant access. Revoked sessions fail safely. App bundle, snapshots, chat context and user-visible errors contain no provider/database secrets. Manual and chat changes follow the same persisted/synced path. If using Neon schema changes, use an isolated development branch, not production.
  - Deployment prerequisites: hosting credentials, identity-provider configuration, an authorized household migration path, and a server-side OpenAI project key. Supply these through deployment secret management, not chat or committed files.

- [ ] **A02 — P1: Integrate the exact Luna model through Responses.**
  - Change: server-configured model `gpt-5.6-luna`, strict schemas, bounded tool rounds/context/output, request cancellation, actionable service/quota errors, and per-household usage limits. Validate access with the deployment account; no silent model fallback. Do not assume a ChatGPT subscription supplies API billing.
  - Use minimal authorized context, `store: false`, and no hosted web search, shell, code interpreter, arbitrary MCP, file access, or other general-purpose tools. These capabilities are not needed even though the model supports some of them.
  - Acceptance: a real staging request uses Luna and returns an allowed structured app result. Offline, cancelled, timed-out, quota-limited, and invalid-schema responses leave household state untouched and offer truthful recovery.

- [ ] **A03 — P0: Enforce app-only operations and output.**
  - Allowlisted model-facing operations: `find_events`, `get_event`, `list_household_people`, `list_saved_places`, `preview_create_events`, `preview_assign_tasks`, `get_schedule_trends`, and bounded `get_app_help`.
  - Scope query inputs by authorized household, explicit date range, person IDs and validated fields. Resolve ambiguous names/dates through structured clarification, not guessed assignments. Pass current date, displayed date context, and household timezone explicitly.
  - Treat event titles/notes and user messages as untrusted data. The model cannot choose credentials, authorization, destinations outside app tools, or execute mutations. Reject unknown tools/fields/IDs. Return fixed app-scope refusal for unrelated requests and restrict mixed requests to explicitly identified app operations.
  - *(Superseded by V1-b: prose is rendered, with numeric grounding in place of templating. Original direction retained below.)* For the user's literal “only able to” requirement, do not directly render arbitrary model prose or raw streaming tokens. Render validated app-owned result/clarification/refusal templates and typed event/trend/proposal cards. User-supplied titles remain quoted data, not instructions. A second LLM classifier is not a hard security boundary.
  - Acceptance: off-topic requests, “ignore previous instructions,” injected event notes, invented household IDs, hidden tool names, and requests for web/code/medical/general knowledge produce no off-scope functionality or unauthorized disclosure. Valid scheduling questions still work.

- [ ] **A04 — P0: Implement reviewed, idempotent app actions.**
  - Change: tool adapters call the same Swift query/command layer used by manual UI. A proposal contains resolved event/person IDs, recurrence, timezone, changes, conflicts, affected count, and a revision/expiry token. Confirmation is a user action, never a model tool. Revalidate record versions, permissions and constraints at confirmation.
  - Creating events and assigning caregivers persist once through the existing save/merge pipeline. Reuse PlanCore conflict/availability rules; conflicts remain visible, not silently overridden. Clearly distinguish “saved on this device / sync pending” from “synced,” and app-local creation from external calendar export. Do not announce success until the corresponding operation succeeds.
  - Acceptance: “Schedule swimming every Tuesday for 30 weeks” produces the correct review, then actual events only after confirmation. “Assign next week's pickups to Alex” resolves a real caregiver and affected scope. Duplicate confirmation/network retry cannot double-create. Cancel does nothing; stale/deleted events force refreshed review instead of overwriting newer work.

- [ ] **A05 — P1: Compute real, bounded trends.**
  - Evidence: `Features/Family/FamilyViewModel.swift:25–54,66–125` computes current-week counts, not a historical trend service. `AppStore.records()` includes dated history; `plan.future` is not future-only.
  - Change: add date-range aggregates for event counts, assigned/unassigned workload, activity/category mix, and recorded completion. Reuse the same metric definitions in Family and assistant; deterministic code computes numbers, not Luna. Use scheduled/planned terminology for future data. Label completion as recorded state, not proof someone attended or was on time; no lateness trend without actual timestamps.
  - Acceptance: current-vs-previous equal-length periods match known fixtures; partial periods, zero baselines and missing history display meaningful “insufficient data”/absolute-change states. Exclude future rows from historical claims. Every result names its period and links to supporting events; no fabricated percentages or travel precision.

- [ ] **A06 — P1: Build the chat surface and data controls.**
  - Proposed new target: `Features/Assistant/`, with service/domain adapters in existing corresponding layers; register new files in the explicit Xcode project source list.
  - Change: native sheet with messages, composer/send/cancel, loading/connection state, structured clarification, event links, proposal confirm/cancel, and trend cards. Suggested prompts should cover finding events, creating a recurring activity, assigning tasks, and workload comparison. Keep the prior tab/week/filter state when dismissed and support reopening.
  - Explain before first use which household/children's schedule information is sent to OpenAI. Minimize fields and omit unrelated notes/addresses/coordinates by default. Keep chat history device-local by default, separated by authenticated user/household, with Clear conversation; clear sensitive state on sign-out/household change. Document provider retention accurately: `store: false` is not a blanket zero-retention guarantee.
  - Acceptance: keyboard and safe areas work on small phones; interrupted responses are not presented as final results; clearing history removes local content. Household switching cannot reveal previous household chat. Event links open the correct event/week; proposal buttons cannot be applied after their context becomes invalid.

## D. Add Lists as the fifth destination

- [ ] **N01 — P1: Keep Settings at the top and add Lists as the fifth bottom button.** *(Revised September 13, 2026, then revised again September 20, 2026, to replace the segmented-control home with the swipeable two-card home. The "Integrate the hybrid navigation — N01 / L01" task in `LISTS_IMPLEMENTATION_PLAN.md` is the authoritative navigation contract.)*
  - Target: `App/ContentView.swift`, `MainTab.lists`, and the Lists feature defined by L01. N01 owns navigation; L01 owns the Lists home and list details. Implement these as one coordinated change.
  - Change: use `Go | Plan | Assistant | Family | Lists`. The Lists home shows two large horizontally swipeable cards, To-do and Grocery, one at a time, with the supplied artwork above the list name, its remaining count and an Open list action. Each opens its list in one tap; there are no custom lists and nothing else on the screen. Accessible page controls offer an alternative to swiping. Keep Settings in the top-right gear with its existing sheet. Assistant remains a normal tab.
  - State: store navigation, drafts, expanded sections, completed-section visibility, and scroll anchors per household and list ID outside transient detail views; returning from another main tab restores the previous Lists position, and a household change clears that state.
  - Icon/layout: five ordinary destination buttons, a checklist symbol for Lists, readable labels, and at least 44-point hit targets. Retain mutually exclusive sheet routing for Settings and other presentations.
  - Acceptance: the fifth button opens Lists with either list one tap away and no second navigation step. Settings remains reachable from every destination through the top-right gear. All five buttons work on compact phones and with accessibility text sizes; keyboard and bottom safe areas do not hide list controls. VoiceOver announces Lists, the selected destination, each card's list name, remaining count and page position correctly.

- [ ] **N02 — P2: Apply actual system Liquid Glass with fallback after functional Lists delivery.**
  - Targets: navigation component, `Core/Theme/HeliColors.swift`, relevant safe-area padding in Go/Plan/Family.
  - Change: iOS 26+ availability-gated `GlassEffectContainer`, system glass button styles or `glassEffect`, with restrained tint and native touch feedback. Use safe-area placement and appropriate scroll-edge treatment; remove the opaque warm-white bar background/border stack where it interferes with glass. On iOS 17–18 use system material and a solid accessible fallback where transparency is reduced. Do not drop iOS 17 support merely to access glass APIs.
  - Acceptance: actual simulator/device visual confirmation over scrolling content, light/dark appearances, Reduce Transparency, Increase Contrast, Reduce Motion, Dynamic Type, landscape and compact iPhones. Bottom content remains reachable; glass layers do not muddy text or consume touches. Keep glass confined to navigation/controls, not every content card.

- [ ] **N03 — P2: Verify presentation and navigation transitions.**
  - Cover all five destinations, the Lists home and both of its cards, both list details, the section-management modes, the top-right Settings gear from each destination, onboarding presentation, keyboard appearance/dismissal, and rapid repeated taps.
  - Also exercise Plan Review → event editor. Source presents the next sheet before dismissing review (`PlanReviewSheet.swift:197–199,435–437`; `PlanView.swift:141–144`); whether this loses presentation is a runtime-sensitive inference, not a confirmed failure.
  - Acceptance: exactly one intended sheet opens; no invisible overlay, duplicate editor, lost draft, blocked bottom control, or content hidden behind the home indicator. Fix shared routing if the review transition fails.

## Execution order and agent ownership

1. **Integration owner:** establish R01 and A01 contracts, coordinate shared `AppStore`/model/persistence/project-file edits, and maintain a single UI command path. Before modifying exported symbols, inspect LSP references and migrate every caller.
2. **Independent work after contracts:** UI correctness (U01–U06/U09–U13), recurrence domain/editor (R01–R06), authenticated AI service/tool adapter (A01–A05), assistant/navigation UI (A06/N01–N03), and external calendar/notification providers (U07–U08). Parallel agents must have nonoverlapping file ownership; serialize shared `AppStore`, `Models`, persistence and Xcode-project mutations under the integration owner.
3. **Dependency gates:** A04 recurrence creation depends on R01–R04; A05 depends on stable historical identities and U05/U06 metric semantics; U07 recurrence export depends on R01; U08 remote alerts depend on A01. Navigation visuals can proceed against an agreed sheet interface, but a placeholder chat is not final delivery.
4. Each implementing agent owns its explicit tasks and acceptance cases. Skip project-wide build/lint/test commands while sibling edits are in flight; the integration owner runs consolidated validation after integration. No silent scope reductions, demo success messages, or unfinished buttons.

## Integrated release checks

- [ ] **V01 — Prove bug fixes and domain boundaries.** Keep targeted regressions for persistence, rule precedence, stale coordinates, overdue completion, recurrence boundaries/exceptions/concurrent merge, permission isolation, and confirmation idempotency. Run the existing `scripts/test-production.sh` once after integration and fix genuinely broken contract tests. Prefer scenario probes over tests that merely assert copied fields, implementation structure, or wording.
- [ ] **V02 — Exercise real end-to-end surfaces.** Build the app, launch on iOS 26+ and the oldest supported available runtime, and capture navigation/chat visual evidence. Run 20-/30-week and end-date flows through actual UI, relaunch, and two-device synchronization. Exercise staging Luna calls, calendar permission/import/export, and real notification registration/delivery paths with nonproduction test households. Missing deployment credentials must be reported precisely; mocked success does not satisfy these gates.
- [ ] **V03 — Finish documentation and remove obsolete paths.** After smoke scenarios pass, update README/product guidance/changelog to describe actual recurrence semantics, assistant limits/privacy, model configuration, calendar direction, navigation and support versions. Remove temporary probes and superseded one-week/date loops or fake calendar success code. Legacy `Features/Today`/`Ports` is not routed from the app and must not be used to implement chat; remove only confirmed-unused code after references are checked, not as an unrelated redesign. Leave unrelated user changes untouched.

## Official implementation references

- [GPT-5.6 Luna model and API ID](https://developers.openai.com/api/docs/models/gpt-5.6-luna)
- [OpenAI function calling and strict tool schemas](https://developers.openai.com/api/docs/guides/function-calling)
- [OpenAI production key/security guidance](https://developers.openai.com/api/docs/guides/production-best-practices)
- [OpenAI data controls and retention](https://developers.openai.com/api/docs/guides/your-data)
- [Apple: Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
- [Apple: Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)
