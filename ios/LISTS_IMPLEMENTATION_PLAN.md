# Full-app Lists: hybrid navigation and household collaboration

## Product decisions

Build Lists into HeliPad as the fifth destination: **Go · Plan · Assistant · Family · Lists**. Settings remains the top-right gear.

The Lists home screen has two large, horizontally swipeable tiles: **To-do** and **Grocery**, one visible at a time. Each centers the supplied SVG illustration above its title, remaining count, and Open list action. Tapping the card opens its default household list. Accessible page controls also switch cards; returning home preserves the selected card. This September 20 design revision replaces the earlier vertically stacked tiles with item previews.

There is nothing else on the home screen. No category switcher, no list-chip strip, and no custom-list row: Lists is two lists, and **sections** inside each list are how the household organises its work.

All lists are shared household-wide when household sync is configured, as confirmed. Without a connection, lists remain usable locally with accurate sync status. Individual permissions and external invitations are deferred.

This is a full-app implementation. Use the lab’s useful interactions and test cases as references; do not ship its sample data, private-link sharing, Mac service, or separate navigation shell.

## Ordered build tasks

### 1. Reconcile the agent backlog — L00

Update `PREWALK_PLAN.md` before implementation:

- Replace the “Lists: first implementation slice” section with these tasks and product decisions.
- Revise L01 and N01 to describe the swipeable two-card home, replacing the segmented-control requirement.
- Settle the list count: Lists is two fixed lists, and custom lists are not a feature. Keep dates, child links, assignments, reminders, recipes, prices, and AI categorization deferred.
- Retain L02–L06 identifiers; add L07–L10 below. Update execution order, the navigation status table, and conflicting historical navigation text.
- State that ListsLab is an experiment, not evidence that production acceptance criteria have passed. Preserve unrelated backlog items and existing working-tree changes.

**Acceptance:** An implementing agent has one current navigation contract, one sharing contract, and an ordered checklist with no conflicting custom-list instructions.

### 2. Establish production models, commands, and local storage — L02 / PF01

Create production list domain types under the full app’s Domain area:

- `HouseholdList`: stable identity, kind, name, ordering, creation/update metadata.
- `HouseholdListGroup`: list identity, name, ordering.
- `HouseholdListItem`: list/group identity, text, optional quantity and note, completion, ordering, activity/review metadata.
- `ListSubtask`: parent item identity, text, completion, ordering. Available for to-dos.
- A versioned list snapshot with deletion records and sync metadata.

Provide two deterministic default list identities within each household. Default names and positions are fixed; default lists cannot be deleted. New households receive empty lists, never lab samples. Every list has a stable default “General” group.

Use stable integer ordering ranks with record-ID tie-breaking. Reorder commands update the affected sibling ranks atomically. Array position and item text must never act as identity.

Introduce an observable `HouseholdListsStore`, owned by `AppStore`, with centralized commands for list/group/item/subtask creation, editing, movement, ordering, explicit completion, deletion, purchased-item clearing, review snoozing, and Undo. UI bindings must not bypass commands.

Persist lists in a versioned, atomic archive scoped to household and connection identity. Keep production list storage separate from the legacy household snapshot so an older app cannot discard unfamiliar list fields when saving. Preserve archives when changing households; never automatically upload the previous household’s lists into a newly selected household.

Use an ordered persistence writer and report local-save failures. Protect corrupt or unsupported archives from replacement and offer recovery. Schedule resets, setup reruns, and week rollover preserve lists.

List mutations publish a dedicated list revision. They must not call the existing schedule-wide save path, rebuild reminders, rehash events, rewrite unchanged credentials, or trigger calendar, routing, or suggestion work.

**Acceptance:** Every command survives offline relaunch; failed persistence is visible; old household data loads unchanged; schedule operations preserve lists.

### 3. Add live household synchronization — L05

Extend the existing Neon integration with a `HouseholdListsCloudService` interface:

- `fetchListsRevision`
- `pullLists`
- `pushLists`, requiring an expected remote revision

Store the versioned list snapshot in a separate `helipad_household_lists` record keyed by household ID. Use compare-and-swap writes and pull/merge/retry on revision conflicts. Older clients can continue writing the existing household record without erasing lists.

