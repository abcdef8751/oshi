# Oshi — frozen contracts (v1)

Everything in this file is **frozen**. Workers code against it and must not
change it. If something here cannot work, stop and report instead of editing it.

Ownership is exclusive: a worker only writes files inside its own owned paths.
Shared files (`pubspec.yaml`, `lib/core/*`, `lib/data/models.dart`,
`lib/services/translator.dart`, `lib/native/capture_channel.dart`,
`android/app/src/main/AndroidManifest.xml`, `MainActivity.kt`,
`CapturePending.kt`, `android/app/build.gradle.kts`, `res/values/styles.xml`)
belong to the orchestrator. Never edit them.

## Shared value types (already on main)

`lib/data/models.dart`

```dart
class ScanResult {
  const ScanResult({required this.detectedLanguage, required this.originalText, required this.translation});
  final String detectedLanguage; // BCP-47, e.g. "ja"
  final String originalText;
  final String translation;
  bool get isTranslationIdentical;         // translation.trim() == originalText.trim()
  ScanResult withTranslation(String t);
  factory ScanResult.fromJson(Map<String, dynamic> json);
  Map<String, dynamic> toJson();
}
```

`lib/services/translator.dart`

```dart
enum TranslatorErrorKind { badRequest, rateLimited, network, server, unknown }

class TranslatorException implements Exception {
  const TranslatorException(this.kind, this.message, {this.retryAfter});
  final TranslatorErrorKind kind;
  final String message;
  final Duration? retryAfter;
}

abstract class Translator {
  Future<ScanResult> analyzeImage(Uint8List png, {required String targetCode, required String targetName});
  Future<String> translateText(String originalText, {required String targetCode, required String targetName});
}

const String kProviderLabel = 'Gemini 3.5 Flash-Lite';
```

`lib/core/languages.dart`

```dart
class AppLanguage { const AppLanguage(this.code, this.name, this.nativeName);
  final String code, name, nativeName; }          // value equality on code
const List<AppLanguage> kLanguages;                // 31 entries, English first
const AppLanguage kEnglish;
AppLanguage languageForCode(String? code);         // never null, falls back to kEnglish
String detectedLanguageLabel(String code);         // endonym for the chip, e.g. "日本語"
```

`lib/core/settings.dart`

```dart
class Settings extends ChangeNotifier {
  static Future<Settings> load();
  factory Settings.memory({String targetLangCode = 'en', bool notificationEnabled = true,
                           bool tilePromptShown = false});
  String get targetLangCode;      Future<void> setTargetLangCode(String code);
  bool   get notificationEnabled; Future<void> setNotificationEnabled(bool enabled);
  bool   get tilePromptShown;     Future<void> setTilePromptShown(bool shown);
}
```

`lib/native/capture_channel.dart`

```dart
class CaptureErrorCodes { static const secureWindow='SECURE_WINDOW';
  static const noAccessibilityAccess='NO_ACCESSIBILITY_ACCESS';
  static const intervalTimeShort='INTERVAL_TIME_SHORT';
  static const internalError='INTERNAL_ERROR'; }

class PendingCapture { const PendingCapture({this.path, this.error});
  final String? path; final String? error; bool get isEmpty; }

class CaptureChannel {                              // non-final, tests subclass it
  CaptureChannel({MethodChannel? channel});
  Future<bool> isAccessibilityEnabled();
  Future<void> openAccessibilitySettings();
  Future<String> takeScreenshot();                  // throws PlatformException(CaptureErrorCodes.*)
  Future<void> postNotification();
  Future<void> cancelNotification();
  Future<bool> isTileAdded();
  Future<void> openTileSettings();
  Future<PendingCapture> getPendingCapture();       // drains native hand-off
  void setCaptureAvailableHandler(void Function() handler);
}
```

## Feature contracts

### A. Crop feature — `lib/features/capture/`

