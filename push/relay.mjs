// Epeaky's push relay: a web push address for Epeaky's iPhone app.
//
// An App Store app gets no web push, only Apple's (APNs), and only the app's
// own team key can send to it. A den sends web push (RFC 8291 and 8030) to
// any push service it trusts, so this relay is one: the app asks it for an
// address, the den posts its encrypted push there, and the relay hands it to
// APNs unopened, for the app to open on the phone.
//
// It keeps nothing. An address carries the phone's APNs token sealed under
// the relay's own key (AES-256-GCM), so there is no list of phones to lose
// or leak; a push it cannot route is refused with 404, one APNs says is gone
// with 410, and the den then drops that address.

import { createCipheriv, createDecipheriv, createPrivateKey, randomBytes, sign } from 'node:crypto';
import http2 from 'node:http2';

const MAX_BODY = 2048; // a den's push is ~200 bytes; sealed and in base64 it must fit APNs' 4 KB
const PER_ADDRESS = 20; // a minute: one den's share of a phone
const PER_PHONE = 60; // a minute, all its addresses together
const TOKEN = /^[0-9a-f]{64,200}$/;

/// An address's id: the APNs token and its environment, sealed under `secret`.
export function sealId(secret, token, env) {
  const iv = randomBytes(12);
  const c = createCipheriv('aes-256-gcm', secret, iv);
  const body = Buffer.concat([c.update(JSON.stringify({ t: token, e: env === 'sandbox' ? 's' : 'p' })), c.final()]);
  return Buffer.concat([iv, body, c.getAuthTag()]).toString('base64url');
}

/// The token and environment an id seals, or null for one this relay did not make.
export function openId(secret, id) {
  try {
    const raw = Buffer.from(id, 'base64url');
    // One spelling an address: base64url decodes several strings to the same bytes.
    if (raw.toString('base64url') !== id || raw.length < 12 + 16 + 10 || raw.length > 400) return null;
    const d = createDecipheriv('aes-256-gcm', secret, raw.subarray(0, 12));
    d.setAuthTag(raw.subarray(raw.length - 16));
    const j = JSON.parse(Buffer.concat([d.update(raw.subarray(12, raw.length - 16)), d.final()]).toString());
    return TOKEN.test(j.t) ? { token: j.t, env: j.e === 's' ? 'sandbox' : 'production' } : null;
  } catch {
    return null;
  }
}

/// The alert APNs shows when the app cannot open the push itself, and the
/// push for the app's notification service extension to open.
export function apnsPayload(id, body) {
  return JSON.stringify({
    aps: { alert: { title: 'Epeaky', body: 'New message' }, sound: 'default', 'mutable-content': 1 },
    s: id,
    w: body.toString('base64'),
  });
}

/// Sends to APNs over HTTP/2 with a token from the team's .p8 key (ES256),
/// made again every 40 minutes. `base` overrides Apple's hosts (tests).
export function apnsSender({ keyPem, keyId, teamId, topic, base = null, now = () => Date.now() }) {
  const key = createPrivateKey(keyPem);
  const sessions = {};
  let jwt = null;
  let made = 0;
  const bearer = () => {
    if (!jwt || now() - made > 40 * 60_000) {
      made = now();
      const part = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
      const signing = `${part({ alg: 'ES256', kid: keyId })}.${part({ iss: teamId, iat: Math.floor(made / 1000) })}`;
      jwt = `${signing}.${sign('sha256', Buffer.from(signing), { key, dsaEncoding: 'ieee-p1363' }).toString('base64url')}`;
    }
    return jwt;
  };
  const session = (env) => {
    const s = sessions[env];
    if (s && !s.closed && !s.destroyed) return s;
    const host = base || (env === 'sandbox' ? 'https://api.sandbox.push.apple.com' : 'https://api.push.apple.com');
    const n = http2.connect(host);
    n.on('error', () => {});
    n.on('goaway', () => n.close());
    sessions[env] = n;
    return n;
  };
  const send = ({ token, env, payload }) => new Promise((resolve) => {
    const req = session(env).request({
      ':method': 'POST',
      ':path': `/3/device/${token}`,
      authorization: `bearer ${bearer()}`,
      'apns-topic': topic,
      'apns-push-type': 'alert',
      'apns-priority': '10',
      'apns-expiration': String(Math.floor(now() / 1000) + 3600),
    });
    let status = 0;
    let text = '';
    req.setTimeout(10_000, () => { req.close(); resolve({ status: 503, reason: 'timeout' }); });
    req.on('response', (h) => { status = h[':status']; });
    req.on('data', (d) => { text += d; });
    req.on('end', () => { let reason = ''; try { reason = JSON.parse(text).reason || ''; } catch { /* no body */ } resolve({ status, reason }); });
    req.on('error', () => resolve({ status: 503, reason: 'connection' }));
    req.end(payload);
  });
  send.close = () => { for (const s of Object.values(sessions)) s.close(); };
  return send;
}

