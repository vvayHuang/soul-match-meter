// The instrument's whole state. Ported from
// soul-match-meter/Model/MeterModel.swift: same flow, same rules, same timings.
// Each serial carries its owner's answers (see serial-codec.js), and the
// report is computed only from the two serials, so both sides agree. The
// relay only carries the guest's serial back to the host.

import { QUESTION_BANK, SNAPSHOT_META, TEXT } from './content.js';
import * as Relay from './relay.js';
import { computeReport } from './report.js';
import * as Codec from './serial-codec.js';
import { loadHistory, loadUnsentReply, saveHistory, saveUnsentReply } from './storage.js';

// Seconds of contact. A setting in the app; fixed at its default here for now.
export const HOLD_SECONDS = 5;
// How long a handed-off serial stays answerable.
const VALID_FOR = 24 * 60 * 60 * 1000;

const DUR_ADVANCE = 260;
const DUR_LOCK = 520;
const DUR_TOAST = 1800;
const BOOT_MS = 2400;
const BOOT_REDUCED_MS = 1600;

export const state = {
  // Navigation
  screen: 'boot',
  mode: 'host', // 'host' | 'guest'

  // Serial entry
  input: '',
  codeError: '',

  // Calibration
  questionIndex: 0,
  answers: [null, null, null],
  // Which three bank questions this exchange uses. The host draws them; the
  // guest reads them out of the host's serial.
  questionSet: [0, 1, 2],

  // Hold
  holding: false,
  holdPct: 0,
  dropped: false,

  // Receipt / peer
  copied: false,
  sent: false,
  // 05b: the id of the entry whose reply came in while its receipt was showing.
  replyArrived: null,
  // Empty until this browser has finished a measurement.
  myCode: '',
  // The other person's serial, once entered and validated.
  peerCode: null,

  // Report
  barsOn: false,
  scoreAnim: null,
  // The report 06 shows: this exchange's, once recorded, or a log entry's.
  viewing: null,

  // Log
  history: [],

  // Chrome
  toast: '',
  confirming: false,
};

let reducedMotion = false;
// Digits from a `?s=` link, held until the boot sequence hands over.
let linkDigits = null;

const listeners = new Set();
let bootTimer;
let holdTimer;
let lockTimer;
let scoreTimer;
let answerTimer;
let toastTimer;

// Relay
// A guest's reply the relay hasn't taken yet; retried until it has, and kept
// across reloads so closing the page doesn't strand the host.
let unsentReply = null;
let lastSend = 0;
let lastAsk = 0;
let asking = false;

export function subscribe(listener) {
  listeners.add(listener);
}

function emit() {
  for (const listener of listeners) listener();
}

export function init(options = {}) {
  reducedMotion = Boolean(options.reducedMotion);
  linkDigits = options.linkDigits ?? null;
  state.history = loadHistory();
  // Past 24 h the host's serial has expired; there is no one left to send to.
  const unsent = loadUnsentReply();
  setUnsentReply(unsent && Date.now() < unsent.since + VALID_FOR ? unsent : null);
  expireStale();
  // Once a second, like the instrument's other readings. Timers are throttled
  // in a background tab; the first tick after coming back catches up.
  let lastPlate = plateSignature();
  setInterval(() => {
    expireStale();
    tickRelay();
    const plate = plateSignature();
    if (plate !== lastPlate) {
      lastPlate = plate;
      if (state.screen === 'home') emit();
    }
  }, 1000);
  armBoot();
}

// MARK: Derived values

// The three questions in play, in serial order.
export function questions() {
  return state.questionSet.map((index) => QUESTION_BANK[index]);
}

export function currentQuestion() {
  const all = questions();
  return all[Math.min(state.questionIndex, all.length - 1)];
}

// 0…1 of the way from the 23.6 °C floor to the 41.8 °C white-hot peak.
export function holdFraction() {
  return state.holdPct / 100;
}

export function liveTemperature() {
  return 23.6 + holdFraction() * 18.2;
}

// Shown on the receipt, before any peer exists — so it's from my serial only.
export function imageNumber() {
  return `IMG_0${372914 + (Codec.stableHash(state.myCode) % 80)}`;
}

