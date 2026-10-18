// Captured tab audio → Signalsmith Stretch (WASM AudioWorklet) → speakers.
// Capturing the tab mutes its normal output, so only the processed audio is heard.
import SignalsmithStretch from './vendor/SignalsmithStretch.mjs';
import { totalSemitones } from './settings.js';

// Load the worklet from the packaged file; the library's default blob: URL is blocked by MV3 CSP.
SignalsmithStretch.moduleUrl = new URL('vendor/SignalsmithStretch.mjs', location.href).href;

let session = null; // { stream, ctx, stretch }

function applySettings(settings) {
  if (!session) return;
  session.stretch.schedule({ active: true, semitones: totalSemitones(settings) });
}

async function start(streamId, settings) {
  stop();
  const stream = await navigator.mediaDevices.getUserMedia({
    audio: { mandatory: { chromeMediaSource: 'tab', chromeMediaSourceId: streamId } },
  });
  const ctx = new AudioContext({ latencyHint: 'interactive' });
  const stretch = await SignalsmithStretch(ctx);
  ctx.createMediaStreamSource(stream).connect(stretch);
  stretch.connect(ctx.destination);
  session = { stream, ctx, stretch };
  applySettings(settings);
  stretch.start();

  // Tab closed or navigated away: tell the background so the popup shows it as off.
  stream.getAudioTracks()[0]?.addEventListener('ended', () => {
    stop();
    chrome.runtime.sendMessage({ target: 'background', type: 'capture-ended' });
  });
  return { ok: true, latencyMs: Math.round(((await stretch.latency()) + ctx.baseLatency) * 1000) };
}

function stop() {
  if (!session) return;
  session.stream.getTracks().forEach((t) => t.stop());
  session.ctx.close();
  session = null;
}

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  if (msg.target !== 'offscreen') return;
  switch (msg.type) {
    case 'start':
      start(msg.streamId, msg.settings).then(sendResponse, (err) =>
        sendResponse({ ok: false, error: String(err?.message || err) }),
      );
      return true;
    case 'settings':
      applySettings(msg.settings);
      sendResponse({ ok: true });
      break;
    case 'stop':
      stop();
      sendResponse({ ok: true });
      break;
  }
});
