// The seven screens. Layout and wording follow soul-match-meter/Screens/*.swift
// and the components in soul-match-meter/Design/IRComponents.swift.
//
// Each screen is a function returning `{ el, update?, destroy? }`: `el` is
// built once when the screen opens, `update` patches it when the model
// changes, `destroy` drops whatever the screen set going.

import { TEXT } from './content.js';
import * as model from './model.js';
import { LENGTH, PREFIX } from './serial-codec.js';

const { state } = model;

// MARK: DOM helpers

function h(tag, props = {}, ...children) {
  const el = document.createElement(tag);
  for (const [key, value] of Object.entries(props)) {
    if (value === null || value === undefined || value === false) continue;
    if (key === 'class') el.className = value;
    else if (key.startsWith('on')) el.addEventListener(key.slice(2), value);
    else el.setAttribute(key, value === true ? '' : value);
  }
  el.append(...children.flat().filter((child) => child !== null && child !== undefined && child !== false));
  return el;
}

function screen(name, ...children) {
  return h('div', { class: `screen ${name}` }, ...children);
}

function chip(text, variant = '') {
  return h('div', { class: `chip ${variant}`.trim() }, text);
}

function button(title, action, primary = false) {
  return h('button', { class: `btn press${primary ? ' primary' : ''}`, type: 'button', onclick: action }, title);
}

function iconButton(glyph, label, action) {
  return h('button', { class: `icon-btn press ${glyph}`, type: 'button', 'aria-label': label, onclick: action });
}

function toast(message, tone = '', blink = false) {
  const slow = blink && tone !== 'error' ? ' slow' : '';
  return h('div', { class: `toast ${tone}${blink ? ` blink${slow}` : ''}`.trim(), role: 'status' }, message);
}

function spacer() {
  return h('div', { class: 'spacer' });
}

// MARK: 00 · BOOT — three beats in 2.4 s, or one tap to skip. Heat sources
// surface at random, a full ramp sweeps up while the name types itself out,
// then the ramp line under it collapses and the instrument hands over.

const BOOT_RAMP = ['#1560B8', '#2DD4D8', '#7FD44E', '#E8F06A', '#F2F4F8', '#E24A2B', '#FFF2C8'];
const BOOT_SECOND_LINE = 'METER · IR';

function randomBetween(low, high) {
  return low + Math.floor(Math.random() * (high - low + 1));
}

function boot({ reducedMotion }) {
  const timers = [];
  const later = (ms, action) => timers.push(setTimeout(action, ms));

  // One radial heat source: a random spot, size and ramp colour, fading to a
  // colour two stops colder at its rim.
  const blobs = Array.from({ length: 40 }, () => {
    const i = randomBetween(0, BOOT_RAMP.length - 1);
    const size = randomBetween(120, 340);
    const blob = h('i', { class: 'boot-blob' });
    blob.style.left = `${randomBetween(0, 100)}%`;
    blob.style.top = `${randomBetween(0, 100)}%`;
    blob.style.width = `${size}px`;
    blob.style.height = `${size}px`;
    blob.style.background = `radial-gradient(circle, ${BOOT_RAMP[i]} 0%, ${BOOT_RAMP[Math.max(0, i - 2)]} 45%, rgb(10 26 110 / 0) 72%)`;
    return blob;
  });

  const typed = h('span');
  const el = h(
    'div',
    { class: 'screen boot', 'data-stage': '1', onclick: () => model.finishBoot() },
    h('div', { class: 'boot-heat' }, blobs),
    h('div', { class: 'boot-dim' }),
    h('div', { class: 'boot-sweep' }),
    h('div', { class: 'scanlines' }),
    h(
      'div',
      { class: 'boot-name' },
      h(
        'div',
        { class: 'plate' },
        h('div', { class: 'boot-title', 'aria-label': 'SOUL MATCH METER · IR' }, 'SOUL MATCH\n', typed, h('i', { class: 'boot-cursor' })),
        h('div', { class: 'boot-line' }),
        h('div', { class: 'boot-sub' }, '靈魂配對測量儀'),
      ),
    ),
  );
  const stage = (n) => { el.dataset.stage = String(n); };

  if (reducedMotion) {
    // The finished frame, held; the model leaves for 01 at 1.6 s.
    blobs.forEach((blob) => blob.classList.add('on'));
    typed.textContent = BOOT_SECOND_LINE;
    stage(3);
    return { el };
  }

  // One heat source every 52 ms.
  blobs.forEach((blob, index) => later(52 * (index + 1), () => blob.classList.add('on')));
  later(800, () => stage(2));
  // Type the second line, one character every 70 ms.
  const chars = Array.from(BOOT_SECOND_LINE);
  chars.forEach((_, index) => {
    later(800 + 70 * (index + 1), () => { typed.textContent = chars.slice(0, index + 1).join(''); });
  });
  const settled = 800 + 70 * chars.length + 100;
  later(settled, () => stage(3));
  later(settled + 400, () => stage(4));

  return { el, destroy: () => timers.forEach(clearTimeout) };
}

