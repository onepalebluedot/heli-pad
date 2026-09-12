# AssistantLab — PREWALK_PLAN.md section C

**Integrated into HeliPad on 12 September 2026.** The package is now a
dependency of the app target and the assistant ships behind the centre button
in the bottom bar. This file still documents the package itself; the
integration is summarised under "In the app" below.

An isolated Swift package implementing the app-only assistant (tasks A01–A06).
**Nothing under `HeliPad/` is modified, and this package is not referenced by
the app.** The app is reached only through two protocols, and a mock
implementation of those protocols lets the whole chat feature run and be tested
now.

```bash
swift test                           # 87 tests
swift run AssistantHarness           # scripted scenarios + the refusal cases
swift run AssistantHarness --repl    # type your own messages
swift run AssistantHarness --attacks # just the adversarial cases
swift run AssistantHarness --live    # answer with a real model (see below)
```

## Testing against a real model

The app is designed to hold no provider key — that is A01, and it is why
`RelayLunaClient` sends a session token to your own service rather than a key
to OpenAI. For development on your Mac that is inconvenient, so there is a
second, deliberately quarantined path.

```bash
cp .env.example .env        # then put your key in it
swift run AssistantHarness --live
```

`.env` is ignored by git (both the repository root and this package's own
`.gitignore`). You can also pass the key for a single run without a file:

```bash
OPENAI_API_KEY=sk-... swift run AssistantHarness --live
```

| Variable | Meaning |
| --- | --- |
| `OPENAI_API_KEY` | Required for `--live`. Nothing else reads it. |
| `HELIPAD_ASSISTANT_MODEL` | Defaults to `gpt-5.6-luna`. If your account cannot reach that model you will see the provider's rejection — nothing falls back to a different model, per the plan. |
| `OPENAI_BASE_URL` | Optional, for a proxy or compatible endpoint. |

**What is quarantined, and how.** The key is read by `AssistantDevRelay`, which
is its own target. `AssistantKit` and `AssistantUI` do not depend on it, so
there is no build in which a provider key reaches the app — the separation is
enforced by the package graph, not by a convention. `AssistantHarness` is the
only thing that links it, and it is a command-line tool.

**What `--live` actually exercises.** Only the model changes. The request body,
the tool schemas, the strict structured-output contract and the reply parsing
all come from `ResponsesWire`, shared with `RelayLunaClient`, so a schema the
provider rejects here would be rejected in production too. The allowlist,
validation, household scoping, proposal building and rendering are identical.
Nothing is auto-confirmed, so a live run only reads the mock household.

This closes part of A02 — you can find out whether the account reaches the
model and whether the strict schemas are accepted — but not all of it: the
relay still does not exist, and per-household rate limiting belongs there.

## Layout

| Target | What it is |
| --- | --- |
| `AssistantKit` | The assistant. No UI, no app dependency, no network except through `LunaClient`. |
| `AssistantMocks` | A fixture household and a deterministic stand-in for the model. |
| `AssistantUI` | The SwiftUI chat sheet (A06), in the app's visual language. iOS 17+ / macOS 14+. |
| `AssistantDevRelay` | **Development only.** Reads a key from `.env` and calls OpenAI directly. Linked by the harness and nothing else. |
| `AssistantHarness` | CLI driver that prints the same cards the sheet draws. |

Inside `AssistantKit`:

- `Boundary/` — `HouseholdQueryPort`, `HouseholdCommandPort`, `AssistantSession`,
  and the value types. **This is the whole integration surface.**
- `Tools/` — the allowlist, strict JSON schemas, argument validation, and the
  router that executes calls against the household.
- `Results/` — the typed cards the UI can draw, and `AssistantCopy`: every
  user-visible sentence the assistant can produce.
- `Proposals/` — reviews, conflict detection, and idempotent confirmation.
- `Trends/` — deterministic period aggregates.
- `Model/` — the Luna client protocol, the relay HTTP client, the strict
  structured-output schema, and the system instruction.
- `Conversation/` — the engine (round budget, rejection budget, rendering) and
  the device-local transcript.

## How "app-only" is enforced

The plan's A03 asks for this to be a property of the code rather than of the
prompt. Five things do the work, and each has tests:

1. **The allowlist is an enum.** `ToolName(rawValue:)` fails for anything else,
   so there is no default branch that guesses. Eight operations, none of which
   write.
