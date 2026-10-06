// Entry point: reads the URL, starts the model, and keeps the one mounted
// screen in step with it. Mirrors soul-match-meter/ContentView.swift.

import * as Camera from './camera.js';
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

// The camera's feed sits over the stills on the screens that show it.
const thermal = Camera.canvas();
thermal.className = 'field-live';
thermal.hidden = true;
subject.append(thermal);

// What each half of the field is showing.
let topKey = null;
let peerKey = null;

// A still in a palette. Repainting takes a moment the first time; the half
// keeps what it had until then, unless the field has moved on.
function paint(half, name, palette, current) {
  if (!name) {
    half.style.backgroundImage = '';
    return;
  }
  stillUrl(name, palette).then((url) => {
    if (current()) half.style.backgroundImage = `url("${url}")`;
  });
}

// The optical ground under the screens. Moving between live screens changes
// only the still; arriving from anywhere else runs the focus pull. Changing
// the palette repaints it in place.
function showField(name, previous) {
  const preset = FIELDS[name];
  field.hidden = !preset;
  // Screens on the feed keep the camera's frames coming; the rest let them go.
  const live = Boolean(preset?.live);
  Camera.setLive(live);
  thermal.hidden = !(live && Camera.hasFrame());
  if (!preset) {
    topKey = null;
    peerKey = null;
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

  // The receipt and the reports show the frames frozen at the end of each
  // side's hold, where there are any: this session's from the camera, the
  // rest from the heat grids kept with the report.
  let frames = { top: null, peer: null };
  if (name === 'receipt') {
    frames.top = model.receiptFrame();
  } else if (name === 'report' || name === 'historyReport') {
    frames = model.reportFrames(state.viewing ?? model.liveReport(), name === 'historyReport');
  }
  const top = frames.top ?? `${preset.image}|${palette}`;
  if (top !== topKey) {
    topKey = top;
    if (frames.top) fieldTop.style.backgroundImage = `url("${frames.top}")`;
    else paint(fieldTop, preset.image, palette, () => topKey === top);
  }
  const peer = frames.peer ?? `${preset.peer ?? ''}|${palette}`;
  if (peer !== peerKey) {
    peerKey = peer;
    if (frames.peer) fieldPeer.style.backgroundImage = `url("${frames.peer}")`;
    else paint(fieldPeer, preset.peer, palette, () => peerKey === peer);
  }
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
// The first frame, a refusal or a fresh snapshot changes what the field shows.
Camera.subscribe(() => {
  if (mountedName) showField(mountedName, mountedName);
});
// A browser hands over the camera only after a touch, so the first one asks.
document.addEventListener('pointerdown', () => Camera.start(), { once: true, capture: true });
model.init({ reducedMotion, linkDigits });
render();

if (debug) debugIndex(device);
