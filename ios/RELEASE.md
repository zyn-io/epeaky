# Releasing Epeaky for iPhone

What the account holder does, in order. Everything here is outside the repo:
the Apple account, its keys, DNS and the servers.

## 1. Apple Developer

1. The Apple Developer Program (the organisation that publishes Nap: Infinity
   Team). Note the **team id** (10 characters).
2. Identifiers: App ID `io.infinityteam.epeaky` with Push Notifications,
   Associated Domains and App Groups; App ID
   `io.infinityteam.epeaky.notifications` with App Groups; the App Group
   `group.io.infinityteam.epeaky`.
3. Keys: one with **Apple Push Notifications service (APNs)**. Download the
   `.p8` once; note its **key id**.

## 2. The push relay (push.epeaky.zyn-network.com)

1. DNS: `push.epeaky.zyn-network.com` → the server that runs gen-epeaky.
2. On that server: `apps/cave-den/push` (the public repo's `push/`) as in its
   README: `RELAY_SECRET` (`openssl rand -hex 32`, kept), `RELAY_ORIGIN`,
   `APNS_KEY_FILE` (the `.p8`, mode 0600, the relay's user), `APNS_KEY_ID`,
   `APNS_TEAM_ID`, `APNS_TOPIC=io.infinityteam.epeaky`; systemd unit and
   the Caddy block from the README.
3. Check: `curl https://push.epeaky.zyn-network.com/health` → `{"ok":true}`.

## 3. gen-epeaky

1. A release with the den changes for the app (Report, Block, Delete
   account, the relay, the association file), then `epeaky update`.
2. In its `.env`: `DEN_APPLE_APP=<TEAMID>.io.infinityteam.epeaky`. Check:
   `curl https://gen-epeaky.zyn-network.com/.well-known/apple-app-site-association`.
3. A den owner on gen-epeaky watches Den settings → Reports (Apple asks that
   reports are acted on).

## 4. Build and upload

```sh
cd apps/cave-den/ios
# DEVELOPMENT_TEAM: the team id, in project.yml (settings.base)
xcodegen generate
xcodebuild -project Epeaky.xcodeproj -scheme Epeaky -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/Epeaky.xcarchive archive
xcodebuild -exportArchive -archivePath build/Epeaky.xcarchive \
  -exportOptionsPlist store/ExportOptions.plist -exportPath build/export
```

Upload `build/export/Epeaky.ipa` with Transporter or Xcode's Organizer.
Automatic signing makes the profiles; the archive's push entitlement
becomes `production`. Bump `CURRENT_PROJECT_VERSION` for every upload.

## 5. App Store Connect

- The app record: listing, screenshots and review notes from `store/LISTING.md`.
- Privacy policy and terms published (drafts: `store/PRIVACY.md`).
- **App Privacy**: the app collects no data for the developer
  (no analytics, ads or tracking). gen-epeaky, which the project runs, keeps a
  device's public key and its pass hash to let it in, unlinked to who the
  person is: declare "Identifiers → User ID, app functionality, not linked to
  identity, not tracking" if you count that as collected. Messages are
  end-to-end encrypted and need no declaration.
- **Export compliance**: the app binary uses Apple's own encryption
  (CryptoKit, TLS, WebKit); the MLS encryption runs in the den's web page
  inside WebKit. Answer the questions in App Store Connect as the account
  holder determines; then set `ITSAppUsesNonExemptEncryption` in project.yml
  so later builds are not asked again.
- **Age rating**: the questionnaire, with the facts in LISTING.md.
- Review notes with a fresh gen-epeaky invite link (`epeaky invite 1`).

## Tests before each upload

```sh
xcodegen generate
xcodebuild test -project Epeaky.xcodeproj -scheme Epeaky \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:EpeakyTests
# with a dev den on :4000 and a fresh invite to it:
TEST_RUNNER_EPEAKY_INVITE='http://localhost:4000/#invite=…' xcodebuild test \
  -project Epeaky.xcodeproj -scheme Epeaky \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:EpeakyUITests
```
