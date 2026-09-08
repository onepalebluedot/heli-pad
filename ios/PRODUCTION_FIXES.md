# Production fixes

Implemented review findings 1, 2, 3, 4, 5, and 10. Personal Neon connections remain supported, as requested.

- Removed the bundled database credential. Personal connection strings and Google API keys use device-only, unlocked Keychain storage. Encoded household data excludes credentials, and uploads also exclude device sync bookkeeping. Legacy plaintext Neon credentials are discarded on restore; legacy Google keys move into Keychain.
- New households receive independent IDs. Restoring app state never uploads sample data. New uploads use insert-if-absent, and updates compare the last known server revision in the same SQL statement. Conflicts preserve local edits and appear in Settings.
- Uploads drain edits made while a request is in flight. Pending revisions survive restart and retry on foreground activation. Concurrent sync callers await the same operation. Explicit downloads reject changes made locally while the download was running.
- The default clock uses device time in the selected household timezone. Tests can inject a clock or explicitly set mock time.
- Week buckets now project absolute event dates. Week rollover preserves history and completion state, and promotes upcoming events into Go. It does not generate new occurrences for one-off events or infer recurring rules.
- Go's clock wakes at minute boundaries and stops when inactive. Schedule analysis is cached by relevant inputs; clock, profile, and weather changes reuse it. Workload totals reuse analyzed routes. Candidate selection no longer sorts lists merely to find the preceding or following event.

## Reconnect an existing household

1. Rotate the previously exposed database password in Neon. Removing it from source does not revoke it. No live database changes or credential rotation were performed by these fixes.
2. Enter the replacement personal connection in Settings, then test it.
3. To recover the household written by the earlier app, enter `primary` as the household ID and choose **Download cloud household**. This explicitly replaces the local household after confirmation.
4. For a new household, keep its generated ID. On another device, enter the same ID and download before making edits. A blind upload to an existing ID is rejected.

Direct database access is still a personal integration. These changes do not add a shared-service authentication backend. Dates already rewritten by an older app version cannot be reconstructed automatically.

## Validation

Run `./scripts/test-production.sh` from the iOS directory. It uses isolated UserDefaults, an in-memory credential store, a controlled fake cloud, and intercepted URLSession requests. It does not contact Neon or touch the user's Keychain.

The suite covers credential serialization and migration, initial restore, date rollover and relaunch, clock publication and timezone handling, cache invalidation, upload interleavings, conflicts, persisted retries, connection changes during sync, and SQL compare-and-swap behavior.

The Release simulator build and existing countdown checks also passed. The existing MapKit delegate concurrency warning remains outside this scope.

Synthetic optimized macOS `analyze + loads` measurements for 100 same-day events dropped from approximately 131 ms in the review to 47 ms after the algorithm change. The Go regression test additionally verifies that unchanged renders perform no new schedule analysis. These are not iPhone battery or rendering measurements.