// MARK: 01 · HOME — the standby viewfinder. Two ways in: measure yourself, or
// enter a peer serial.

// 01b / 01c — the newest exchange still in flight, one tap from where it left
// off: info while the reply is out, success once it's in.
function pendingPlate(entry) {
  const waiting = entry.status === 'waiting';
  return h(
    'button',
    {
      class: `pending press${waiting ? '' : ' unread'}`,
      type: 'button',
      title: waiting ? TEXT.hintWaiting : TEXT.hintUnread,
      onclick: () => model.open(entry),
    },
    h(
      'div',
      { class: 'pending-inner' },
      h(
        'div',
        { class: 'pending-text' },
        h('span', { class: 'pending-serial' }, entry.serial),
        h('span', { class: 'pending-label' }, waiting ? TEXT.pendingWaiting : TEXT.pendingUnread),
      ),
      waiting && h('span', { class: 'pending-hours' }, TEXT.hoursLeft(model.hoursLeft(entry))),
      h('i', { class: 'triangle', 'aria-hidden': 'true' }),
    ),
  );
}

function home() {
  const plateSlot = h('div', { class: 'row' });
  const update = () => {
    const entry = model.pending();
    plateSlot.replaceChildren(...(entry ? [pendingPlate(entry)] : []));
    plateSlot.hidden = !entry;
  };
  update();

  const el = screen(
    'home',
    h(
      'div',
      { class: 'hud' },
      h(
        'div',
        { class: 'row' },
        chip('36.4 °C', 'hot'),
        spacer(),
        h('div', { class: 'row pair' }, chip('MAX 36.4 °C', 's'), chip('MIN 16.5 °C', 's')),
      ),
      plateSlot,
      spacer(),
      button(TEXT.homeStart, () => model.startHost(), true),
      button(TEXT.homeHaveSerial, () => model.startGuest()),
    ),
  );
  return { el, update };
}

// MARK: 02 · SERIAL — six digits (the last one is a check digit) and one
// error line.

const KEYS = ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'RND', '0', 'DEL'];

function keyName(key) {
  if (key === 'RND') return TEXT.keyRandom;
  if (key === 'DEL') return TEXT.keyDelete;
  return key;
}

function serial() {
  const value = h('div', { class: 'serial-value' });
  const errorSlot = h('div', { class: 'row' });
  let shownError = null;

  const update = () => {
    value.textContent = PREFIX + state.input.padEnd(LENGTH, '_');
    value.setAttribute('aria-label', PREFIX + state.input);
    if (state.codeError !== shownError) {
      shownError = state.codeError;
      // A fresh element per message, so the blink starts over.
      const line = shownError ? toast(shownError, 'error', true) : null;
      if (line) line.style.flex = '1';
      errorSlot.replaceChildren(...(line ? [line] : []));
      errorSlot.hidden = !line;
    }
  };
  update();

  // No text field, so no system keyboard; a hardware one still works.
  const onKey = (event) => {
    if (event.metaKey || event.ctrlKey || event.altKey) return;
    if (/^[0-9]$/.test(event.key)) model.tapKey(event.key);
    else if (event.key === 'Backspace') model.tapKey('DEL');
    else if (event.key === 'Enter' && !(event.target instanceof HTMLButtonElement)) model.submitCode();
    else return;
    event.preventDefault();
  };
  document.addEventListener('keydown', onKey);

  const el = screen(
    'serial',
    h(
      'div',
      { class: 'hud' },
      h('div', { class: 'row' }, iconButton('back', TEXT.back, () => model.serialBack())),
      h(
        'div',
        { class: 'plate' },
        h('div', { class: 'serial-title' }, model.enteringReply() ? TEXT.serialTitleReply : TEXT.serialTitleGuest),
        value,
      ),
      errorSlot,
      spacer(),
      h(
        'div',
        { class: 'keypad' },
        KEYS.map((key) => h(
          'button',
          {
            class: `key press${key.length > 1 ? ' word' : ''}`,
            type: 'button',
            'aria-label': keyName(key),
            onclick: () => model.tapKey(key),
          },
          key,
        )),
      ),
      button(TEXT.serialConfirm, () => model.submitCode(), true),
    ),
  );
  return { el, update, destroy: () => document.removeEventListener('keydown', onKey) };
}

