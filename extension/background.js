// Owns the offscreen document that captures one tab and pitch-shifts its audio.
import { loadSettings, totalSemitones } from './settings.js';

const OFFSCREEN_URL = 'offscreen.html';

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

function toOffscreen(type, data = {}) {
  return chrome.runtime.sendMessage({ target: 'offscreen', type, ...data });
}

// The tab being shifted: { tabId, title } or null.
async function getCapture() {
  const { capture = null } = await chrome.storage.session.get('capture');
  if (capture && !(await offscreenExists())) {
    await chrome.storage.session.remove('capture');
    return null;
  }
  return capture;
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

async function handle(msg) {
  switch (msg.type) {
    case 'status':
      return { capture: await getCapture() };
    case 'start': {
      await stopCapture();
      await ensureOffscreen();
      const result = await toOffscreen('start', { streamId: msg.streamId, settings: await loadSettings() });
      if (result?.ok) await chrome.storage.session.set({ capture: { tabId: msg.tabId, title: msg.title } });
      else await stopCapture();
      await updateBadge();
      return result;
    }
    case 'stop':
    case 'capture-ended':
      await stopCapture();
      return { ok: true };
  }
}

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  if (msg.target !== 'background') return;
  handle(msg).then(sendResponse, (err) => sendResponse({ ok: false, error: String(err?.message || err) }));
  return true;
});

// Live parameter changes go straight from storage to the offscreen document.
chrome.storage.onChanged.addListener(async (changes, area) => {
  if (area !== 'local' || !(await offscreenExists())) return;
  toOffscreen('settings', { settings: await loadSettings() }).catch(() => {});
  updateBadge();
});

chrome.tabs.onRemoved.addListener(async (tabId) => {
  if ((await getCapture())?.tabId === tabId) stopCapture();
});