/// At most `max` a minute for each key. A full table drops past minutes'
/// entries, then (only if all are this minute's) its oldest: refusing
/// newcomers instead would let anyone lock every new phone out, and getting
/// round a phone's cap this way takes 50,000 other phones' tokens a minute.
function limiter(max, now, size = 50_000) {
  const counts = new Map();
  let swept = -1;
  return (key) => {
    const minute = Math.floor(now() / 60_000);
    const c = counts.get(key);
    if (c && c.minute === minute) return ++c.n > max;
    if (c) counts.delete(key);
    else if (counts.size >= size) {
      // At most one sweep a minute: past it, the oldest goes, in constant time.
      if (swept !== minute) {
        swept = minute;
        for (const [k, v] of counts) if (v.minute !== minute) counts.delete(k);
      }
      if (counts.size >= size) counts.delete(counts.keys().next().value);
    }
    counts.set(key, { minute, n: 1 });
    return false;
  };
}

/// The relay's HTTP handler. `send({token, env, payload})` → {status, reason}.
export function createRelay({ secret, origin, send, now = () => Date.now() }) {
  if (!Buffer.isBuffer(secret) || secret.length !== 32) throw new Error('the relay needs a 32-byte secret');
  // Each address has its own share (a den knows only its own), and the phone
  // a cap over all of them (anyone with its token can make more addresses).
  const perAddress = limiter(PER_ADDRESS, now);
  const perPhone = limiter(PER_PHONE, now);
  const reply = (res, status, body = null) => {
    res.writeHead(status, body ? { 'content-type': 'application/json' } : {});
    res.end(body ? JSON.stringify(body) : undefined);
  };
  const read = (req, max) => new Promise((resolve) => {
    const parts = [];
    let n = 0;
    req.on('data', (d) => { n += d.length; if (n <= max) parts.push(d); });
    req.on('end', () => resolve(n > max ? null : Buffer.concat(parts)));
    req.on('error', () => resolve(null));
  });

  const handle = async (req, res) => {
    const url = new URL(req.url, 'http://relay');
    if (req.method === 'GET' && url.pathname === '/health') return reply(res, 200, { ok: true });

    // The app asks for an address for its APNs token.
    if (req.method === 'POST' && url.pathname === '/register') {
      const body = await read(req, 1024);
      let j = null;
      try { j = JSON.parse(body); } catch { /* below */ }
      if (!j || typeof j.token !== 'string' || !TOKEN.test(j.token.toLowerCase()) || !['production', 'sandbox'].includes(j.env)) return reply(res, 400, { error: 'send {token, env}: the APNs token in hex, production or sandbox' });
      return reply(res, 200, { endpoint: `${origin}/w/${sealId(secret, j.token.toLowerCase(), j.env)}` });
    }

    // A den's push (RFC 8030, encrypted as RFC 8291 says).
    const w = /^\/w\/([A-Za-z0-9_-]{1,400})$/.exec(url.pathname);
    if (req.method === 'POST' && w) {
      const to = openId(secret, w[1]);
      if (!to) return reply(res, 404, { error: 'no such push address' });
      if (String(req.headers['content-encoding']).toLowerCase() !== 'aes128gcm') return reply(res, 400, { error: 'pushes here are aes128gcm' });
      const body = await read(req, MAX_BODY);
      if (!body) return reply(res, 413, { error: `a push here is at most ${MAX_BODY} bytes` });
      if (!body.length) return reply(res, 400, { error: 'an empty push' });
      if (perAddress(w[1]) || perPhone(to.token)) return reply(res, 429, { error: 'too many pushes to this address' });
      const r = await send({ token: to.token, env: to.env, payload: apnsPayload(w[1], body) });
      if (r.status === 200) return reply(res, 201);
      // The app was deleted, or the token is not one APNs knows: the den drops the address.
      if (r.status === 410 || (r.status === 400 && /BadDeviceToken|DeviceTokenNotForTopic/.test(r.reason))) return reply(res, 410, { error: 'gone' });
      if (r.status === 429) return reply(res, 429, { error: 'too many pushes to this phone' });
      return reply(res, 502, { error: 'Apple did not take the push' });
    }

    return reply(res, 404, { error: 'not here' });
  };

  // Nothing a caller sends ends the process: a request it cannot take is refused.
  return (req, res) => handle(req, res).catch(() => { if (!res.headersSent) reply(res, 400, { error: 'refused' }); else res.destroy(); });
}
