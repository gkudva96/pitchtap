import { DEFAULTS, loadSettings, saveSettings, totalSemitones } from './settings.js';

const $ = (id) => document.getElementById(id);
const statusEl = $('status');
let settings = { ...DEFAULTS };
let tab = null;
let capture = null; // { tabId, title } of the tab being shifted
let latencyMs = null;
let error = null;
let busy = false; // a start or stop is in progress; the controls that trigger one are locked

const toBackground = (type, data = {}) => chrome.runtime.sendMessage({ target: 'background', type, ...data });

// Chrome refuses to capture its own pages and the Web Store.
const capturable = (t) => /^(https?|file):/.test(t?.url ?? '') && !/^https:\/\/chromewebstore\.google\.com\//.test(t.url);

const signed = (n) => `${n >= 0 ? '+' : ''}${n}`;

function render() {
  $('enabled').checked = settings.enabled;
  $('enabled').disabled = busy;
  $('move').disabled = busy;
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
    const semis = totalSemitones(settings);
    text = `Shifting ${signed(Number.isInteger(semis) ? semis : semis.toFixed(2))} st in ${where}` +
      (latencyMs ? ` · ~${latencyMs} ms delay` : '');
  } else if (capturable(tab)) text = 'Starting…'; // captureThisTab is running
  else if (!tab?.url) text = "Chrome didn't let PitchTap see this tab. Click the PitchTap icon while you're on the tab that's playing.";
  else text = "Chrome doesn't let extensions capture this page (New Tab, Settings and the Web Store, for example). " +
    'Go to the tab that\'s playing and click PitchTap there.';
  statusEl.textContent = text;
  statusEl.classList.toggle('error', !!error || (settings.enabled && !capture && !capturable(tab)));
}

// Tab capture is only allowed right after the user opens the popup on that tab.
async function captureThisTab() {
  if (busy) return;
  busy = true;
  error = null;
  render();
  try {
    const streamId = await chrome.tabCapture.getMediaStreamId({ targetTabId: tab.id });
    const result = await toBackground('start', { streamId, tabId: tab.id, title: tab.title });
    if (!result?.ok) throw new Error(result?.error || 'Capture failed');
    capture = { tabId: tab.id, title: tab.title };
    latencyMs = result.latencyMs;
  } catch (err) {
    console.error('PitchTap: capture failed', err);
    error = `Couldn't capture this tab: ${err.message}`;
  } finally {
    busy = false;
    render();
  }
}

async function stopCapture() {
  if (busy) return;
  busy = true;
  render();
  try {
    const result = await toBackground('stop');
    if (!result?.ok) throw new Error(result?.error || 'Stop failed');
    capture = null;
  } catch (err) {
    console.error('PitchTap: stop failed', err);
    error = `Couldn't switch off: ${err.message}`;
  } finally {
    busy = false;
    render();
  }
}

async function syncCapture() {
  if (!settings.enabled && capture) await stopCapture();
  else if (settings.enabled && !capture && capturable(tab)) await captureThisTab();
  render();
}

async function update(patch) {
  settings = { ...settings, ...patch };
  if ('enabled' in patch) error = null;
  render();
  try {
    await saveSettings(settings);
    if ('enabled' in patch) await syncCapture();
  } catch (err) {
    console.error('PitchTap: update failed', err);
    error = `Something went wrong: ${err.message}`;
    render();
  }
}

$('enabled').addEventListener('change', (e) => update({ enabled: e.target.checked }));
for (const id of ['semitones', 'cents']) {
  $(id).addEventListener('input', (e) => update({ [id]: Number(e.target.value) }));
}
$('reset').addEventListener('click', () => update({ semitones: 0, cents: 0 }));
$('move').addEventListener('click', () => captureThisTab());

(async () => {
  try {
    [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    settings = await loadSettings();
    ({ capture = null } = (await toBackground('status')) ?? {});
  } catch (err) {
    console.error('PitchTap: popup failed to load', err);
    error = `PitchTap couldn't load: ${err.message}`;
  }
  render();
  if (!error) await syncCapture(); // resume if it was left on
})();
