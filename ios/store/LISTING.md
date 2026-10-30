# App Store listing: Epeaky

Copy for App Store Connect, in its fields. Plain facts, no slogans.

## App information

| Field | Value |
|---|---|
| Name | Epeaky |
| Subtitle (30) | End-to-end encrypted chat |
| Bundle id | io.infinityteam.epeaky |
| SKU | epeaky-ios |
| Primary category | Social Networking |
| Secondary category | Productivity |
| Support URL | https://epeaky.zyn-network.com/support (to publish) |
| Marketing URL | https://epeaky.zyn-network.com |
| Privacy policy URL | https://epeaky.zyn-network.com/privacy (to publish; draft in PRIVACY.md) |
| Copyright | 2026 Infinity Team |

## Promotional text (170)

Rooms, private chats, files and voice, end-to-end encrypted. Open the public den or any den you are invited to.

## Description

Epeaky is a chat app for groups. Messages, files and voice are end-to-end encrypted with MLS: only members' devices hold the keys.

- Rooms for the whole group, and private rooms with the people you pick
- Voice in any room, files and images, replies, reactions, pins and search
- Each den is run by its host. The host relays what it cannot read and sees who is in which room and when, never the words
- Your device enters under a name made from a key of its own, not from your phone number or email
- Notifications name the den and the room, never the words
- Report a message to a den's moderators, block a member, or delete your account from Settings
- Open the public den, gen-epeaky, or any den by its address or an invite link

Epeaky is open source: github.com/zyn-io/epeaky

## Keywords (100)

encrypted,chat,group,private,messenger,MLS,rooms,voice,community,secure,end-to-end,open source

## Screenshots

6.9" (1320×2868), in `screenshots/`: chat list, a room, a private chat, Settings.
Made from a dev den with a seeded conversation; the den's page renders the same in the app.

## Age rating

Answer in App Store Connect; the facts:

- Unrestricted user-generated content between members (chat, files): yes.
- Moderation: reports to the den's moderators, blocking, removal (timeout, kick, ban) by moderators.
- Web access: the app opens only den pages and sends other links to Safari.

## Review notes (App Review Information)

```
Epeaky opens a "den": a chat server's own page. To review, open this invite link on the device
(or paste it into "Another den" on the first screen):

  <an invite link to gen-epeaky, made at submission by its host with `epeaky invite 1`>

What to try:
- Chats: the list of rooms; tap General to write; the microphone joins voice.
- Report: tap a message (another member's) → the flag icon → give a reason.
- Block: tap a member's name (⋯ → Members) → Block.
- Delete account: Settings tab → Delete account.
- Notifications: allowed on first open; a message in a private room while the app is closed
  shows "Builders: New message in a private room" (never the words).

Messages are end-to-end encrypted (MLS); the den relays ciphertext. Moderators of each den act
on reports with timeouts, kicks and bans. Contact: <support address>.
```

Demo account: none needed; the invite link is the way in.
