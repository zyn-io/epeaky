import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { passFromPasskey, savePasskey } from '../passkey.js';

const PASS = 'ab'.repeat(32);

// A password manager in memory: create keeps the user id, get hands it back.
function manager() {
  const kept = [];
  return {
    kept,
    create: async ({ publicKey }) => { kept.push(publicKey); return { id: 'x' }; },
    get: async () => ({ response: { userHandle: kept.at(-1).user.id.buffer } }),
  };
}

test('a passkey keeps the pass as its user id, discoverable and behind the user', async () => {
  const m = manager();
  await savePasskey(PASS, 'gen-epeaky.zyn-network.com', m);
  const k = m.kept[0];
  assert.equal(Buffer.from(k.user.id).toString('hex'), PASS);
  assert.equal(k.authenticatorSelection.residentKey, 'required');
  assert.equal(k.authenticatorSelection.userVerification, 'required');
  assert.match(k.user.name, /gen-epeaky\.zyn-network\.com/);
  assert.equal(k.rp.id, undefined, 'the den\'s own address, by default');
});

test('the passkey gives the pass back', async () => {
  const m = manager();
  await savePasskey(PASS, 'den', m);
  assert.equal(await passFromPasskey(m), PASS);
});

test('a passkey with no pass in it is refused', async () => {
  const m = { get: async () => ({ response: { userHandle: new Uint8Array(16).buffer } }) };
  await assert.rejects(passFromPasskey(m), /holds no pass/);
  await assert.rejects(passFromPasskey({ get: async () => ({ response: { userHandle: null } }) }), /holds no pass/);
});

test('closing the passkey prompt is no error', async () => {
  const no = Object.assign(new Error('cancelled'), { name: 'NotAllowedError' });
  await assert.rejects(passFromPasskey({ get: async () => { throw no; } }), (e) => e.quiet === true);
  await assert.rejects(savePasskey(PASS, 'den', { create: async () => { throw no; } }), (e) => e.quiet === true);
});

test('only a pass code goes in a passkey', async () => {
  await assert.rejects(savePasskey('not a pass', 'den', manager()), /no pass/);
});

test('nothing of the passkey goes to the den', async () => {
  assert.doesNotMatch(await readFile(new URL('../passkey.js', import.meta.url), 'utf8'), /fetch|XMLHttpRequest|WebSocket|sendBeacon/);
});