// MARK: 03 · CALIB — three questions with no correct answer.

function calibration() {
  const fill = h('i');
  const card = h('div', { class: 'row' });
  const options = h('div', { class: 'options' });
  let shownIndex = -1;

  const update = () => {
    const all = model.questions();
    const index = Math.min(state.questionIndex, all.length - 1);
    const question = all[index];
    fill.style.width = `${((index + 1) / all.length) * 100}%`;

    if (index !== shownIndex) {
      shownIndex = index;
      // A fresh card per question, so each one rises in on its own.
      const plate = h(
        'div',
        { class: 'plate question' },
        h('div', { class: 'question-no' }, String(index + 1).padStart(2, '0')),
        h('div', { class: 'question-text' }, question.text),
      );
      plate.style.flex = '1';
      card.replaceChildren(plate);
      options.replaceChildren(
        ...question.options.map((label, optionIndex) => button(label, () => model.pick(optionIndex))),
      );
    }
    // The chosen option turns white-hot.
    Array.from(options.children).forEach((option, optionIndex) => {
      option.classList.toggle('primary', state.answers[state.questionIndex] === optionIndex);
    });
  };
  update();

  const track = h('div', { class: 'track' }, fill);
  fill.style.transition = 'width var(--dur-hover) var(--ease-hud)';

  const el = screen(
    'calibration',
    h(
      'div',
      { class: 'hud' },
      h('div', { class: 'row calib-top' }, track, iconButton('close', TEXT.close, () => model.go('home'))),
      card,
      spacer(),
      options,
    ),
  );
  return { el, update };
}

// MARK: 04 · HOLD — five seconds of contact. Let go and the reading cools to 0.0s.

