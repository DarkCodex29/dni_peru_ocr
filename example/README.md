# dni_peru_ocr — Example App

Runnable example for the `dni_peru_ocr` Flutter library. It demonstrates the
complete DNI capture flow — front scan, back scan with field seeding, and result
display — on a real Android or iOS device.

## Quick start

```bash
cd example
flutter pub get
flutter run -d <your-physical-device>
```

> **Physical device required.** ML Kit's text recognition and the camera stream
> do not work on Android Emulator or iOS Simulator. Connect a real device before
> running.

## What the app demonstrates

- **HomeScreen** — entry point with a single "Start Scan" call-to-action.
- **ScanScreen** — front-side then back-side capture driven by a small state
  machine (`initializing → frontCapturing → backCapturing → backComplete`).
  Manages the `CameraController` lifecycle and wires `DniCameraMask` for both
  sides, including the `frontSideFields` seeding pattern.
- **ResultScreen** — displays all seven extracted DNI fields (`documentNumber`,
  `firstName`, `lastName`, `secondLastName`, `dateOfBirth`, `expirationDate`,
  `address`) with per-field confidence indicators.
- **ErrorScreen** — handles the four failure paths: document expiration, capture
  cancellation, camera permission denial, and camera initialization failure.

## Required permissions

Both platforms are already configured in this example. For your own app:

**Android** — add to `android/app/src/main/AndroidManifest.xml` before
`<application>`:

```xml
<uses-permission android:name="android.permission.CAMERA"/>
```

Also ensure `minSdkVersion 21` (or higher) in your `build.gradle`.

**iOS** — add to `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Camera access required to scan Peruvian DNI documents.</string>
```

Also ensure `platform :ios, '12.0'` (or higher) in your `Podfile`.

## Android release builds

The example ships with ProGuard rules already configured in
`android/app/proguard-rules.pro` and minification enabled in
`android/app/build.gradle.kts`. Without these, R8 fails the release build
because `google_mlkit_text_recognition` references script-specific
recognizer options (Chinese, Devanagari, Japanese, Korean) that the
package does not bundle when only the Latin recognizer is used.

If you adapt this example into your own app, copy
`example/android/app/proguard-rules.pro` and the matching `release` block
of `build.gradle.kts` over. See the root README's *Android release builds*
section for the rules and a build snippet.

## The frontSideFields seeding pattern

This is the most important integration detail. When the user scans the front
side of the DNI, `DniCameraMask` progressively accumulates OCR fields and
delivers them via `onFrontSideOcrUpdated`. You **must persist those fields in
your own state** and pass them back as `frontSideFields` when mounting the
back-side widget.

```dart
// In your StatefulWidget state:
OcrExtractedFields? _frontFields;

// Front-side widget — accumulate fields as they come in:
DniCameraMask(
  controller: cameraController,
  isBackSide: false,
  onValidCapture: (file, consensus) {
    setState(() => _step = ScanStep.backCapturing);
  },
  onFrontSideOcrUpdated: (fields) {
    // Store the latest snapshot — no setState needed, it's just state.
    _frontFields = fields;
  },
  onDocumentExpired: (_) => _goToError(),
),

// Back-side widget — seed with the accumulated front fields:
DniCameraMask(
  controller: cameraController,
  isBackSide: true,
  frontSideFields: _frontFields,   // <-- the seeding step
  onValidCapture: (file, consensus) {
    if (consensus != null) {
      // consensus is populated only on the back side.
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => ResultScreen(result: consensus),
      ));
    }
  },
  onDocumentExpired: (_) => _goToError(),
),
```

**Why does this matter?** Flutter destroys the widget `State` when the host
swaps from front-side to back-side (e.g. via a `switch` over an enum step). The
back-side accumulator starts empty by default, which means it reads the MRZ and
text fields from scratch and may need more frames to reach consensus. By passing
`frontSideFields`, the library pre-loads the MRZ hypotheses gathered during the
front scan, allowing the back-side accumulator to reach high confidence in fewer
frames.

## Project structure

```
example/
├── pubspec.yaml
├── lib/
│   ├── main.dart              — app entry point and MaterialApp setup
│   ├── theme/
│   │   └── app_theme.dart     — Material 3 theme (ColorScheme.fromSeed, indigo)
│   ├── screens/
│   │   ├── home_screen.dart   — entry CTA
│   │   ├── scan_screen.dart   — state machine + camera lifecycle + DniCameraMask
│   │   ├── result_screen.dart — field display with confidence badges
│   │   └── error_screen.dart  — failure handling (expired/cancelled/permission/init)
│   └── widgets/
│       ├── primary_button.dart    — filled button wrapper
│       ├── loading_overlay.dart   — full-screen loading indicator
│       ├── confidence_badge.dart  — colored chip (red/amber/green by confidence)
│       └── field_card.dart        — label + value + ConfidenceBadge
└── android/
└── ios/
```

## Customizing

The example uses `ColorScheme.fromSeed(seedColor: Colors.indigo)` defined in
`lib/theme/app_theme.dart`. To use your own brand color, change `Colors.indigo`
to any `Color` constant and run `flutter pub get && flutter run`.
