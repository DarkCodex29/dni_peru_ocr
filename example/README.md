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
  Manages the `CameraController` lifecycle and wires `DniScanner`, which drives
  both sides of the scan internally and reports the final result via
  `onScanComplete`.
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

> **`sensors_plus` build floor (Android):** `DniScanner` reads the IMU, so the
> host needs Java 17, Android Gradle Plugin ≥ 8.12.1, and Gradle ≥ 8.13. This
> example currently pins AGP 8.11.1 — bump it to 8.12.1+ in your own project.
> On iOS no extra `Info.plist` key is required: only the accelerometer and
> gyroscope are read (the barometer, which would need `NSMotionUsageDescription`,
> is never initialized).

## Driving the scan with DniScanner

`DniScanner` owns the entire two-sided flow internally — front capture, the
flip prompt, back capture, and OCR consensus — and reports the final result
through a single `onScanComplete` callback. There is no manual front/back
seeding to wire up.

```dart
DniScanner(
  controller: cameraController,
  fields: widget.fields ?? DniFields.full(),
  autoCaptureMs: 1500,
  manualFallbackMs: 30000,
  onScanComplete: (result) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => ResultScreen(result: result),
    ));
  },
)
```

For a single-side capture, provide `isBackSide` plus `onSideCaptured` instead
of `onScanComplete`. The scanner auto-captures once the document is framed,
still (IMU gate), well-lit (lighting gate), and sharp (post-shutter blur gate);
if auto-capture has not fired after `manualFallbackMs`, a manual capture button
appears so the user is never stuck.

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
│   │   ├── scan_screen.dart   — state machine + camera lifecycle + DniScanner
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