Coordinate list sync through the app’s foreground sync lifecycle. Maintain independent list revisions, pending state, and errors; a failure in schedule sync must not prevent list synchronization. Use the existing two-second active cadence while Lists is visible, bounded idle/error backoff, and stop polling in the background. Refresh on foregrounding and after local changes.

Reuse `RecordStamp` ordering, with independent stamps for editable fields, completion, placement/order, and review snoozing. Merge by identity. Different-field edits survive together; simultaneous edits to the same field resolve deterministically by stamp. Detail editors use expected field stamps and preserve stale drafts for review instead of overwriting incoming changes.

Keep list-specific deletion records without time-based expiry in this release. Deletion wins for the deleted identity, including edits arriving after long offline periods. Deleting a list suppresses its descendants. Undo restores fresh identities; it never removes a deletion record or overwrites a remotely edited record.

Capture household identity and connection generation for all async work. Discard responses from an obsolete session and clear visible drafts, navigation, and Undo state on household change. Switching caregiver within one household retains shared lists.

**Acceptance:** Two devices converge after concurrent additions, edits, checks, reorders, and reconnects. Deleted content does not resurrect. Old-client household uploads leave lists intact.

### 4. Integrate the hybrid navigation — N01 / L01

Add `MainTab.lists` and a production Lists feature area. Reuse the app’s colors, cards, and typography style with scalable text styles.

Implement:

- **Lists home:** two large, horizontally swipeable cards — To-do and Grocery — one visible at a time, each centering the supplied artwork above the list name, its remaining count and an **Open list** action, with accessible page controls and the chosen card preserved on return. Nothing else is on the screen.
- **List detail:** Back to Lists, title, remaining count, compact sync status, sectioned items, the section-management row, and bottom quick-add. The same screen serves both lists.

Store navigation, drafts, expanded sections, completed-section visibility, and scroll anchors per household and list ID outside transient detail views. Returning from another main tab restores the previous Lists position. Switching to a different household clears that presentation state.

Use readable body text, at least 44-point controls, lazy row rendering, and keyboard-safe placement above the app’s bottom navigation. Preserve the existing mutually exclusive sheet routing.

**Acceptance:** Each list is one tap from Lists home and there is no second navigation step; Settings remains reachable; drafts and scroll positions survive navigation.

### 5. Complete everyday item workflows — L03 / L04

For both list types, support quick-add, detail editing, check/reopen, manual reorder, move to another group, and removal with Undo.

The capture bar explicitly identifies its target group. Default to General, remember the last selected group per list, and let the user change it. A group’s “Add item” action preselects that group. Expanding a group must not silently redirect quick-add.

For to-dos, support notes and collapsible steps. Completing all steps does not automatically complete the parent; checking the parent preserves its step states for reopening.

For groceries, support optional quantity text and notes. Normalize whitespace and case for duplicate detection within the current list. Offer **Edit existing** or **Add another**; never silently combine quantities or units.

Completed items appear in a collapsed Completed/Purchased section. Reopening restores their group and ordering. Add **Clear purchased** with a batch Undo: target exactly the purchased IDs shown when invoked, and do not clear items subsequently added or checked by another device.

Use one persistent, household-scoped Undo batch for the latest destructive action. Preserve its saved contents across navigation and relaunch until it is undone or replaced by the next destructive action. Persist Undo locally only.

**Acceptance:** Rapid additions and checks lose no actions; quantity and notes survive reopening; bulk clearing and Undo preserve unrelated and concurrent work.

### 6. Add manageable sections and shallow nesting — L07 / L08

*(Revised: there are no custom lists. The two lists are fixed and derived, and
the section is the only thing a household structures.)*

Under the sections, one row: an **Add section** button, plus two icon-only
buttons that put the sections into a mode.

- **Edit** — each section header becomes an editable name field, committed when
  the field is submitted or the mode is left. A blank name is refused rather
  than renaming a section to nothing. The General section shows no removal
  control; every other section shows one, and removing it moves its rows into
  General with their wording intact.
- **Rearrange** — each section header shows a grip and can be dragged up or
  down, and the sections animate into their new places. Dropping a section onto
  another puts it in that position.

Keep nesting shallow: list → section → item → optional to-do steps. No separate
folder entity, no nested sections, and no list creation.

