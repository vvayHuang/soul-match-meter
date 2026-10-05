// The false-colour palettes the instrument can render with. Ported from
// soul-match-meter/Design/ThermalPalette.swift. None of them changes a
// result: they repaint the thermal stills and the data ramps (palette scale,
// receipt band, log thumbnails), nothing else.

// Cold (0) to hot (1). `iron` is IR.rampStops in IRTheme.swift.
export const PALETTES = [
  {
    id: 'iron',
    label: '鐵紅',
    stops: [
      [0, 0x0A1A6E], [0.15, 0x1560B8], [0.3, 0x2DD4D8], [0.45, 0x7FD44E],
      [0.58, 0xE8F06A], [0.7, 0xF2F4F8], [0.84, 0xE24A2B], [1, 0xFFF2C8],
    ],
  },
  { id: 'white', label: '白熱', stops: [[0, 0x050608], [1, 0xF5F6F8]] },
  { id: 'black', label: '黑熱', stops: [[0, 0x8A8E96], [1, 0x050608]] },
  {
    id: 'rainbow',
    label: '彩虹',
    stops: [
      [0, 0x3B0A8C], [0.2, 0x1E5BFF], [0.4, 0x12C9A4],
      [0.6, 0xE8E23A], [0.8, 0xFF7A1A], [1, 0xFF1F4B],
    ],
  },
];

export const DEFAULT_PALETTE = 'iron';

// The stills every palette has to be able to repaint.
const STILLS = ['ir-scene', 'ir-scene-empty', 'ir-scene-solo', 'ir-scene-face', 'ir-scene-target'];

export function isPalette(id) {
  return PALETTES.some((palette) => palette.id === id);
}

function find(id) {
  return PALETTES.find((palette) => palette.id === id) ?? PALETTES[0];
}

function hex(value) {
  return `#${value.toString(16).padStart(6, '0').toUpperCase()}`;
}

// The stops as a CSS gradient's colour list, cold first.
export function cssStops(id) {
  return find(id).stops.map(([at, colour]) => `${hex(colour)} ${Math.round(at * 100)}%`).join(', ');
}

const luts = new Map();

// 256 RGB entries, cold to hot, for colouring a heat map.
export function lut(id) {
  const hit = luts.get(id);
  if (hit) return hit;
  const { stops } = find(id);
  const table = new Uint8Array(256 * 3);
  for (let i = 0; i < 256; i++) {
    const t = i / 255;
    let upper = stops.findIndex(([at]) => at >= t);
    if (upper < 0) upper = stops.length - 1;
    upper = Math.max(upper, 1);
    const [l0, c0] = stops[upper - 1];
    const [l1, c1] = stops[upper];
    const f = l1 > l0 ? Math.min(1, Math.max(0, (t - l0) / (l1 - l0))) : 0;
    for (let channel = 0; channel < 3; channel++) {
      const shift = 16 - channel * 8;
      const from = (c0 >> shift) & 0xFF;
      const to = (c1 >> shift) & 0xFF;
      table[i * 3 + channel] = Math.round(from + (to - from) * f);
    }
  }
  luts.set(id, table);
  return table;
}

// How hot an iron-palette colour is: the nearest point on the iron ramp,
// 0…255. Every 4th ramp entry is plenty to place a colour on the ramp.
export function heatOf(r, g, b) {
  const iron = lut('iron');
  let nearest = 0;
  let best = Infinity;
  for (let i = 0; i < 256; i += 4) {
    const dr = r - iron[i * 3];
    const dg = g - iron[i * 3 + 1];
    const db = b - iron[i * 3 + 2];
    const d = dr * dr + dg * dg + db * db;
    if (d < best) {
      best = d;
      nearest = i;
    }
  }
  return nearest;
}

// Repaints RGBA pixels drawn in iron with another palette, in place. The
// stills are flat bands of a few colours, so each one is placed on the ramp
// once and remembered.
export function recolor(pixels, id) {
  const target = lut(id);
  const heats = new Map();
  for (let o = 0; o < pixels.length; o += 4) {
    const key = (pixels[o] << 16) | (pixels[o + 1] << 8) | pixels[o + 2];
    let heat = heats.get(key);
    if (heat === undefined) {
      heat = heatOf(pixels[o], pixels[o + 1], pixels[o + 2]);
      heats.set(key, heat);
    }
    pixels[o] = target[heat * 3];
    pixels[o + 1] = target[heat * 3 + 1];
    pixels[o + 2] = target[heat * 3 + 2];
  }
}

// MARK: Stills

export function loadImage(src) {
  return new Promise((resolve, reject) => {
    const image = new Image();
    image.onload = () => resolve(image);
    image.onerror = () => reject(new Error(`image failed: ${src}`));
    image.src = src;
  });
}

function ironUrl(name) {
  return `img/${name}.png`;
}

const urls = new Map();

async function repaint(name, id) {
  const image = await loadImage(ironUrl(name));
  const canvas = document.createElement('canvas');
  canvas.width = image.naturalWidth;
  canvas.height = image.naturalHeight;
  const context = canvas.getContext('2d', { willReadFrequently: true });
  context.drawImage(image, 0, 0);
  const frame = context.getImageData(0, 0, canvas.width, canvas.height);
  recolor(frame.data, id);
  context.putImageData(frame, 0, 0);
  const blob = await new Promise((resolve) => canvas.toBlob(resolve, 'image/png'));
  if (!blob) throw new Error('no blob');
  return URL.createObjectURL(blob);
}

// Where to load a still in a palette from. The files are drawn in iron; the
// other palettes are repainted here once and kept. If that fails, the iron
// still stands in.
export function stillUrl(name, id) {
  if (id === DEFAULT_PALETTE || !isPalette(id)) return Promise.resolve(ironUrl(name));
  const key = `${name}|${id}`;
  let url = urls.get(key);
  if (!url) {
    url = repaint(name, id).catch(() => ironUrl(name));
    urls.set(key, url);
  }
  return url;
}

// Repaints every still ahead of time, one after another with a breath in
// between, so changing screens doesn't wait on it and nothing on screen stalls.
export async function warm(id) {
  for (const name of STILLS) {
    await stillUrl(name, id);
    await new Promise((resolve) => { setTimeout(resolve, 60); });
  }
}
