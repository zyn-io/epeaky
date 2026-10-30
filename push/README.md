# epeaky-push

Epeaky's push relay: how a den's notification reaches Epeaky's iPhone app.

An App Store app gets no web push, only Apple's (APNs), and only the app's own
team key can send to it. A den sends web push (RFC 8030, encrypted as RFC 8291
says) to the push services it trusts; this relay is one of them
(`DEN_PUSH_RELAYS`, on by default). The app asks it for an address, the den
posts its encrypted push there, and the relay hands it to APNs unopened. The
phone opens it (only it holds the key) and shows the den's name and the room.

It keeps nothing: an address carries the phone's APNs token sealed under the
relay's key (AES-256-GCM). There is no list of phones. A push to an address it
did not make is refused (404); one APNs says is gone is answered 410, and the
den drops that address.

## What it sees

When a push arrives, from which den's server address, for which phone token.
Apple sees the same. Never the words or the room: the push is encrypted for
the phone. See THREAT_MODEL.md, Pushes.

## API

| | |
|---|---|
| `POST /register` `{token, env}` | the app: its APNs token (hex) and `production` or `sandbox` → `{endpoint}` |
| `POST /w/<id>` | a den: an `aes128gcm` push of at most 2 KB → 201, or 404, 410, 413, 429, 502 |
| `GET /health` | 200 |

At most 20 pushes a minute to one address (a den's share) and 60 to one phone over all its addresses; a full table forgets its oldest entry rather than turn anyone away. The APNs alert is "Epeaky: New
message"; the app's notification service extension replaces it with the den's
own words when it can open the push.

## Run

Node 22 or later, no dependencies:

```sh
RELAY_SECRET=$(openssl rand -hex 32) \
RELAY_ORIGIN=https://push.epeaky.zyn-network.com \
APNS_KEY_FILE=/etc/epeaky-push/AuthKey_XXXXXXXXXX.p8 \
APNS_KEY_ID=XXXXXXXXXX APNS_TEAM_ID=YYYYYYYYYY APNS_TOPIC=io.infinityteam.epeaky \
node bin/epeaky-push.mjs           # 127.0.0.1:4400 (PORT)
```

Keep `RELAY_SECRET` the same across restarts: a new one retires every address
made with the old (the app registers again when it next opens). The `.p8` key
is the team's (Apple Developer → Keys, with Apple Push Notifications), readable
only by the relay's user.

Behind Caddy, beside a den:

```
push.epeaky.zyn-network.com {
	reverse_proxy 127.0.0.1:4400
}
```

A systemd unit:

```ini
[Unit]
Description=Epeaky push relay
After=network-online.target

[Service]
EnvironmentFile=/etc/epeaky-push/env
ExecStart=/usr/bin/node /opt/epeaky-push/bin/epeaky-push.mjs
User=epeaky-push
Restart=always
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
```

## Tests

```sh
npm test
```
