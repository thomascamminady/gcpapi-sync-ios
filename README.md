# gcpapi-sync-ios

[![CI](https://github.com/thomascamminady/gcpapi-sync-ios/actions/workflows/ci.yml/badge.svg)](https://github.com/thomascamminady/gcpapi-sync-ios/actions/workflows/ci.yml)
![iOS](https://img.shields.io/badge/iOS-26-blue)
![Swift](https://img.shields.io/badge/Swift-6-orange)

An open-source iPhone app for your Garmin health data, built on Garmin's official
[Personal API](https://developer.garmin.com/gc-developer-program/personal/personal-faq/) and
[gcpapi-sync-swift](https://github.com/thomascamminady/gcpapi-sync-swift).

<p>
  <img src="docs/connect.png" width="280" alt="Connecting a Garmin account with a Personal API key">
  <img src="docs/dashboard.png" width="280" alt="The last seven days: steps and sleep">
</p>

> **Disclaimer.** This is a personal, private project. It is not affiliated with, endorsed
> by, or developed on behalf of my employer, Wahoo Fitness, and it is not affiliated with or
> endorsed by Garmin. "Garmin" and "Garmin Connect" are trademarks of Garmin Ltd. or its
> subsidiaries. The screenshots show the app's synthetic sample data.

## What it does today

- **Connect** with a Personal API key (Garmin Connect → Settings → Personal API). The key is
  checked with Garmin, then kept in this iPhone's Keychain: never synced to iCloud, never in
  backups, only ever sent to Garmin. Access tokens are cached in the Keychain too.
- **The last 7 days at a glance**: steps against your goal, sleep stages and score, resting
  heart rate, HRV with Garmin's status, Body Battery range, stress, and intensity minutes
  against the weekly goal of 150.
- **Explore with sample data** without an account, also used for previews, screenshots and
  App Review.

## Under the hood

- SwiftUI for iOS 26 (Liquid Glass), Swift Charts, `@Observable` models.
- Swift 6 language mode with complete concurrency checking, *approachable concurrency* and
  main-actor isolation by default; non-UI code opts out explicitly with `nonisolated`.
- Data comes from [gcpapi-sync-swift](https://github.com/thomascamminady/gcpapi-sync-swift):
  typed `Codable` models for every Personal API endpoint, retries, token handling. The week
  is fetched with three concurrent requests.
- Errors are translated into what a person can do about them (offline, key rejected,
  Garmin unavailable, ...); a failed refresh keeps the data on screen.
- No tracking and no data collection (see `App/Resources/PrivacyInfo.xcprivacy`).

```text
App/
  Auth/       Keychain storage, the Keychain token cache, the session, the connect screen
  Health/     the week's data model and loader, the dashboard, charts
  Settings/   account and about
  Shared/     problem descriptions, formatting, the demo transport
AppTests/     Swift Testing tests (Keychain, session, loading, mapping, formatting)
```

## Building

Requirements: Xcode 26 or newer, an iOS 26 simulator or device.

```text
git clone https://github.com/thomascamminady/gcpapi-sync-ios.git && cd gcpapi-sync-ios
open GCPAPISync.xcodeproj
```

Run the `GCPAPISyncApp` scheme; launch with `-demo` to start in sample-data mode. For a
device, choose your team under *Signing & Capabilities*.

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen && xcodegen generate`) and committed for convenience; source folders
are synchronized, so adding files needs no project change.

## Quality bar

The same as gcpapi-sync-python and gcpapi-sync-swift:

- swift-format (`--strict`) and SwiftLint with every opt-in rule; rules are disabled only
  where they contradict swift-format or idiomatic Swift, each with its reason.
- Warnings are errors; no suppression comments or concurrency escape hatches
  (`swiftlint:disable`, `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`).
- Tests run on the iOS simulator in CI; pre-commit hooks run the same checks locally:

```text
brew install pre-commit swiftlint xcodegen && pre-commit install
Scripts/test.sh
```

## Roadmap

Ideas for what comes next: day and trend detail screens, activities with maps and laps,
background refresh with widgets, HealthKit export, and longer time ranges.

## License

[MIT](LICENSE)
