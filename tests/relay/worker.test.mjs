// Run with: node --test tests/relay/worker.test.mjs
//
// The relay against an in-memory stand-in for its KV namespace.

import assert from 'node:assert/strict';
import { test } from 'node:test';

import relay from '../../relay/worker.js';
import * as Codec from '../../web/js/serial-codec.js';

const BASE = 'https://relay.example';

function fakeKV() {
  const store = new Map();
  return {
    store,
    puts: [],
    async get(key, type) {
      const value = store.get(key);
      if (value === undefined) return null;
      return type === 'json' ? JSON.parse(value) : value;
    },
    async put(key, value, options) {
      this.puts.push({ key, options });
      store.set(key, value);
    },
  };
}

let client = 0;
// Each call comes from its own address unless told otherwise, so the limiter
// only bites in the test that is about it.
function call(env, method, path, body, headers = {}) {
  client += 1;
  return relay.fetch(
    new Request(BASE + path, {
      method,
      body: body === undefined ? undefined : JSON.stringify(body),
      headers: { 'CF-Connecting-IP': `10.0.${client >> 8}.${client & 255}`, ...headers },
    }),
    env,
  );
}

// A host serial and a guest serial answering the same draw.
function pair() {
  const host = Codec.random();
  const guest = Codec.make(Codec.decode(host).questions, [1, 2, 3], host);
  return { host, guest };
}

// A serial answering a different draw from `serial`.
function otherDraw(serial) {
  const questions = Codec.decode(serial).questions;
  for (;;) {
    const candidate = Codec.random();
    if (Codec.decode(candidate).questions.join() !== questions.join()) return candidate;
  }
}

test('a reply is stored for 24 h and read back by the host', async () => {
  const env = { REPLIES: fakeKV() };
  const { host, guest } = pair();

  const empty = await call(env, 'GET', `/reply/${host.slice(3)}`);
  assert.deepEqual(await empty.json(), { guest: null });

  const posted = await call(env, 'POST', '/reply', { host, guest });
  assert.equal(posted.status, 201);
  assert.equal(env.REPLIES.puts[0].options.expirationTtl, 86400);

  const found = await call(env, 'GET', `/reply/${host}`);
  const reply = await found.json();
  assert.equal(reply.guest, guest);
  assert.equal(typeof reply.at, 'number');
  assert.equal(found.headers.get('Cache-Control'), 'no-store');
});

test('the first reply stands; repeating it writes nothing', async () => {
  const env = { REPLIES: fakeKV() };
  const { host, guest } = pair();
  const second = Codec.make(Codec.decode(host).questions, [0, 0, 0], host);

  assert.equal((await call(env, 'POST', '/reply', { host, guest })).status, 201);
  assert.equal((await call(env, 'POST', '/reply', { host, guest })).status, 200);
  if (second !== guest) {
    assert.equal((await call(env, 'POST', '/reply', { host, guest: second })).status, 409);
  }
  assert.equal(env.REPLIES.puts.length, 1);
  assert.equal((await (await call(env, 'GET', `/reply/${host}`)).json()).guest, guest);
});

test('bad serials, own serial and a different draw are refused', async () => {
  const env = { REPLIES: fakeKV() };
  const { host, guest } = pair();
  const typo = host.slice(0, -1) + ((Number(host.at(-1)) + 1) % 10);

  const cases = [
    { host: typo, guest },
    { host, guest: 'SM-12' },
    { host, guest: host },
    { host, guest: otherDraw(host) },
    { host },
    'not an object',
  ];
  for (const body of cases) {
    assert.equal((await call(env, 'POST', '/reply', body)).status, 400, JSON.stringify(body));
  }
  assert.equal((await call(env, 'GET', '/reply/abc')).status, 400);
  assert.equal(env.REPLIES.puts.length, 0);
});

// A grid and a key in the shapes the relay accepts.
const grid = (fill) => Buffer.alloc(96 * 128, fill).toString('base64');
// The size the first grids were; still taken.
const smallGrid = (fill) => Buffer.alloc(48 * 64, fill).toString('base64');
const secret = (digit) => String(digit).repeat(32);

test('each side gets the other\'s grid, for their own key only', async () => {
  const env = { REPLIES: fakeKV() };
  const { host, guest } = pair();

  assert.equal((await call(env, 'POST', '/host', { host, key: secret(1), heat: grid(10) })).status, 201);
  assert.equal(env.REPLIES.puts[0].options.expirationTtl, 86400);
  // The key itself is not what is kept.
  assert.ok(!env.REPLIES.store.get(`host:${host.slice(3)}`).includes(secret(1)));

  const replied = await call(env, 'POST', '/reply', { host, guest, key: secret(2), heat: grid(20) });
  assert.equal(replied.status, 201);
  assert.equal((await replied.json()).heat, grid(10));

  // Asking after the reply shows the serial and nothing else.
  assert.deepEqual(Object.keys(await (await call(env, 'GET', `/reply/${host}`)).json()).sort(), ['at', 'guest']);

  const mine = await call(env, 'POST', '/heat', { host, key: secret(1) });
  assert.equal((await mine.json()).heat, grid(20));
  assert.equal((await call(env, 'POST', '/heat', { host, key: secret(3) })).status, 403);

  // Repeating the reply brings the host's grid again only with the guest's key.
  const again = await call(env, 'POST', '/reply', { host, guest, key: secret(2) });
  assert.equal((await again.json()).heat, grid(10));
  assert.deepEqual(await (await call(env, 'POST', '/reply', { host, guest, key: secret(3) })).json(), { ok: true });
  assert.deepEqual(await (await call(env, 'POST', '/reply', { host, guest })).json(), { ok: true });
});