2. **Arguments are re-validated against the schema.** Unknown fields are
   refused rather than ignored; dates, times, enums and bounds are checked even
   though the schema already declares them, because strict-mode enforcement
   happens on the provider's side.
3. **Ids resolve inside the authenticated session's household or not at all.**
   A person or event id from another family is `unknownPersonID` /
   `unknownEventID`, not a lookup.
4. **Prose is allowed, but every figure in it is grounded.** The model writes
   the reply in its own words. Before it is shown, `ProseValidator` extracts
   every number in the sentence and checks each one against the numbers the
   app's own operations returned this turn; a figure that came from nowhere
   rejects the message and the app's own sentence is shown instead. On a
   conversational turn, where nothing was looked up, no figure is permitted at
   all. A `result` with no operation behind it is still a refusal.
5. **Confirmation is not a tool.** There is no operation the model can call that
   writes. Creating and assigning build a `Proposal`; a button applies it.

Prompt-injected text in an event title or note is therefore just text: there is
nothing outside the allowlist for it to reach. `UntrustedText` strips control
characters and caps length so a note cannot forge structure in a payload, and
event notes are not sent to the model at all.

## What is verified, and how

`swift test` covers the acceptance cases named in the plan:

- **Recurrence** matches the occurrence table the prewalk compiled from the
  app's own `PlanCore`: Mon/Wed from 2026-09-14 gives 2 / 40 / 60 occurrences at
  1 / 20 / 30 weeks, last dates 2026-09-16 / 2027-01-27 / 2027-04-07.
- **"Schedule swimming every Tuesday for 30 weeks"** produces a 30-row review
  and writes nothing; events appear only after confirmation.
- **"Assign next week's pickups to Alex"** resolves a real caregiver and the
  five real unassigned events.
- **Duplicate confirmation and post-failure retry** each reach the store once.
- **Stale or deleted records** force a fresh review instead of overwriting.
- **Cancel, expiry, and a review from another household** change nothing.
- **Off-topic requests, "ignore previous instructions", injected event notes,
  invented household ids, unknown tool names, unknown fields, and a year-long
  history sweep** all produce a refusal and no data access.
- **Trends** exclude future rows from recorded claims, report absolute change
  when the baseline is zero, say "insufficient data" rather than inventing a
  percentage, and label completion as recorded state.

## What is NOT done, and must not be reported as done

- **A01 — deployed for this household, not for users.**
  `tools/relay-worker/` is a Cloudflare Worker, live at
  `helipad-assistant-relay.es-johnv.workers.dev`, holding the OpenAI key as a
  Worker secret with one static token per device and a daily per-device
  request cap in KV. Verified in production: all five refusals hold, and the
  iOS app answers through it with no local relay running. What it still is
  not: real identity, session issuance, expiry, or server-derived household
  scoping — the app still asserts its own household id. Fine for two trusted
  phones on one API account; not fine for anyone else. The older note: `tools/dev-relay/relay.py` proves the
  shape and has served real traffic from the simulator, so `RelayLunaClient`
  is no longer unexercised. But it is a laptop prototype: no real identity, no
  per-household rate limiting, no TLS, no deployment. Hosting, an identity
  provider, a household migration path and a server-side project key are all
  still outstanding.
- **A02 — partly verified, 12 September 2026.** A live `--live` run against a
  real key confirmed: the account reaches `gpt-5.6-luna`; the strict tool
  schemas, the strict structured-output format and `store: false` are all
  accepted as written; and the model chose the correct operation on five of
  five requests, including refusing an off-scope one without calling a tool.
  Still unverified: the relay (below), per-household limits, and the quota,
  timeout and cancellation paths, which have only been exercised against
  injected errors rather than real provider behaviour.

  Three behaviours differed from the scripted planner and have since been
  fixed and re-verified live — see "What the live runs changed".
- **Dynamic Type does nothing.** See "Accessibility sweep" below. A real
  defect, inherited from the app's `HeliTypography`. Deliberately **deferred
  and tracked separately** rather than fixed here: the mirror must not diverge
  from the app, so this is one app-wide change to make in its own pass.
- **iOS 17 is untested.** Only the iOS 26.5 runtime is installed on this
  machine, so the oldest supported OS has never run this code. The package
  declares `.iOS(.v17)` and compiles against it, which is not the same thing.
