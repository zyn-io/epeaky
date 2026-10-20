// This device's pass, kept in a passkey too: the browser's data can be cleared
// (or dropped by the browser itself), a passkey stays with the member's
// password manager. The pass is the passkey's user id, which the manager
// gives only to this den's address, after the member unlocks it; nothing of
// it goes to the den, and the passkey's signature is never checked: the pass
// is what lets the device in, through the door as always.

const PASS = /^[0-9a-f]{64}$/;
const hex = (u8) => [...u8].map((x) => x.toString(16).padStart(2, '0')).join('');
const unhex = (h) => Uint8Array.from(h.match(/../g).map((x) => parseInt(x, 16)));
const quiet = (m) => Object.assign(new Error(m), { quiet: true });
const cancelled = (e) => e?.name === 'NotAllowedError' || e?.name === 'AbortError';

/// Whether this browser makes passkeys here.
export const passkeys = () => typeof PublicKeyCredential !== 'undefined' && globalThis.isSecureContext === true && !!navigator.credentials?.create;

/// A passkey for this den holding `code`. Saving again for the same pass
/// replaces it in the password manager (same site, same user id).
export async function savePasskey(code, den, creds = navigator.credentials) {
  if (!PASS.test(code || '')) throw new Error('This device keeps no pass to save.');
  try {
    await creds.create({
      publicKey: {
        rp: { name: 'Epeaky' },
        user: { id: unhex(code), name: `Pass for ${den}`, displayName: `Epeaky pass, ${den}` },
        challenge: crypto.getRandomValues(new Uint8Array(32)),
        pubKeyCredParams: [{ type: 'public-key', alg: -7 }, { type: 'public-key', alg: -257 }],
        authenticatorSelection: { residentKey: 'required', requireResidentKey: true, userVerification: 'required' },
        attestation: 'none',
      },
    });
  } catch (e) {
    if (cancelled(e)) throw quiet('Not saved.');
    throw e;
  }
}

/// The pass in this den's passkey the member picks.
export async function passFromPasskey(creds = navigator.credentials) {
  let c;
  try {
    c = await creds.get({ publicKey: { challenge: crypto.getRandomValues(new Uint8Array(32)), userVerification: 'required' } });
  } catch (e) {
    if (cancelled(e)) throw quiet('Not entered.');
    throw e;
  }
  const id = c?.response?.userHandle ? new Uint8Array(c.response.userHandle) : null;
  if (!id || id.length !== 32) throw new Error('That passkey holds no pass for this den.');
  return hex(id);
}
