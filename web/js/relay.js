// Ported from soul-match-meter/Model/Relay.swift.
//
// The relay carries the guest's serial back to the host, so the host's report
// arrives on its own instead of being typed in (see relay/worker.js). It holds
// host serial → guest serial for 24 h — and, when both sides turned the pair
// photo on, each one's heat grid for the other, handed out only for a key.
//
// Every call can fail quietly: typing the serial in on 02 still works.

import { PREFIX } from './serial-codec.js';

const BASE = 'https://soul-match-relay.momoopsoops.workers.dev';
const TIMEOUT_MS = 8000;

function request(path, options = {}) {
  return fetch(BASE + path, { ...options, cache: 'no-store', signal: AbortSignal.timeout?.(TIMEOUT_MS) });
}

// No Content-Type header: a plain-text body needs no preflight.
function post(path, body) {
  return request(path, { method: 'POST', body: JSON.stringify(body) });
}

const retry = (response) => response.status === 429 || response.status >= 500;

// The guest finished measuring: file their serial under the host's. `settled`
// is true when it is filed or refused for good, false when it is worth another
// try (offline, rate-limited, or the relay is down). With a `key`, the guest's
// grid goes along and `heat` is the host's, when there is one.
export async function send(host, guest, key = null, heat = null) {
  try {
    if (key === null) return { settled: !retry(await post('/reply', { host, guest })), heat: null };
    const response = await post('/reply', { host, guest, key, ...(heat && { heat }) });
    // A relay from before grids refuses the longer body: the serial still has
    // to get through.
    if (response.status === 400) return send(host, guest);
    if (retry(response)) return { settled: false, heat: null };
    const answer = response.ok ? await response.json() : null;
    return { settled: true, heat: typeof answer?.heat === 'string' ? answer.heat : null };
  } catch {
    return { settled: false, heat: null };
  }
}

// The host handed their serial out: file the key their guest's grid will be
// fetched with, and their own grid if they have one. Resolves like `send`'s
// `settled`.
export async function file(host, key, heat = null) {
  try {
    return !retry(await post('/host', { host, key, ...(heat && { heat }) }));
  } catch {
    return false;
  }
}

// The guest's grid, for the host's key: the grid, null when there is none to
// be had, or undefined when it is worth asking again.
export async function peerHeat(host, key) {
  try {
    const response = await post('/heat', { host, key });
    if (retry(response)) return undefined;
    if (!response.ok) return null;
    const answer = await response.json();
    return typeof answer?.heat === 'string' ? answer.heat : null;
  } catch {
    return undefined;
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
