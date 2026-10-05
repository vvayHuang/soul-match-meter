// Front camera → simulated thermal frames. Ported from
// soul-match-meter/Model/ThermalCamera.swift: the same sensor grid, heat
// arithmetic, diffusion blur, auto-ranging, sensor noise and NUC freezes.
//
// The app asks Vision where the person and their face are. A browser has no
// such thing without downloading a model, so here bare skin is found by its
// colour and reads hot wherever it is — unless it looks like the frame's
// edges, which are taken to be the room: a warm wall is skin-coloured too.
// The body is assumed to be where a selfie puts it — a head in the upper
// middle over shoulders — weighted by how bright that part of the picture is.
// When no skin stands out from the room, the face is assumed to be there too.
// Eyes, nose, lips and hair, which need real landmarks, are left out.
//
// Frames never leave the page: they are drawn to a canvas and thrown away.

import { DEFAULT_PALETTE, lut } from './palette.js';

// Sensor resolution, matching a 256×192 handheld core held in portrait.
const W = 192;
const H = 256;
const COUNT = W * H;
// Handheld thermal cores run at 9–15 Hz; the stutter is part of the look.
const FRAME_MS = 1000 / 15;

// 'idle' until asked, then 'starting', and 'running' or 'unavailable'.
let status = 'idle';
let live = false;
let table = lut(DEFAULT_PALETTE);
let framed = false;
let snapshotUrl = null;
const listeners = new Set();

let video = null;
let grab = null;
let grabContext = null;
let output = null;
let outputContext = null;
let image = null;
let loop = 0;
let lastFrame = 0;

const luma = new Float32Array(COUNT);
const lumaMean = new Float32Array(COUNT);
const skin = new Float32Array(COUNT);
const chromaB = new Float32Array(COUNT);
const chromaR = new Float32Array(COUNT);
const heat = new Float32Array(COUNT);
const scratch = new Float32Array(COUNT);

// Where a selfie's subject sits, in sensor pixels.
const FACE = { cx: W * 0.5, cy: H * 0.4, w: W * 0.44, h: H * 0.36 };
// Fixed per pixel, since the assumed subject doesn't move.
const subject = new Float32Array(COUNT);
const faceGlow = new Float32Array(COUNT);
const neckGlow = new Float32Array(COUNT);
const foreheadGlow = new Float32Array(COUNT);
// The frame's edges, where a selfie shows the room rather than the person:
// a band along the top, and the sides down to the shoulders.
const room = [];
for (let y = 0; y < H * 0.6; y++) {
  for (let x = 0; x < W; x++) {
    if (y < H * 0.12 || x < W * 0.1 || x >= W * 0.9) room.push(y * W + x);
  }
}
// Column-wise fixed-pattern offsets, the faint vertical banding of a bolometer.
const fixedPattern = Float32Array.from({ length: W }, () => (Math.random() - 0.5) * 0.02);

for (let y = 0; y < H; y++) {
  const py = y + 0.5;
  for (let x = 0; x < W; x++) {
    const px = x + 0.5;
    const i = y * W + x;

    // Head, then shoulders rising from the bottom edge: flat-topped, so the
    // subject reads as one warm body rather than a glow.
    const hx = (px - FACE.cx) / (FACE.w * 0.62);
    const hy = (py - FACE.cy) / (FACE.h * 0.72);
    const head = Math.exp(-((hx * hx + hy * hy) ** 2));
    const sx = (px - FACE.cx) / (W * 0.55);
    const sy = (py - H * 1.02) / (H * 0.36);
    const shoulders = Math.exp(-((sx * sx + sy * sy) ** 2));
    subject[i] = Math.max(head, shoulders);

    // Face: flat-topped ellipse so cheeks read evenly hot.
    const fx = (px - FACE.cx) / (FACE.w * 0.5);
    const fy = (py - (FACE.cy + FACE.h * 0.04)) / (FACE.h * 0.62);
    const fd = fx * fx + fy * fy;
    faceGlow[i] = Math.exp(-fd * fd);

    // Neck and throat run as hot as the face.
    const nx = (px - FACE.cx) / (FACE.w * 0.3);
    const ny = (py - (FACE.cy + FACE.h * 0.78)) / (FACE.h * 0.35);
    neckGlow[i] = Math.exp(-(nx * nx + ny * ny));

    // Forehead glow.
    const bx = (px - FACE.cx) / (FACE.w * 0.38);
    const by = (py - (FACE.cy - FACE.h * 0.3)) / (FACE.h * 0.16);
    foreheadGlow[i] = Math.exp(-(bx * bx + by * by));
  }
}

// 0…1: how much of the frame's skin was found, eased so it doesn't flicker.
let skinFound = 0;
let rangeLo = 0.15;
let rangeHi = 0.9;
let nextNuc = 0;
let frozenUntil = 0;

function between(low, high) {
  return low + Math.random() * (high - low);
}

function notify() {
  for (const listener of listeners) listener();
}

// Told when the first frame lands, when the camera turns out to be
// unavailable, and when a snapshot is taken.
export function subscribe(listener) {
  listeners.add(listener);
}

