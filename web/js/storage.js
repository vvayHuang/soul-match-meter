// What survives a reload: the log and the settings. Mirrors MeterModel.Saved
// in soul-match-meter/Model/MeterModel.swift, kept under two keys.
// Everything is wrapped: private browsing can refuse storage, and the game
// must still play — it just can't be picked up again later.

import { isGrid, isKey } from './heat.js';
import { DEFAULT_PALETTE, isPalette } from './palette.js';

const SAVED_KEY = 'meter.saved.web.v1';
const STATUSES = ['waiting', 'unread', 'done', 'expired'];

function validEntry(entry) {
  return Boolean(entry)
    && typeof entry.id === 'string'
    && typeof entry.serial === 'string'
    && typeof entry.meta === 'string'
    && STATUSES.includes(entry.status);
}

// Returns the saved log, or an empty one when nothing readable is there.
export function loadHistory() {
  try {
    const raw = localStorage.getItem(SAVED_KEY);
    if (!raw) return [];
    const saved = JSON.parse(raw);
    if (!Array.isArray(saved?.history)) return [];
    return saved.history.filter(validEntry).map((entry) => {
      // Saved before reports and entries kept their palette: the report's,
      // else the factory one.
      const report = entry.report
        ? {
          ...entry.report,
          palette: isPalette(entry.report.palette) ? entry.report.palette : DEFAULT_PALETTE,
          // Each side's heat grid, when the pair photo was on.
          heat: isGrid(entry.report.heat) ? entry.report.heat : null,
          peerHeat: isGrid(entry.report.peerHeat) ? entry.report.peerHeat : null,
        }
        : null;
      return {
        id: entry.id,
        serial: entry.serial,
        meta: entry.meta,
        status: entry.status,
        sentAt: typeof entry.sentAt === 'number' ? entry.sentAt : null,
        report,
        palette: isPalette(entry.palette) ? entry.palette : (report?.palette ?? DEFAULT_PALETTE),
        // A waiting host's own grid, the key the reply's grid is fetched
        // with, and whether the relay has that key yet.
        heat: isGrid(entry.heat) ? entry.heat : null,
        key: isKey(entry.key) ? entry.key : null,
        filed: entry.filed === true,
      };
    });
  } catch {
    return [];
  }
}

const UNSENT_KEY = 'meter.unsent.web.v1';

// A guest's reply the relay hasn't taken yet: `{ host, guest, since }`, plus
// `key` and `heat` when the pair photo was on. Null when there is none.
export function loadUnsentReply() {
  try {
    const reply = JSON.parse(localStorage.getItem(UNSENT_KEY));
    const whole = reply
      && typeof reply.host === 'string'
      && typeof reply.guest === 'string'
      && typeof reply.since === 'number';
    if (!whole) return null;
    const key = isKey(reply.key) ? reply.key : null;
    return {
      host: reply.host,
      guest: reply.guest,
      since: reply.since,
      key,
      heat: key && isGrid(reply.heat) ? reply.heat : null,
    };
  } catch {
    return null;
  }
}

export function saveUnsentReply(reply) {
  try {
    if (reply) {
      localStorage.setItem(UNSENT_KEY, JSON.stringify(reply));
    } else {
      localStorage.removeItem(UNSENT_KEY);
    }
  } catch {
    // Nowhere to keep it; it is still retried while the page stays open.
  }
}

// Heat grids are the bulk of a saved log. When it no longer fits, the oldest
// reports give theirs up, one at a time, so the log itself is still kept.
export function saveHistory(history) {
  let kept = history;
  for (;;) {
    try {
      localStorage.setItem(SAVED_KEY, JSON.stringify({ history: kept }));
      return;
    } catch {
      const oldest = kept.findLastIndex((entry) => entry.report?.heat || entry.report?.peerHeat);
      // Nothing left to drop: nowhere to keep it; carry on without.
      if (oldest < 0) return;
      kept = kept.map((entry, index) => (
        index === oldest ? { ...entry, report: { ...entry.report, heat: null, peerHeat: null } } : entry
      ));
    }
  }
}

const SETTINGS_KEY = 'meter.settings.web.v1';

export const HOLD_OPTIONS = [3, 5, 10];
// The pair photo sends a heat grid off the device. It starts on, so a pair
// gets their photo without setting anything up; the privacy policy says so.
export const FACTORY_SETTINGS = { palette: DEFAULT_PALETTE, holdSeconds: 5, shutter: true, pairPhoto: true };

// A missing or unreadable value falls back to its factory setting.
export function loadSettings() {
  try {
    const saved = JSON.parse(localStorage.getItem(SETTINGS_KEY)) ?? {};
    return {
      palette: isPalette(saved.palette) ? saved.palette : FACTORY_SETTINGS.palette,
      holdSeconds: HOLD_OPTIONS.includes(saved.holdSeconds) ? saved.holdSeconds : FACTORY_SETTINGS.holdSeconds,
      shutter: typeof saved.shutter === 'boolean' ? saved.shutter : FACTORY_SETTINGS.shutter,
      pairPhoto: typeof saved.pairPhoto === 'boolean' ? saved.pairPhoto : FACTORY_SETTINGS.pairPhoto,
    };
  } catch {
    return { ...FACTORY_SETTINGS };
  }
}

export function saveSettings(settings) {
  try {
    localStorage.setItem(SETTINGS_KEY, JSON.stringify(settings));
  } catch {
    // Nowhere to keep them; they hold until the page closes.
  }
}
