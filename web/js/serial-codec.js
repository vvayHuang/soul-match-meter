// Ported from soul-match-meter/Model/SerialCodec.swift. Keep the two in step:
// a serial minted here must decode in the app, and the other way round.
//
// Serial format: `SM-` + 6 digits = 5 data digits + 1 check digit.
//
//     data = nonce * 7680 + setIndex * 64 + answerCode   (0 … 99_839)
//     answerCode = a0 + a1 * 4 + a2 * 16

export const PREFIX = 'SM-';
export const LENGTH = 6;
export const OPTIONS_PER_QUESTION = 4;
export const QUESTION_COUNT = 3;
export const BANK_SIZE = 10;

// Every 3-question draw from the bank, in lexicographic order.
const SETS = [];
for (let a = 0; a < BANK_SIZE; a++) {
  for (let b = a + 1; b < BANK_SIZE; b++) {
    for (let c = b + 1; c < BANK_SIZE; c++) {
      SETS.push([a, b, c]);
    }
  }
}

const ANSWER_COMBOS = 64;
const COMBOS = SETS.length * ANSWER_COMBOS; // 7680
export const MAX_NONCE = Math.floor(100_000 / COMBOS) - 1; // 12 → data ≤ 99_839
const WEIGHTS = [1, 3, 7, 9, 1];

function randomInt(below) {
  return Math.floor(Math.random() * below);
}

function sameSet(a, b) {
  return a.length === b.length && a.every((value, i) => value === b[i]);
}

// A fresh random draw of three questions.
export function randomQuestions() {
  return SETS[randomInt(SETS.length)].slice();
}

function answerCode(answers) {
  let code = 0;
  let place = 1;
  for (let i = 0; i < QUESTION_COUNT; i++) {
    const a = i < answers.length ? answers[i] : 0;
    code += Math.max(0, Math.min(OPTIONS_PER_QUESTION - 1, a)) * place;
    place *= OPTIONS_PER_QUESTION;
  }
  return code;
}

function checkDigit(data) {
  let sum = 0;
  for (let i = 0; i < WEIGHTS.length; i++) {
    sum += Number(data[i]) * WEIGHTS[i];
  }
  return (10 - (sum % 10)) % 10;
}

// Builds a serial from a question draw and three answer indices (each 0…3).
// Pass the peer's serial as `avoiding` so the two can never come out
// identical, even with identical answers.
export function make(questions, answers, avoiding = null) {
  const taken = avoiding ? decode(avoiding)?.nonce : undefined;
  const free = [];
  for (let n = 0; n <= MAX_NONCE; n++) {
    if (n !== taken) free.push(n);
  }
  const nonce = free[randomInt(free.length)];
  const sorted = questions.slice().sort((x, y) => x - y);
  const setIndex = Math.max(0, SETS.findIndex((set) => sameSet(set, sorted)));
  const value = nonce * COMBOS + setIndex * ANSWER_COMBOS + answerCode(answers);
  const data = String(value).padStart(LENGTH - 1, '0');
  return PREFIX + data + checkDigit(data);
}

// A valid serial with a random draw and random answers — used by the RND key.
export function random() {
  const answers = [];
  for (let i = 0; i < QUESTION_COUNT; i++) answers.push(randomInt(OPTIONS_PER_QUESTION));
  return make(randomQuestions(), answers);
}

// Accepts "SM-123456" or "123456". Returns null when the length or the check
// digit is wrong, or the data is out of range.
export function decode(serial) {
  const digits = serial.startsWith(PREFIX) ? serial.slice(PREFIX.length) : serial;
  if (!/^[0-9]{6}$/.test(digits)) return null;
  const data = digits.slice(0, LENGTH - 1);
  if (Number(digits[LENGTH - 1]) !== checkDigit(data)) return null;
  const value = Number(data);
  if (value >= (MAX_NONCE + 1) * COMBOS) return null;
  let code = value % ANSWER_COMBOS;
  const answers = [];
  for (let i = 0; i < QUESTION_COUNT; i++) {
    answers.push(code % OPTIONS_PER_QUESTION);
    code = Math.floor(code / OPTIONS_PER_QUESTION);
  }
  return {
    questions: SETS[Math.floor((value % COMBOS) / ANSWER_COMBOS)].slice(),
    answers,
    nonce: Math.floor(value / COMBOS),
  };
}

export function isValid(serial) {
  return decode(serial) !== null;
}

// Stable string hash. The running value stays under 9973, so every step fits
// a double exactly and matches Swift's Int arithmetic without BigInt.
export function stableHash(s) {
  let h = 7;
  for (const ch of s) {
    h = (h * 31 + ch.codePointAt(0)) % 9973;
  }
  return h;
}