- **VoiceOver has not been driven.** Labels are present (see below) but nobody
  has navigated the sheet with the screen reader on.
- **No per-household usage limit.** A client-side limit is advisory; this
  belongs on the relay and is not implemented anywhere. `--live` therefore has
  no spend ceiling beyond the round budget (4 model turns per message) and your
  own account limits.
- **Conflict detection is narrower than the app's.** It covers caregiver
  overlap with the travel buffer, same-child double booking, and the protected
  dinner window. It does not estimate travel between two places — the app's
  `PlanCore.candidate` does that, and it replaces the overlap test at
  integration rather than running beside it.
- **Trends have no completion timestamps to work from**, so there is no
  lateness or attendance metric and there should not be one.

## What the live runs changed

Three behaviours differed from the scripted planner on the first real run.
None was a hole in the boundary - every one produced a review, so nothing was
saved - but each was a bad default. All are fixed, and a fourth turned up while
verifying the fix.

1. **Invented duration.** "Swimming every Tuesday at 4pm" has no end time. The
   model chose 16:00-16:30; the scripted planner had chosen 17:00. Neither was
   what the user said. `end_time` is now nullable, and a null means the app
   applies `EventKind.defaultDurationMinutes` - a table matching durations
   already in household data - and states the assumption on the review card.
   A default that would cross midnight is refused rather than clamped.
2. **Saved places were never consulted.** The model passed a null location, so
   the event landed at Home even though "Eastside Pool" was saved. It had no
   way to know the place existed, because nothing told it to look. The
   instructions now require `list_saved_places` before a create, and a
   fallback to home is stated on the card along with the places it could have
   used instead.
3. **Lowercase title.** The schema asks for the user's own words, so `swimming`
   arrived lowercase where the manual editor would have written "Swimming".
   `TitleNormalizer` capitalises the first word only when that word is entirely
   lowercase, so "iPad setup" and "LEGO club" keep their shape.
4. **Wrong activity kind** (found while checking the fix for 1). The model
   filed swimming as `other`, which put it in the Other category and gave it
   the generic 60-minute default instead of a practice's 90. The raw enum
   values do not say that a sport is a "practice"; the schema description now
   spells the mapping out.

After the fixes, the same request produces `Swimming`, at `Eastside Pool`,
16:00-17:30, with the assumed duration stated - and the model calls
`list_saved_places` before creating.

These were only findable against a real model. The scripted planner had a
hardcoded swimming-to-pool mapping, which was quietly cheating; it now passes
a null end time so it exercises the same default path.

## Live AI in the simulator

`tools/dev-relay/relay.py` is a local stand-in for the A01 relay. It runs on
your Mac, holds the OpenAI key in its own process, and the simulator reaches
it over localhost. The app therefore talks to a real model **without ever
holding a provider credential** - which is the arrangement A01 asks for, not a
workaround for it.

```bash
cd tools/dev-relay && python3 relay.py     # terminal 1, reads ../../.env
```

Then run `AssistantLabDemo`, flip the switch on the blank page from
**Scripted** to **Live relay**, and open the assistant. The page reports
whether the relay is reachable.

This exercises `RelayLunaClient` - the production client, unchanged, with only
its base URL pointed at localhost. Until this existed, that client had never
made a successful request.

The relay also enforces the boundary server-side, because a client-side
allowlist is not a control. Verified by hand on 12 September 2026:

| Request | Result |
| --- | --- |
| Wrong session token | 401 |
| `model` other than the configured one | refused, named in the error |
| `store: true` | refused |
| A hosted tool (`web_search`) | refused |
| A function outside the allowlist | refused |

What it is not: real identity, per-household rate limiting, TLS, or anything
deployable. It is the shape of the service, running on your laptop.

## Seeing it

`AssistantLabDemo` next to this package is a throwaway host: a blank page with
the assistant launcher on it. It is not HeliPad, and it will be deleted once
A06 is integrated.

