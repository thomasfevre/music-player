# Build, sign, upload & submit — Music Player (app id 6783991846)

The harness blocks me from running `xcodebuild` with the signing key directly, so run the
build yourself. Two options — pick one.

First set your App Store Connect API credentials (do NOT commit real values):
```
export ASC_KEY_ID=XXXXXXXXXX
export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
export ASC_KEY=/path/to/AuthKey_XXXXXXXXXX.p8
```

## Option A — Xcode GUI (simplest)
1. `open /Users/toma/dev/SunoPlayer/SunoPlayer.xcodeproj`
2. Top device selector → **Any iOS Device (arm64)**.
3. **Product → Archive**. (Automatic signing will create the distribution cert/profile.)
4. In the Organizer: **Distribute App → App Store Connect → Upload**.

## Option B — CLI (run each line in the prompt prefixed with `! `)
```
xcodebuild -project /Users/toma/dev/SunoPlayer/SunoPlayer.xcodeproj -scheme SunoPlayer \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath /Users/toma/dev/SunoPlayer/build/SunoPlayer.xcarchive \
  -allowProvisioningUpdates \
  -authenticationKeyPath $ASC_KEY \
  -authenticationKeyID $ASC_KEY_ID \
  -authenticationKeyIssuerID $ASC_ISSUER_ID archive
```
```
xcodebuild -exportArchive \
  -archivePath /Users/toma/dev/SunoPlayer/build/SunoPlayer.xcarchive \
  -exportOptionsPlist /Users/toma/dev/SunoPlayer/ExportOptions.plist \
  -exportPath /Users/toma/dev/SunoPlayer/build/export \
  -allowProvisioningUpdates \
  -authenticationKeyPath $ASC_KEY \
  -authenticationKeyID $ASC_KEY_ID \
  -authenticationKeyIssuerID $ASC_ISSUER_ID
```
```
asc builds upload --app 6783991846 --ipa /Users/toma/dev/SunoPlayer/build/export/SunoPlayer.ipa
```
After upload, processing takes ~5-15 min. Then I (or you) attach the build to version 1.0.

## Already done via asc (by Claude)
- Age rating: 4+   · Category: Music   · Subtitle, Description, Keywords, Promo text
- App icon (1024) embedded in the project
- Bundle id com.thomas.sunoplayer registered; Team VYGBHQ4ZDQ

## Still required before you can submit
- [ ] **Privacy Policy URL** (mandatory) — host the text in PRIVACY.md somewhere (GitHub Pages/gist), then:
      `asc localizations update --app 6783991846 --type app-info --locale en-US --privacy-policy-url "https://..."`
- [ ] **Support URL** (mandatory):
      `asc localizations update --version <VERSION_ID> --locale en-US --support-url "https://..."`
- [ ] **App Privacy** ("Data Not Collected") — set in App Store Connect web UI (not exposed by asc).
- [ ] **Screenshots** — generated in .asc-metadata/screenshots/ (6.9"); upload via asc or web UI.
- [ ] **Pricing** = Free + availability.
- [ ] Attach the processed build to version 1.0, then **Submit for Review** (I'll pause for your OK).
