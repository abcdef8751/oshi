# Oshi

Screen OCR + translation overlay for Android. Tap the notification-shade
shortcut (or the Quick Settings tile), drag a box over any text, and read it in
your language — transcribed and translated by `gemini-3.5-flash-lite` in a
single multimodal call.

Personal sideload build. Android 11 (API 30) and up.

## Setup

```sh
cp .env.example .env            # then paste your Google AI Studio key
flutter pub get
flutter build apk --debug       # or: flutter run -d <device>
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

`.env` is gitignored but ships as a bundled asset, so it must exist at build
time.

On the device:

1. Open Oshi → **Enable capture** → turn on the *Oshi capture* accessibility
   service. (It only takes screenshots on demand; window content is not read.)
2. **Allow** the floating overlay (*Display over other apps*) so captures render
   on top of whatever you are reading instead of opening Oshi. Without it, Oshi
   falls back to a foreground activity and returns you to your app afterwards.
3. **Add the Quick Settings tile** (optional but recommended).
4. Tap the ongoing notification, or the tile, and drag over the text.

## Architecture

```
notification / QS tile
        │
        ▼
CaptureTriggerActivity (native, no UI)
  · waits 400 ms for the shade to collapse (one retry)
  · AccessibilityService.takeScreenshot()
  · PNG → cacheDir/captures/latest.png
        │
        ├─ overlay permitted ──────────────► CaptureActivity
        │                                    transparent, own task,
        │                                    excluded from recents, no animation
        │                                    · crop UI paints over your app
        │                                    · result sheet floats over it (dimmed)
        │                                    · finishing returns to your app
        │
        └─ no permission ─────────────────► MainActivity with the path
                                             · returns you to your app on dismiss
        │
        ▼
Flutter: CropScreen (frozen screenshot, drag a rect)
        ▼
GeminiFlashLiteTranslator.analyzeImage  →  ResultSheet
  (original ⇄ translation, copy, target language, text-only retranslate)
```

- `lib/core` — settings, theme, language list (shared contracts).
- `lib/data` — Gemini REST client, prompt builders, models.
- `lib/services` — `Translator` interface + Gemini implementation.
- `lib/features` — crop overlay, result sheet, settings screen.
- `lib/overlay` — the overlay UI (`CaptureActivity` starts the app on the
  `/capture` route) and its channel (`oshi/overlay`).
- `android/.../kotlin/dev/rp/oshi` — accessibility service, trigger activity,
  tile service, notification/boot receiver, method-channel handler.

Frozen interfaces and ownership boundaries live in
[`docs/contracts.md`](docs/contracts.md).

## Tests

```sh
flutter test
flutter analyze
```

Unit coverage: crop geometry math, Gemini request/response parsing (incl.
fenced JSON and error mapping), prompt builders, language list.
Widget coverage: crop screen export, result sheet toggle/copy/cache, language
bar, settings screen.

## Manual acceptance checklist (the part tests cannot cover)

[`docs/device-checklist.md`](docs/device-checklist.md) — notification-tap
timing on the target device, QS tile from a partially collapsed shade, secure
windows, rotation mid-crop, boot re-post, 429 handling, airplane mode, and
verifying that retranslate sends no `inlineData`.

## Known limits

- The API key is extractable from the APK. Acceptable for a personal sideload;
  do not publish this build.
- Free-tier Gemini quotas change without notice; 429s surface inline with
  Gemini's `RetryInfo` delay.
- Source language is always auto-detected. A manual override is a later toggle.
