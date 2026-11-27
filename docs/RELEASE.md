# Releasing Albatross

What it takes to get a build to real players, and which pieces need the paid Apple Developer Program ($99 a year).
A free personal team can install on your own phone for 7 days at a time and nothing more.

## Two entitlement sets

`Albatross.xcodeproj` signs the app with `ENTITLEMENTS_FILE`:

| Setting | File | For |
| --- | --- | --- |
| `Albatross/Albatross.entitlements` (default) | App Groups only | free personal team, device builds today |
| `Config/Albatross.paid.entitlements` | App Groups, Push, Sign in with Apple, WeatherKit, Time Sensitive Notifications | paid program |

After joining, change `ENTITLEMENTS_FILE` in the Albatross target's build settings (Debug and Release) to the paid file, then in
Signing & Capabilities check that Push Notifications, Sign in with Apple, WeatherKit and Time Sensitive Notifications show up.
`ci_scripts/ci_post_clone.sh` makes the same switch for Xcode Cloud builds. Before an App Store or TestFlight archive,
`aps-environment` is rewritten to `production` by Xcode's distribution signing.

Everything in the app that needs a paid capability fails quietly without it: the forecast section stays hidden, the Apple button
shows a short message, and push registration logs a line.

## One-time setup after joining

1. App Store Connect: create the app record for bundle id `TrujSoft.Albatross`. The widgets bundle id is `TrujSoft.Albatross.AlbatrossWidgets`.
2. Apple developer account, Keys: create an APNs key (Apple Push Notifications service). Download the .p8 once. Note the key id and team id.
3. Supabase, Edge Functions secrets: `APNS_KEY_P8` (the text of the .p8 file), `APNS_KEY_ID`, `APNS_TEAM_ID`. `APNS_BUNDLE_ID` only if the id changes.
4. Supabase, Authentication, Providers, Apple: enable it with the bundle id `TrujSoft.Albatross` as the client id (native sign-in needs no secret).
5. Apply migrations 022, 023 and 024 (already live for 022). Deploy `send-news-push` and `drain-push-queue`.
6. Check `pg_cron` and `pg_net` are enabled (Database, Extensions) so tee time reminders and the push triggers run.

## TestFlight

```bash
xcodebuild archive -project Albatross.xcodeproj -scheme Albatross -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/Albatross.xcarchive
xcodebuild -exportArchive -archivePath build/Albatross.xcarchive -exportOptionsPlist ExportOptions.plist -exportPath build/export
```

Upload the build from Xcode's Organizer (or `xcrun altool`/Transporter), then add testers under TestFlight in App Store Connect:
internal testers (your team) get builds at once, external testers (the players) after a short beta review.
`ITSAppUsesNonExemptEncryption` is set to NO in Info.plist, so there is no export-compliance question per build.
The app collects email, name, user id, round scores and scanned scorecard photos; the privacy manifest (`Albatross/PrivacyInfo.xcprivacy`)
and the App Store privacy answers should say the same.

## Xcode Cloud

Create the workflow in Xcode (Product, Xcode Cloud, Create Workflow): start condition on pushes to `main`,
actions Test (scheme Albatross, iPhone simulator) and Archive (TestFlight internal distribution). Every membership includes 25
compute hours a month. The `ci_scripts` folder at the repository root is picked up automatically.
