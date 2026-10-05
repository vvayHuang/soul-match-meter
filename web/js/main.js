// Entry point: reads the URL, starts the model, and keeps the one mounted
// screen in step with it. Mirrors soul-match-meter/ContentView.swift.

import * as model from './model.js';
import { cssStops, stillUrl, warm } from './palette.js';
import { FIELDS, SCREENS, debugIndex } from './screens.js';
import { LENGTH, PREFIX } from './serial-codec.js';

const { state } = model;

const device = document.getElementById('device');
const stage = document.getElementById('stage');
const field = document.getElementById('field');
const subject = field.querySelector('.field-subject');
const [fieldTop, fieldPeer] = subject.querySelectorAll('.field-half');

const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

// `?s=SM-123456` carries a serial in; `?debug=1` shows the screen index.
// The serial is taken out of the address once read, so a reload doesn't
// replay it.
function readUrl() {
  const params = new URLSearchParams(location.search);
  const debug = params.get('debug') === '1';
  const serial = params.get('s');
  let linkDigits = null;
  if (serial !== null) {
    const digits = serial.replace(new RegExp(`^${PREFIX}`, 'i'), '').replace(/[^0-9]/g, '').slice(0, LENGTH);
    if (digits) linkDigits = digits;
    params.delete('s');
    params.delete('openExternalBrowser');
    const query = params.toString();
    try {
      history.replaceState(null, '', location.pathname + (query ? `?${query}` : '') + location.hash);
    } catch {
      // Leaving it in the address only means a reload offers the serial again.
    }
  }
  return { debug, linkDigits };
}

// Which stills the field is showing, and in which palette.
let fieldKey = '';

// A still in a palette. Repainting takes a moment the first time; the half
// keeps what it had until then, unless the field has moved on.
function paint(half, name, palette, key) {
  if (!name) {
    half.style.backgroundImage = '';
    return;
  }
  stillUrl(name, palette).then((url) => {
    if (fieldKey === key) half.style.backgroundImage = `url("${url}")`;
  });
}

// The optical ground under the screens. Moving between live screens changes
// only the still; arriving from anywhere else runs the focus pull. Changing
// the palette repaints it in place.
function showField(name, previous) {
  const preset = FIELDS[name];
  field.hidden = !preset;
  if (!preset) {
    fieldKey = '';
    return;
  }
  const palette = model.fieldPalette();
  // The data ramps on the screen (palette scale, receipt band) follow it too.
  device.style.setProperty('--palette-stops', cssStops(palette));

  if (name !== previous) {
    field.style.setProperty('--mid-stop', `${preset.midStop}%`);
    subject.classList.toggle('split', Boolean(preset.peer));
    if (!(preset.live && FIELDS[previous]?.live)) {
      subject.classList.remove('focus-pull');
      void subject.offsetWidth; // restart the animation
      subject.classList.add('focus-pull');
    }
  }

  const key = `${preset.image}|${preset.peer ?? ''}|${palette}`;
  if (key === fieldKey) return;
  fieldKey = key;
  paint(fieldTop, preset.image, palette, key);
  paint(fieldPeer, preset.peer, palette, key);
}

let mounted = null;
let mountedName = null;
let warmed = null;

function render() {
  // Repaint the stills for the palette in use before a screen asks for them.
  if (state.palette !== warmed) {
    warmed = state.palette;
    warm(warmed);
  }
  if (state.screen === mountedName) {
    showField(state.screen, mountedName);
    mounted.update?.();
    return;
  }
  mounted?.destroy?.();
  const previous = mountedName;
  mountedName = state.screen;
  showField(state.screen, previous);
  mounted = SCREENS[state.screen]({ reducedMotion });
  stage.replaceChildren(mounted.el);
}

const { debug, linkDigits } = readUrl();

model.subscribe(render);
model.init({ reducedMotion, linkDigits });
render();

if (debug) debugIndex(device);
