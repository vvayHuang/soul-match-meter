// The heat grid: a frozen thermal frame boiled down to 96 × 128 readings, one
// byte each, cold (0) to hot (255). It is what the two sides of a pair swap
// through the relay, and what the log keeps, so a report can show both people.
// It carries no colour — half the sensor's resolution each way, which is
// about all the detail the diffused frame holds.
//
// Web only for now: the app neither sends nor reads one.

import { lut } from './palette.js';

export const GRID_W = 96;
export const GRID_H = 128;
// The first grids were 48 × 64. Ones already in a log still open.
const SIZES = [[GRID_W, GRID_H], [48, 64]];

// A key the relay hands a grid out for: 128 random bits, hex.
const KEY_PATTERN = /^[0-9a-f]{32}$/;
const GRID_PATTERN = /^[A-Za-z0-9+/]+$/;

// The width and height of the grid a text of this length holds, or undefined.
function sizeOf(text) {
  return SIZES.find(([width, height]) => text.length === (width * height * 4) / 3);
}

export function isGrid(text) {
  return typeof text === 'string' && sizeOf(text) !== undefined && GRID_PATTERN.test(text);
}

export function isKey(text) {
  return typeof text === 'string' && KEY_PATTERN.test(text);
}

export function newKey() {
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('');
}

// Averages a `width` × `height` heat map down to the grid. `low` and `span`
// are the range on screen when it was frozen, so the grid reads as the frame did.
export function pack(heat, width, height, low, span) {
  const stepX = width / GRID_W;
  const stepY = height / GRID_H;
  let binary = '';
  for (let gy = 0; gy < GRID_H; gy++) {
    for (let gx = 0; gx < GRID_W; gx++) {
      let sum = 0;
      let count = 0;
      for (let y = Math.floor(gy * stepY); y < Math.floor((gy + 1) * stepY); y++) {
        for (let x = Math.floor(gx * stepX); x < Math.floor((gx + 1) * stepX); x++) {
          sum += heat[y * width + x];
          count++;
        }
      }
      const t = Math.min(1, Math.max(0, (sum / count - low) / span));
      binary += String.fromCharCode(Math.round(t * 255));
    }
  }
  return btoa(binary);
}

// The grid's readings and its size, `{ cells, width, height }`, or null when
// the text isn't one.
export function unpack(text) {
  if (!isGrid(text)) return null;
  const [width, height] = sizeOf(text);
  const binary = atob(text);
  const cells = new Uint8Array(width * height);
  for (let i = 0; i < cells.length; i++) cells[i] = binary.charCodeAt(i);
  return { cells, width, height };
}

// Stretches an unpacked grid to `width` × `height`, blending between
// readings, as 0…1 values. Heat diffuses; the blend is the look, not a loss.
export function stretch(grid, width, height) {
  const { cells, width: gridW, height: gridH } = grid;
  const out = new Float32Array(width * height);
  for (let y = 0; y < height; y++) {
    const fy = Math.min(gridH - 1, Math.max(0, ((y + 0.5) * gridH) / height - 0.5));
    const y0 = Math.floor(fy);
    const y1 = Math.min(gridH - 1, y0 + 1);
    const wy = fy - y0;
    for (let x = 0; x < width; x++) {
      const fx = Math.min(gridW - 1, Math.max(0, ((x + 0.5) * gridW) / width - 0.5));
      const x0 = Math.floor(fx);
      const x1 = Math.min(gridW - 1, x0 + 1);
      const wx = fx - x0;
      const top = cells[y0 * gridW + x0] * (1 - wx) + cells[y0 * gridW + x1] * wx;
      const bottom = cells[y1 * gridW + x0] * (1 - wx) + cells[y1 * gridW + x1] * wx;
      out[y * width + x] = (top * (1 - wy) + bottom * wy) / 255;
    }
  }
  return out;
}

// MARK: Painting

// Drawn at the sensor's resolution, like the frame the grid came from.
const W = 192;
const H = 256;

const urls = new Map();

// The grid as an image address in a palette, or null when it can't be drawn.
// Painted once and kept: a report shows the same two over and over.
export function url(text, palette) {
  const key = `${palette}|${text}`;
  const hit = urls.get(key);
  if (hit) return hit;
  const grid = unpack(text);
  if (!grid) return null;
  try {
    const canvas = document.createElement('canvas');
    canvas.width = W;
    canvas.height = H;
    const context = canvas.getContext('2d');
    const image = context.createImageData(W, H);
    const table = lut(palette);
    const heat = stretch(grid, W, H);
    for (let i = 0, o = 0; i < heat.length; i++, o += 4) {
      // The same sensor noise the live feed carries.
      const t = Math.min(1, Math.max(0, heat[i] + (Math.random() - 0.5) * 0.035));
      const from = Math.floor(t * 255) * 3;
      image.data[o] = table[from];
      image.data[o + 1] = table[from + 1];
      image.data[o + 2] = table[from + 2];
      image.data[o + 3] = 255;
    }
    context.putImageData(image, 0, 0);
    const painted = canvas.toDataURL('image/png');
    if (urls.size >= 16) urls.clear();
    urls.set(key, painted);
    return painted;
  } catch {
    return null;
  }
}
