# Heli-Pad

Heli-Pad is a native iOS app for household schedules, driving handoffs, shared to-dos, and groceries. The SwiftUI app lives in [ios/HeliPad](ios/HeliPad). The root HTML application is an earlier design prototype, available at [heli-pad.vercel.app](https://heli-pad.vercel.app).

## In the app

The bottom navigation has five tabs. Settings stays in the header gear button.

- Go shows the next departure, the day's stops, and caregiver driving time.
- Plan manages schedules, recurring activities, assignments, and calendar review.
- Assistant answers household questions and prepares changes for review before saving.
- Family manages caregivers, children, places, activity shortcuts, and shortcut suggestions.
- Lists holds household To-dos and Groceries, independent of dates and children.

### Shared lists

Swipe between two large illustrated tiles to open To-dos or Groceries. Inside each list, collapsible sections keep longer lists manageable. Items support check-off, notes, grocery quantities, and to-do steps. Choose Reorder, then use the up and down arrows to move a section. Moves animate unless Reduce Motion is enabled.

Cleanup suggestions flag older items for review. Nothing is removed automatically.

Lists save locally and sync through the household's Neon connection. They use a separate cloud record from the calendar data, revision-checked writes, and merge logic for edits from different devices. Offline changes stay pending. The list screen shows sync status, explains failures, and offers Retry sync.

The current list archive format is version 2. Older custom lists migrate into sections under To-dos or Groceries while preserving their items and details. This addresses the earlier error, `expected exactly the To-dos and Groceries lists`. Update all household devices to the current app build before using the migrated lists together. Older builds cannot read the new format.

### Assistant

The assistant can read To-dos and Groceries and prepare list additions, including quantities and sections. Additions use the same local store and sync path as manual edits. A review card requires confirmation before anything is saved; the result distinguishes a local save from a completed sync.

For events, a time without a date defaults to today in the household's time zone. Activity-based duration defaults reduce follow-up questions, including one hour for a lesson. Assumptions appear in the review and can be edited. The assistant still asks when an ambiguity would materially change the request.

The app calls an authenticated relay. Provider API keys belong on the relay, not in the iOS app or this repository. List queries send item text, quantities, sections, and completion state; item notes and steps are not included unless the user types them into chat.

## Run the iOS app

1. Clone this repository and open `ios/HeliPad/HeliPad.xcodeproj` in Xcode.
2. Select the `HeliPad` scheme and an iOS simulator, or configure signing for a physical device. The deployment target is iOS 17.0.
3. Build and run. Xcode resolves the local `AssistantLab` Swift package used by the app.
4. Use Settings to configure the household's integrations and personal cloud connection. Devices sharing lists must use the same household and cloud database.
5. To enable live assistant responses, configure the assistant service URL and device token in Settings. See the [relay setup instructions](ios/AssistantLab/tools/relay-worker/README.md).

Local list editing does not require a working cloud connection. Cross-device updates do. A failed connection or database permission check should remain visible as a sync error, not appear as a successful upload.

## Repository layout

| Path | Purpose |
| --- | --- |
| [ios/HeliPad](ios/HeliPad) | Native app, Xcode project, assets, household domain, and integration services |
| [ios/AssistantLab](ios/AssistantLab) | Integrated assistant package, command-line test tools, and relay implementations |
| [ios/ListsLab](ios/ListsLab) | Earlier standalone list prototype and its separate test service |
| [ios/Tests](ios/Tests) | Production domain and sync regression tests |
| [ios/scripts](ios/scripts) | Regression runner and list artwork rendering script |
| [ios/HeliPad/ArtworkSources](ios/HeliPad/ArtworkSources) | Source SVGs for the list tile graphics |
| Root HTML, CSS, JavaScript, and [tests](tests) | Web prototype and its tests |

The native app's list sync uses `HouseholdListsCloudService`, not the standalone ListsLab service. Deploying the assistant relay does not distribute a new iOS app build.

## Checks

Run these commands from the repository root on macOS with Xcode installed:

```bash
# Assistant behavior, tool boundaries, and household isolation
swift test --package-path ios/AssistantLab

# Native domain, persistence, migration, and sync regressions
bash ios/scripts/test-production.sh

# Relay authentication and tool allowlist
node --test ios/AssistantLab/tools/relay-worker/relay.test.mjs

# Native app compile check without device signing
xcodebuild -project ios/HeliPad/HeliPad.xcodeproj -scheme HeliPad \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

# Older web prototype
node --test tests/*.test.cjs
```

Automated tests cover legacy-list migration, recovery copies, pending edits, revision conflicts, assistant list operations, and confirmation boundaries. These checks do not replace a live two-device test. Before a release, verify that an item added on one device appears on the other, simultaneous edits survive, and offline changes upload after reconnecting. Check section movement and reduced-motion behavior on a device as well.

Keep connection strings, provider keys, device tokens, local databases, and build caches out of commits. The relay has its own deployment instructions and tool allowlist, which must stay compatible with the app's assistant tools.

## Web prototype

The root web prototype has no bundler. To run it locally:

```bash
python3 -m http.server 8080
```

Open `http://localhost:8080`. The initial load needs internet access for CDN-hosted fonts and icons. Its navigation and integrations are separate from the native app and should not be used as a guide to current iOS behavior.

## Design and implementation notes

- [design.md](design.md) describes the visual language.
- [SYSTEM.md](SYSTEM.md) and [BUILD.md](BUILD.md) contain the earlier architecture and build plans.
- [ios/PREWALK_PLAN.md](ios/PREWALK_PLAN.md) tracks app review findings and implementation opportunities.
- [ios/LISTS_IMPLEMENTATION_PLAN.md](ios/LISTS_IMPLEMENTATION_PLAN.md) records the Lists implementation plan.

Planning documents include historical proposals. Check the current source and tests when a plan differs from the shipped implementation.
