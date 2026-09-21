# Lists Preview

A separate native iOS app for testing to-dos and groceries. It has its own bundle ID, storage, Swift package, Xcode project, and collaboration service. Nothing is linked into HeliPad's navigation, event model, children, or production data.

## Try it

Open `ListsPreview.xcodeproj` in Xcode, choose **ListsPreview**, and run on an iPhone simulator (iOS 17+). For a physical phone, select your development team in this project's Signing & Capabilities settings. No production signing settings need to change.

The app starts with clearly separate sample lists. Add items from the bottom field, tap an item to edit its section, notes, quantity, or steps, and use the circles to check things off. Sections and to-do steps collapse; completed items tuck into a separate section.

## Many lists, and moving between them

A list is the user's folder. There is no separate folder object: To-dos and Groceries each hold as many named lists as the household wants, and each list holds sections of items.

- **Switcher strip** — under the To-dos/Groceries control, one chip per list with its remaining count. One tap switches.
- **Lists index** — tap the list title (or **All lists** in the ••• menu) for one screen with both categories, per-list remaining/done counts, and shared state. Create, rename, drag-reorder, and delete lists there; **Edit** enables reordering, swipe deletes. Opening a row switches to it.
- **New list** — the **+** in the header, or the **+** on either section in the index. A new list is created with one named section so it is immediately valid.
- **Sections** — "Add a section" under the items. Long-press a section header to rename, move, or delete it; deleting a section moves its items into the first remaining section rather than discarding them.
- **Reordering items** — long-press an item for Move up, Move down, and Move to section. Moving a row is not an edit: it does not restart the 14/45-day review clock or clear a "keep for now" snooze.
- **Removing** — delete a list, a section, an item, or "Clear purchased/completed". Each offers its own Undo, including multi-item Undo for a cleared section. Undo restores items under fresh identities so it cannot resurrect something another device deleted.
- **Capture target** — when a list has more than one section, the field shows where new items land and lets you change it, instead of silently using the first section.
- **Groceries** — adding a name already on the list asks whether to update that item's quantity or add another. Quantities are never combined automatically.

List order is a device preference and stays local. Renaming a list, and adding, renaming, reordering, or deleting sections, are published when the list is shared.

The design follows HeliPad's ivory background, forest-green controls, warm cards, and serif headings. Body text uses native Dynamic Type and controls have generous touch targets.

## Live collaboration

Start the standalone service from the repository's `ios` directory:

```sh
python3 ListsLab/service/server.py --host 0.0.0.0 --port 8788
```

Keep the Mac awake and both devices on the same trusted network. Both devices need the Lists Preview build. In **Share**, enter `http://your-mac.local:8788`, using the Mac's actual local hostname, then choose **Create shared list** and send the private link. Do not use `localhost` for a link sent to another device: that points to the recipient's own device. Allow the preview's local-network access if iOS asks.

The recipient can open the link and choose **Open Lists Preview**, or paste it under **List options → Join a shared list**. Both people edit the same list. The active list refreshes roughly every 3 seconds while foregrounded, backing off after connection failures. Changes made offline are persisted locally and sent when the list is reopened with a connection. This is foreground polling, not background push.

Changes to different items and different item fields merge. Replayed requests cannot duplicate edits. A conflicting edit to the same field pauses that list and offers **Keep my copy & refresh**: it preserves unsent work as a separate local copy before loading the shared version. The user can then reconcile the two. Steps are currently one field, so simultaneous edits to different steps may require this review.

### Preview security boundary

This service is for a trusted LAN and non-sensitive test data, **not an internet-ready deployment**. Anyone holding a private link can read and edit that list. There are no accounts, participant roles, link revocation, TLS termination, or production abuse controls yet. HTTP on the LAN is unencrypted; do not port-forward this service or put real sensitive lists in it. Cross-network sharing requires a separately hosted, secured service and is not deployed by this prototype.

The service stores SQLite data in `service/.data/lists.sqlite` (git-ignored); the app stores `ListsPreview/lists.json` in its own Application Support directory. Item content and private links are not written to request logs. No API keys or AI provider are needed.

## Gentle cleanup

Suggestions use predictable inactivity rules, not an AI call:

- Groceries: unchanged for 14 days.
- To-dos: unchanged for 45 days.
- Completed items: never suggested.
- **Keep for now** pauses the suggestion for 30 days.
- **Remove** is always explicit and offers Undo; nothing is removed automatically.

The last removal can be undone during the current session. Undo restores a new item identity so it cannot accidentally resurrect a remotely deleted item. Suggested thresholds are prototype defaults, ready for feedback.

## Verification

With the service running:

```sh
LISTS_TEST_SERVER=http://127.0.0.1:8788 swift test --package-path ListsLab
python3 -m unittest discover -s ListsLab/service -p 'test_*.py' -v
xcodebuild -project ListsLab/ListsPreview.xcodeproj -scheme ListsPreview -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Swift tests cover inactivity, snooze, validation, persistence, safe copies, stale editor protection, two independent native clients syncing through HTTP, conflict preservation, the durable queue across restart, list lifecycle (create, rename, reorder, delete, Undo), section removal with item carry-over, item reordering, clearing completed items with Undo, additive decoding of files written before ordering existed, and convergence of rename/section/reorder edits across two clients. Service tests cover merge behavior, replay protection, conflicts, deletion, private-token access, invalid requests, rename, section save and delete, and that a reorder neither counts as an edit nor clears a snooze.

## Remaining before main-app integration

- Feedback on sections, review thresholds, and whether a list should be able to hold nested lists.
- Deleting a shared list removes it from this device only; the private link stays valid for everyone else. A revocation path needs the hosted service.
- Authenticated cloud collaboration, membership and revocation, encrypted transport, quotas, backup/retention, and optional push updates.
- Physical-device testing across separate networks after hosting, plus VoiceOver and larger Dynamic Type device coverage.
- A richer conflict-resolution screen if simultaneous editing is common.
- Any eventual fifth navigation button stays a separate decision. Settings remains untouched.