```dart
// crop_geometry.dart
const double kMinCropSize = 48;

enum CropHandle { topLeft, topRight, bottomLeft, bottomRight, move }

Rect rectFromPoints(Offset a, Offset b);                    // handles inverted drags
Rect clampSelection(Rect rect, Size bounds, {double minSize = kMinCropSize});
Rect resizeSelection({required Rect selection, required CropHandle handle,
    required Offset delta, required Size bounds, double minSize = kMinCropSize});
bool shouldUpscale(double cropWidth);                       // < 800
int upscaleFactor(double cropWidth);                        // 2 or 1

class CropTransform {
  const CropTransform({required this.scale, required this.offset});
  final double scale;   // image px per logical px
  final Offset offset;  // top-left of the drawn image in the viewport
  Offset toImage(Offset local);
  Offset toView(Offset image);
  Rect toImageRect(Rect viewRect);
  static CropTransform fitContain(Size image, Size viewport); // BoxFit.contain
}
```

```dart
// crop_screen.dart
class CropScreen extends StatefulWidget {
  const CropScreen({super.key, required this.screenshotPath, this.upscaleThreshold = 800});
  final String screenshotPath;
  // Pushed as a route. Pops `Uint8List?`: PNG bytes of the selection, or null on
  // cancel. Export = crop at image resolution, 2x (cubic) when the crop is
  // narrower than the threshold, then PNG encode.
}
```

