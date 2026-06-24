# Music Player

A focused, **offline** iOS music player for the audio files you keep on your device.
SwiftUI + AVFoundation. No account, no streaming, no ads, no tracking — everything stays local.

## Features
- Import your own audio (MP3, M4A, AAC, AIFF, WAV…) from the Files app
- Background playback with lock-screen / Control Center controls
- Shuffle and repeat (off / all / one)
- Search and sort your library
- A dark, animated now-playing experience
- 100% offline — your library never leaves your device

## Build
This repo uses [XcodeGen](https://github.com/yonyz/XcodeGen). Generate the project and open it:

```bash
brew install xcodegen
xcodegen generate
open SunoPlayer.xcodeproj
```

Run the tests:

```bash
xcodebuild test -scheme SunoPlayer -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
```

## Privacy
The app collects no data. See [PRIVACY.md](PRIVACY.md).

## Support
Open an issue on this repository.