**Acceptance:** Both lists offer identical section behaviour. General cannot be
removed. Removing a section never deletes tasks or groceries. Dragging a section
reorders it and the change survives a relaunch and a merge.

### 7. Add advisory cleanup — L09

Use deterministic inactivity rules:

- Groceries: 14 days.
- To-dos: 45 days.
- Completed items: excluded.
- Keep for now: suppress that item’s suggestion household-wide for 30 days.

Meaningful item edits, step changes, or reopening restart inactivity. Viewing, reordering, and syncing do not.

Show a compact **Still need these?** entry within the affected list. Its review screen provides Keep and Remove with Undo. Evaluate when opening or foregrounding a list and when relevant data changes. No scheduled AI request or automatic deletion is required.

**Acceptance:** Both devices respect Keep; old unfinished items become eligible; completed items are excluded; removal always follows an explicit action.

### 8. Extend Assistant after manual workflows pass — L06 / P2

Add typed list queries and reviewed item-mutation proposals through the production list store. Extend the assistant boundary and receipt types with list/item identities and accurate local-versus-synced outcomes.

“Add milk to groceries” targets the Groceries list, and a to-do request targets the To-dos list. There are only two lists, so an unnamed target is never ambiguous; a request naming a list the household does not have is a clarification, not a guess.

Require current household identity and expected record revisions at confirmation. Repeated confirmation is idempotent. Update the data-disclosure text to cover list information actually sent; fetch only the lists needed for the request.

Custom-list/group administration remains manual in this release.

**Acceptance:** List requests never create scheduled events or require a child/date. Stale proposals cannot alter another household or overwrite newer edits.

## Verification and release gate — L10

Add meaningful production tests for:

- Empty initialization, deterministic default identities, legacy household loading, corrupt-list recovery, and household/connection switching.
- Durable commands, explicit completion, duplicate handling, ordering, subtasks, group removal, batch deletion, and Undo after relaunch.
- Two independent clients: offline additions, different-field edits, same-field conflicts, simultaneous reorders, delete-versus-edit, retained deletion records, replay, and edits made during an in-flight upload.
- Older household clients writing while list sync continues; failed list uploads retaining local pending changes.
- Cleanup thresholds and household-wide snooze.
- No schedule revision, calendar write, route request, credential rewrite, or reminder rebuild from list edits.

Register new sources in the full iOS target and production test inputs. Run `bash scripts/test-production.sh`, the AssistantLab tests when its interfaces change, and a full HeliPad build.

Verify the actual app on compact iPhones with large Dynamic Type, VoiceOver, Reduce Motion, keyboard presentation, five-tab navigation, and household changes. Exercise two-device collaboration across separate networks using a test household.

Profile 500 groceries and 500 to-dos alongside representative event history. Target p95 visible check-off response under 100 ms and healthy active-list propagation within approximately five seconds. Record measured results rather than inferring performance from code.

Complete the manual feature only when L01–L05 and L07–L10 pass. L06 follows as a separate assistant increment.

## Explicit implementation boundaries

The first release includes the two fixed lists, editable sections, steps, cleanup suggestions, and household-wide collaboration. The two tiles are the whole of the home screen; there are no custom lists, and the tiles remain fixed.

Use the household’s existing configured cloud connection; show **On this device**, **Waiting to sync**, or **Up to date** truthfully. Do not claim participant-based authorization or expose invitations that the current app does not support.

Preserve ListsLab as a separate reference app. Production implementation and verification must occur in HeliPad.

## Findings from the current working tree

Recorded September 20, 2026, after reconciling `PREWALK_PLAN.md` (L00) and
comparing this plan against the existing production source and the `ListsLab`
experiment.

### Plan-of-record status

- `PREWALK_PLAN.md` carries this plan's navigation contract, product decisions,
  and the L00–L10 backlog summary, with the earlier segmented-control
  description removed. L00 is closed.
- Production Lists code now exists in HeliPad: `MainTab.lists` is the fifth tab,
  `Features/Lists/` holds the home, detail and editor, and the domain, storage
  and cloud seam live under `Domain/` and `Services/`. See "Implementation
  status" below for what is built and what is not verified.

### Plan revisions after implementation started

