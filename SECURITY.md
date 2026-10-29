# Security

Please report vulnerabilities privately through GitHub's
[private vulnerability reporting](https://github.com/thomascamminady/gcpapi-sync-ios/security/advisories/new)
or by email to thomas@camminady.dev.

- The Personal API key and access tokens live only in the Keychain of the device
  (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: no iCloud Keychain, no backups).
- They are only ever sent to Garmin's API host; the client does not follow redirects.
- The app collects no data and does not track; everything it reads stays on the device.
- If a key may be exposed, delete it in Garmin Connect (Settings → Personal API), which
  also invalidates every token issued from it.
