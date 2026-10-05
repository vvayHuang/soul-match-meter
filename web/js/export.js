// A still, phone-sized copy of the report for sharing: no buttons, no
// animation, and the instrument's name at the foot. Ported from
// ReportExportCard in soul-match-meter/Screens/ReportScreen.swift — 390×844
// drawn at 3×, in the palette the report was recorded in. The web copy adds
// where to find the instrument under its name.

import { TEXT } from './content.js';
import { loadImage, stillUrl } from './palette.js';

const WIDTH = 390;
const HEIGHT = 844;
const SCALE = 3;

// Tokens from styles.css.
const MONO = 'ui-monospace, Menlo, monospace';
const CJK = 'system-ui, -apple-system, "PingFang TC", "Noto Sans TC", sans-serif';
const PLATE = 'rgb(18 21 27 / 0.88)';
const ON_PLATE = '#FFFFFF';
const ON_PLATE_VARIANT = '#D6DAE2';
const OUTLINE_QUIET = '#2A2F38';
const INSET = 14;
const GAP = 9;

// The field the archive preset describes: this side's still over the peer's.
const FIELD = { image: 'ir-scene-face', peer: 'ir-scene-solo', midStop: 0.44, scrim: 0.3 };

// Text with letter-spacing, which a canvas can't be relied on to apply. Like
// CSS, the spacing follows every character, the last one included.
function trackedWidth(context, text, spacing) {
  if (spacing === 0) return context.measureText(text).width;
  let width = 0;
  for (const character of text) width += context.measureText(character).width + spacing;
  return width;
}

function drawTracked(context, text, x, y, spacing) {
  if (spacing === 0) {
    context.fillText(text, x, y);
    return;
  }
  let at = x;
  for (const character of text) {
    context.fillText(character, at, y);
    at += context.measureText(character).width + spacing;
  }
}

// Shortens a line to fit, ending it with an ellipsis.
function fitted(context, text, width) {
  if (context.measureText(text).width <= width) return text;
  const characters = Array.from(text);
  while (characters.length > 1 && context.measureText(`${characters.join('')}…`).width > width) {
    characters.pop();
  }
  return `${characters.join('')}…`;
}

// A readout chip (`.chip.s` / `.chip.xs`). `right` anchors its right edge.
const CHIPS = {
  s: { size: 11.5, padX: 8, padY: 5.5 },
  xs: { size: 10, padX: 8, padY: 5.3 },
};

function chipHeight(variant) {
  const { size, padY } = CHIPS[variant];
  return size * 1.45 + padY * 2;
}

function drawChip(context, text, variant, { left, right, top }) {
  const { size, padX } = CHIPS[variant];
  context.font = `${size}px ${MONO}`;
  const width = trackedWidth(context, text, 1.5) + padX * 2;
  const height = chipHeight(variant);
  const x = left ?? right - width;
  context.fillStyle = PLATE;
  context.fillRect(x, top, width, height);
  context.fillStyle = ON_PLATE;
  context.textBaseline = 'middle';
  drawTracked(context, text, x + padX, top + height / 2, 1.5);
}

// Fills a box with an image, cropped to it, as `aspectRatio(.fill)` does.
function drawFilled(context, image, x, y, width, height) {
  const scale = Math.max(width / image.naturalWidth, height / image.naturalHeight);
  const drawnWidth = image.naturalWidth * scale;
  const drawnHeight = image.naturalHeight * scale;
  context.save();
  context.beginPath();
  context.rect(x, y, width, height);
  context.clip();
  context.drawImage(image, x + (width - drawnWidth) / 2, y + (height - drawnHeight) / 2, drawnWidth, drawnHeight);
  context.restore();
}

function drawField(context, top, peer) {
  const base = context.createLinearGradient(0, 0, 0, HEIGHT);
  base.addColorStop(0, '#0A1A6E');
  base.addColorStop(FIELD.midStop, '#0C2280');
  base.addColorStop(1, '#06103A');
  context.fillStyle = base;
  context.fillRect(0, 0, WIDTH, HEIGHT);

  // The optical subject overhangs its frame by 28%; the two halves meet on a
  // 1pt hairline.
  const width = WIDTH * 1.28;
  const height = HEIGHT * 1.28;
  const x = (WIDTH - width) / 2;
  const y = (HEIGHT - height) / 2;
  drawFilled(context, top, x, y, width, height / 2);
  drawFilled(context, peer, x, y + height / 2, width, height / 2);
  context.fillStyle = OUTLINE_QUIET;
  context.fillRect(0, HEIGHT / 2, WIDTH, 1);

  context.fillStyle = `rgb(4 6 14 / ${FIELD.scrim})`;
  context.fillRect(0, 0, WIDTH, HEIGHT);

  // 1pt dark line every 3pt.
  for (let line = 0; line < HEIGHT; line += 3) {
    context.fillStyle = 'rgb(0 0 0 / 0.26)';
    context.fillRect(0, line, WIDTH, 1);
    context.fillStyle = 'rgb(255 255 255 / 0.015)';
    context.fillRect(0, line + 1, WIDTH, 2);
  }
}

// The report's middle row (`.report-grid`): the score on the left, sized to
// its number, and the title with its metric bars filling the rest.
const METRIC_HEAD = 12.5 * 1.3;
const METRIC_HEIGHT = METRIC_HEAD + 5 + 4;
const TITLE_HEIGHT = 15 * 1.3;

