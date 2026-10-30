// Cashboard (https://cashboard.live), a market board, as an app inside the
// den, when the host turns it on (DEN_CASHBOARD). It runs framed, in its own
// origin: it never sees this den's keys, rooms or words. The den tells it the
// host's fee codes (Cashboard applies them within its own caps, and only for a
// den on its partner list), and it may hand the den a board a member chose to
// share. Protocol cashboard-host/1, from Cashboard's partner-mode design.

export const CASHBOARD = 'https://cashboard.live';
export const CASHBOARD_EMBED = `${CASHBOARD}/embed`;
const PROTO = 'cashboard-host/1';
// A shared board as Cashboard encodes it: a format digit, then base64url, at
// most 64 000 characters.
const BOARD = /^[01][A-Za-z0-9_-]{1,63999}$/;
/// Shared boards go into a room as sealed files with this ending.
export const BOARD_SUFFIX = '.cashboard';

export const isBoard = (s) => typeof s === 'string' && BOARD.test(s);
const plainName = (s) => String(s ?? '').replace(/[\u0000-\u001f\u007f/\\​-‏‪-‮⁠-⁩﻿؜]/g, '').replace(/\s+/g, ' ').trim().slice(0, 80);

/// A board as a file for a room.
export const boardFile = (board, name) => new File([board], `${plainName(name) || 'Board'}${BOARD_SUFFIX}`, { type: 'application/octet-stream' });

/// The board's name when a room's file is a shared board, else null.
export function boardName(file) {
  const name = String(file?.name ?? '');
  if (!name.endsWith(BOARD_SUFFIX) || !(file.size > 0 && file.size <= 64_000)) return null;
  return name.slice(0, -BOARD_SUFFIX.length) || 'Board';
}

/// Talks with the Cashboard in `frame`: greets it with the host's `codes`
/// whenever it says it is ready (again after a reload), hands `onShare` the
/// boards members share from it, and opens boards in it with `load`. Sharing
/// is on; trading is off until the den has a trade window of its own.
export function connectCashboard({ frame, codes = {}, onShare = () => {}, win = window }) {
  let ready = false;
  const waiting = [];
  const post = (m) => frame.contentWindow?.postMessage({ proto: PROTO, ...m }, CASHBOARD);
  win.addEventListener('message', (e) => {
    if (e.origin !== CASHBOARD || e.source !== frame.contentWindow) return;
    const m = e.data;
    if (!m || typeof m !== 'object' || m.proto !== PROTO) return;
    if (m.t === 'ready') {
      ready = true;
      post({ t: 'hello', partner: 'epeaky', codes, features: { share: true, trade: false } });
      while (waiting.length) post({ t: 'load-board', board: waiting.shift() });
    } else if (m.t === 'share-board' && isBoard(m.board)) {
      onShare({ board: m.board, name: plainName(m.name) });
    }
  });
  return {
    /// Opens a board on Cashboard's review screen; nothing is saved there until the member says so.
    load(board) {
      if (!isBoard(board)) throw new Error('That file is not a Cashboard board.');
      if (ready) post({ t: 'load-board', board });
      else waiting.push(board);
    },
  };
}