```bash
cd ../AssistantLabDemo
xcodebuild -scheme AssistantLabDemo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Then run it from Xcode, or install the built `.app` with `xcrun simctl`.

It links `AssistantKit`, `AssistantMocks` and `AssistantUI` only - deliberately
**not** `AssistantDevRelay`. The invariant holds: no app bundle contains a
provider key, and no app target can reach the provider directly. Live answers
come through the local relay above, exactly as they will in production.

The host does carry two things the shipping app will not: an
`NSAllowsLocalNetworking` exception so it can reach `http://localhost`, and a
hard-coded development session token. Neither is a secret - the token
identifies a local dev session to a relay running on the same machine.

### Styling

`Sources/AssistantUI/Theme/AssistantTheme.swift` mirrors the app's
`HeliColors`, `HeliTypography`, `HeliCard` and the Lucide-name-to-SF-Symbol
indirection from `HeliIcons`. The names match the originals one for one, so at
integration that file is deleted and the views point at the app's own theme -
a find-and-replace, not a redesign. Until then a palette change in the app has
to be mirrored by hand.

The cards follow the planner's existing idioms: ivory canvas, warm-white cards
with a sage hairline at radius 26, serif headings, heavy widely-tracked
eyebrows, a category-coloured spine on every event row, and caregiver-inked
owner chips and workload bars.

## Accessibility sweep

Run on 12 September 2026, iPhone 17 Pro and iPhone 17e simulators, iOS 26.5.

| Configuration | Result |
| --- | --- |
| Dark mode | **Fixed.** The sheet is light-only, like the app. The demo host was missing `UIUserInterfaceStyle = Light`, so in dark mode the system placeholder colour flipped and the composer's "Ask about your schedule" became nearly invisible against the fixed warm-white field. Setting it to match the app resolved it. Worth knowing: any host that does not force Light inherits that bug. |
| Dynamic Type (AX5) | **Fails.** Nothing changes at all. See below. |
| Increase Contrast | No change, no failure. The palette is fixed, so the setting is inert. Body text measures about 4.8:1 against the card, which passes WCAG AA. |
| Reduce Transparency | No change, no failure. The cards are solid fills, not materials, so there is nothing to flatten. |
| Reduce Motion | No change, no failure. The only animations are a 0.12s press scale and a scroll-to-bottom. |
| Landscape | Works. The sheet presents full screen, content scrolls, nothing is clipped or unreachable. Only three of the four suggested prompts fit above the fold, which is what the scroll view is for. |
| iPhone 17e (390pt) | Works. The 30-week review, its assumption note, the occurrence rows and the Confirm/Cancel row all fit without truncation. No SE or mini runtime is installed, so nothing narrower than 390pt has been tried. |
| iOS 17 | **Not tested.** Only iOS 26.5 is installed. |
| VoiceOver | **Not driven.** Annotations audited by hand, below. |

### Dynamic Type: the real finding

At the largest accessibility text size the UI is pixel-identical to the
default. A user who has turned text size all the way up gets nothing.

The cause is that every font goes through `Font.system(size:weight:design:)`
with a hard-coded point size. That API does not participate in Dynamic Type.
`AssistantTheme.swift` does this because it mirrors the app's
`HeliTypography`, which does the same thing on every one of its helpers - so
this is an app-wide issue that the assistant inherited, not one this work
stream introduced.

It is deliberately **not fixed here**. Making the mirror scale while the app
does not would make the sheet visibly disagree with every screen around it,
and the sizes are hand-picked, so switching to text styles changes the
default-size design too. The fix is a decision about the app's type system:
either pair each helper with a text style so it scales, or adopt
`@ScaledMetric`. Several labels are also 10-11pt, which is below what those
sizes should ever shrink from.

### VoiceOver annotations present

