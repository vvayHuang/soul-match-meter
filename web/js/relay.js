// Ported from soul-match-meter/Model/Relay.swift.
//
// The relay carries the guest's serial back to the host, so the host's report
// arrives on its own instead of being typed in (see relay/worker.js). It holds
// host serial → guest serial for 24 h and nothing else.
//
// Every call can fail quietly: typing the serial in on 02 still works.

import { PREFIX } from './serial-codec.js';

const BASE = 'https://soul-match-relay.momoopsoops.workers.dev';
const TIMEOUT_MS = 8000;

function request(path, options = {}) {
  return fetch(BASE + path, { ...options, cache: 'no-store', signal: AbortSignal.timeout?.(TIMEOUT_MS) });
}

// The guest finished measuring: file their serial under the host's. Resolves
// true when it is filed or refused for good, false when it is worth another
// try (offline, rate-limited, or the relay is down).
export async function send(host, guest) {
  try {
    // No Content-Type header: a plain-text body needs no preflight.
    const response = await request('/reply', { method: 'POST', body: JSON.stringify({ host, guest }) });
    return !(response.status === 429 || response.status >= 500);
  } catch {
    return false;
  }
}

// Whether anything has come back for this host serial: `{ guest, at }`, with
// `at` in milliseconds since 1970, or null.
export async function reply(host) {
  try {
    const response = await request(`/reply/${host.slice(PREFIX.length)}`);
    if (response.status !== 200) return null;
    const found = await response.json();
    return typeof found?.guest === 'string' ? found : null;
  } catch {
    return null;
  }
}