function gridHeight(report) {
  return 11 * 2 + TITLE_HEIGHT + report.metrics.length * (GAP + METRIC_HEIGHT);
}

function drawGrid(context, report, top) {
  const height = gridHeight(report);
  const score = String(report.score);

  // Score plate: the number, then a small "%" on the same baseline.
  context.font = `600 62px ${MONO}`;
  const numberWidth = trackedWidth(context, score, -2);
  const ascent = context.measureText(score).actualBoundingBoxAscent;
  context.font = `600 16px ${MONO}`;
  const unitWidth = context.measureText('%').width;
  const scoreWidth = 14 * 2 + numberWidth + 4 + unitWidth;
  const baseline = top + height / 2 + ascent / 2;

  context.fillStyle = PLATE;
  context.fillRect(INSET, top, scoreWidth, height);
  context.fillStyle = ON_PLATE;
  context.textBaseline = 'alphabetic';
  context.font = `600 62px ${MONO}`;
  drawTracked(context, score, INSET + 14, baseline, -2);
  context.font = `600 16px ${MONO}`;
  context.fillText('%', INSET + 14 + numberWidth + 4, baseline);

  // Detail plate.
  const left = INSET + scoreWidth + 6;
  const width = WIDTH - INSET - left;
  const inner = width - 10 * 2;
  context.fillStyle = PLATE;
  context.fillRect(left, top, width, height);

  context.textBaseline = 'middle';
  context.fillStyle = ON_PLATE;
  context.font = `700 15px ${CJK}`;
  context.fillText(fitted(context, report.title, inner), left + 10, top + 11 + TITLE_HEIGHT / 2);

  let y = top + 11 + TITLE_HEIGHT + GAP;
  for (const metric of report.metrics) {
    const middle = y + METRIC_HEAD / 2;
    context.fillStyle = ON_PLATE_VARIANT;
    context.font = `500 12.5px ${CJK}`;
    context.fillText(metric.key, left + 10, middle);

    context.fillStyle = ON_PLATE;
    context.font = `11.5px ${MONO}`;
    drawTracked(context, metric.value, left + 10 + inner - trackedWidth(context, metric.value, 1.5), middle, 1.5);

    // A 4pt track from the cold origin to ink white.
    const trackTop = y + METRIC_HEAD + 5;
    context.fillStyle = OUTLINE_QUIET;
    context.fillRect(left + 10, trackTop, inner, 4);
    const filled = inner * metric.amount;
    if (filled > 0) {
      const ramp = context.createLinearGradient(left + 10, 0, left + 10 + filled, 0);
      ramp.addColorStop(0, '#2DD4D8');
      ramp.addColorStop(1, '#F2F4F8');
      context.fillStyle = ramp;
      context.fillRect(left + 10, trackTop, filled, 4);
    }
    y += METRIC_HEIGHT + GAP;
  }
}

// Where this page lives, as someone would type it.
function address() {
  return (location.host + location.pathname).replace(/index\.html$/, '').replace(/\/$/, '');
}

// Draws the report and returns it as a PNG blob. `frozen` is this side's
// snapshot from the hold, when there is one; a report from the log has only
// the stills.
export async function renderReport(report, frozen = null) {
  const [top, peer] = await Promise.all([
    frozen ? loadImage(frozen) : stillUrl(FIELD.image, report.palette).then(loadImage),
    stillUrl(FIELD.peer, report.palette).then(loadImage),
  ]);

  const canvas = document.createElement('canvas');
  canvas.width = WIDTH * SCALE;
  canvas.height = HEIGHT * SCALE;
  const context = canvas.getContext('2d');
  context.scale(SCALE, SCALE);

  drawField(context, top, peer);

  const headerTop = 24;
  drawChip(context, 'MATCH REPORT', 's', { left: INSET, top: headerTop });
  drawChip(context, report.pair, 'xs', { right: WIDTH - INSET, top: headerTop });

  // The name, and under it where to find the instrument.
  const footerBottom = HEIGHT - 28;
  const addressTop = footerBottom - chipHeight('xs');
  const nameTop = addressTop - 1 - chipHeight('s');
  drawChip(context, TEXT.exportFooter, 's', { left: INSET, top: nameTop });
  drawChip(context, address(), 'xs', { left: INSET, top: addressTop });

  // The grid floats midway between the header and the footer.
  const above = headerTop + chipHeight('s') + GAP;
  const below = nameTop - GAP;
  drawGrid(context, report, above + (below - above - gridHeight(report)) / 2);

  const blob = await new Promise((resolve) => canvas.toBlob(resolve, 'image/png'));
  if (!blob) throw new Error('no blob');
  return blob;
}

const FILE_NAME = 'soul-match-report.png';

// Hands the image to the share sheet — where a phone offers "Save Image" — or
// downloads it where files can't be shared. False only when the user backed
// out of the share sheet.
export async function deliver(blob) {
  const file = new File([blob], FILE_NAME, { type: 'image/png' });
  if (navigator.canShare?.({ files: [file] })) {
    try {
      await navigator.share({ files: [file] });
      return true;
    } catch (error) {
      if (error?.name === 'AbortError') return false;
      // Refused for any other reason: download it instead.
    }
  }
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = FILE_NAME;
  document.body.append(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 60_000);
  return true;
}
