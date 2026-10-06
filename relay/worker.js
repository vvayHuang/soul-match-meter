// The relay: a Cloudflare Worker that carries the guest's serial back to the
// host, so the host's report arrives on its own instead of being typed in.
//
// It holds one thing per exchange, for 24 hours: host serial → guest serial.
//
//     POST /reply          { "host": "SM-123456", "guest": "SM-654321" }
//     GET  /reply/123456   → { "guest": "SM-654321", "at": 1790000000000 }
//                          → { "guest": null } while nothing has come back
//
// When both sides opted in, it also carries each one's heat grid to the other,
// so a report can show the pair (see web/js/heat.js). A serial is short enough
// to guess, so a grid is never handed out for a serial alone:
//
//     POST /host           { "host", "key", "heat"? }
//         The host files a key of their own making, and their grid.
//     POST /reply          { "host", "guest", "key", "heat"? }
//         → { "ok": true, "heat": … }  the host's grid, to the one guest whose
//         reply stands, and again only to whoever holds that guest's key.
//     POST /heat           { "host", "key" }
//         → { "heat": … }  the guest's grid, to whoever holds the host's key.
//
// A guest's grid is kept only when a host key is on file to fetch it with.
//
// Bindings: REPLIES (KV namespace, required); LIMITER (rate limiting, optional).
//
// One file with no imports, so it can be pasted into the dashboard editor.
// The serial rules below are ported from soul-match-meter/Model/SerialCodec.swift
// (see also web/js/serial-codec.js). Keep them in step.

const PREFIX = 'SM-';
const LENGTH = 6;
const BANK_SIZE = 10;
const ANSWER_COMBOS = 64;
const SET_COUNT = (BANK_SIZE * (BANK_SIZE - 1) * (BANK_SIZE - 2)) / 6; // 120
const COMBOS = SET_COUNT * ANSWER_COMBOS; // 7680
const MAX_NONCE = Math.floor(100_000 / COMBOS) - 1; // 12
const WEIGHTS = [1, 3, 7, 9, 1];

// A serial is good for 24 h; so is its reply.
const VALID_FOR_SECONDS = 24 * 60 * 60;

// Where the web version is served from. The app sends no Origin at all.
const ALLOWED_ORIGINS = ['https://vvayhuang.github.io', 'http://localhost:4173'];

// A heat grid: 48 × 64 bytes, base64. A key: 128 random bits, hex.
const HEAT_PATTERN = /^[A-Za-z0-9+/]{4096}$/;
const KEY_PATTERN = /^[0-9a-f]{32}$/;
// Two serials, a key and a grid, with room to spare.
const MAX_BODY = 4400;

// Per client, per minute. A host waiting on the receipt asks every few seconds.
const READS_PER_MINUTE = 40;
const WRITES_PER_MINUTE = 6;

function checkDigit(data) {
  let sum = 0;
  for (let i = 0; i < WEIGHTS.length; i++) {
    sum += Number(data[i]) * WEIGHTS[i];
  }
  return (10 - (sum % 10)) % 10;
}

// Accepts "SM-123456" or "123456". Returns the six digits and which question
// draw they carry, or null when the length, check digit or range is wrong.
function read(serial) {
  if (typeof serial !== 'string') return null;
  const digits = serial.startsWith(PREFIX) ? serial.slice(PREFIX.length) : serial;
  if (!/^[0-9]{6}$/.test(digits)) return null;
  const data = digits.slice(0, LENGTH - 1);
  if (Number(digits[LENGTH - 1]) !== checkDigit(data)) return null;
  const value = Number(data);
  if (value >= (MAX_NONCE + 1) * COMBOS) return null;
  return { digits, set: Math.floor((value % COMBOS) / ANSWER_COMBOS) };
}

// A fixed window per client, kept in this isolate's memory. Isolates come and
// go and each location has its own, so this slows one client down rather than
// guaranteeing a ceiling; bind LIMITER for a real one.
const windows = new Map();

function overLimit(key, limit, now) {
  const minute = Math.floor(now / 60_000);
  const seen = windows.get(key);
  if (!seen || seen.minute !== minute) {
    if (windows.size > 5000) windows.clear();
    windows.set(key, { minute, count: 1 });
    return false;
  }
  seen.count += 1;
  return seen.count > limit;
}

async function limited(request, env, kind, limit) {
  const client = request.headers.get('CF-Connecting-IP') ?? 'unknown';
  const key = `${kind}:${client}`;
  if (overLimit(key, limit, Date.now())) return true;
  if (kind === 'write' && env.LIMITER) {
    const { success } = await env.LIMITER.limit({ key });
    return !success;
  }
  return false;
}

function corsHeaders(request) {
  const origin = request.headers.get('Origin');
  const headers = { Vary: 'Origin' };
  if (origin && ALLOWED_ORIGINS.includes(origin)) {
    headers['Access-Control-Allow-Origin'] = origin;
    headers['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS';
    headers['Access-Control-Allow-Headers'] = 'Content-Type';
    headers['Access-Control-Max-Age'] = '86400';
  }
  return headers;
}

function json(request, status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
      ...corsHeaders(request),
    },
  });
}

const key = (digits) => `reply:${digits}`;
const hostKey = (digits) => `host:${digits}`;

// The request's JSON body, or null when it is too long or isn't JSON.
async function readBody(request) {
  try {
    const text = await request.text();
    if (text.length > MAX_BODY) return null;
    return JSON.parse(text);
  } catch {
    return null;
  }
}

// Keys are kept hashed, so what is stored can't be replayed.
async function hashed(secret) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(secret));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, '0')).join('');
}

