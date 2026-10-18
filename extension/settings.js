// Shared settings model (same shape as the Mac app's PitchParams).
export const DEFAULTS = { enabled: false, semitones: 0, cents: 0 };

export async function loadSettings() {
  return { ...DEFAULTS, ...(await chrome.storage.local.get(Object.keys(DEFAULTS))) };
}

export function saveSettings(settings) {
  return chrome.storage.local.set(settings);
}

export function totalSemitones(s) {
  return s.semitones + s.cents / 100;
}