export function receiptRows() {
  const all = questions();
  return [
    { key: 'HOLD TIME', value: `${HOLD_SECONDS.toFixed(1)}s` },
    { key: 'PEAK TEMP', value: '41.8 °C' },
    { key: 'EMISSIVITY', value: '0.80' },
    {
      key: 'ANSWERS',
      value: state.answers
        .map((answer, index) => (answer === null ? '—' : Array.from(all[index].options[answer]).slice(0, 2).join('')))
        .join(' / '),
    },
    { key: 'VALID FOR', value: '24H' },
  ];
}

// This exchange's report, as the report screen shows it.
export function liveReport() {
  return computeReport(state.myCode, state.peerCode, state.questionSet);
}

// The serial has left this browser: copied now, or on an earlier visit.
export function handedOff() {
  return state.sent || state.copied;
}

// Whole hours left to reply, rounded up and never below 1.
export function hoursLeft(entry, now = Date.now()) {
  if (entry.sentAt === null) return 1;
  return Math.max(1, Math.ceil((entry.sentAt + VALID_FOR - now) / 3_600_000));
}

// 01b / 01c: the newest exchange still waiting on its reply or its reading.
export function pending() {
  return state.history.find((entry) => entry.status === 'waiting' || entry.status === 'unread') ?? null;
}

function plateSignature() {
  const entry = pending();
  return entry ? `${entry.id}:${entry.status}:${hoursLeft(entry)}` : '';
}

// MARK: Navigation

// `report` is what 06 will show; without one, 06 records this exchange's
// report and shows that.
export function go(next, report = null) {
  clearTimeout(bootTimer);
  clearInterval(holdTimer);
  clearTimeout(lockTimer);
  clearInterval(scoreTimer);
  clearTimeout(answerTimer);
  clearTimeout(toastTimer);
  state.screen = next;
  state.viewing = report;
  state.holding = false;
  state.holdPct = 0;
  state.dropped = false;
  state.replyArrived = null;
  state.toast = '';
  state.confirming = false;

  if (next === 'boot') armBoot();
  if (next === 'report') runReport();
  emit();
}

// The boot sequence runs 2.4 s; with reduced motion it holds its last frame
// and leaves at 1.6 s.
function armBoot() {
  clearTimeout(bootTimer);
  bootTimer = setTimeout(finishBoot, reducedMotion ? BOOT_REDUCED_MS : BOOT_MS);
}

// Leaves the boot screen for home — or, when the page was opened from a
// shared link, for wherever that serial belongs.
export function finishBoot() {
  if (linkDigits === null) {
    go('home');
    return;
  }
  const digits = linkDigits;
  linkDigits = null;
  openLink(digits);
}

// A serial that arrived in the URL. When it answers a draw this browser is
// still waiting on, it is that reply: back to that receipt's serial entry.
// Otherwise it is an invitation, entered as a guest would. Either way it is
// only filled in — nothing starts until the user confirms it.
function openLink(digits) {
  const reading = Codec.decode(Codec.PREFIX + digits);
  const waiting = reading && state.history.find((entry) => {
    if (entry.status !== 'waiting') return false;
    const own = Codec.decode(entry.serial);
    return own !== null && sameSet(own.questions, reading.questions);
  });
  if (waiting) {
    restore(waiting);
    state.codeError = '';
  } else {
    state.mode = 'guest';
    state.peerCode = null;
    state.myCode = '';
    state.sent = false;
    state.copied = false;
    state.codeError = '';
  }
  state.input = digits;
  go('serial');
}

function sameSet(a, b) {
  return a.length === b.length && a.every((value, i) => value === b[i]);
}

// MARK: Flow entry points

export function startHost() {
  state.mode = 'host';
  state.peerCode = null;
  state.questionSet = Codec.randomQuestions();
  // A new measurement supersedes whatever was waiting.
  state.myCode = '';
  state.sent = false;
  state.copied = false;
  state.questionIndex = 0;
  state.answers = [null, null, null];
  go('calibration');
}

export function startGuest() {
  state.mode = 'guest';
  state.peerCode = null;
  state.myCode = '';
  state.sent = false;
  state.copied = false;
  state.input = '';
  state.codeError = '';
  go('serial');
}

