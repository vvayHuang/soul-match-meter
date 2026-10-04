// The match report. Ported from the derived values in
// soul-match-meter/Model/MeterModel.swift (pairCodes, hash, score, resultTier,
// metrics, liveReport). It depends only on the two serials, never on which
// side is asking, so the web and the app print the same report.

import { QUESTION_BANK, RESULT_TIERS } from './content.js';
import { QUESTION_COUNT, decode, stableHash } from './serial-codec.js';

// Score bands by identical answers (0…3): [lower bound, width].
const SCORE_BANDS = [
  [30, 30], // 30...59
  [45, 30], // 45...74
  [60, 30], // 60...89
  [85, 16], // 85...100
];

const SPREAD = [1, 3, 7];

// `questionSet` is the draw in play: three ascending indices into the bank.
export function computeReport(myCode, peerCode, questionSet) {
  // The two serials in a fixed order, so A×B and B×A are the same pair.
  const codes = [myCode, peerCode ?? ''].sort();
  const hash = stableHash(codes.join('|'));

  // Both people's answers, read back out of the serials. Only comparable
  // when both answered the same draw.
  const a = decode(codes[0]);
  const b = decode(codes[1]);
  const comparable = a && b && a.questions.every((q, i) => q === b.questions[i]);
  const sameAnswer = (slot) => Boolean(comparable) && a.answers[slot] === b.answers[slot];

  let matchCount = 0;
  for (let slot = 0; slot < QUESTION_COUNT; slot++) {
    if (sameAnswer(slot)) matchCount++;
  }

  const [lower, width] = SCORE_BANDS[Math.min(matchCount, SCORE_BANDS.length - 1)];
  const score = lower + (hash % width);
  const tier = RESULT_TIERS.find((t) => score >= t.min) ?? RESULT_TIERS[RESULT_TIERS.length - 1];

  // One bar per question in the draw. Same answer → the bar looks "right":
  // high for a match metric, low for a difference metric.
  const metrics = questionSet.map((bankIndex, slot) => {
    const question = QUESTION_BANK[bankIndex];
    const v = hash * SPREAD[slot % SPREAD.length];
    const value = question.lowerIsBetter
      ? (sameAnswer(slot) ? v % 12 : 35 + (v % 60))
      : (sameAnswer(slot) ? 82 + (v % 18) : 18 + (v % 50));
    return { key: question.metric, value: `${value}%`, amount: value / 100 };
  });

  return {
    pair: codes.map((code) => (code === '' ? 'SM-??????' : code)).join(' × '),
    score,
    title: tier.title,
    metrics,
  };
}