Two revisions were made to this plan while it was being implemented, and both
supersede the text above:

1. **Sections replace custom lists.** Lists is two lists only, and the section is
   the only structure a household creates.
2. **The home is two swipeable cards**, not stacked tiles with item previews:
   one card visible at a time, each centering the supplied artwork above the
   list name, its remaining count, and an **Open list** action, with accessible
   page controls and the chosen card preserved. The artwork is line art drawn
   with `currentColor`, so it is tinted white on the card rather than shown as
   black ink on the fill.

### What the experiment supplies, and what it contradicts

`ListsLab/` is useful as interaction and test reference for L02–L05 and L09:
integer ordering ranks, "moving a row is not an edit" (a placement-only update
preserves activity metadata), section removal carrying its items forward,
duplicate detection on normalized text, batch clear with multi-item Undo,
retained-and-idempotent structural operations, and two-client convergence tests.

It must **not** be ported as-is. Eight concrete conflicts, each checkable
against the plan above:

| # | Experiment behaviour | This plan requires |
| --- | --- | --- |
| 1 | Group/item ordering ties break on **array offset** | Stable integer ranks with **record-ID** tie-breaking; array position is never identity |
| 2 | Removing a group moves its items to the **first remaining group** | Move them to **General**, and route incoming items referencing a removed group to General |
| 3 | Undo batch is **in-memory only**, lost on relaunch | One persistent household-scoped Undo batch that survives navigation and relaunch, persisted locally |
| 4 | Review snooze (`reviewAfter`) is **local per device** | **Keep for now** suppresses the suggestion **household-wide** for 30 days |
| 5 | Sharing is per-list via **anonymous token links** and a Mac HTTP service | Household-wide sync through the existing configured cloud connection (`HouseholdListsCloudService`); no invitations, no participant authorization |
| 6 | Lists are seeded from **sample data** | Two deterministic default lists per household, fixed names and positions, non-deletable, empty for a new household, each with a stable General group |
| 7 | Home is a **category switcher + chip strip + index sheet** | Two swipeable cards, one visible at a time, with the supplied artwork; no switcher, no chip strip, no custom-list row |
| 8 | `ListBoard` has no default/custom role; items carry only a group ID | Two fixed lists with no user-created lists at all; items carry list **and** section identity; `ListSubtask` exists for to-dos |

Two further gaps the experiment does not model at all: a **separate** versioned
archive (so an older client cannot discard unfamiliar list fields) and
**list-specific deletion records without time-based expiry**.

## Implementation status

Recorded September 20, 2026. Production code now exists in HeliPad.

### Built

| Task | What landed |
| --- | --- |
| L02 | `Domain/HouseholdLists.swift` (`HouseholdList`, `HouseholdListGroup`, `HouseholdListItem`, `ListSubtask`, `ListStamps`, `ListDeletion`, `HouseholdListsArchive`), `HouseholdListsQueries.swift` (queries, deterministic defaults, validation, rank normalisation), `HouseholdListsMerge.swift`, `HouseholdListsPersistence.swift`, `HouseholdListsStore.swift`. Two deterministic defaults per household with fixed names and positions and non-deletable role; a stable General group per list; integer ranks with **record-id** tie-breaking; a canonical array order so two converged documents compare equal; a separate versioned document per household with quarantine and a visible save failure. |
| L05 | `Services/HouseholdListsCloudService.swift` — `fetchListsRevision` / `pullLists` / `pushLists(expectedRevision:)` over the existing Neon SQL transport, in its own `helipad_household_lists` record with compare-and-swap writes. `HouseholdListsStore` runs its **own** sync loop, revision, pending flag and backoff, so a schedule-sync failure cannot hold lists back, and polling stops when the tab is not visible. Merge is per-facet (`content`, `completion`, `placement`, `review`); deletions never expire and are never removed by Undo. |
| N01 / L01 | `MainTab.lists` and the fifth tab button; `Features/Lists/` with the paged card home — one card at a time, the supplied artwork tinted white over the green To-dos and gold Groceries fills, accessible page control, and the chosen card held in `ListsPresentation.homeKind` so leaving and returning lands on the same one — plus list detail, with drafts, expanded sections, completed visibility and scroll anchors held above the destination switch. |
| L03 / L04 | Quick add with an explicit target section, detail editor, check/reopen, reorder, move to section, steps (ticking every step never completes the parent), quantity and notes, normalized duplicate detection with Edit existing / Add another, Clear purchased targeting exactly the rows checked at invocation, and one locally-persisted Undo batch that restores under fresh identities. |
| L07 / L08 | Section create, rename, reorder and delete, managed in place from one row under the sections: an Add-section button, an edit button that turns each section name into a field, and an icon-only rearrange button that makes the sections draggable with animation. General is unremovable and its siblings' rows move into General. |
| L09 | 14/45-day inactivity thresholds, completed rows excluded, household-wide 30-day Keep, evaluated from the stored activity timestamp so viewing, reordering and syncing do not restart it. |
| L10 | Production regression checks added to `Tests/ProductionRegressionTests.swift`; new sources registered in `HeliPad.xcodeproj` and picked up by `scripts/test-production.sh` (which globs `Domain/*.swift` and `Services/*.swift`). |

