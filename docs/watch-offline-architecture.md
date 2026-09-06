# Independent offline Watch companion

This implementation was developed from the base iOS app, without consulting another Watch implementation.

## User flow

The library header has a Watch button. Watch Offline offers a whole-library send, differential refresh, inventory check, pause/resume, cancellation, and retry. A track context menu offers Send to Watch. Both bulk actions skip IDs proven present by a fresh Watch inventory; neither deletes existing Watch music. Watch plays its own committed audio files with a playback audio session and system Now Playing controls.

## Durable truth and transport

- iPhone: `Documents/WatchOutbox/ledger.json` records intent and per-attempt state before calling WatchConnectivity. Only three jobs may occupy transport/receipt slots. A file completion enters `awaitingReceipt`, never `persisted`.
- Watch: `Documents/OfflineMusic/identity.json` is an installation identity. Files target that identity, preventing an old queued delivery from silently populating another Watch.
- Each activation or explicit refresh sends a fresh request UUID through application context, with a reachable-message optimization. The Watch returns a JSON inventory **file**, avoiding the dictionary size ceiling on large libraries. Only the matching request UUID is accepted. A revision protects against receipts overtaking an older snapshot.
- Inventories enumerate manifests with actual matching-size audio files. They are not derived from the iPhone's transfer history.
- Watch receives a temporary file, copies it synchronously into app-owned staging, checks byte count and streaming SHA-256, writes its manifest, then atomically commits the directory before `session(_:didReceive:)` returns. Incomplete transaction directories are excluded from inventory and cleaned on startup.
- Save receipts are persisted to a Watch outbox before `transferUserInfo`. Success receipts describe a committed track. They include installation, track and attempt IDs. Duplicate files and receipts are idempotent.
- Both peers implement the actual `session(_:didFinish:error:)` delegate signatures, separately for file transfers and user-info transfers where applicable.

## Recovery

After activation, iPhone reconciles the ledger against fresh inventory and `outstandingFileTransfers`. Existing OS transfers are not duplicated. Missing tracks with lost callbacks/receipts return to the local queue, with at most three automatic submission attempts. Explicit transport/storage failures are visible and require Retry failed tracks. A foreground timer rechecks stale receipt waits, but is not claimed to execute while suspended. The OS owns background scheduling.

The Watch application delegate retains `WKWatchConnectivityRefreshBackgroundTask` instances until the session is activated and `hasContentPending` is false. Receiver disk work finishes synchronously before that drain check. Pending durable receipts are retried on activation, foreground, reachability changes, and subsequent requests. Latest inventory requests survive in WC's received application context.

Pause stops new submissions, not already submitted OS work. Cancellation marks durable jobs cancelled before cancelling the corresponding OS transfers. Late delivery can still be saved and is reported honestly; cancellation is not remote deletion. Restart preserves pause and cancellation. A corrupt/unwritable phone ledger stops submission instead of silently erasing queue history.

## Verification and remaining hardware gate

Verified on 2026-09-06 with Xcode 26.5:

- Full iOS simulator test suite: **120 tests, 0 failures**.
- Final focused `WatchOfflineTests` rerun: **12 tests, 0 failures**.
- Generic iOS simulator build, including embedded Watch: **succeeded**.
- Final generic iOS device build, including embedded Watch: **succeeded**, signing disabled.
- Inspected rendered iPhone Watch Offline settings and Watch empty-state UI on dedicated simulators.
- Verified the built watchOS Info.plist contains `UIBackgroundModes = [audio]`.
- No new compiler warnings in the final incremental device build; AppIntents metadata extraction notices remain. A clean build also reports the base app's existing deprecated `showsRouteButton` API.

Commands (run from this worktree):

```sh
xcodegen generate
xcodebuild -scheme SunoPlayer -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -scheme SunoPlayer -destination 'platform=iOS Simulator,id=<dedicated simulator UUID>' CODE_SIGNING_ALLOWED=NO test
xcodebuild -scheme SunoPlayer -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Unit tests cover ID-based differential reconciliation, lost callbacks, outstanding-transfer adoption, receipt identity validation, cancellation/late receipts, bounded retry attempts, the three-slot window with 900 jobs, transport-versus-save semantics, ledger round trips, synchronous file ownership, restart, duplicate delivery, missing audio, wrong Watch identity and damaged delivery.

Build simulator and unsigned device destinations with Xcode. Inspect the generated Watch Info.plist for the `audio` background mode. File transfers themselves require **paired physical devices** according to Apple; simulator UI and store tests are not evidence of real radio/background reliability.

Before release, verify on an iPhone/Watch pair:

1. Send one MP3, confirm persisted count, disconnect iPhone, play through Bluetooth headphones.
2. Send 900 tracks; observe at most three OS file transfers and distinct queued/receipt/persisted counts.
3. Background both apps, interrupt Bluetooth/Wi-Fi, relaunch, and compare a fresh inventory against actual Watch storage.
4. Terminate after submission, after Watch commit, and before receipt delivery; confirm no duplicates or false success.
5. Cancel then relaunch; verify cancelled jobs stay cancelled and explain any late committed track.
6. Switch/re-pair Watches, uninstall/reinstall Watch app, simulate low disk space and retry visible failures.
7. Confirm headphone disconnection/interruption pauses playback and a pending route activation cannot override a later Pause.

No artwork, playlist synchronization, remote deletion, chunk-resumable per-file transport, or automatic playback queue is included. Track IDs are the differential identity; changing bytes under the same ID is not a content-refresh operation. The OS can delay transfers indefinitely and provides no guaranteed bulk-completion deadline. App Store icon/signing/distribution and physical-device acceptance remain separate release work.

## Apple references

- [Receiving a file](https://developer.apple.com/documentation/watchconnectivity/wcsessiondelegate/session(_:didreceive:))
- [File transfer completion](https://developer.apple.com/documentation/watchconnectivity/wcsessiondelegate/session(_:didfinish:error:)-6dtcu)
- [Background WatchConnectivity task](https://developer.apple.com/documentation/watchkit/wkwatchconnectivityrefreshbackgroundtask)
- [Background file transfer](https://developer.apple.com/documentation/watchconnectivity/wcsession/transferfile(_:metadata:))
