# Device acceptance checklist (v1)

Automated tests cover geometry, parsing and widget behaviour. These are the
things only a real phone can answer. Work through them in order — the first two
decide whether the whole design works.

Build and install:

```sh
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

Setup on the device: open Oshi → **Enable capture** → turn on *Oshi capture* in
Settings → Accessibility. Grant **Floating overlay** (*Display over other apps*)
from Oshi's settings. Optionally **Add the Quick Settings tile**.

## 1. Shade timing (tune `SHADE_COLLAPSE_DELAY_MS`)

Open a page with dense text (a news article). Pull down the shade, tap the
ongoing **Capture text** notification, and drag a box.

- [ ] No notification-shade pixels appear in the frozen screenshot.
- [ ] The crop screen appears without a flash of the app's own UI.
- [ ] If the shade was still animating, try 500–600 ms in
      `CaptureTriggerActivity.kt` (`SHADE_COLLAPSE_DELAY_MS`). The code retries
      once on `ERROR_TAKE_SCREENSHOT_INTERVAL_TIME_SHORT`.

## 1b. Floating overlay

- [ ] With the overlay granted, open another app (a browser, a chat), tap the
      notification: the crop screen appears over it, the result sheet floats
      over your app (dimmed), and dismissing returns you straight to it —
      Oshi's own UI never appears.
- [ ] The overlay paints edge to edge (no black bars, no status-bar gap) and
      the crop/result UI is fully touchable.
- [ ] The capture does not leave an entry in the recents/app switcher.
- [ ] Rotate while the overlay is up: the crop screen reflows and the selection
      stays usable.
- [ ] Copy from the result sheet lands on the clipboard (it goes through
      `oshi/overlay`'s native handler).
- [ ] Revoke *Display over other apps*: the next capture falls back to the
      foreground activity (Oshi opens, then returns you when you dismiss).
- [ ] Overlay survives ten captures in a row without the engine dying or the
      window leaking.

## 2. Quick Settings tile

- [ ] Tile tap captures correctly from a fully expanded shade.
- [ ] Tile tap captures correctly from a **partially collapsed** shade.
- [ ] Tile works while a full-screen video is playing (the video frame, not
      the player controls, is captured).

## 3. Cropping

- [ ] Drag a new rectangle in every direction; edges snap inside the screen.
- [ ] Drag inside the rectangle to move it; it cannot leave the screen.
- [ ] Corner handles respond with ~24 dp of slop (fingers are fat).
- [ ] Rotate during the crop screen; the selection survives and stays usable.
- [ ] Cancel returns to whatever was underneath.
- [ ] Tiny text (< 800 px wide crop) is exported at 2× and reads better.

## 4. Translation

- [ ] Japanese → English: transcription matches the screen exactly, line
      breaks preserved.
- [ ] Change the target language in the sheet: text updates without a new
      screenshot, and logcat shows no `inlineData` in the second request:

      adb logcat | grep -i generativelanguage   # or watch your proxy

- [ ] Switching back to a previous language is instant (per-sheet cache).
- [ ] Copy copies the variant currently on screen; the sheet stays open.
- [ ] When source and target are the same language, the toggle is absent.

## 5. Failure states

- [ ] Open a banking app or DRM video, capture: "This screen is protected
      (DRM / banking app)", no crash.
- [ ] Disable the accessibility service, capture: the dialog offers
      *Open settings* and lands on the right page.
- [ ] Airplane mode, capture: inline "No connection" with Retry; nothing hangs
      past the 30 s timeout.
- [ ] Burn the free tier (15 requests in a minute): 429 shows the RetryInfo
      delay when present, and Retry works after the wait.
- [ ] Kill the app process, then tap the notification: the app starts, the
      capture still arrives.

## 6. Persistence

- [ ] Reboot the phone: the ongoing notification comes back (if enabled in
      Settings); the tile stays added.
- [ ] Force-stop Oshi, relaunch: the notification is re-posted.
- [ ] Toggle the notification off in Settings: it disappears immediately and
      does not come back after a reboot.
- [ ] Change the default target language in Settings; the next capture uses it.

## 7. Battery-manager sanity (OEM-dependent)

- [ ] After a few hours idle, the ongoing notification is still there and a
      capture still works. If not, exclude Oshi from battery optimisation —
      some OEMs kill accessibility services aggressively.