// An optional field: undefined when absent, null when present and malformed.
function optional(value, pattern) {
  if (value === undefined || value === null) return undefined;
  return typeof value === 'string' && pattern.test(value) ? value : null;
}

// The host handed their serial out: file their key, and their grid if any.
async function postHost(request, env) {
  if (await limited(request, env, 'write', WRITES_PER_MINUTE)) {
    return json(request, 429, { error: 'slow down' });
  }
  const body = await readBody(request);
  if (!body) return json(request, 400, { error: 'bad request' });

  const host = read(body.host);
  if (!host) return json(request, 400, { error: 'bad serial' });
  const secret = optional(body.key, KEY_PATTERN);
  const heat = optional(body.heat, HEAT_PATTERN);
  if (!secret || heat === null) return json(request, 400, { error: 'bad request' });

  const owner = await hashed(secret);
  const existing = await env.REPLIES.get(hostKey(host.digits), 'json');
  if (existing) {
    // The first key stands. Filing it again is fine and writes nothing.
    return existing.key === owner
      ? json(request, 200, { ok: true })
      : json(request, 409, { error: 'already filed' });
  }

  await env.REPLIES.put(hostKey(host.digits), JSON.stringify({ key: owner, heat: heat ?? null }), {
    expirationTtl: VALID_FOR_SECONDS,
  });
  return json(request, 201, { ok: true });
}

// The guest finished measuring: file their serial under the host's.
async function postReply(request, env) {
  if (await limited(request, env, 'write', WRITES_PER_MINUTE)) {
    return json(request, 429, { error: 'slow down' });
  }
  const body = await readBody(request);
  if (!body) return json(request, 400, { error: 'bad request' });

  const host = read(body.host);
  const guest = read(body.guest);
  if (!host || !guest) return json(request, 400, { error: 'bad serial' });
  if (host.digits === guest.digits) return json(request, 400, { error: 'own serial' });
  // The guest answers the host's draw, so a reply always carries the same one.
  if (host.set !== guest.set) return json(request, 400, { error: 'wrong set' });
  const secret = optional(body.key, KEY_PATTERN);
  const heat = optional(body.heat, HEAT_PATTERN);
  if (secret === null || heat === null) return json(request, 400, { error: 'bad request' });

  const guestSerial = PREFIX + guest.digits;
  const owner = secret ? await hashed(secret) : null;
  // A guest who sent a key gets the host's grid back with the answer.
  const settled = async (status, filed) => {
    if (!owner) return json(request, status, { ok: true });
    const from = filed ?? (await env.REPLIES.get(hostKey(host.digits), 'json'));
    return json(request, status, { ok: true, heat: from?.heat ?? null });
  };

  const existing = await env.REPLIES.get(key(host.digits), 'json');
  if (existing) {
    if (existing.guest !== guestSerial) return json(request, 409, { error: 'already replied' });
    // The first reply stands. Sending it again is fine and writes nothing —
    // and brings the grid again only for the key it was first sent with.
    if (owner && existing.key !== owner) return json(request, 200, { ok: true });
    return settled(200);
  }

  const reply = { guest: guestSerial, at: Date.now() };
  let filed = null;
  if (owner) {
    reply.key = owner;
    filed = await env.REPLIES.get(hostKey(host.digits), 'json');
    // Only a host with a key on file can ever fetch the guest's grid.
    if (filed && heat) reply.heat = heat;
  }
  await env.REPLIES.put(key(host.digits), JSON.stringify(reply), { expirationTtl: VALID_FOR_SECONDS });
  return settled(201, filed ?? {});
}

// The host's reply came in: hand over the guest's grid, for the host's key.
async function postHeat(request, env) {
  if (await limited(request, env, 'read', READS_PER_MINUTE)) {
    return json(request, 429, { error: 'slow down' });
  }
  const body = await readBody(request);
  if (!body) return json(request, 400, { error: 'bad request' });

  const host = read(body.host);
  if (!host) return json(request, 400, { error: 'bad serial' });
  const secret = optional(body.key, KEY_PATTERN);
  if (!secret) return json(request, 400, { error: 'bad request' });

  const filed = await env.REPLIES.get(hostKey(host.digits), 'json');
  if (!filed || filed.key !== (await hashed(secret))) return json(request, 403, { error: 'not yours' });
  const reply = await env.REPLIES.get(key(host.digits), 'json');
  return json(request, 200, { heat: reply?.heat ?? null });
}

// The host asks whether anything has come back for their serial.
async function getReply(request, env, serial) {
  if (await limited(request, env, 'read', READS_PER_MINUTE)) {
    return json(request, 429, { error: 'slow down' });
  }
  const host = read(serial);
  if (!host) return json(request, 400, { error: 'bad serial' });
  const reply = await env.REPLIES.get(key(host.digits), 'json');
  return json(request, 200, reply ? { guest: reply.guest, at: reply.at } : { guest: null });
}

export default {
  async fetch(request, env) {
    const { pathname } = new URL(request.url);

    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: corsHeaders(request) });
    }
    if (request.method === 'POST' && pathname === '/reply') {
      return postReply(request, env);
    }
    if (request.method === 'POST' && pathname === '/host') {
      return postHost(request, env);
    }
    if (request.method === 'POST' && pathname === '/heat') {
      return postHeat(request, env);
    }
    const match = /^\/reply\/([^/]+)$/.exec(pathname);
    if (request.method === 'GET' && match) {
      return getReply(request, env, decodeURIComponent(match[1]));
    }
    return json(request, 404, { error: 'not found' });
  },
};