// The canvas the feed is drawn on, for the field to show.
export function canvas() {
  if (!output) {
    output = document.createElement('canvas');
    output.width = W;
    output.height = H;
    outputContext = output.getContext('2d');
    image = outputContext.createImageData(W, H);
    for (let o = 3; o < image.data.length; o += 4) image.data[o] = 255;
  }
  return output;
}

// Whether there is a frame to show yet. Until there is — the permission
// prompt, the first frame's latency, no camera at all — the stills stand in.
export function hasFrame() {
  return framed;
}

// Recolours the live feed from the next frame on. A frozen snapshot keeps the
// palette it was taken in.
export function setPalette(id) {
  table = lut(id);
}

// Asks for the front camera. Browsers only allow it from a touch, and only
// once per page: a refusal stands.
export async function start() {
  if (status !== 'idle') return;
  if (!navigator.mediaDevices?.getUserMedia) {
    status = 'unavailable';
    notify();
    return;
  }
  status = 'starting';
  try {
    const stream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: 'user', width: { ideal: 640 }, height: { ideal: 480 }, frameRate: { ideal: 15 } },
      audio: false,
    });
    video = document.createElement('video');
    // Without these an iPhone plays the camera full screen, or not at all.
    video.playsInline = true;
    video.muted = true;
    video.autoplay = true;
    video.setAttribute('playsinline', '');
    video.setAttribute('aria-hidden', 'true');
    video.style.cssText = 'position:fixed;left:0;top:0;width:1px;height:1px;opacity:0;pointer-events:none;';
    document.body.append(video);
    video.srcObject = stream;
    await video.play();

    grab = document.createElement('canvas');
    grab.width = W;
    grab.height = H;
    grabContext = grab.getContext('2d', { willReadFrequently: true });
    canvas();
    status = 'running';
    schedule();
  } catch {
    status = 'unavailable';
    notify();
  }
}

// Off while no screen shows the feed: frames arrive and are left unprocessed.
export function setLive(on) {
  if (live === on) return;
  live = on;
  if (on) {
    // A NUC that fell due while paused would freeze the feed the moment it's back.
    nextNuc = 0;
    frozenUntil = 0;
    schedule();
  }
}

function schedule() {
  if (loop || !live || status !== 'running') return;
  loop = requestAnimationFrame(tick);
}

function tick(now) {
  loop = 0;
  if (!live || status !== 'running') return;
  schedule();
  if (now - lastFrame < FRAME_MS) return;
  lastFrame = now;

  // NUC: the shutter drops, the image holds still for a beat, then resumes.
  if (nextNuc === 0) nextNuc = now + between(6000, 10_000);
  if (now < frozenUntil) return;
  if (now >= nextNuc) {
    frozenUntil = now + 350;
    nextNuc = now + between(9000, 16_000);
    return;
  }

  if (!readFrame()) return;
  lumaMean.set(luma);
  boxBlur(lumaMean, 4, 2);
  boxBlur(skin, 3, 2);
  buildHeat();
  boxBlur(heat, 1, 2);
  colorize();

  if (!framed) {
    framed = true;
    notify();
  }
}

// Downsamples the camera to sensor resolution: cropped to the sensor's shape
// and mirrored like a selfie, so the subject moves the way they expect.
function readFrame() {
  const width = video.videoWidth;
  const height = video.videoHeight;
  if (!width || !height) return false;
  const scale = Math.max(W / width, H / height);
  const drawnWidth = width * scale;
  const drawnHeight = height * scale;
  grabContext.setTransform(-1, 0, 0, 1, W, 0);
  grabContext.drawImage(video, (W - drawnWidth) / 2, (H - drawnHeight) / 2, drawnWidth, drawnHeight);
  const pixels = grabContext.getImageData(0, 0, W, H).data;
  for (let i = 0, o = 0; i < COUNT; i++, o += 4) {
    const r = pixels[o];
    const g = pixels[o + 1];
    const b = pixels[o + 2];
    luma[i] = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
    chromaB[i] = 128 - 0.169 * r - 0.331 * g + 0.5 * b;
    chromaR[i] = 128 + 0.5 * r - 0.419 * g - 0.081 * b;
  }

  // What the room looks like: the edges' average brightness and colour, and
  // how much they vary.
  let sumL = 0;
  let sumB = 0;
  let sumR = 0;
  let squareL = 0;
  let squareB = 0;
  let squareR = 0;
  for (const i of room) {
    sumL += luma[i];
    sumB += chromaB[i];
    sumR += chromaR[i];
    squareL += luma[i] * luma[i];
    squareB += chromaB[i] * chromaB[i];
    squareR += chromaR[i] * chromaR[i];
  }
  const n = room.length;
  const meanL = sumL / n;
  const meanB = sumB / n;
  const meanR = sumR / n;
  // Anything within a couple of deviations counts as the room, with a floor
  // so an evenly lit wall still takes its near shades with it.
  const spreadL = Math.max(0.07, 2 * Math.sqrt(Math.max(0, squareL / n - meanL * meanL)));
  const spreadB = Math.max(4, 2 * Math.sqrt(Math.max(0, squareB / n - meanB * meanB)));
  const spreadR = Math.max(4, 2 * Math.sqrt(Math.max(0, squareR / n - meanR * meanR)));

  let found = 0;
  for (let i = 0; i < COUNT; i++) {
    const l = luma[i];
    const cb = chromaB[i];
    const cr = chromaR[i];
    // Skin of any tone sits in one small patch of chroma, whatever its
    // brightness. Too dark to tell is left out.
    if (l > 0.15 && cb >= 77 && cb <= 127 && cr >= 133 && cr <= 173) {
      const dl = (l - meanL) / spreadL;
      const db = (cb - meanB) / spreadB;
      const dr = (cr - meanR) / spreadR;
      // …less whatever part of it could as well be the wall.
      skin[i] = 1 - Math.exp(-(dl * dl + db * db + dr * dr) / 2);
      found += skin[i];
    } else {
      skin[i] = 0;
    }
  }
  // A face at arm's length covers a few percent of the frame at least.
  skinFound += (Math.min(1, found / (COUNT * 0.03)) - skinFound) * 0.2;
  return true;
}