Behaviour: full-bleed screenshot, dim `0x99000000` outside the rect, 1px accent
border (`AppTheme.accent`), 4 corner handles with >= 24dp hit slop, drag inside
moves (clamped), drag outside starts a new rect, top bar `Cancel` / `Use`
(`Use` disabled until a valid selection >= kMinCropSize exists), bottom hint
"Drag to select text". Selection defaults to a centred rect ~80% of the screen.
Must handle rotation and very large screenshots without OOM (decode at device
resolution; don't decode twice).

### B. Gemini data layer — `lib/data/gemini_client.dart`, `lib/data/prompts.dart`, `lib/services/gemini_translator.dart`

```dart
// prompts.dart
String buildAnalyzePrompt({required String targetName, required String targetCode});
String buildTranslatePrompt({required String targetName, required String targetCode});
const Map<String, dynamic> kAnalyzeResponseSchema;

// gemini_client.dart
class GeminiClient {
  GeminiClient({required String apiKey, http.Client? httpClient,
      Duration timeout = const Duration(seconds: 30), Uri? baseUri});
  Future<Map<String, dynamic>> generateContent({
    required List<Map<String, dynamic>> parts,        // raw Gemini parts
    Map<String, dynamic>? generationConfig,
  });
}
/// Parses the model's JSON (tolerating ```/```json fences) into a ScanResult.
ScanResult parseScanResult(String rawModelText);

// gemini_translator.dart
class GeminiFlashLiteTranslator implements Translator {
  GeminiFlashLiteTranslator({required String apiKey, http.Client? httpClient,
      Duration timeout = const Duration(seconds: 30), Uri? baseUri});
  // both Translator methods; image downscaled to <= 1536px long edge before send.
}
```

Rules: raw `http`, model `gemini-3.5-flash-lite`, header `x-goog-api-key`.
`generateContent` maps status codes to `TranslatorException`
(400 -> badRequest, 429 -> rateLimited + `RetryInfo` delay when parseable,
network/timeout -> network, 5xx -> server, unparseable -> unknown). One
automatic retry on 5xx/timeout only. Analyze returns
`detected_language`/`original_text`/`translation`; retranslate is text-only
(never sends `inlineData`) and returns just the translation string.

### C. Result sheet — `lib/features/result/`

```dart
// result_sheet.dart
Future<void> showResultSheet(
  BuildContext context, {
  required Translator translator,
  required ValueNotifier<AppLanguage> targetLanguage,
  Uint8List? imagePng,        // required when initialResult == null
  ScanResult? initialResult,  // session cache: render immediately, no analyze call
  ValueChanged<ScanResult>? onResult, // fired when an analyze call succeeds
});

class ResultSheet extends StatefulWidget {          // public for widget tests
  const ResultSheet({super.key, required this.translator, required this.targetLanguage,
      this.imagePng, this.initialResult, this.onResult});
}
```

```dart
// language_bar.dart
class LanguageBar extends StatelessWidget {
  const LanguageBar({super.key, required this.targetLanguage,
      required this.onRetranslate, this.busy = false});
  final ValueNotifier<AppLanguage> targetLanguage;
  final VoidCallback onRetranslate;
  final bool busy;
}
```

Behaviour: modal sheet, max height 85%, scrollable, header = detected chip +
`kProviderLabel`; body `SelectableText` of the currently shown variant; actions
`Copy` (current variant, brief "Copied" feedback, sheet stays open) and
`Original`/`Translation` toggle (hidden when `isTranslationIdentical`); language
bar pinned at the bottom (`Auto` disabled, target picker from `kLanguages`,
reload icon). A target-language change triggers text-only retranslate with a
per-sheet cache keyed `(originalText, targetCode)` and keeps the old text
visible with a subtle progress indicator; errors render inline with `Retry`.
`imagePng == null && initialResult == null` is an assertion error.

### D. Settings screen — `lib/features/settings/settings_screen.dart`

```dart
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.settings, required this.captureChannel});
  final Settings settings;
  final CaptureChannel captureChannel;
}
```

Rows: accessibility status + "Enable capture" (`openAccessibilitySettings`);
tile status using `isTileAdded()` (`Add tile` -> `openTileSettings`, remember
`tilePromptShown`); default target language picker (writes
`setTargetLangCode`); notification switch (`postNotification` /
`cancelNotification` + `setNotificationEnabled`); a short privacy note (text
never leaves the device except to Gemini). Any pending async platform call must
not break layout; show a `CircularProgressIndicator` only inline.

### E. Native capture — `android/app/src/main/kotlin/dev/rp/oshi/`

Owned files: `CaptureAccessibilityService.kt`, `CaptureTriggerActivity.kt`,
`CaptureTileService.kt`, `BootReceiver.kt`, `CaptureChannelHandler.kt`, plus any
new helpers you add in that directory (e.g. `ScreenshotStore.kt`). Also
`android/app/src/main/res/drawable/*` and a **new** file
`android/app/src/main/res/values/strings_capture.xml` if you need strings.

Frozen bridge (already written by the orchestrator, do not modify):

```kotlin
object CapturePending {                       // CapturePending.kt
  const val EXTRA_CAPTURE_PATH; const val EXTRA_CAPTURE_ERROR
  fun set(path: String?, error: String? = null)
  fun hasPending(): Boolean
  fun drain(): Pair<String?, String?>?        // consumes
}

class MainActivity : FlutterActivity() {      // MainActivity.kt
  // calls CaptureChannelHandler(this, flutterEngine) in configureFlutterEngine
  // calls handler.notifyCaptureAvailable() when an intent carries a capture
}
```

`CaptureChannelHandler` must therefore be constructible as
`CaptureChannelHandler(activity: Activity, engine: FlutterEngine)`, register
itself as the handler for channel `oshi/capture` in its constructor, and expose
`fun notifyCaptureAvailable()`.

Channel methods it must implement: `isAccessibilityEnabled`, `openAccessibilitySettings`,
`takeScreenshot` (returns String path; throws `PlatformException` with codes
`SECURE_WINDOW` / `NO_ACCESSIBILITY_ACCESS` / `INTERVAL_TIME_SHORT` /
`INTERNAL_ERROR`), `postNotification`, `cancelNotification`, `isTileAdded`,
`openTileSettings`, `getPendingCapture` (returns `mapOf("path" to ..., "error" to ...)`
or empty map; drains `CapturePending`). It also invokes `onCaptureAvailable`
on Dart when a capture arrives.

`CaptureTriggerActivity`: translucent, no UI, excludes itself from recents,
waits 400 ms (retry once at +400 ms on `ERROR_TAKE_SCREENSHOT_INTERVAL_TIME_SHORT`),
captures via the active service instance, writes PNG to `cacheDir/captures/latest.png`,
then starts `MainActivity` with `CapturePending.EXTRA_CAPTURE_PATH` (or
`EXTRA_CAPTURE_ERROR`) using `FLAG_ACTIVITY_NEW_TASK | FLAG_ACTIVITY_SINGLE_TOP`
and `finish()`.

Method channel name: `oshi/capture`. Notification id/constants are yours.

## Commands

- `flutter analyze` must be clean.
- `flutter test` must pass (your own tests; other features may not exist yet).
- `flutter build apk --debug` for native work (Android SDK 36 is installed).
- Copy `/home/rp/oshi/.env` into your worktree if you need a live API call;
  never commit it, never print the key.

## Git rules

Commit small, on your own branch, frequently. Never `git push`, never merge,
never rebase, never touch another worker's files or the files listed as shared
at the top.