- Event rows are a single combined element with a spoken label ("Swimming, Sep
  15 at 16:00, Needs a driver") and a hint.
- The launcher, send/stop control and overflow menu carry explicit labels.
- Trend bars are combined per row and read as "Alex, 14" rather than as a
  bare number next to an unlabelled shape.

Not yet addressed: cards other than those read as loose runs of text rather
than grouped elements, and the uppercase eyebrows ("TRY", "RECORDED") may be
spelled out letter by letter by the screen reader. Both need a real VoiceOver
pass to confirm.

## In the app

Wired in on 12 September 2026. Two existing files changed:

- `App/ContentView.swift` — the assistant is a fourth destination (Go, Plan,
  Assistant, Family), styled like the other tabs. Settings stayed as the
  top-right gear. The two competing sheet booleans became one `PresentedRoute`
  enum so two sheets can no longer race.

  This departs from N01, which specified a raised centre launcher with
  Settings moved into the bar and the assistant as a presentation action. The
  five-slot version was built and then replaced on request. The tab version is
  arguably better on one of N01's own acceptance points: a destination keeps
  its scroll position and unsent draft when you switch away and back, where a
  sheet resets them. **PREWALK_PLAN.md N01 now contradicts the code and should
  be updated.**
- `HeliPad.xcodeproj` — local package reference plus `AssistantKit` and
  `AssistantUI`.

Four new files under `Features/Assistant/`:

- `AssistantHouseholdAdapter.swift` — the entire integration surface. Writes go
  through `AppStore.saveEvent(draft:recurrence:)` and
  `AppStore.assignEvents(_:)`, the same entry points the Go editor and Plan
  assign sheet use, so A04's "one path" requirement holds. `RecordStamp.counter`
  is the revision the concurrency check compares.
- `AssistantHost.swift` — builds the engine, and rebuilds it when the caregiver
  or household changes so no conversation survives the switch.
- `AssistantSettings.swift` — device-local settings, deliberately outside the
  synced household document and the merge fingerprint.

And one more existing file changed: `Features/Settings/SettingsView.swift`
gained an **Assistant** accordion section, so the service can be configured
without a terminal.

Verified on device: the Assistant tab opens inline, a live relay request
returns real household data, switching tabs and back preserves the
conversation, and `scripts/test-production.sh` passes unchanged.

### Known limits of the integration

- **Event links only work inside the displayed week.** `AppStore.weekStart` is
  `private(set)` and follows the device date; there is no API to jump to an
  arbitrary week. Rather than close the sheet and land the user on the wrong
  week, an out-of-week link currently does nothing. Adding that API is a
  shared-state change and belongs with the integration owner.
- **The session token lives in UserDefaults, not Keychain.** There is no
  session issuance to store yet. A01 must move it.
- **Plaintext is allowed to local hosts only.** `HeliPad/Info.plist` sets
  `NSAllowsLocalNetworking`, which lifts iOS's App Transport Security block
  for `localhost`, `*.local` and link-local addresses so the app can be
  pointed at a relay on a developer's machine. Everything on the internet
  still has to be HTTPS, so the real relay is unaffected. Xcode keeps
  generating the standard keys and merges them over that file.
- **The relay URL is unset by default**, so the assistant reports itself
  unavailable rather than opening a chat box that cannot answer. Configure it
  in **Settings › Assistant**, which has a URL field, a token field and a
  "Test connection" button that hits the service's `/health` endpoint. The
  unavailable screen links straight there.
- **Chat history is on disk now**, one JSON file per user+household under
  Application Support, written with complete file protection, capped at 100
  messages. It survives quitting the app and is removed by Clear conversation
  and on sign-out. A transcript that will not decode (card shapes change
  between app versions) is discarded rather than crashing the sheet.
- **The token field is a `SecureField`, but the value is still in
  UserDefaults.** Masking the characters on screen is not storage security;
  moving it to Keychain is part of A01.

## Integrating later

The adapter is small, and deliberately so.

1. Implement `HouseholdQueryPort` over `AppStore`: `records()` maps to
   `events(in:)`, `people`/`locations` map across directly, and
   `planningOptions()` supplies `PlanningContext`. Map `RecordStamp.counter` to
   `AssistantEvent.revision`.
2. Implement `HouseholdCommandPort` by calling the same save path the manual UI
   uses (`AppStore.save(syncToCloud:)` after the same mutations the editor
   performs) — not by writing storage directly. A04 depends on chat and manual
   edits sharing one path.
3. Replace `RecurrenceCore` with the extended `PlanCore.occurrences` once R01–R04
   land. The rule type here (`.weeks(n)` / `.until(date)`) is the shape those
   tasks describe; keep the rule stored separately from the occurrences.
4. Feed `AssistantSession` from server-derived identity. The local caregiver
   picker is not authentication and must not produce one.
5. `AssistantChatView` is presentation only and holds no schedule state, so N01
   can present it without disturbing the destination underneath.

Dependency gates from the plan still apply: A04's recurrence creation needs
R01–R04, and A05 needs U05/U06's metric semantics to be settled so Family and
the assistant count the same things.
