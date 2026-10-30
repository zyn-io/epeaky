import assert from 'node:assert/strict';
import { generateKeyPairSync, randomBytes, verify } from 'node:crypto';
import { createServer } from 'node:http';
import http2 from 'node:http2';
import { test } from 'node:test';
import { apnsSender, createRelay, openId, sealId } from '../relay.mjs';

const TOKEN = 'ab'.repeat(32);
const listen = (handler) => new Promise((resolve) => { const s = createServer(handler).listen(0, '127.0.0.1', () => resolve(s)); });
const base = (s) => `http://127.0.0.1:${s.address().port}`;

/// A relay on a free port, sending through `answer` (APNs stood in for).
async function relay(answer = () => ({ status: 200 })) {
  const sent = [];
  let t = 1_000_000;
  const secret = randomBytes(32);
  const server = await listen(createRelay({ secret, origin: 'https://push.example', send: async (p) => { sent.push(p); return answer(p); }, now: () => t }));
  const register = async (body) => fetch(`${base(server)}/register`, { method: 'POST', body: JSON.stringify(body) });
  const push = (path, body = randomBytes(200), headers = { 'content-encoding': 'aes128gcm' }) => fetch(`${base(server)}${path}`, { method: 'POST', headers, body });
  return { server, sent, secret, register, push, tick: (ms) => { t += ms; } };
}

test('an address seals the token under the relay key: only this relay opens it, and a changed one opens nowhere', () => {
  const k = randomBytes(32);
  const id = sealId(k, TOKEN, 'sandbox');
  assert.deepEqual(openId(k, id), { token: TOKEN, env: 'sandbox' });
  assert.deepEqual(openId(k, sealId(k, TOKEN, 'production')), { token: TOKEN, env: 'production' });
  assert.notEqual(sealId(k, TOKEN, 'sandbox'), id, 'a new address each time');
  assert.equal(openId(randomBytes(32), id), null);
  const raw = Buffer.from(id, 'base64url');
  raw[14] ^= 1;
  assert.equal(openId(k, raw.toString('base64url')), null);
  assert.equal(openId(k, 'short'), null);
  // The same bytes spelled another way (base64url's spare low bits) are not the address.
  const alt = id.slice(0, -1) + String.fromCharCode(id.charCodeAt(id.length - 1) ^ 1);
  if (Buffer.from(alt, 'base64url').equals(Buffer.from(id, 'base64url'))) assert.equal(openId(k, alt), null);
  assert.equal(openId(k, `${id}=`), null);
});

test("the app registers its token; a den's push goes to APNs unopened, as the alert and the sealed body", async () => {
  const r = await relay();
  const res = await r.register({ token: TOKEN.toUpperCase(), env: 'production' });
  assert.equal(res.status, 200);
  const { endpoint } = await res.json();
  assert.match(endpoint, /^https:\/\/push\.example\/w\/[A-Za-z0-9_-]+$/);
  const path = new URL(endpoint).pathname;
  const body = randomBytes(180);
  const p = await r.push(path, body);
  assert.equal(p.status, 201);
  assert.equal(r.sent.length, 1);
  assert.equal(r.sent[0].token, TOKEN);
  assert.equal(r.sent[0].env, 'production');
  const payload = JSON.parse(r.sent[0].payload);
  assert.deepEqual(payload.aps.alert, { title: 'Epeaky', body: 'New message' });
  assert.equal(payload.aps['mutable-content'], 1);
  assert.equal(payload.s, path.slice(3));
  assert.deepEqual(Buffer.from(payload.w, 'base64'), body);
  assert.ok(Buffer.byteLength(r.sent[0].payload) < 4096, 'within APNs 4 KB');
  r.server.close();
});

