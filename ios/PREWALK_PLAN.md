# HeliPad prewalk: UI gaps, recurrence, assistant, and navigation

Reviewed September 11, 2026. Originally a planning deliverable with no
application source changed.

**Updated September 12, 2026.** Section C is implemented and integrated, and
the navigation changed. Read **V1** below first: it records what is actually in
the code and where it departs from the direction planned here. Everything after
that section is the original plan, preserved so the earlier direction can be
picked back up.

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

Paths below are relative to `HeliPad/HeliPad/` unless prefixed otherwise. Priorities: **P0** data integrity/security prerequisite; **P1** requested feature or materially misleading behavior; **P2** smaller interaction/confidence patch. All unchecked items are implementation work, not completed features.

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

What the original still has going for it: Settings in the bar frees the top
right entirely, and a raised centre action is a stronger affordance for a
feature you want discovered.

Reverting: small and self-contained. `MainTab` drops `.assistant`,
`PresentedRoute` regains it, `AssistantChatView` takes `.sheet` instead of
`.embedded`, and the deleted `Features/Assistant/AssistantLauncher.swift`
comes back from git history. The centre button and the five-slot bar were both
built and working, so this is a revert, not a rebuild.

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
- **N01** — superseded by V1-a. **N02** (Liquid Glass) — not started.
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
5. **Bottom layout:** *(superseded by V1-a; original direction retained.)* `Go | Plan | Assistant | Family | Settings`. Preserve the three existing destinations. Settings opens its existing sheet; Assistant opens a chat sheet without changing the selected destination. Move the top Settings gear into the bottom action rather than inventing another product screen.
6. **Icon:** a simple speech bubble containing a compact calendar/checkmark motif, in the existing forest-green palette. Use a legible custom vector/SF Symbols composition, not the sample's mascot or an OpenAI logo. Label it “Assistant”; VoiceOver label “Open HeliPad assistant.”
7. **Native appearance, honest tradeoff:** *(the raised centre action is superseded by V1-a; the Liquid Glass direction still stands as N02.)* a raised exact-center action is custom navigation, not a stock `TabView` tab-bar configuration. Use a minimal safe-area bar with actual system Liquid Glass APIs and standard buttons/navigation behavior. Do not simulate glass with a flat translucent fill or overlap an untouched system bar with conflicting tap targets.
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

## D. Add centered launcher and Liquid Glass navigation

- [ ] **N01 — P1: Build the centered five-slot action layout.** *(Superseded by V1-a. Retained as the alternative direction.)*
  - Target: `App/ContentView.swift:3–17,29–55,91–178`, plus a small navigation component if needed.
  - Change: Go, Plan, centered Assistant, Family, Settings. Retain three destination identities; Assistant and Settings are presentation actions, not fake selectable tabs. Use one mutually exclusive presentation route to avoid competing sheet booleans. Preserve destination state across tab switches and sheet presentation. Remove the relocated top gear.
  - Icon/layout: subtly raised circular center action, approximately 56 points, with the speech/calendar-checkmark symbol; outer actions have at least 44-point hit targets and readable labels. Do not copy the reference's oversized mascot/notched ornament.
  - Acceptance: center is geometrically centered regardless of selected label; every destination/action works; opening/dismissing assistant returns to the same screen/week/filter/scroll position. VoiceOver distinguishes selected destinations from launch actions.

- [ ] **N02 — P1: Apply actual system Liquid Glass with fallback.**
  - Targets: navigation component, `Core/Theme/HeliColors.swift`, relevant safe-area padding in Go/Plan/Family.
  - Change: iOS 26+ availability-gated `GlassEffectContainer`, system glass button styles or `glassEffect`, with restrained tint and native touch feedback. Use safe-area placement and appropriate scroll-edge treatment; remove the opaque warm-white bar background/border stack where it interferes with glass. On iOS 17–18 use system material and a solid accessible fallback where transparency is reduced. Do not drop iOS 17 support merely to access glass APIs.
  - Acceptance: actual simulator/device visual confirmation over scrolling content, light/dark appearances, Reduce Transparency, Increase Contrast, Reduce Motion, Dynamic Type, landscape and compact iPhones. Bottom content remains reachable; glass layers do not muddy text or consume touches. Keep glass confined to navigation/controls, not every content card.

- [ ] **N03 — P2: Verify presentation and navigation transitions.**
  - Cover assistant from each destination, Settings from each destination, onboarding presentation, keyboard appearance/dismissal, and rapid repeated taps.
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
