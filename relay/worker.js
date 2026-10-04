// The relay: a Cloudflare Worker that carries the guest's serial back to the
// host, so the host's report arrives on its own instead of being typed in.
//
// It holds one thing per exchange, for 24 hours: host serial → guest serial.
//
//     POST /reply          { "host": "SM-123456", "guest": "SM-654321" }
//     GET  /reply/123456   → { "guest": "SM-654321", "at": 1790000000000 }
//                          → { "guest": null } while nothing has come back
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

// The guest finished measuring: file their serial under the host's.
async function postReply(request, env) {
  if (await limited(request, env, 'write', WRITES_PER_MINUTE)) {
    return json(request, 429, { error: 'slow down' });
  }

  let body;
  try {
    const text = await request.text();
    if (text.length > 200) return json(request, 400, { error: 'bad request' });
    body = JSON.parse(text);
  } catch {
    return json(request, 400, { error: 'bad request' });
  }

  const host = read(body?.host);
  const guest = read(body?.guest);
  if (!host || !guest) return json(request, 400, { error: 'bad serial' });
  if (host.digits === guest.digits) return json(request, 400, { error: 'own serial' });
  // The guest answers the host's draw, so a reply always carries the same one.
  if (host.set !== guest.set) return json(request, 400, { error: 'wrong set' });

  const guestSerial = PREFIX + guest.digits;
  const existing = await env.REPLIES.get(key(host.digits), 'json');
  if (existing) {
    // The first reply stands. Sending it again is fine and writes nothing.
    return existing.guest === guestSerial
      ? json(request, 200, { ok: true })
      : json(request, 409, { error: 'already replied' });
  }

  await env.REPLIES.put(key(host.digits), JSON.stringify({ guest: guestSerial, at: Date.now() }), {
    expirationTtl: VALID_FOR_SECONDS,
  });
  return json(request, 201, { ok: true });
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
    const match = /^\/reply\/([^/]+)$/.exec(pathname);
    if (request.method === 'GET' && match) {
      return getReply(request, env, decodeURIComponent(match[1]));
    }
    return json(request, 404, { error: 'not found' });
  },
};
