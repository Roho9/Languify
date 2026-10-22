# Setup

## Requirements

- macOS with Xcode 26 or newer (built with Xcode 26.6, iOS 26.5 SDK)
- XcodeGen (`brew install xcodegen`)
- Node 22 for the backend
- An iPhone on iOS 26 for anything involving the microphone, speech models, Siri or AirPods. The Simulator has no Tamil/Malayalam speech models.
- An Apple Developer Program membership for Sign in with Apple, iCloud sync and in-app purchase on device. A free team can still build and run the core app (see below).
- For AI features, either Ollama with a local model (free, the default) or an Anthropic API key.

## 1. Generate and open the project

```bash
cd Languify
cp Config/Local.xcconfig.example Config/Local.xcconfig   # then edit it
xcodegen generate
open Languify.xcodeproj
```

`Config/Local.xcconfig` (git-ignored):

```
DEVELOPMENT_TEAM = <your team id>
LANGUIFY_API_BASE_URL = http:/$()/192.168.1.20:8787     // your Mac's LAN IP while developing
// LANGUIFY_ENTITLEMENTS = App/Resources/Languify-Basic.entitlements   // free team: no SIWA / iCloud
```

The `$()` keeps xcconfig from treating `//` as a comment.

## 2. Capabilities

With a paid team, enable these for `app.languify.Languify` in the developer portal (Xcode's automatic signing does this for you):

- Sign in with Apple
- iCloud with CloudKit, container `iCloud.app.languify.Languify`
- Push Notifications (CloudKit sync uses silent pushes)
- In-App Purchase

Already in `Info.plist`: microphone and speech usage descriptions, `UIBackgroundModes` `audio` and `remote-notification`, `NSSupportsLiveActivities`. The widget extension `app.languify.Languify.Widgets` hosts the Live Activity.

Siri needs no entitlement for App Shortcuts. They appear after the first launch.

## 3. Backend and AI credentials

```bash
cd backend
npm install
cp .env.example .env
# LANGUIFY_TOKEN_SECRET: openssl rand -base64 48
# Free local AI (default): brew install ollama && brew services start ollama && ollama pull gemma3:27b
# Or paid: AI_PROVIDER=claude and ANTHROPIC_API_KEY from console.anthropic.com (server only, never in the app)
npm run dev
```

Point `LANGUIFY_API_BASE_URL` at it and rebuild. Without a URL, the app runs fully on device and AI features say "not configured" instead of producing fake answers.

## 4. Run on a physical iPhone

1. Select your iPhone and run the `Languify` scheme.
2. Onboarding: choose a language, then on the last step allow the microphone and download the speech models (Wi-Fi recommended).
3. Turn on **Allow AI explanations** in onboarding or Settings, Privacy.

## 5. Try Live Rewind

1. Rewind tab, Start Listening. The Live Activity appears.
2. Have someone say a Tamil or Malayalam sentence near the phone (or play a recording).
3. Tap **That word** or **That sentence**. The card shows the explanation; the word appears in Vocabulary.
4. Connect AirPods and repeat with Adaptive mode to hear the answer privately.

## 6. Try Siri and AirPods

1. Start a session, lock the phone.
2. "Siri, ask Languify what that word meant". Siri should speak the answer through the AirPods.
3. "Siri, stop Languify".

Record results in `docs/TESTING_CHECKLIST.md`.

## 7. Subscriptions

- Local: the `Languify` scheme uses `App/Resources/Languify.storekit` (monthly and annual in one group, 1-week free trial). Prices there are test values only; real prices are set in App Store Connect and read at runtime.
- Backend: `APP_STORE_ENVIRONMENT=Xcode` accepts Xcode-signed test transactions.
- Sandbox/TestFlight: create the same product ids (`app.languify.premium.monthly`, `app.languify.premium.annual`) in App Store Connect, set `APP_STORE_ENVIRONMENT=Sandbox` and `APPLE_ROOT_CERTS_DIR`.

## 8. Tests

```bash
(cd Packages/LanguifyKit && swift test)        # core logic, 64 tests
(cd backend && npm test)                       # API, 20 tests
xcodebuild test -project Languify.xcodeproj -scheme Languify \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'   # 22 unit + 4 UI tests
```
