// What survives a reload: the log. Mirrors MeterModel.Saved in
// soul-match-meter/Model/MeterModel.swift, minus the settings (not built yet).
// Everything is wrapped: private browsing can refuse storage, and the game
// must still play — it just can't be picked up again later.

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
    return saved.history.filter(validEntry).map((entry) => ({
      id: entry.id,
      serial: entry.serial,
      meta: entry.meta,
      status: entry.status,
      sentAt: typeof entry.sentAt === 'number' ? entry.sentAt : null,
      report: entry.report ?? null,
    }));
  } catch {
    return [];
  }
}

const UNSENT_KEY = 'meter.unsent.web.v1';

// A guest's reply the relay hasn't taken yet: `{ host, guest, since }`, or null.
export function loadUnsentReply() {
  try {
    const reply = JSON.parse(localStorage.getItem(UNSENT_KEY));
    const whole = reply
      && typeof reply.host === 'string'
      && typeof reply.guest === 'string'
      && typeof reply.since === 'number';
    return whole ? reply : null;
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

export function saveHistory(history) {
  try {
    localStorage.setItem(SAVED_KEY, JSON.stringify({ history }));
  } catch {
    // Nowhere to keep it; carry on without.
  }
}
