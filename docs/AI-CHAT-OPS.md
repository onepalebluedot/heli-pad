# AI chat agent — ops / tool contract

**Status:** draft on `feature/ai-chat-agent` — **DO NOT MERGE to main** until John greenlights.  
**Owners:** Devon (contract) · Jordan (Neon R/W) · Avery (chat entry + confirm sheet)

## 1. Goal

An AI API–powered chat that can **read and propose writes** against the household’s existing Neon blob — not a second database of chat intents.

## 2. Storage (non-negotiable)

| Piece | Rule |
| --- | --- |
| Table | `helipad_household` (`id`, `state_data` JSONB, `updated_at`) |
| Blob | `PersistedState` encoded as JSON via `cloudPayload()` |
| Revision | `updated_at::text` as `expectedRevision` on push (CAS) |
| Secrets | Never in cloud payload: `googleMapsApiKey`, `neonConnectionString`, `syncMetadata`, sync flags/timestamps |
| Schema | **No** parallel chat / message / intent tables |

Pull → propose → **human confirm** → push. On `NeonError.conflict`, pull again, re-diff, re-confirm.

## 3. Readable surface (`PersistedState`)

Agent context should be built from `cloudPayload()` fields:

- `people`, `locations`, `eventsByDay` (`[dayIndex: [TaskRecord]]`)
- `templates`, `routes`, `parentLocations`
- `homeAddress` / `homePlaceName`, household `buffer`, `trafficMode`, `dinnerProtection`
- `currentUser` (active viewer identity string)
- Notify prefs: `notifyLeaveBy`, `notifyDriverNeeded`, `notifyCrew`
- `settingsStamp` / per-record `stamp` (Lamport) for merge awareness
- `plan`, `weekStart`, `dismissedEventIds` as needed

Do **not** expose raw Neon connection strings or Maps keys to the model.

## 4. `TaskRecord` fields the agent may touch

| Field | Ops |
| --- | --- |
| `owner` / `lead` | Reassign caregiver (Tell-the-crew if crew-visible) |
| `done` | Mark complete / reopen |
| `time` / `endTime` / `bufferMinutes` | Leave-by / buffer nudges (derive leave-by from travel+buffer like Today; persist by shifting schedule fields consistently) |
| `notes` | Optional clarification only — not a back-channel for crew notify |
| `stamp` | Must be refreshed on real content change (existing Lamport rules) |

**Out of scope for v1 agent writes:** inventing new people/places, rewriting `routes` wholesale, wiping `eventsByDay`, changing secrets/connections, silent multi-task bulk without per-op confirm.

## 5. Tool ops (propose → confirm → apply)

Each tool returns a **Proposal**, never a silent Neon write.

### `get_household_snapshot`
- Input: `householdId` (Jordan supplies pull)
- Output: redacted `PersistedState` + `revision`

### `find_tasks`
- Filter by day, viewer (`currentUser` / owner), kid, kind, done, text
- Output: task ids + glanceable summary (title, owner, time, leave-by if travel, done)

### `propose_reassign`
- Input: `taskId`, `newOwner` (and `newLead` if distinct)
- Crew-visible if owner/lead change affects another caregiver → **requires Tell-the-crew confirm**

### `propose_leave_by_or_buffer`
- Input: `taskId`, either absolute leave-by / time shift **or** `bufferMinutes` delta
- If \|Δ leave-by\| ≥ 10 min (or buffer change that shifts leave-by ≥ 10) → **Tell-the-crew confirm** (same gate as Today)

### `propose_mark_done`
- Input: `taskId`, `done: Bool`
- Usually local-confirm; crew notify only if product rules say so (default: confirm sheet, notify optional)

### `propose_tell_the_crew`
- Input: `taskId`, change summary, recipients
- Always confirm; maps to existing notify grammar (Send / Don’t notify) — never swipe-only dismiss

### `apply_proposals` (Jordan)
- Input: list of accepted proposals, `expectedRevision`
- Applies to in-memory `PersistedState`, stamps records, `pushHousehold(..., expectedRevision)`
- On conflict: return conflict + fresh snapshot; **do not** retry without a new confirm

## 6. Confirm-before-write (crew-visible)

Align with Today / `NOTIFY-PATH` / SWIPE-TAP-MAP:

- Critical actions are **tap-confirm** (Send / Don’t notify / Ask X)
- Swipe-down / dismiss from Tell-the-crew → **back to edit/review only** — never skip Send, never silent discard mid-change
- Chat UI must not bury the Today leave-by / hottest Task hero (Avery)

## 7. Active viewer

- Proposals are interpreted in the **active viewer** frame (`currentUser` / sticky caregiver)
- Do not label-swap a merged household view; mom’s chrome must not paint dad’s

## 8. SYSTEM.md alignment

- Root model remains broader `Task` / `TaskRecord` with optional travel
- Overlays (assignee, done, buffer) live in the blob + shared Neon path — Calendar stays read-only v1
- AI chat is an **agent over the same state**, not a new product surface that invents parallel truth

## 9. Definition of done (branch)

- [ ] Ops contract reviewed by Devon + Jordan
- [ ] Neon pull/propose/confirm/push path with CAS (Jordan)
- [ ] Chat entry + confirm sheet that preserves Today hero (Avery + Design)
- [ ] SYSTEM.md §10 present on branch
- [ ] Draft PRs labeled **DO NOT MERGE** until John says otherwise
