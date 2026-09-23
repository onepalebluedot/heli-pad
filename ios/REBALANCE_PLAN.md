# Plan › Rebalance: removed

Audited September 22, 2026, and **removed from the iOS app on the same day.**
This document records why, what was deleted, and what a future version would
need. It is not a backlog item.

This matches the web app, where `design.md` already records Plan's rebalance
entry points as removed. The iOS port had brought them back.

## Why it was removed

**For a real household, it did nothing.** It only produced proposals for the
built-in sample family. For anyone who finished onboarding it always said
*"Schedule is already optimal"*. That message was false: the week was never
evaluated.

1. **No drive times for real places.** Candidates with an unknown route were
   filtered out (`.filter { !$0.conflict && !$0.unknown }` in
   `PlanCore.proposals`). Routes came from `AppStore.travel`, which only reads
   the static `routes` matrix. Only the sample household has that matrix
   (`RoutesData.swift`). Onboarded places have a `routeKey` but no matrix
   entries. The result: every caregiver was unknown for every stop, and there
   were zero proposals.
2. **It skipped the stops that need help most.** Stops marked `tentative` were
   excluded outright. Unassigned stops at an unrecognised place were dropped as
   unknown.
3. **Load meant travel minutes only.** A caregiver with six home stops showed
   `0m` and looked idle.
4. **It didn't know who was available.** The model has no working hours, so it
   could suggest someone who is at work.
5. **Cost and design.** The sheet computed proposals inside `body`, at roughly
   O(n² × crew) on every render. The pass was greedy and depended on order, and
   Apply was all or nothing.
6. **It overlapped with Assign.** `PlanAssignSheet` already ranks caregivers
   for a single stop using the same `PlanCore.candidate`. Review and Assign
   remain the way to cover and fix stops.

## What was deleted

- `Features/Plan/Sheets/PlanRebalanceSheet.swift` and its Xcode project entries
- the Rebalance button and the `onRebalance` parameter in
  `PlanCommandCardView`. "Review assignments" now takes the full action row.
- `showRebalanceSheet` in `PlanViewModel`, and its `.sheet` in `PlanView`
- `PlanCore.proposals`
- `RebalanceProposal` and `ProposalsResult` in `Models.swift`

Nothing else referenced them: not the assistant package, not the tests. The
data model is unchanged, so no stored household is affected.

## If it comes back

Only build it again as a week-level answer to one question:

> *Is the week covered, is anyone double-booked, and is one of us carrying all
> of it? Fix what you can, with as few changes as possible.*

Before it can say anything true, it needs:

1. **Drive times that exist for real places:** the routes matrix when present,
   then cached Apple Maps times between geocoded places, then a labelled
   straight-line estimate. An unknown route should lower confidence, not
   discard the candidate.
2. **Load as committed time** (stop duration plus travel), with home stops
   counted.
3. **Optional caregiver availability** on `Person`, so it never proposes
   someone who is at work. Honour `locked` stops.
4. **A deterministic search off the main thread,** in this order: cover
   unassigned and tentative stops, most constrained first; then fix clashes
   with moves and swaps; then even out the load with a churn penalty, so it
   never reshuffles the week for a few minutes.
5. **An honest interface:**
   - the entry point appears only when there is something to fix;
   - per-row accept, then apply through `AppStore.assignEvents` so recurring
     overrides are kept;
   - undo afterwards;
   - an explicit line for stops it couldn't judge. Never "already optimal"
     without having looked.

An assistant tool that returns the same proposals, reviewed through the
existing proposal flow, would be the natural second entry point.