test('the first host key stands', async () => {
  const env = { REPLIES: fakeKV() };
  const { host } = pair();
  assert.equal((await call(env, 'POST', '/host', { host, key: secret(1) })).status, 201);
  assert.equal((await call(env, 'POST', '/host', { host, key: secret(1), heat: grid(1) })).status, 200);
  assert.equal((await call(env, 'POST', '/host', { host, key: secret(2), heat: grid(2) })).status, 409);
  assert.equal(env.REPLIES.puts.length, 1);
});

test('a guest\'s grid is kept only when a host key is on file', async () => {
  const env = { REPLIES: fakeKV() };
  const { host, guest } = pair();

  const replied = await call(env, 'POST', '/reply', { host, guest, key: secret(2), heat: grid(20) });
  assert.deepEqual(await replied.json(), { ok: true, heat: null });
  assert.ok(!env.REPLIES.store.get(`reply:${host.slice(3)}`).includes(grid(20)));

  // Filing a key afterwards opens nothing.
  assert.equal((await call(env, 'POST', '/host', { host, key: secret(9) })).status, 201);
  assert.deepEqual(await (await call(env, 'POST', '/heat', { host, key: secret(9) })).json(), { heat: null });
  assert.equal((await call(env, 'POST', '/heat', { host: pair().host, key: secret(9) })).status, 403);
});

test('a host with no grid still receives one; a plain reply gets none', async () => {
  const env = { REPLIES: fakeKV() };
  const first = pair();
  await call(env, 'POST', '/host', { host: first.host, key: secret(1) });
  const replied = await call(env, 'POST', '/reply', { ...first, key: secret(2), heat: grid(20) });
  assert.deepEqual(await replied.json(), { ok: true, heat: null });
  assert.equal((await (await call(env, 'POST', '/heat', { host: first.host, key: secret(1) })).json()).heat, grid(20));

  // The app's reply: serials only.
  const second = pair();
  await call(env, 'POST', '/host', { host: second.host, key: secret(1), heat: grid(10) });
  assert.deepEqual(await (await call(env, 'POST', '/reply', second)).json(), { ok: true });
  assert.deepEqual(await (await call(env, 'POST', '/heat', { host: second.host, key: secret(1) })).json(), { heat: null });
});

test('a grid of the first, smaller size is still carried', async () => {
  const env = { REPLIES: fakeKV() };
  const { host, guest } = pair();
  assert.equal((await call(env, 'POST', '/host', { host, key: secret(1), heat: smallGrid(10) })).status, 201);
  const replied = await call(env, 'POST', '/reply', { host, guest, key: secret(2), heat: smallGrid(20) });
  assert.equal((await replied.json()).heat, smallGrid(10));
  assert.equal((await (await call(env, 'POST', '/heat', { host, key: secret(1) })).json()).heat, smallGrid(20));
});

test('malformed keys and grids are refused', async () => {
  const env = { REPLIES: fakeKV() };
  const { host, guest } = pair();
  const cases = [
    ['/host', { host }],
    ['/host', { host, key: 'short' }],
    ['/host', { host, key: secret(1), heat: 'AAAA' }],
    ['/host', { host, key: secret(1), heat: `${grid(1).slice(0, -1)}!` }],
    ['/host', { host: 'SM-12', key: secret(1) }],
    ['/reply', { host, guest, key: 'SHORT' }],
    ['/reply', { host, guest, key: secret(1), heat: 12 }],
    ['/reply', { host, guest, key: secret(1), heat: grid(1) + grid(1) }],
    ['/reply', { host, guest, key: secret(1), heat: smallGrid(1) + smallGrid(1) }],
    ['/heat', { host }],
    ['/heat', { host: 'abc', key: secret(1) }],
  ];
  for (const [path, body] of cases) {
    assert.equal((await call(env, 'POST', path, body)).status, 400, JSON.stringify([path, body]).slice(0, 80));
  }
  assert.equal(env.REPLIES.puts.length, 0);
});

test('one client is slowed down; others are not', async () => {
  const env = { REPLIES: fakeKV() };
  const from = { 'CF-Connecting-IP': '203.0.113.9' };
  const statuses = [];
  for (let i = 0; i < 8; i++) {
    const { host, guest } = pair();
    statuses.push((await call(env, 'POST', '/reply', { host, guest }, from)).status);
  }
  assert.deepEqual(statuses, [201, 201, 201, 201, 201, 201, 429, 429]);

  const { host, guest } = pair();
  assert.equal((await call(env, 'POST', '/reply', { host, guest })).status, 201);
});

test('only the web version\'s origins get CORS headers', async () => {
  const env = { REPLIES: fakeKV() };
  const allowed = await call(env, 'OPTIONS', '/reply', undefined, { Origin: 'https://vvayhuang.github.io' });
  assert.equal(allowed.status, 204);
  assert.equal(allowed.headers.get('Access-Control-Allow-Origin'), 'https://vvayhuang.github.io');

  const other = await call(env, 'GET', '/reply/123456', undefined, { Origin: 'https://example.com' });
  assert.equal(other.headers.get('Access-Control-Allow-Origin'), null);
});

test('anything else is not found', async () => {
  const env = { REPLIES: fakeKV() };
  assert.equal((await call(env, 'GET', '/')).status, 404);
  assert.equal((await call(env, 'DELETE', '/reply/123456')).status, 404);
});