// Host, after copying: type in the serial the other person sent back.
export function enterPeerCode() {
  state.input = '';
  state.codeError = '';
  go('serial');
}

// Whether serial entry is for the reply to a measurement already made here.
export function enteringReply() {
  return state.mode === 'host' && state.myCode !== '';
}

// Back from serial entry: a host who already measured returns to the receipt.
export function serialBack() {
  go(enteringReply() ? 'receipt' : 'home');
}

export function receiptBack() {
  go('home');
}

// MARK: Serial entry

export function tapKey(label) {
  if (label === 'DEL') {
    state.input = state.input.slice(0, -1);
  } else if (label === 'RND') {
    // Easter egg: a valid serial from a random stranger's soul.
    state.input = Codec.random().slice(Codec.PREFIX.length);
  } else {
    if (state.input.length >= Codec.LENGTH) return;
    state.input += label;
  }
  state.codeError = '';
  emit();
}

export function submitCode() {
  const fail = (message) => {
    state.codeError = message;
    emit();
  };
  if (state.input.length < Codec.LENGTH) return fail(TEXT.errShort(Codec.LENGTH));
  const code = Codec.PREFIX + state.input;
  const reading = Codec.decode(code);
  if (!reading) return fail(TEXT.errChecksum);
  if (code === state.myCode) return fail(TEXT.errOwn);

  if (enteringReply()) {
    // Host already measured: the reply must answer the same draw.
    if (!sameSet(reading.questions, state.questionSet)) return fail(TEXT.errWrongSet);
    state.peerCode = code;
    go('report');
  } else {
    // Guest: answer whatever the host drew.
    state.peerCode = code;
    state.questionSet = reading.questions;
    state.questionIndex = 0;
    state.answers = [null, null, null];
    go('calibration');
  }
}

// MARK: Calibration

export function pick(optionIndex) {
  // One answer per question; a second tap while the first settles is ignored.
  if (state.answers[state.questionIndex] !== null) return;
  state.answers[state.questionIndex] = optionIndex;
  const wasLast = state.questionIndex >= questions().length - 1;
  clearTimeout(answerTimer);
  // Long enough for the selected row to read as selected before moving on.
  answerTimer = setTimeout(() => {
    if (wasLast) {
      go('hold');
    } else {
      state.questionIndex += 1;
      emit();
    }
  }, DUR_ADVANCE);
  emit();
}

// MARK: Hold

export function startHold() {
  if (state.holdPct >= 100 || state.holding) return;
  state.holding = true;
  state.dropped = false;
  clearInterval(holdTimer);

  // 50ms ticks, matching the instrument's reading cadence.
  holdTimer = setInterval(() => {
    const next = Math.min(100, state.holdPct + 100 / (HOLD_SECONDS * 20));
    if (next < 100) {
      state.holdPct = next;
      emit();
      return;
    }
    clearInterval(holdTimer);
    state.holdPct = 100;
    state.holding = false;
    // The serial is minted only now, so it can carry the answers.
    state.myCode = Codec.make(
      state.questionSet,
      state.answers.map((answer) => answer ?? 0),
      state.peerCode,
    );
    // A fresh serial hasn't been handed to anyone yet.
    state.sent = false;
    state.copied = false;
    keepMeasurement();
    // The guest's serial goes back to the host on its own.
    if (state.peerCode !== null) {
      setUnsentReply({ host: state.peerCode, guest: state.myCode, since: Date.now() });
      lastSend = 0;
    }
    emit();
    // Hold the locked reading on screen before moving on. The host gets a
    // receipt to hand out. The guest's serial is already on its way back, so
    // they go straight to the report.
    const after = state.peerCode === null ? 'receipt' : 'report';
    lockTimer = setTimeout(() => go(after), DUR_LOCK);
  }, 50);
  emit();
}

export function endHold() {
  if (state.holdPct >= 100 || !state.holding) return;
  clearInterval(holdTimer);
  state.holding = false;
  state.holdPct = 0;
  state.dropped = true;
  emit();
}

// MARK: Peer exchange

