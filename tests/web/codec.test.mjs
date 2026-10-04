// Run with: node --test tests/web/codec.test.mjs
//
// The web version must print the same report as the app for the same pair of
// serials. The expected values below were read off the app (PRD §10.1).

import assert from 'node:assert/strict';
import { test } from 'node:test';

import { computeReport } from '../../web/js/report.js';
import * as Codec from '../../web/js/serial-codec.js';

function report(a, b) {
  return computeReport(a, b, Codec.decode(a).questions);
}

function summary(r) {
  return {
    score: r.score,
    title: r.title,
    metrics: r.metrics.map((m) => `${m.key} ${m.value}`).join(' / '),
  };
}

const APP_RESULTS = [
  {
    a: 'SM-831840',
    b: 'SM-370565',
    score: 84,
    title: '共用一條充電線',
    metrics: '回覆同步 88% / 淋雨協議 82% / 社交噪音差 83%',
  },
  // The PRD records only the score and title for this pair.
  { a: 'SM-206721', b: 'SM-513928', score: 89, title: '共用一條充電線' },
  // The PRD records only the score and metrics for this pair.
  {
    a: 'SM-712161',
    b: 'SM-865760',
    score: 88,
    metrics: '動物相容 89% / 選擇障礙同步 85% / 社交噪音差 1%',
  },
];

for (const expected of APP_RESULTS) {
  test(`${expected.a} × ${expected.b} matches the app`, () => {
    const got = summary(report(expected.a, expected.b));
    assert.equal(got.score, expected.score);
    if (expected.title) assert.equal(got.title, expected.title);
    if (expected.metrics) assert.equal(got.metrics, expected.metrics);
  });

  test(`${expected.a} × ${expected.b} is the same from either side`, () => {
    assert.deepEqual(report(expected.a, expected.b), report(expected.b, expected.a));
  });
}

test('stableHash matches values worked out by hand from the Swift', () => {
  assert.equal(Codec.stableHash(''), 7);
  assert.equal(Codec.stableHash('A'), 7 * 31 + 65);
  assert.equal(Codec.stableHash('AB'), ((7 * 31 + 65) * 31 + 66) % 9973);
});

test('decode reads the draw, the answers and the nonce', () => {
  // 831840 → data 83184 = 10 * 7680 + 99 * 64 + 48
  const reading = Codec.decode('SM-831840');
  assert.equal(reading.nonce, 10);
  assert.deepEqual(reading.answers, [0, 0, 3]);
  assert.deepEqual(reading.questions, Codec.decode('SM-370565').questions);
  assert.deepEqual(Codec.decode('831840'), reading);
});

test('decode rejects malformed serials', () => {
  for (const bad of ['', 'SM-', 'SM-83184', 'SM-8318400', 'SM-83184a', 'SM-８３１８４０', 'XX-831840']) {
    assert.equal(Codec.decode(bad), null, bad);
  }
  // Data past the last nonce: 99840 with its correct check digit.
  assert.equal(Codec.decode('SM-998400'), null);
  assert.equal(Codec.decode('SM-998407'), null);
});

test('any single mistyped digit is caught', () => {
  const serial = '831840';
  for (let position = 0; position < serial.length; position++) {
    for (let digit = 0; digit <= 9; digit++) {
      if (String(digit) === serial[position]) continue;
      const typo = serial.slice(0, position) + digit + serial.slice(position + 1);
      assert.equal(Codec.decode(typo), null, typo);
    }
  }
});

test('make and decode round-trip every draw and answer', () => {
  for (let a = 0; a < 10; a++) {
    for (let b = a + 1; b < 10; b++) {
      for (let c = b + 1; c < 10; c++) {
        for (let code = 0; code < 64; code++) {
          const answers = [code % 4, Math.floor(code / 4) % 4, Math.floor(code / 16)];
          const serial = Codec.make([a, b, c], answers);
          assert.match(serial, /^SM-[0-9]{6}$/);
          const reading = Codec.decode(serial);
          assert.deepEqual(reading.questions, [a, b, c]);
          assert.deepEqual(reading.answers, answers);
        }
      }
    }
  }
});

test('make never repeats the peer nonce', () => {
  const peer = Codec.make([0, 1, 2], [1, 1, 1]);
  const taken = Codec.decode(peer).nonce;
  for (let i = 0; i < 500; i++) {
    const mine = Codec.make([0, 1, 2], [1, 1, 1], peer);
    assert.notEqual(Codec.decode(mine).nonce, taken);
    assert.notEqual(mine, peer);
  }
});

test('random serials are valid', () => {
  for (let i = 0; i < 500; i++) {
    assert.ok(Codec.isValid(Codec.random()));
  }
});

test('score bands follow the number of identical answers', () => {
  const bands = [[30, 59], [45, 74], [60, 89], [85, 100]];
  for (let i = 0; i < 2000; i++) {
    const host = Codec.random();
    const reading = Codec.decode(host);
    const guestAnswers = reading.answers.map((answer) => (Math.random() < 0.5 ? answer : (answer + 1) % 4));
    const guest = Codec.make(reading.questions, guestAnswers, host);
    const same = guestAnswers.filter((answer, slot) => answer === reading.answers[slot]).length;
    const { score, metrics } = computeReport(host, guest, reading.questions);
    assert.ok(score >= bands[same][0] && score <= bands[same][1], `${host} × ${guest}: ${score}`);
    assert.equal(metrics.length, 3);
  }
});
