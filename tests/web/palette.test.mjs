// Run with: node --test tests/web/palette.test.mjs
//
// The palettes repaint the iron-coloured stills. These check the colour
// tables against soul-match-meter/Design/ThermalPalette.swift and that a
// repaint keeps cold cold and hot hot.

import assert from 'node:assert/strict';
import { test } from 'node:test';

import { PALETTES, cssStops, heatOf, isPalette, lut, recolor } from '../../web/js/palette.js';

function entry(id, index) {
  return Array.from(lut(id).slice(index * 3, index * 3 + 3));
}

test('the four palettes, in the app\'s order', () => {
  assert.deepEqual(PALETTES.map((palette) => palette.label), ['鐵紅', '白熱', '黑熱', '彩虹']);
  assert.ok(isPalette('rainbow'));
  assert.ok(!isPalette('sepia'));
});

test('each table runs from its first stop to its last', () => {
  assert.deepEqual(entry('iron', 0), [0x0A, 0x1A, 0x6E]);
  assert.deepEqual(entry('iron', 255), [0xFF, 0xF2, 0xC8]);
  assert.deepEqual(entry('white', 0), [0x05, 0x06, 0x08]);
  assert.deepEqual(entry('white', 255), [0xF5, 0xF6, 0xF8]);
  assert.deepEqual(entry('black', 0), [0x8A, 0x8E, 0x96]);
  assert.deepEqual(entry('black', 255), [0x05, 0x06, 0x08]);
  assert.deepEqual(entry('rainbow', 0), [0x3B, 0x0A, 0x8C]);
  assert.deepEqual(entry('rainbow', 255), [0xFF, 0x1F, 0x4B]);
});

test('a stop\'s colour lands at its place on the table', () => {
  // Rainbow's third stop sits at 0.4.
  assert.deepEqual(entry('rainbow', 102), [0x12, 0xC9, 0xA4]);
});

// The eight colours the bundled stills are actually drawn in, cold to hot.
// They sit a shade off the ramp's stops, which matters at the top: the exact
// white-hot stop reads as nearer the ramp's ink white than its own end.
const STILL_COLOURS = [
  [9, 26, 109], [20, 95, 184], [44, 211, 215], [126, 211, 78],
  [232, 239, 106], [241, 244, 248], [225, 73, 43], [255, 241, 199],
];

test('the stills\' colours read back hotter in order', () => {
  assert.deepEqual(STILL_COLOURS.map(([r, g, b]) => heatOf(r, g, b)), [0, 36, 76, 116, 148, 180, 216, 252]);
});

test('a repaint keeps cold cold and hot hot, and leaves alpha alone', () => {
  const pixels = new Uint8ClampedArray([...STILL_COLOURS[0], 255, ...STILL_COLOURS[7], 128]);
  recolor(pixels, 'white');
  assert.deepEqual(Array.from(pixels), [5, 6, 8, 255, 242, 243, 245, 128]);
});

test('the CSS colour list matches the stops', () => {
  assert.equal(cssStops('white'), '#050608 0%, #F5F6F8 100%');
  assert.ok(cssStops('iron').startsWith('#0A1A6E 0%, #1560B8 15%'));
});