// MARK: Heat model

function buildHeat() {
  // How far to lean on the assumed face: fully when no skin shows up.
  const assumed = 1 - skinFound;
  for (let i = 0; i < COUNT; i++) {
    const l = luma[i];
    // In place of the app's person mask: the assumed subject, more so where
    // the picture is bright there, and any bare skin.
    const body = subject[i] * Math.min(1, 0.35 + 1.1 * lumaMean[i]);
    const m = Math.max(body, skin[i]);

    // Background sits cold; lamps and windows read a touch warmer.
    let t = 0.12 + 0.1 * l;
    // Clothed body: warm, with a little texture from the fabric.
    t += m * (0.34 + 0.05 * l);

    // High-pass of the camera image: brows, lash lines, nostrils and the lip
    // seam are darker than the skin around them and read cooler.
    const detail = l - lumaMean[i];
    t += m * 0.12 * detail;

    // In place of the app's face box: bare skin, or the assumed face.
    const faceWeight = Math.max(skin[i], assumed * body * faceGlow[i]);
    t += faceWeight * 0.26;
    // Features get extra contrast inside the face so it stays legible.
    t += faceWeight * 0.55 * detail;
    t += assumed * body * 0.18 * neckGlow[i];
    t += assumed * 0.06 * foreheadGlow[i];

    heat[i] = t;
  }
}

// Separable box blur. Two passes approximate a Gaussian — heat diffuses.
function boxBlur(buffer, radius, passes) {
  const norm = 1 / (2 * radius + 1);
  for (let pass = 0; pass < passes; pass++) {
    for (let y = 0; y < H; y++) {
      const row = y * W;
      for (let x = 0; x < W; x++) {
        let sum = 0;
        for (let k = -radius; k <= radius; k++) sum += buffer[row + Math.min(W - 1, Math.max(0, x + k))];
        scratch[row + x] = sum * norm;
      }
    }
    for (let y = 0; y < H; y++) {
      for (let x = 0; x < W; x++) {
        let sum = 0;
        for (let k = -radius; k <= radius; k++) sum += scratch[Math.min(H - 1, Math.max(0, y + k)) * W + x];
        buffer[y * W + x] = sum * norm;
      }
    }
  }
}

// Auto-range, add sensor noise, and map through the palette.
function colorize() {
  let lo = Infinity;
  let hi = -Infinity;
  for (let i = 0; i < COUNT; i++) {
    const value = heat[i];
    if (value < lo) lo = value;
    if (value > hi) hi = value;
  }
  // The span drifts toward the scene rather than snapping, like AGC.
  rangeLo += (lo - rangeLo) * 0.08;
  rangeHi += (hi - rangeHi) * 0.08;
  const span = Math.max(rangeHi - rangeLo, 0.35);

  const pixels = image.data;
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      const i = y * W + x;
      const noise = (Math.random() - 0.5) * 0.035 + fixedPattern[x];
      const t = Math.min(1, Math.max(0, (heat[i] - rangeLo) / span + noise));
      const from = Math.floor(t * 255) * 3;
      const o = i * 4;
      pixels[o] = table[from];
      pixels[o + 1] = table[from + 1];
      pixels[o + 2] = table[from + 2];
    }
  }
  outputContext.putImageData(image, 0, 0);
}

// MARK: Snapshot

// Freezes the frame on screen when a measurement locks, for the receipt and
// the report. Kept only in this page's memory. With no frame to freeze, the
// last snapshot (or none) stands and the stills take over.
export function takeSnapshot() {
  if (!framed) return;
  try {
    snapshotUrl = output.toDataURL('image/png');
    notify();
  } catch {
    // Nothing frozen; the receipt falls back to its still.
  }
}

// The frozen frame as an image address, or null when there isn't one.
export function snapshot() {
  return snapshotUrl;
}
