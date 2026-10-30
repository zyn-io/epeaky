import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { BOARD_SUFFIX, CASHBOARD, boardFile, boardName, connectCashboard, isBoard } from '../cashboard.js';

const PROTO = 'cashboard-host/1';
const CODES = { lifi: { integrator: 'epeaky', fee: 0.005 } };

// The den's page around a frame: the frame's window records what is posted to it.
function page() {
  const sent = [];
  const frameWin = { postMessage: (data, origin) => sent.push({ data, origin }) };
  const target = new EventTarget();
  const from = (data, origin = CASHBOARD, source = frameWin) => target.dispatchEvent(Object.assign(new Event('message'), { data, origin, source }));
  return { sent, frame: { contentWindow: frameWin }, win: target, from };
}

test('Cashboard\'s ready gets the den\'s hello, with the host\'s codes, sent to Cashboard only', () => {
  const p = page();
  connectCashboard({ frame: p.frame, codes: CODES, win: p.win });
  p.from({ proto: PROTO, t: 'ready' });
  assert.deepEqual(p.sent, [{ data: { proto: PROTO, t: 'hello', partner: 'epeaky', codes: CODES, features: { share: true, trade: false } }, origin: CASHBOARD }]);
});

test('messages from anywhere but the Cashboard frame are ignored', () => {
  const p = page();
  const shared = [];
  connectCashboard({ frame: p.frame, codes: CODES, win: p.win, onShare: (b) => shared.push(b) });
  p.from({ proto: PROTO, t: 'ready' }, 'https://evil.example');
  p.from({ proto: PROTO, t: 'ready' }, CASHBOARD, { postMessage() {} });
  p.from({ proto: 'cashboard-host/0', t: 'ready' });
  p.from({ proto: PROTO, t: 'share-board', board: '0abc', name: 'x' }, 'https://evil.example');
  assert.equal(p.sent.length, 0);
  assert.equal(shared.length, 0);
});

test('a shared board reaches the den only when it is one, with a plain name', () => {
  const p = page();
  const shared = [];
  connectCashboard({ frame: p.frame, codes: CODES, win: p.win, onShare: (b) => shared.push(b) });
  p.from({ proto: PROTO, t: 'share-board', board: '1AbC_-9', name: '  Perps‮ desk  ' });
  p.from({ proto: PROTO, t: 'share-board', board: '<script>', name: 'x' });
  p.from({ proto: PROTO, t: 'share-board', board: '0' + 'a'.repeat(64_000), name: 'x' });
  p.from({ proto: PROTO, t: 'share-board', board: 42, name: 'x' });
  assert.deepEqual(shared, [{ board: '1AbC_-9', name: 'Perps desk' }]);
});

test('a trade from Cashboard is not acted on: this den has no trade window yet', () => {
  const p = page();
  let traded = false;
  connectCashboard({ frame: p.frame, codes: CODES, win: p.win, onShare: () => { traded = true; } });
  p.from({ proto: PROTO, t: 'trade', venue: 'hyperliquid', coin: 'BTC' });
  assert.equal(traded, false);
  assert.equal(p.sent.length, 0);
});

test('a board to open waits for Cashboard to be ready, and goes to it once', () => {
  const p = page();
  const cb = connectCashboard({ frame: p.frame, codes: {}, win: p.win });
  cb.load('0first');
  assert.equal(p.sent.length, 0);
  p.from({ proto: PROTO, t: 'ready' });
  assert.deepEqual(p.sent.map((s) => s.data.t), ['hello', 'load-board']);
  assert.equal(p.sent[1].data.board, '0first');
  assert.equal(p.sent[1].origin, CASHBOARD);
  cb.load('0second');
  assert.equal(p.sent[2].data.board, '0second');
  assert.throws(() => cb.load('not a board'), /not a Cashboard board/);
});

test('a reloaded Cashboard is greeted again', () => {
  const p = page();
  connectCashboard({ frame: p.frame, codes: {}, win: p.win });
  p.from({ proto: PROTO, t: 'ready' });
  p.from({ proto: PROTO, t: 'ready' });
  assert.deepEqual(p.sent.map((s) => s.data.t), ['hello', 'hello']);
});

test('a board travels as a sealed file named after it, and is told apart by that name', async () => {
  const f = boardFile('1AbC', 'Perps desk');
  assert.equal(f.name, `Perps desk${BOARD_SUFFIX}`);
  assert.equal(await f.text(), '1AbC');
  assert.equal(boardFile('1AbC', '').name, `Board${BOARD_SUFFIX}`);
  assert.equal(boardName({ name: `Perps desk${BOARD_SUFFIX}`, size: 4 }), 'Perps desk');
  assert.equal(boardName({ name: 'Perps desk.json', size: 4 }), null);
  assert.equal(boardName({ name: `big${BOARD_SUFFIX}`, size: 70_000 }), null);
  assert.equal(isBoard('0abc'), true);
  assert.equal(isBoard('2abc'), false);
});

test('nothing of the den goes to Cashboard but the codes and boards', async () => {
  const src = await readFile(new URL('../cashboard.js', import.meta.url), 'utf8');
  assert.doesNotMatch(src, /fetch|XMLHttpRequest|WebSocket|sendBeacon|localStorage|indexedDB/);
});