function hold() {
  const temp = chip('', 'hot');
  const status = chip('', 'xs');
  const seconds = h('div', { class: 'big-value' });
  const unit = h('div', { class: 'big-unit' });
  const crosshair = h('div', { class: 'crosshair', 'aria-hidden': 'true' }, h('i'));
  const droppedSlot = h('div', { class: 'row' });
  const marker = h('i', { class: 'scale-marker' });
  const target = h('div', { class: 'hold-target', role: 'button', tabindex: '0' });
  const wrap = h('div', { class: 'hold-wrap' }, h('i', { class: 'hold-ring' }), target);
  let shownDropped = false;

  // Pressing is the whole interaction. Lifting, leaving the target or having
  // the touch taken away all let go.
  target.addEventListener('pointerdown', (event) => {
    if (event.button !== 0) return;
    event.preventDefault();
    model.startHold();
  });
  for (const type of ['pointerup', 'pointercancel', 'pointerleave']) {
    target.addEventListener(type, () => model.endHold());
  }
  // A long press must not open the callout menu, the magnifier or a selection.
  for (const type of ['contextmenu', 'selectstart', 'dragstart']) {
    target.addEventListener(type, (event) => event.preventDefault());
  }
  target.addEventListener('keydown', (event) => {
    if (event.key !== ' ' && event.key !== 'Enter') return;
    event.preventDefault();
    if (!event.repeat) model.startHold();
  });
  target.addEventListener('keyup', (event) => {
    if (event.key === ' ' || event.key === 'Enter') model.endHold();
  });
  target.addEventListener('blur', () => model.endHold());

  const update = () => {
    const locked = state.holdPct >= 100;
    const fraction = model.holdFraction();
    const phase = state.holding ? 'RISING' : (locked ? 'LOCKED' : 'IDLE');

    temp.textContent = `${model.liveTemperature().toFixed(1)} °C`;
    status.textContent = `${locked ? 'DONE' : 'MEASURING'}\nHOLD`;
    seconds.textContent = `${(fraction * model.HOLD_SECONDS).toFixed(1)}s`;
    unit.textContent = `/ ${model.HOLD_SECONDS.toFixed(1)}s · ${phase}`;
    crosshair.classList.toggle('locked', locked);
    wrap.classList.toggle('holding', state.holding);
    target.textContent = locked ? TEXT.holdLocked : (state.holding ? TEXT.holdHolding : TEXT.holdIdle);
    // The marker rides up the 230px ramp, centred on its 12px height.
    marker.style.transform = `translateY(${Math.max(0, 230 * (1 - Math.round(fraction * 100) / 100) - 6)}px)`;

    if (state.dropped !== shownDropped) {
      shownDropped = state.dropped;
      const line = shownDropped ? toast(TEXT.holdDropped, 'error', true) : null;
      if (line) line.style.flex = '1';
      droppedSlot.replaceChildren(...(line ? [line] : []));
      droppedSlot.hidden = !line;
    }
  };
  droppedSlot.hidden = true;
  update();

  const el = screen(
    'hold',
    h(
      'div',
      { class: 'hud fixed' },
      h('div', { class: 'row top' }, temp, spacer(), status),
      h('div', { class: 'big' }, seconds, unit),
      h('div', { class: 'crosshair-area' }, crosshair),
      droppedSlot,
      wrap,
      h('div', { class: 'row' }, chip('x 1', 's'), spacer(), chip('ε = 0.80', 's')),
    ),
    h('div', { class: 'scale', 'aria-hidden': 'true' }, marker, h('div', { class: 'scale-ramp' })),
  );
  return { el, update };
}

// MARK: 05 · RECEIPT — the snapshot. The only paper surface in the system.

function receipt() {
  const actions = h('div', { class: 'receipt-actions' });

  const update = () => {
    const host = state.mode === 'host';
    const handedOff = model.handedOff();
    const next = host
      ? button(TEXT.receiptNextHost, () => model.enterPeerCode(), true)
      : button(TEXT.receiptNextGuest, () => model.go('report'), true);

    actions.replaceChildren(
      ...[
        state.toast && toast(state.toast),
        host && handedOff && toast(TEXT.receiptWaiting, 'info', true),
        // One button out: copying is the hand-off. After it, copying again
        // steps down and the next step takes the white-hot button.
        handedOff
          ? button(TEXT.receiptCopyAgain, () => model.copyCode())
          : button(TEXT.receiptCopy, () => model.copyCode(), true),
        handedOff && next,
      ].filter(Boolean),
    );
  };
  update();

  const el = screen(
    'receipt',
    h(
      'div',
      { class: 'hud' },
      h(
        'div',
        { class: 'row' },
        iconButton('back', TEXT.back, () => model.receiptBack()),
        spacer(),
        h('div', { class: 'row pair' }, chip('SNAPSHOT SAVED', 's'), chip(model.imageNumber(), 's')),
      ),
      h(
        'div',
        { class: 'receipt-card' },
        h('div', { class: 'receipt-band' }),
        h('div', { class: 'receipt-serial' }, state.myCode),
        h(
          'div',
          { class: 'receipt-rows' },
          model.receiptRows().map((row) => h('div', { class: 'receipt-row' }, row.key, h('b', {}, row.value))),
        ),
        h('div', { class: 'receipt-foot' }, TEXT.receiptFootnote),
      ),
      spacer(),
      actions,
    ),
  );
  return { el, update };
}

// MARK: 06 · REPORT — a completely unfounded percentage, reported with confidence.

