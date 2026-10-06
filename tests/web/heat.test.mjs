// Run with: node --test tests/web/heat.test.mjs
//
// The heat grid two sides swap for the pair photo: what goes in comes back
// out, at half the sensor's resolution, and nothing else passes for one.

import assert from 'node:assert/strict';
import { test } from 'node:test';

import { GRID_H, GRID_W, isGrid, isKey, newKey, pack, stretch, unpack } from '../../web/js/heat.js';

const W = 192;
const H = 256;

test('a frame packs down to 96 × 128 readings and back', () => {
  // Cold on the left half, hot on the right.
  const heat = Float32Array.from({ length: W * H }, (_, i) => (i % W < W / 2 ? 0.2 : 0.9));
  const text = pack(heat, W, H, 0.2, 0.7);
  assert.equal(text.length, 16384);
  assert.ok(isGrid(text));

  const { cells, width, height } = unpack(text);
  assert.deepEqual([width, height], [GRID_W, GRID_H]);
  assert.equal(cells.length, 96 * 128);
  assert.equal(cells[0], 0);
  assert.equal(cells[GRID_W - 1], 255);
  assert.equal(cells[(GRID_H - 1) * GRID_W + GRID_W / 2], 255);
});

test('each reading is the average of its 2 × 2 block, held to the range', () => {
  const heat = new Float32Array(W * H);
  // One hot sensor pixel in the first block; the second block is off the scale.
  heat[0] = 1.6;
  for (let y = 0; y < 2; y++) for (let x = 2; x < 4; x++) heat[y * W + x] = 9;
  const { cells } = unpack(pack(heat, W, H, 0, 1));
  assert.equal(cells[0], Math.round((1.6 / 4) * 255));
  assert.equal(cells[1], 255);
  assert.equal(cells[2], 0);
});

test('stretching blends between readings and keeps the ends', () => {
  const cells = new Uint8Array(GRID_W * GRID_H);
  for (let i = 0; i < cells.length; i++) cells[i] = i % GRID_W < GRID_W / 2 ? 0 : 255;
  const out = stretch({ cells, width: GRID_W, height: GRID_H }, W, H);
  assert.equal(out[0], 0);
  assert.equal(out[W - 1], 1);
  const seam = out[W / 2 - 1];
  assert.ok(seam > 0 && seam < 1, String(seam));
});

test('a grid of the first, smaller size still opens', () => {
  const small = Buffer.alloc(48 * 64, 128).toString('base64');
  assert.ok(isGrid(small));
  const grid = unpack(small);
  assert.deepEqual([grid.width, grid.height], [48, 64]);
  const out = stretch(grid, W, H);
  assert.equal(out.length, W * H);
  assert.ok(Math.abs(out[1000] - 128 / 255) < 1e-6);
});

test('only a whole grid and a whole key pass', () => {
  assert.equal(unpack('AAAA'), null);
  assert.ok(!isGrid('A'.repeat(8192)));
  assert.ok(!isGrid(`${'A'.repeat(16383)}!`));
  assert.ok(!isGrid(null));
  const key = newKey();
  assert.ok(isKey(key));
  assert.notEqual(key, newKey());
  assert.ok(!isKey(key.toUpperCase().replace(/[0-9]/g, 'A')));
  assert.ok(!isKey(key.slice(1)));
});
