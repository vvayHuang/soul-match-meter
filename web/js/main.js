// Entry point: reads the URL, starts the model, and keeps the one mounted
// screen in step with it. Mirrors soul-match-meter/ContentView.swift.

import * as model from './model.js';
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

function image(name) {
  return name ? `url("img/${name}.png")` : '';
}

// The optical ground under the screens. Moving between live screens changes
// only the still; arriving from anywhere else runs the focus pull.
function showField(name, previous) {
  const preset = FIELDS[name];
  field.hidden = !preset;
  if (!preset) return;
  field.style.setProperty('--mid-stop', `${preset.midStop}%`);
  fieldTop.style.backgroundImage = image(preset.image);
  fieldPeer.style.backgroundImage = image(preset.peer);
  subject.classList.toggle('split', Boolean(preset.peer));
  if (!(preset.live && FIELDS[previous]?.live)) {
    subject.classList.remove('focus-pull');
    void subject.offsetWidth; // restart the animation
    subject.classList.add('focus-pull');
  }
}

let mounted = null;
let mountedName = null;

function render() {
  if (state.screen === mountedName) {
    mounted.update?.();
    return;
  }
  mounted?.destroy?.();
  showField(state.screen, mountedName);
  mountedName = state.screen;
  mounted = SCREENS[state.screen]({ reducedMotion });
  stage.replaceChildren(mounted.el);
}

const { debug, linkDigits } = readUrl();

model.subscribe(render);
model.init({ reducedMotion, linkDigits });
render();

if (debug) debugIndex(device);