function report() {
  const shown = state.viewing ?? model.liveReport();
  const score = h('div', { class: 'big-value score-value' });
  // Space for the final number is reserved so the count-up doesn't push the
  // right-hand plate around.
  score.style.minWidth = `calc(${String(shown.score).length}ch - ${String(shown.score).length * 2}px)`;

  const bars = shown.metrics.map((metric) => {
    const value = h('span', { class: 'metric-value' });
    const fill = h('i');
    const el = h(
      'div',
      { class: 'metric' },
      h('div', { class: 'metric-head' }, h('span', { class: 'metric-label' }, metric.key), value),
      h('div', { class: 'track', 'aria-hidden': 'true' }, fill),
    );
    return { el, value, fill, metric };
  });

  let dialog = null;
  const el = screen(
    'report',
    h(
      'div',
      { class: 'hud' },
      h('div', { class: 'row top' }, chip('MATCH REPORT', 's'), spacer(), chip(shown.pair, 'xs')),
      spacer(),
      h(
        'div',
        { class: 'report-grid' },
        h(
          'div',
          { class: 'score', role: 'img', 'aria-label': TEXT.scoreLabel(shown.score) },
          h('div', { class: 'score-inner' }, score, h('span', { class: 'score-unit' }, '%')),
        ),
        h('div', { class: 'plate report-detail' }, h('h1', { class: 'report-title' }, shown.title), bars.map((bar) => bar.el)),
      ),
      spacer(),
      button(TEXT.reportAgain, () => model.askAgain(), true),
    ),
  );

  const update = () => {
    score.textContent = String(state.scoreAnim ?? shown.score);
    for (const bar of bars) {
      bar.value.textContent = state.barsOn ? bar.metric.value : '0%';
      bar.fill.style.width = state.barsOn ? `${bar.metric.amount * 100}%` : '0';
    }
    if (state.confirming && !dialog) {
      dialog = h(
        'div',
        { class: 'overlay' },
        h(
          'div',
          { class: 'dialog', role: 'alertdialog', 'aria-modal': 'true', 'aria-label': TEXT.confirmTitle },
          h('h2', { class: 'dialog-title' }, TEXT.confirmTitle),
          h(
            'div',
            { class: 'dialog-actions' },
            button(TEXT.confirmNo, () => model.cancelAgain()),
            button(TEXT.confirmYes, () => model.again(), true),
          ),
        ),
      );
      el.append(dialog);
    } else if (!state.confirming && dialog) {
      dialog.remove();
      dialog = null;
    }
  };
  update();

  return { el, update };
}

export const SCREENS = { boot, home, serial, calibration, hold, receipt, report };

// MARK: Thermal field presets — FieldPreset in soul-match-meter/Design/IRTheme.swift.
// `live` screens share one field in the app (the camera feed); here they share
// the stills, and only arriving from a non-live screen pulls focus.

export const FIELDS = {
  boot: null,
  home: { image: 'ir-scene', midStop: 46, live: true },
  serial: { image: 'ir-scene-empty', midStop: 44, live: true },
  calibration: { image: 'ir-scene-solo', midStop: 46, live: true },
  hold: { image: 'ir-scene-face', midStop: 44, live: true },
  receipt: { image: 'ir-scene-face', midStop: 44 },
  // This side's reading over the peer's still.
  report: { image: 'ir-scene-face', midStop: 44, peer: 'ir-scene-solo' },
};

// MARK: Debug index — development-only jump list (`?debug=1`), mirroring the
// app's ScreenIndexSheet.

const INDEX = [
  ['boot', '00', '開機動畫', 'BOOT'],
  ['home', '01', '待機觀景窗', 'HOME'],
  ['serial', '02', '輸入對方序號', 'SERIAL'],
  ['calibration', '03', '校正問題 ×3', 'CALIB'],
  ['hold', '04', '按住測量', 'HOLD'],
  ['receipt', '05', '快照收據', 'RECEIPT'],
  ['report', '06', '配對報告', 'REPORT'],
];

export function debugIndex(container) {
  let sheet = null;
  const close = () => {
    sheet?.remove();
    sheet = null;
  };
  container.append(h(
    'button',
    {
      class: 'index-btn',
      type: 'button',
      onclick: () => {
        if (sheet) return close();
        sheet = h(
          'div',
          { class: 'index-sheet' },
          h('div', { class: 'index-head' }, `SCREEN INDEX · ${INDEX.length} 頁`),
          INDEX.map(([name, no, label, tag]) => h(
            'button',
            {
              class: `index-row${state.screen === name ? ' on' : ''}`,
              type: 'button',
              onclick: () => {
                close();
                model.go(name);
              },
            },
            no,
            h('b', {}, label),
            tag,
          )),
        );
        container.append(sheet);
      },
    },
    'INDEX',
  ));
}
