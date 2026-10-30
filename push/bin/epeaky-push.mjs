#!/usr/bin/env node
// Epeaky's push relay, on localhost behind the host's TLS (Caddy).
//
//   RELAY_SECRET     64 hex characters (openssl rand -hex 32); a new one
//                    retires every address made with the old
//   RELAY_ORIGIN     https://push.epeaky.zyn-network.com
//   APNS_KEY_FILE    the team's .p8 key (Apple Developer → Keys, APNs)
//   APNS_KEY_ID      its key id
//   APNS_TEAM_ID     the team id
//   APNS_TOPIC       the app's bundle id (io.infinityteam.epeaky)
//   PORT             default 4400, bound to 127.0.0.1
import { readFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { apnsSender, createRelay } from '../relay.mjs';

const need = (k) => process.env[k] || (console.error(`epeaky-push: ${k} is not set`), process.exit(2));
const secret = Buffer.from(need('RELAY_SECRET'), 'hex');
const send = apnsSender({ keyPem: readFileSync(need('APNS_KEY_FILE'), 'utf8'), keyId: need('APNS_KEY_ID'), teamId: need('APNS_TEAM_ID'), topic: need('APNS_TOPIC') });
const relay = createRelay({ secret, origin: need('RELAY_ORIGIN').replace(/\/$/, ''), send });
const port = Number(process.env.PORT || 4400);
createServer(relay).listen(port, '127.0.0.1', () => console.log(`epeaky-push on 127.0.0.1:${port}`));
const stop = () => { send.close(); process.exit(0); };
process.on('SIGTERM', stop);
process.on('SIGINT', stop);
