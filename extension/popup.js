import { DEFAULTS, loadSettings, saveSettings, totalSemitones } from './settings.js';

const $ = (id) => document.getElementById(id);
const statusEl = $('status');
let settings = { ...DEFAULTS };
let tab = null;
let capture = null; // { tabId, title } of the tab being shifted
let latencyMs = null;
let error = null;

const toBackground = (type, data = {}) => chrome.runtime.sendMessage({ target: 'background', type, ...data });

// Chrome refuses to capture its own pages and the Web Store.
const capturable = (t) => /^(https?|file):/.test(t?.url ?? '') && !/^https:\/\/chromewebstore\.google\.com\//.test(t.url);

const signed = (n) => `${n >= 0 ? '+' : ''}${n}`;

function render() {
  $('enabled').checked = settings.enabled;
  $('semitones').value = settings.semitones;
  $('cents').value = settings.cents;
  $('semitones-value').textContent = signed(settings.semitones);
  $('cents-value').textContent = `${signed(settings.cents)} cents`;

  const elsewhere = settings.enabled && capture && capture.tabId !== tab?.id;
  $('move').hidden = !(elsewhere && capturable(tab));

  let text;
  if (error) text = error;
  else if (!settings.enabled) text = 'Off — audio plays normally.';
  else if (capture) {
    const where = capture.tabId === tab?.id ? 'this tab' : `“${capture.title || 'another tab'}”`;
    text = `Shifting ${signed(totalSemitones(settings).toFixed(2))} st in ${where}` +
      (latencyMs ? ` · ~${latencyMs} ms delay` : '');
  } else text = "This page can't be captured. Open the tab you want to shift and click PitchTap there.";
  statusEl.textContent = text;
  statusEl.classList.toggle('error', !!error || (settings.enabled && !capture));
}

// Tab capture is only allowed right after the user opens the popup on that tab.
async function captureThisTab() {
  error = null;
  try {
    const streamId = await chrome.tabCapture.getMediaStreamId({ targetTabId: tab.id });
    const result = await toBackground('start', { streamId, tabId: tab.id, title: tab.title });
    if (!result?.ok) throw new Error(result?.error || 'Capture failed');
    capture = { tabId: tab.id, title: tab.title };
    latencyMs = result.latencyMs;
  } catch (err) {
    error = `Couldn't capture this tab: ${err.message}`;
  }
  render();
}

async function syncCapture() {
  if (!settings.enabled && capture) {
    await toBackground('stop');
    capture = null;
  } else if (settings.enabled && !capture && capturable(tab)) {
    await captureThisTab();
  }
  render();
}

async function update(patch) {
  settings = { ...settings, ...patch };
  render();
  await saveSettings(settings);
  if ('enabled' in patch) await syncCapture();
}

$('enabled').addEventListener('change', (e) => update({ enabled: e.target.checked }));
for (const id of ['semitones', 'cents']) {
  $(id).addEventListener('input', (e) => update({ [id]: Number(e.target.value) }));
}
$('reset').addEventListener('click', () => update({ semitones: 0, cents: 0 }));
$('move').addEventListener('click', captureThisTab);

(async () => {
  [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  settings = await loadSettings();
  ({ capture } = await toBackground('status'));
  render();
  await syncCapture(); // resume if it was left on
})();
