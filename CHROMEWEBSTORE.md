# Chrome Web Store Listing — PitchTap

> Last Updated: 2026-10-19

Everything to paste into the developer dashboard (https://chrome.google.com/webstore/devconsole).
Build the package and images with `store/build.sh` (output in `store/out/`).

## Store Listing

**Extension Name**
PitchTap

**Short Description** (90/132 chars; comes from `extension/manifest.json`)
Change the key of any song in a Chrome tab. Same tempo. Shift live in semitones and cents.

**Detailed Description** (plain text; the store strips Markdown)

```
PitchTap changes the key of whatever a browser tab is playing, live, without changing its speed.

FEATURES
• Shift up or down by up to 12 semitones while the song plays
• Fine-tune by ±50 cents for recordings that aren't at standard pitch
• The tempo never changes, only the key
• A badge on the PitchTap icon shows the current shift at a glance
• Works on most sites that play audio, including video and music streaming sites
• Remembers your settings for next time

GREAT FOR
• Singing along in your own range: drop a song a couple of semitones so the chorus fits your voice
• Practising an instrument: match a song to your tuning, or raise it to play with a capo
• Trying A = 432 Hz (−32 cents) or lining up an old recording with your instrument

HOW TO USE
1. Go to the tab that's playing audio.
2. Click the PitchTap icon in the toolbar (pin it from the puzzle-piece menu so it's always visible).
3. Switch on "Pitch shift" and move the Semitones or Fine tune slider.
4. Switch it off or press Reset to hear the original again.
PitchTap works on one tab at a time. To move it, open the other tab, click the icon and choose "Shift this tab instead".

PRIVACY
The sound is processed on your own computer as it plays. Nothing is recorded, saved or sent anywhere. PitchTap has no account, no ads, no tracking and no access to the content of the pages you visit. Your slider settings are stored only on your computer.

PERMISSIONS
PitchTap only hears a tab after you click its icon on that tab and switch it on. It can't hear any other tab, and it stops when you switch it off or close the tab.

SUPPORT
Questions or problems: [contact email]

Version 0.3.0
```

**Category**: Tools (if the dashboard doesn't offer it, Entertainment)

**Single Purpose**
Changes the pitch (musical key) of the audio playing in a browser tab, in real time, without changing its speed.

**Primary Language**: English

## Graphics & Assets

| Asset | Dimensions | Status | Filename |
|-------|-----------|--------|----------|
| Store Icon | 128×128 PNG | ✅ Ready | `extension/icons/128.png` |
| Screenshot 1 | 1280×800 | ✅ Ready | `store/out/screenshot-1.png` |
| Screenshot 2 | 1280×800 | ✅ Ready | `store/out/screenshot-2.png` |
| Screenshot 3 | 1280×800 | ✅ Ready | `store/out/screenshot-3.png` |
| Screenshot 4 | 1280×800 | ✅ Ready | `store/out/screenshot-4.png` |
| Small Promo Tile | 440×280 | ✅ Ready | `store/out/promo-tile.png` |
| Marquee Promo Tile | 1400×560 | Skipped (optional) | |
| Promo video (YouTube link) | — | ⬜ Owner to record (20–30 s) | |

### Screenshot Notes
Rendered from the real popup (`store/scene.html`, `store/popup-preview.html`) over an invented video site, so no third-party names or logos.
1. Shifting −2 semitones: "Change the key of any song in a Chrome tab."
2. +3 semitones: "Sing it in your range."
3. −32 cents: "Fine-tune to the cent."
4. Switched off: "Private by design."
Re-run `store/build.sh` whenever the popup changes.

## Permissions Justification

| Permission | Type | Justification |
|------------|------|---------------|
| `tabCapture` | permissions | Receives the audio of the one tab the user chooses so PitchTap can change its pitch and play it back. Capture starts only after the user clicks the PitchTap icon on that tab and switches it on, and stops when they switch it off or close the tab. |
| `activeTab` | permissions | Limits PitchTap to the tab the user clicked its icon on, so it needs no access to any website or to browsing history. |
| `offscreen` | permissions | The audio processing runs in a hidden extension page so the music keeps playing at the new pitch after the popup closes. |
| `storage` | permissions | Saves the user's on/off switch, semitone and cents settings on their computer so they're kept between sessions. |

No `host_permissions`, no content scripts.

## Privacy & Data Use

### Data Collection

**Does the extension collect user data?** No

Audio is processed in memory and never stored or transmitted. Settings use `chrome.storage.local` (not `sync`), so nothing leaves the device. The extension makes no network requests.

### Data Use Certification
- [x] Data is NOT sold to third parties
- [x] Data is NOT used for purposes unrelated to the extension's core functionality
- [x] Data is NOT used for creditworthiness or lending purposes

**Remote code:** No. Everything, including the audio engine, is in the package.

## Privacy Policy

**Privacy Policy URL**: ⬜ not hosted yet. Source: `store/privacy.html` (fill in the contact email first). Must be a live public URL before submitting.

## Distribution

**Visibility**: Unlisted for the friends beta, Public later
**Regions**: All regions
**Price**: Free

## Developer Info

**Publisher Name**: ⬜
**Contact Email**: ⬜ (shown publicly; Google sends policy notices here)
**Support URL / Email**: ⬜
**Homepage URL**: ⬜ (optional)

## Version History

| Version | Date | Changes | Status |
|---------|------|---------|--------|
| 0.3.0 | 2026-10-19 | Fixed the audio engine never starting in the installed extension (WebAssembly was blocked). Clearer status messages, a lock against double starts, and error handling throughout. | Draft |

## Review Notes

### Note for the reviewer
`vendor/SignalsmithStretch.mjs` is the published JavaScript/WebAssembly build of Signalsmith Stretch (MIT, https://signalsmith-audio.co.uk/code/stretch/), compiled with Emscripten. It contains its WebAssembly binary inline, which is why it is one long minified line; it is not obfuscated and makes no network requests. The manifest's `'wasm-unsafe-eval'` CSP exists only so this packaged WebAssembly can compile. Licence: `vendor/LICENSE-signalsmith-stretch.txt`.

### Known Issues / Limitations
- One tab at a time.
- Chrome doesn't allow capturing its own pages (New Tab, Settings) or the Chrome Web Store; PitchTap says so in the popup.
- About 120 ms of delay between the original and shifted sound, so video lip-sync is slightly late.

### Rejection History
None yet.
