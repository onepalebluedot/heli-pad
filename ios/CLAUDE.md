# HeliPad iOS

A SwiftUI family-logistics app. Five tabs, one shared store, one linked local
Swift package.

## Where the app is

The app target is `HeliPad/HeliPad/`. Everything below is relative to it unless
it starts with `ios/`.

Tabs are declared in `App/ContentView.swift` — the `MainTab` enum and the
destination `switch` in `body`. Start there when you need to know what a tab
actually renders.

## Tab → folder

| Tab | Folder | What else it touches |
|---|---|---|
| Go (⚡) | `Features/Go/` | `Domain/RoutesData.swift` |
| Plan (📅) | `Features/Plan/` | `Domain/PlanCore.swift` |
| Assistant (💬) | `Features/Assistant/` **and `ios/AssistantLab/Sources/`** | see below |
| Family (👥) | `Features/Family/` | `Domain/FamilyCore.swift` |
| Lists (☑️) | `Features/Lists/` | `Domain/HouseholdLists*.swift` (5 files) |

Feature folders follow one shape: `XView.swift` + `XViewModel.swift` at the top,
with `Views/` for the pieces that view composes and `Sheets/` for anything
presented modally.

**Assistant is split, and the split matters.** `Features/Assistant/` holds only
the host and the adapter between app types and assistant types — `AssistantHost`,
`AssistantHouseholdAdapter`, `AssistantSettings`, `AssistantSuggestionStore`. The
chat UI and the engine live in the local package at `ios/AssistantLab/Sources/`:
`AssistantUI/AssistantChatView.swift` for the UI, `AssistantKit/` for the engine,
tool catalog and router, proposals, suggestions and trends. A change to how the
assistant behaves is almost always a package change, not a `Features/` change.

**Lists is four files.** `ListsHomeView.swift` (the tab root `ListsView` plus the
two list cards), `ListsDetailView.swift` (one list, open — the big one),
`ListsItemEditorView.swift` (the item sheet), and `ListsPresentation.swift`.

`ListsPresentation` is the pattern to understand before editing Lists: the
destination `switch` in `ContentView` rebuilds a fresh view on every tab change,
so drafts, expanded sections, the target section and scroll anchors are held
above it in an `ObservableObject` keyed by household. Do not move that state into
`@State` inside a Lists view — it will be lost on a tab switch.

## Shared layers

- `Core/Theme/` — `HeliColors` (all colors are tokens here; do not inline hex in
  a view), `HeliTypography`, `HeliIcons`, `TimeFormat`, and `Components/`
  (`AvatarDisc`, `GoDialInstrument`, `HeliCard`).
- `Domain/` — pure-ish logic and models. `AppStore.swift` is the central
  `ObservableObject` every tab observes; it is ~2,700 lines, so grep it rather
  than reading it whole. `Models.swift`, `Persistence.swift`, and the
  `HouseholdLists*` family (model, store, queries, merge, persistence).
- `Services/` — the outside world: Google Calendar, Google Maps, Neon database,
  household-lists cloud sync, location, notifications, weather. These sit behind
  protocols declared in `Ports/Ports.swift`, which is what the tests mock.
- `Features/Settings/`, `Features/Onboarding/` — reachable from the top bar and a
  full-screen cover, not from the tab bar.

## Traps

- **`Features/Today/` is dead code.** Nothing outside that folder references
  `TodayView`, `TodayViewModel` or `EditSheet`. It is the predecessor of the Go
  tab. Do not read it to learn how the app works, and do not change it expecting
  a visible effect.
- **`ios/ListsLab/` is a standalone prototype, not the app.** The Xcode project's
  only local package reference is `../AssistantLab`, and no app file imports
  `ListsKit` or `ListsUI`. Real Lists code is `Features/Lists/`.
- `ios/AssistantLabDemo/` is a demo harness for the assistant package, not a
  shipping target.

## Build and test

Build the app (scheme `HeliPad`, project `HeliPad/HeliPad.xcodeproj`):

```bash
xcodebuild -project HeliPad/HeliPad.xcodeproj -scheme HeliPad -destination 'generic/platform=iOS Simulator' build
```

Pass `-derivedDataPath` to a temp directory if you do not want build output in
the working tree — `HeliPad/build/` is **not** gitignored, only `DerivedData/` is.

Domain and service regression tests compile a subset of sources directly with
`swiftc` rather than running through Xcode:

```bash
./scripts/test-production.sh
```

Assistant package tests are ordinary SwiftPM tests in
`ios/AssistantLab/Tests/AssistantKitTests/`.

## Conventions

- Comments explain *why*, not what — they name the alternative that was rejected
  and the failure it caused. Match that density and voice; do not add narration
  comments to code that reads plainly.
- Colors come from `HeliColors`, type from `HeliTypography`. A new hex literal in
  a view is a mistake.
- Tap targets are 44pt: views use `.frame(minHeight: 44)` or
  `.frame(width: 44, height: 44)` plus `.contentShape(Rectangle())`.
- Accessibility labels, values and hints are written on interactive views as a
  matter of course, not added later.
- iOS-only files are wrapped in `#if os(iOS)`.
