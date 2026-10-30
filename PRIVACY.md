# Privacy Policy

*GCPAPI Sync for iPhone, iPad and Mac. Last updated: 30 October 2026.*

**The short version: the app collects nothing. Your data goes from Garmin to your device, and
only where you send it yourself.**

## What the app does with your data

- **Your Garmin Personal API key** is stored in your device's Keychain, available only on this
  device and never included in backups. It is sent only to Garmin, to sign in.
- **Your health and activity data** is fetched from Garmin's Personal API over an encrypted
  connection, directly from your device. The app keeps the latest data on the device so that
  it opens instantly; this copy is protected by the device's encryption, excluded from
  backups, and deleted when you disconnect.
- **Settings** (units, colors, which tiles to show) are stored on the device.

## What the app does not do

- It has no servers. The developer never receives your data, your key, or anything about you.
- It contains no analytics, no advertising, no tracking and no third-party SDKs.
- It does not use your location. Maps show the routes recorded by your Garmin device; the map
  tiles come from Apple Maps.
- **Planning routes** along roads and paths asks Apple Maps for walking directions between the
  points you place. Turn off path-following to keep a route entirely on the device. Planned
  routes are stored on the device.

## Data you choose to send elsewhere

- **Exports** (CSV, JSON, iCalendar, FIT, GPX) go only where you share or save them, for example
  Mail, AirDrop, iCloud Drive or Dropbox.
- **Folder sync**, if you turn it on, writes CSV files to the folder you choose.
- **Activities in Calendar**, if you turn it on, asks for Calendar access and adds a calendar
  named Activities to the Calendar app. It syncs wherever your calendars sync (for example
  iCloud). Turning it off removes that calendar.

## Background refresh

If allowed (on by default, can be turned off in the app's settings and in iOS Settings), iOS
lets the app fetch new data from Garmin in the background, so it opens up to date.

## Contact

Questions: open an issue at https://github.com/thomascamminady/gcpapi-sync-ios/issues.

This app is not affiliated with or endorsed by Garmin or Wahoo Fitness. Garmin and Garmin Connect
are trademarks of Garmin Ltd.
