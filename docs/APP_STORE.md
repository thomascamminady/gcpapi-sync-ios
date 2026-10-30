# App Store Readiness

A checklist for publishing the app, kept with the code so it stays true. ✅ done, ⬜ to do,
❗ needs a decision.

## Privacy

- ✅ **No data collection.** No analytics, ads, tracking, accounts or third-party SDKs. App
  Privacy label: *Data Not Collected*.
- ✅ **Privacy manifest** (`App/Resources/PrivacyInfo.xcprivacy`): no tracking, no collected
  data types; required-reason API `UserDefaults` declared with reason `CA92.1` (the app's own
  settings).
- ✅ **Privacy policy** in [`PRIVACY.md`](../PRIVACY.md). ⬜ Publish it at a stable URL (for
  example GitHub Pages) and enter that URL in App Store Connect.
- ✅ **Minimal permissions.** The only permission prompt is Calendar, asked for only when the
  user turns on *Activities in Calendar*. No location, no HealthKit, no photos, no contacts,
  no notifications, no network extensions.
  - Usage string: `NSCalendarsFullAccessUsageDescription`.
  - Background App Refresh (`UIBackgroundModes: fetch`) needs no prompt and can be turned off
    in the app.
- ✅ **Health data stays out of iCloud by default.** Saved data is excluded from backups and
  never synced by the app. Exports, the folder sync and the calendar are explicit user actions.
  This matters for guideline 5.1.3(ii).
- ✅ **Keychain** items are stored with `AfterFirstUnlockThisDeviceOnly`.

## Review

- ✅ **Demo mode for App Review.** Reviewers have no Garmin key, so the connect screen offers
  *Explore with Sample Data*. ⬜ Mention it in the App Review notes.
- ✅ **No sign-up.** The app has no accounts of its own, so account deletion (guideline
  5.1.1(v)) does not apply. *Disconnect* deletes the key and all saved data.
- ✅ **Export compliance:** only standard HTTPS through URLSession;
  `ITSAppUsesNonExemptEncryption = NO`.
- ✅ **Licenses** of all included open-source code are shown in *Settings › Licenses* (MIT and
  Apache 2.0, including SwiftLog's NOTICE).
- ⬜ **Age rating** questionnaire: no objectionable content. Health information is shown, but
  no medical advice is given.
- ⬜ **Screenshots** for iPhone 6.9", iPad 13" and Mac, taken from the demo.

## Decisions for the owner

- ❗ **Garmin's API terms.** The Personal API is intended for a person's own data. Publishing a
  client app for everyone (each user brings their own key) must be checked against Garmin's
  developer and API terms before submission. Consider asking Garmin.
- ❗ **Name and trademarks.** Avoid "Garmin" in the app name and icon (guideline 5.2.1). Use it
  only descriptively, such as "for Garmin Connect" in the subtitle, if Garmin's brand
  guidelines allow.
- ❗ **Medical claims.** VO2max is an estimate and the analyses are descriptive. Keep marketing
  free of diagnostic or medical claims.
- ❗ **Developer account.** Publishing needs a paid Apple Developer Program membership; the
  current signing team is a free Personal Team.

## Accessibility and quality

- ✅ Dynamic Type through system text styles; VoiceOver labels on charts, tiles and controls.
- ✅ Light and dark mode; color themes, one checked for color-vision deficiencies.
- ✅ CI on every pull request: lint, secret scan, and tests in a German and a US region.
