// Owns the offscreen document that captures one tab and pitch-shifts its audio.
// Service workers are stopped when idle, so all state lives in chrome.storage.session.
import { loadSettings, totalSemitones } from './settings.js';

const OFFSCREEN_URL = 'offscreen.html';
const START_TIMEOUT_MS = 10000;
const STALE_MS = 15000; // a 'starting'/'stopping' lock older than this was left by a stopped worker

async function offscreenExists() {
  const contexts = await chrome.runtime.getContexts({ contextTypes: ['OFFSCREEN_DOCUMENT'] });
  return contexts.length > 0;
}

async function ensureOffscreen() {
  if (await offscreenExists()) return;
  await chrome.offscreen.createDocument({
    url: OFFSCREEN_URL,
    reasons: ['USER_MEDIA'],
    justification: 'Pitch-shift the captured audio of the chosen tab.',
  });
}

const toOffscreen = (type, data = {}) => chrome.runtime.sendMessage({ target: 'offscreen', type, ...data });

// The tab being shifted: { tabId, title } or null.
async function getCapture() {
  const { capture = null } = await chrome.storage.session.get('capture');
  if (capture && !(await offscreenExists())) {
    await chrome.storage.session.remove('capture');
    return null;
  }
  return capture;
}

// Tab capture and the offscreen document are exclusive, so starts and stops never overlap:
// 'idle' → 'starting' → 'idle', 'idle' → 'stopping' → 'idle'.
// The in-memory check is the atomic one (a storage read then write lets two messages both pass);
// it's safe here because the worker stays alive while the operation runs. The storage copy covers
// a worker that was stopped mid-operation.
let lockHeld = null;
async function withLock(state, work) {
  const busy = (held) => ({ ok: false, error: `PitchTap is still ${held.state}. Try again in a moment.` });
  if (lockHeld) return busy(lockHeld);
  const mine = (lockHeld = { state, at: Date.now() }); // claimed before any await
  try {
    const { lock } = await chrome.storage.session.get('lock');
    if (lock && Date.now() - lock.at < STALE_MS) return busy(lock);
    await chrome.storage.session.set({ lock: mine });
    try {
      return await work();
    } finally {
      await chrome.storage.session.remove('lock');
    }
  } finally {
    lockHeld = null;
  }
}

// Toolbar badge: the shift (e.g. "+3") while a tab is being shifted, nothing otherwise.
async function updateBadge() {
  const capture = await getCapture();
  const semis = totalSemitones(await loadSettings());
  const text = capture ? `${semis >= 0 ? '+' : ''}${Number.isInteger(semis) ? semis : semis.toFixed(1)}` : '';
  await chrome.action.setBadgeText({ text });
}
chrome.action.setBadgeBackgroundColor({ color: '#ff9b3d' });

async function stopCapture() {
  if (await offscreenExists()) {
    await toOffscreen('stop').catch(() => {});
    await chrome.offscreen.closeDocument().catch(() => {});
  }
  await chrome.storage.session.remove('capture');
  await updateBadge();
}

async function startCapture({ streamId, tabId, title }) {
  await stopCapture();
  await ensureOffscreen();
  const result = await Promise.race([
    toOffscreen('start', { streamId, settings: await loadSettings() }),
    new Promise((resolve) => setTimeout(() => resolve({ ok: false, error: 'the audio engine took too long to start' }), START_TIMEOUT_MS)),
  ]);
  if (result?.ok) await chrome.storage.session.set({ capture: { tabId, title } });
  else await stopCapture();
  await updateBadge();
  return result ?? { ok: false, error: 'The audio engine did not answer' };
}

async function handle(msg) {
  switch (msg.type) {
    case 'status':
      return { capture: await getCapture() };
    case 'start':
      return withLock('starting', () => startCapture(msg));
    case 'stop':
      return withLock('stopping', async () => {
        await stopCapture();
        return { ok: true };
      });
    case 'capture-ended': // the tab closed or navigated away
      await stopCapture();
      return { ok: true };
  }
}

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  if (msg.target !== 'background') return;
  (async () => {
    try {
      sendResponse(await handle(msg));
    } catch (err) {
      sendResponse({ ok: false, error: String(err?.message || err) });
    }
  })();
  return true;
});

// Live parameter changes go straight from storage to the offscreen document.
chrome.storage.onChanged.addListener(async (changes, area) => {
  if (area !== 'local') return;
  try {
    if (await offscreenExists()) await toOffscreen('settings', { settings: await loadSettings() });
    await updateBadge();
  } catch (err) {
    console.error('PitchTap: settings update failed', err);
  }
});

chrome.tabs.onRemoved.addListener(async (tabId) => {
  try {
    if ((await getCapture())?.tabId === tabId) await stopCapture();
  } catch (err) {
    console.error('PitchTap: cleanup after tab close failed', err);
  }
});