async function writeClipboard(text) {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    return copyBySelection(text);
  }
}

// The older way in, for where the clipboard API is missing or refused (an
// in-app browser, a page that isn't served securely).
function copyBySelection(text) {
  const holder = document.createElement('textarea');
  holder.value = text;
  holder.readOnly = true;
  holder.style.cssText = 'position:fixed;top:0;left:0;opacity:0;';
  document.body.append(holder);
  holder.select();
  let copied = false;
  try {
    copied = document.execCommand('copy');
  } catch {
    copied = false;
  }
  holder.remove();
  return copied;
}

// The only way out of the receipt: the serial alone, for pasting anywhere.
// Copying it counts as handing it off.
export async function copyCode() {
  const code = state.myCode;
  if (!(await writeClipboard(code))) {
    showToast(TEXT.toastCopyFailed);
    return;
  }
  if (state.myCode !== code) return;
  state.copied = true;
  // Once the reply is in, the entry holds the pair; nothing to log.
  if (state.replyArrived === null) logSnapshot();
  showToast(TEXT.toastCopied);
}

function newId() {
  return typeof crypto.randomUUID === 'function'
    ? crypto.randomUUID()
    : `${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

function commitHistory() {
  saveHistory(state.history);
}

// Logs a measurement the moment it locks, so one that was read off the screen
// rather than copied isn't lost on leaving the receipt: home's plate
// leads back to it. (The app logs only on hand-off; this is ahead of it.)
// The host's waits for the reply, its 24 h starting now. The guest already
// holds both serials, so theirs is a finished report; it stays unread until
// the report screen opens, half a second later.
function keepMeasurement() {
  if (state.peerCode !== null) {
    recordReport('unread');
    return;
  }
  logWaiting();
}

// The serial left the browser. The host's entry is already waiting.
function logSnapshot() {
  logWaiting();
}

function logWaiting() {
  if (state.history.some((entry) => entry.serial === state.myCode)) return;
  state.history.unshift({
    id: newId(),
    serial: state.myCode,
    meta: SNAPSHOT_META,
    status: 'waiting',
    sentAt: Date.now(),
    report: null,
  });
  commitHistory();
}

// Files the finished pair at the top of the log, replacing the row that was
// waiting on it.
function recordReport(status = 'done') {
  const report = liveReport();
  state.history = state.history.filter((entry) => entry.serial !== state.myCode && entry.serial !== report.pair);
  state.history.unshift({
    id: newId(),
    serial: report.pair,
    meta: SNAPSHOT_META,
    status,
    sentAt: null,
    report,
  });
  commitHistory();
  return report;
}

// The home plate. Waiting picks up at the receipt, unread opens 06.
export function open(entry) {
  if (entry.status === 'waiting') {
    if (!restore(entry)) return;
    go('receipt');
  } else if (entry.status === 'unread' && entry.report) {
    entry.status = 'done';
    commitHistory();
    go('report', entry.report);
  }
}

// Back to a handed-off measurement, waiting for the reply. The serial carries
// the draw and the answers, so they come back out of it.
function restore(entry) {
  const reading = Codec.decode(entry.serial);
  if (!reading) return false;
  state.mode = 'host';
  state.myCode = entry.serial;
  state.peerCode = null;
  state.questionSet = reading.questions;
  state.answers = reading.answers.slice();
  state.sent = true;
  state.copied = false;
  return true;
}

// MARK: Relay

// How often a waiting serial asks the relay: briskly while its receipt is on
// screen, slowly from anywhere else.
const ASK_ON_RECEIPT_MS = 5000;
const ASK_ELSEWHERE_MS = 20_000;
const RESEND_MS = 10_000;
// The relay's clock and this device's needn't agree to the second.
const CLOCK_SLACK_MS = 10 * 60 * 1000;

function setUnsentReply(reply) {
  unsentReply = reply;
  saveUnsentReply(reply);
}

// Runs once a second: pushes a guest's reply out, and asks after the host's
// waiting serials.
function tickRelay() {
  const now = Date.now();

  if (unsentReply && now - lastSend >= RESEND_MS) {
    lastSend = now;
    const sending = unsentReply;
    Relay.send(sending.host, sending.guest).then((settled) => {
      if (settled && unsentReply === sending) setUnsentReply(null);
    });
  }

  const waiting = state.history.filter((entry) => entry.status === 'waiting');
  if (waiting.length === 0 || asking) return;
  const shown = state.screen === 'receipt' ? waiting.find((entry) => entry.serial === state.myCode) : undefined;
  if (now - lastAsk < (shown ? ASK_ON_RECEIPT_MS : ASK_ELSEWHERE_MS)) return;
  lastAsk = now;
  asking = true;
  // The one on screen, or else the newest few.
  const entries = shown ? [shown] : waiting.slice(0, 3);
  Promise.all(
    entries.map(async (entry) => {
      const reply = await Relay.reply(entry.serial);
      if (reply) receive(reply, entry);
    }),
  ).finally(() => {
    asking = false;
  });
}

// A reply came back through the relay: the waiting entry becomes the finished
// pair, unread. On its own receipt, that turns 05a into 05b.
function receive(reply, entry) {
  if (entry.status !== 'waiting' || !state.history.includes(entry)) return;
  const host = entry.serial;
  // Same checks as typing it in on 02, plus: it can't predate the serial.
  const own = Codec.decode(host);
  const theirs = Codec.decode(reply.guest);
  if (!own || !theirs || reply.guest === host || !sameSet(own.questions, theirs.questions)) return;
  if (entry.sentAt !== null && typeof reply.at === 'number' && reply.at < entry.sentAt - CLOCK_SLACK_MS) return;

  const report = computeReport(host, reply.guest, own.questions);
  entry.serial = report.pair;
  entry.status = 'unread';
  entry.sentAt = null;
  entry.report = report;
  commitHistory();
  if (state.screen === 'receipt' && state.myCode === host) state.replyArrived = entry.id;
  emit();
}

// 05b's button: straight to the report that just came in.
export function openArrivedReply() {
  const entry = state.history.find((candidate) => candidate.id === state.replyArrived);
  if (entry) open(entry);
}

// A serial is good for 24 h. Past that, a waiting entry can't be picked up again.
function expireStale() {
  const now = Date.now();
  let changed = false;
  for (const entry of state.history) {
    if (entry.status === 'waiting' && entry.sentAt !== null && now >= entry.sentAt + VALID_FOR) {
      entry.status = 'expired';
      changed = true;
    }
  }
  if (changed) commitHistory();
}

// MARK: Report

// 06 shows the report it was opened with, or records this exchange's. Jumping
// straight here from the debug index has no pair to record.
function runReport() {
  if (state.viewing === null) {
    state.viewing = state.myCode !== '' && state.peerCode !== null ? recordReport() : liveReport();
  }
  runCountUp(state.viewing.score);
}

// Count the percentage up over ~26 frames, eased out; the bars start filling
// 90ms in.
function runCountUp(target) {
  state.barsOn = false;
  state.scoreAnim = 0;
  if (reducedMotion) {
    state.barsOn = true;
    state.scoreAnim = null;
    return;
  }
  let t = 0;
  let elapsed = 0;
  clearInterval(scoreTimer);
  scoreTimer = setInterval(() => {
    elapsed += 34;
    if (elapsed >= 90) state.barsOn = true;
    t += 1 / 26;
    if (t >= 1) {
      clearInterval(scoreTimer);
      state.scoreAnim = null;
    } else {
      state.scoreAnim = Math.round(target * (1 - (1 - t) ** 3));
    }
    emit();
  }, 34);
}

export function askAgain() {
  state.confirming = true;
  emit();
}

export function cancelAgain() {
  state.confirming = false;
  emit();
}

export function again() {
  state.myCode = '';
  state.peerCode = null;
  state.mode = 'host';
  state.questionIndex = 0;
  state.answers = [null, null, null];
  state.input = '';
  state.confirming = false;
  go('home');
}

// MARK: Toast

function showToast(message) {
  clearTimeout(toastTimer);
  state.toast = message;
  toastTimer = setTimeout(() => {
    state.toast = '';
    emit();
  }, DUR_TOAST);
  emit();
}