### Revised September 20, 2026: two lists, no custom lists

The product decision changed after the first implementation. Lists is **two
lists and only two**: To-dos and Groceries, derived from the household id, never
created and never deleted. The home screen is those two tiles and nothing else.

What followed from that:

- The whole custom-list layer was removed: `ListRole`, `createList`,
  `renameList`, `moveList`, `deleteList`, the Other-lists index, the create-list
  sheet, the `ListsPresentation.index` screen, and the list slot in
  `ListUndoBatch`. `ensureDefaults` now prunes any list that is not one of the
  two canonical ones, along with its sections and rows, and validation requires
  exactly the two derived identities.
- Sections are the only structure a household owns, so their management moved
  out of a secondary menu and onto the screen: Add section, an edit button for
  names (and removal of anything but General), and an icon-only rearrange button
  for dragging sections into a new order with animation.
- Tiles are filled: white on the forest green To-dos tile, white on a deep
  harvest gold Groceries tile (`HeliColors.tileForest` / `harvestGold`). Both
  are dark enough to keep white text legible.
- **The home is two swipeable cards, one visible at a time** (revised after the
  first build): each centres the supplied artwork — `ListsTodoArtwork` and
  `ListsGroceryArtwork` — above the list name, its remaining count and an
  **Open list** action. `ListsPresentation.homeKind` holds the chosen card,
  which is reset only when the household changes. Item previews were dropped
  from the home; the artwork is shipped as a template image so it takes the
  card's white instead of sitting on the fill as black ink.
- The checkbox circle and the item's name share a baseline in the list rows, so
  the circle reads as part of the row rather than floating under it.
- Both lists run the same screen and the same commands; the only differences are
  what an item may carry — a grocery may have a quantity, a to-do may have steps.

### Verified

- `bash scripts/test-production.sh` — passes, including the new Lists checks for identity, storage, commands, convergence, two-store sync, recovery, household switching, cleanup thresholds and schedule isolation.
- `xcodebuild -scheme HeliPad -destination 'generic/platform=iOS Simulator'` — **BUILD SUCCEEDED**.
- Rendered on an iPhone 17 Pro simulator: the fifth tab; the paged home with the
  to-do card (white artwork on green) and the grocery card (white artwork on
  gold), each with its name, remaining count and Open list, and the page control
  showing which of the two is up; the list detail for both kinds with their
  sections, capture target and truthful "On this device" status; the section
  edit mode with inline name fields and removal for everything but General; and
  the section rearrange mode with grips and the Add section row.
- Two defects found only by looking at the running app: custom lists received a
  **second** General section with the capture bar pointing at the empty
  duplicate (fixed before custom lists were removed entirely), and a section row
  whose checkbox sat below its text rather than on the same line (fixed with a
  baseline guide).

### Not performed

- Physical-device runs, VoiceOver, Reduce Motion, landscape, and large Dynamic Type on a real phone. Lists uses native scalable text styles, but that has not been exercised at accessibility sizes.
- Two-device collaboration across separate networks with an authenticated test household, and the p95 check-off latency measurement against 500 + 500 rows. Both need deployment credentials and hardware that were not available; nothing here should be read as evidence for them.
- L06 (assistant list operations) remains a separate increment, as this plan specifies.
