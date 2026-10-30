# Privacy and terms: drafts for epeaky.zyn-network.com

Drafts for the pages the App Store listing points to (`/privacy`, `/terms`,
`/support`). The site is published by its owner; these are the facts the
pages must state, from THREAT_MODEL.md.

## /privacy

**Epeaky** is a chat app. Each den (chat server) is run by its host; the
public den, gen-epeaky.zyn-network.com, is run by the Epeaky project.

What a den's host can see: which device names are in which room, when they
write or talk, file sizes, the names of open rooms, who joins or leaves, and
the network address a device connects from. Never the words, files or voice:
they are end-to-end encrypted (MLS) and only members' devices hold the keys.
A message a member reports reaches that den's moderators with its words only
if the reporter chooses to include them.

What stays on your phone: your messages, your device's keys and its pass.
Deleting the app or using Delete account removes them.

Notifications: a den sends a push through Epeaky's push relay
(push.epeaky.zyn-network.com) and Apple's push service. Both learn that a
push arrived for your phone and from which den's server; the push is
encrypted so that only your phone can open it, and it names the den and the
room, never the words. The relay stores nothing.

The app collects no analytics, has no ads and no tracking.

Delete account (Settings): your pass is removed from the den, your device
leaves every room, and everything the app keeps is deleted. Messages others
already received stay on their devices.

Contact: <support address>.

## /terms

By using Epeaky you agree:

- No objectionable content: nothing illegal, no sexual content involving
  minors, no harassment, threats, hate or spam.
- No abusive behaviour toward other members.
- Members can report messages and block members. Each den's moderators act
  on reports and may time out, remove or ban a member. The Epeaky project
  moderates gen-epeaky and acts on reports within 24 hours.
- A den you open that the Epeaky project does not run is its host's; its
  host sets its rules.

## /support

How to get help, report abuse on gen-epeaky, and reach the project:
<support address>. Abuse on another den: its moderators, through Report.
