# SunoPlayer — Xcode Setup Guide

A premium offline music player for your Suno AI–generated songs.
Dark-mode, Liquid Glass aesthetic, AVFoundation playback, zero cloud dependencies.

---

## 1. Create an Xcode Project

1. Open **Xcode** (16+ recommended, supports iOS 17+).
2. **File → New → Project…**
3. Choose **iOS → App**.
4. Fill in:
   | Field | Value |
   |---|---|
   | Product Name | `SunoPlayer` |
   | Bundle Identifier | `com.yourname.SunoPlayer` |
   | Interface | **SwiftUI** |
   | Language | **Swift** |
   | Storage | None |
5. Uncheck **Include Tests** (optional).
6. Save the project wherever you like.

---

## 2. Copy the Source Files

Delete the auto-generated `ContentView.swift` Xcode created.

Then copy every `.swift` file from this repo into the Xcode project:

```
SunoPlayer/
├── SunoPlayerApp.swift
├── Models/
│   └── Track.swift
├── Managers/
│   ├── MusicLibraryManager.swift
│   └── AudioPlayerManager.swift
├── Views/
│   ├── ContentView.swift
│   ├── LibraryView.swift
│   ├── TrackRowView.swift
│   ├── MiniPlayerView.swift
│   └── NowPlayingView.swift
└── Utilities/
    └── DurationFormatter.swift
```

In Xcode's Project Navigator (left panel):
- Right-click the **SunoPlayer** group → **Add Files to "SunoPlayer"…**
- Select all `.swift` files, keeping **"Copy items if needed"** checked.
- You can create matching Groups in Xcode to mirror the folder structure (optional, cosmetic only).

---

## 3. Replace Info.plist

Xcode 15+ uses a newer style for Info.plist keys, but the classic `.plist` file still works.

**Option A — Merge keys manually (recommended):**

In Xcode, select your project → **SunoPlayer target → Info tab** and add:

| Key | Type | Value |
|---|---|---|
| `UIBackgroundModes` | Array | Item 0: `audio` |
| `UIFileSharingEnabled` | Boolean | YES |
| `LSSupportsOpeningDocumentsInPlace` | Boolean | YES |

**Option B — Replace Info.plist entirely:**

Replace the file Xcode generated at `SunoPlayer/Info.plist` with the `Info.plist` included in this repo.

---

## 4. Enable Background Audio Capability

1. Select your project in Navigator.
2. Click the **SunoPlayer** target → **Signing & Capabilities** tab.
3. Click **+ Capability** → search for **Background Modes** → double-click to add.
4. Check **✓ Audio, AirPlay, and Picture in Picture**.

This is required for music to continue playing when you lock the screen or switch apps.

---

## 5. Set Deployment Target

**Project → SunoPlayer target → General → Minimum Deployments**

Set to **iOS 17.0** (or iOS 16.0 if you need older device support — the code is compatible).

---

## 6. Sign the App

1. **Signing & Capabilities → Team** — select your Apple ID (free developer account works for personal use).
2. Xcode will auto-manage provisioning profiles.

---

## 7. Build & Run on Your iPhone

1. Connect your iPhone via USB.
2. Select your device in the Xcode toolbar (top left).
3. Press **⌘R** (or the ▶ Run button).
4. First time: on your iPhone go to **Settings → General → VPN & Device Management → Trust** your developer certificate.

---

## 8. Test Checklist

After the app launches on your device:

- [ ] **Import a song** — tap **+** (top right) → pick a `.mp3` or `.m4a` from Files
- [ ] **Play it** — tap the track row; the full player opens
- [ ] **Pause / Resume** — tap the large play/pause button
- [ ] **Seek** — drag the progress bar thumb
- [ ] **Next / Previous** — tap ⏮ ⏭ (or swipe back if < 3 s in)
- [ ] **Mini player** — press the drag handle at top to dismiss full player; mini player stays at bottom
- [ ] **Shuffle** — enable in full player; tap next a few times
- [ ] **Repeat** — cycle Off → All → One
- [ ] **Persistence** — force-quit the app and reopen; your tracks are still there
- [ ] **Background audio** — start a track, press the Home button or lock the screen; music continues and Lock Screen controls appear
- [ ] **Remote controls** — use AirPods or Lock Screen scrubber to skip/pause

---

## Supported Audio Formats

| Format | Extension |
|---|---|
| MPEG Layer 3 | `.mp3` |
| AAC (MPEG-4 Audio) | `.m4a`, `.aac` |
| WAV / AIFF | `.wav`, `.aif`, `.aiff` |
| Apple Core Audio | `.caf` |

All formats Suno AI exports (mp3, m4a) are natively supported.

---

## Architecture Overview

```
SunoPlayerApp          — entry point, configures AVAudioSession
├── MusicLibraryManager   (ObservableObject)
│   ├── importTracks()    — document picker + file copy + metadata
│   ├── deleteTrack()     — remove from disk + library
│   └── displayedTracks   — filtered + sorted computed property
├── AudioPlayerManager    (ObservableObject)
│   ├── play(_:in:)       — loads AVPlayerItem, sets queue
│   ├── next() / previous()
│   ├── seek(to:)
│   ├── toggleShuffle()
│   ├── cycleRepeatMode()
│   └── NowPlayingInfo    — lock screen / control center integration
└── Views
    ├── ContentView        — root ZStack with mini player overlay
    ├── LibraryView        — list, search, sort, empty state
    ├── TrackRowView       — gradient artwork, animated equalizer bars
    ├── MiniPlayerView     — compact player + progress line
    └── NowPlayingView     — full-screen player, animated gradients, seek bar
```

---

## Troubleshooting

**"Could not launch" error on device**
→ Trust the developer certificate: Settings → General → VPN & Device Management.

**Track doesn't play after import**
→ Verify the file isn't DRM-protected. Suno exports are DRM-free by default.

**Music stops when screen locks**
→ Ensure Background Modes → Audio capability is enabled in Signing & Capabilities.

**File picker shows no audio files**
→ On the Files sheet, tap Browse → On My iPhone → check the Downloads or Suno folder.

**Metadata shows as file name**
→ Normal for Suno exports — they often have no embedded ID3 tags. You can rename them in Files before importing.