test('refused: a bad registration, an address it did not make, a push not aes128gcm, empty or over 2 KB, past 20 a minute an address or 60 a phone', async () => {
  const r = await relay();
  for (const b of [{}, { token: 'xyz', env: 'production' }, { token: TOKEN, env: 'staging' }]) assert.equal((await r.register(b)).status, 400, JSON.stringify(b));
  const path = new URL((await (await r.register({ token: TOKEN, env: 'sandbox' })).json()).endpoint).pathname;
  assert.equal((await r.push(`/w/${sealId(randomBytes(32), TOKEN, 'sandbox')}`)).status, 404);
  assert.equal((await r.push(path, randomBytes(10), { 'content-encoding': 'aesgcm' })).status, 400);
  assert.equal((await r.push(path, Buffer.alloc(0))).status, 400);
  assert.equal((await r.push(path, randomBytes(2049))).status, 413);
  assert.equal((await r.push('/elsewhere')).status, 404);
  // 20 a minute an address (a den's share), 60 a phone over all its addresses.
  for (let i = 0; i < 20; i++) assert.equal((await r.push(path)).status, 201);
  assert.equal((await r.push(path)).status, 429);
  const more = async () => new URL((await (await r.register({ token: TOKEN, env: 'sandbox' })).json()).endpoint).pathname;
  const [b, c, d] = [await more(), await more(), await more()];
  for (let i = 0; i < 20; i++) assert.equal((await r.push(b)).status, 201, "another den's address still gets its share");
  for (let i = 0; i < 20; i++) assert.equal((await r.push(c)).status, 201);
  assert.equal((await r.push(d)).status, 429, 'past 60 for the phone, a new address does not get round it');
  r.tick(60_000);
  assert.equal((await r.push(path)).status, 201, 'the next minute');
  assert.equal(r.sent.length, 61);
  r.server.close();
});

test('a request it cannot parse is refused, and the relay goes on', async () => {
  const r = await relay();
  const { request } = await import('node:http');
  const status = await new Promise((resolve) => {
    const q = request({ host: '127.0.0.1', port: r.server.address().port, method: 'POST', path: '//[' }, (res) => resolve(res.statusCode));
    q.on('error', () => resolve('error'));
    q.end();
  });
  assert.ok(status === 400 || status === 404, `refused (${status})`);
  assert.equal((await fetch(`${base(r.server)}/health`)).status, 200, 'and still answers');
  r.server.close();
});

test('APNs says the app is gone: the den is told 410 and drops the address; other failures are not that', async () => {
  for (const [answer, want] of [[{ status: 410, reason: 'Unregistered' }, 410], [{ status: 400, reason: 'BadDeviceToken' }, 410], [{ status: 400, reason: 'DeviceTokenNotForTopic' }, 410], [{ status: 429, reason: 'TooManyRequests' }, 429], [{ status: 500, reason: 'InternalServerError' }, 502], [{ status: 503, reason: 'timeout' }, 502]]) {
    const r = await relay(() => answer);
    const path = new URL((await (await r.register({ token: TOKEN, env: 'production' })).json()).endpoint).pathname;
    assert.equal((await r.push(path)).status, want, JSON.stringify(answer));
    r.server.close();
  }
});

test("APNs is called as Apple says: HTTP/2, the device's path, the topic, an ES256 token from the team's key", async () => {
  const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const seen = [];
  const h2 = http2.createServer();
  h2.on('stream', (stream, headers) => {
    let body = '';
    stream.on('data', (d) => { body += d; });
    stream.on('end', () => {
      seen.push({ headers, body });
      const gone = headers[':path'].endsWith('dead');
      stream.respond({ ':status': gone ? 410 : 200, 'content-type': 'application/json' });
      stream.end(gone ? JSON.stringify({ reason: 'Unregistered' }) : '');
    });
  });
  await new Promise((r) => h2.listen(0, '127.0.0.1', r));
  const send = apnsSender({ keyPem: privateKey.export({ type: 'pkcs8', format: 'pem' }), keyId: 'KEY123', teamId: 'TEAM45', topic: 'io.infinityteam.epeaky', base: `http://127.0.0.1:${h2.address().port}` });
  assert.deepEqual(await send({ token: TOKEN, env: 'production', payload: '{"aps":{}}' }), { status: 200, reason: '' });
  assert.deepEqual(await send({ token: 'dead', env: 'production', payload: '{}' }), { status: 410, reason: 'Unregistered' });
  const [h] = seen.map((s) => s.headers);
  assert.equal(h[':method'], 'POST');
  assert.equal(h[':path'], `/3/device/${TOKEN}`);
  assert.equal(h['apns-topic'], 'io.infinityteam.epeaky');
  assert.equal(h['apns-push-type'], 'alert');
  assert.equal(seen[0].body, '{"aps":{}}');
  const [head, claims, sig] = h.authorization.replace(/^bearer /, '').split('.');
  assert.deepEqual(JSON.parse(Buffer.from(head, 'base64url')), { alg: 'ES256', kid: 'KEY123' });
  assert.equal(JSON.parse(Buffer.from(claims, 'base64url')).iss, 'TEAM45');
  assert.ok(verify('sha256', Buffer.from(`${head}.${claims}`), { key: publicKey, dsaEncoding: 'ieee-p1363' }, Buffer.from(sig, 'base64url')), 'signed by the team key');
  assert.equal(seen[1].headers.authorization, h.authorization, 'one token reused, not one a push');
  send.close();
  h2.close();
});
