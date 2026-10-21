# Release readiness

## App Store capabilities and review

- [ ] Paid developer account; bundle ids `app.languify.Languify` and `.Widgets` registered
- [ ] Sign in with Apple, iCloud (CloudKit container), Push, In-App Purchase enabled
- [ ] CloudKit schema deployed to Production in the CloudKit console
- [ ] Subscription group and products created; prices, trial and localisations set in App Store Connect
- [ ] Review notes explain: background audio is used only during user-started listening sessions with a visible Live Activity; audio is not saved; how to reproduce (start session, ask a question)
- [ ] Demo video for reviewers showing the mic indicator and Live Activity
- [ ] Siri phrases tested on device in English (en-US, en-IN, en-GB Siri languages)
- [ ] Guideline 3.1.2 subscription disclosures on the paywall (present) and in the App Store description
- [ ] Guideline 5.1.1: microphone purpose strings (present); privacy policy URL live at languify.app/privacy

## Privacy

- [ ] Privacy nutrition labels match [PRIVACY.md](PRIVACY.md)
- [x] Privacy manifest (`App/Resources/PrivacyInfo.xcprivacy`): no tracking, `UserDefaults` reason CA92.1, purchase history, user id, usage counts; review before submission
- [ ] Zero data retention requested from Anthropic for the production organisation
- [ ] Privacy policy describes the rolling buffer, on-device transcription, text processing, retention and deletion
- [ ] Data export and account deletion verified end to end (checklist F5)

## Security

- [ ] App Attest on `/v1/auth/install`
- [ ] Shared `UsageStore` (Redis/DynamoDB); multiple backend instances
- [ ] `LANGUIFY_TOKEN_SECRET` rotated and stored in the host's secret manager
- [ ] Apple token revocation on account deletion for signed-in users
- [ ] Dependency audit (`npm audit`, Swift package list)

## Quality

- [ ] Real-device checklist complete ([TESTING_CHECKLIST.md](TESTING_CHECKLIST.md))
- [ ] Recognition and explanation benchmark meets the bar in [AI_PROVIDERS.md](AI_PROVIDERS.md)
- [ ] Latency targets set from measured device data (p50, p90 per stage)
- [ ] Battery impact measured for a 60 minute session
- [ ] Crash and error monitoring (MetricKit subscriber or a privacy-reviewed crash SDK); backend error alerting
- [ ] Localisation: strings extracted into a String Catalog; Tamil and Malayalam UI translations reviewed by native speakers

## Production configuration

- [ ] `LANGUIFY_API_BASE_URL` set to the HTTPS production URL in the Release configuration
- [ ] `NSAllowsLocalNetworking` removed from Release builds
- [ ] `aps-environment` set to `production` for distribution
- [ ] Backend `APP_STORE_ENVIRONMENT=Production`, `APPLE_APP_ID`, `APPLE_ROOT_CERTS_DIR`
