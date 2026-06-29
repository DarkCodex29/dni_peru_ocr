import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dni_peru_ocr/src/presentation/widgets/quad_overlay_painter.dart';

void main() {
  group('mapQuadToPreview — frame px -> preview widget space (BoxFit.cover)', () {
    test('rotation 0, square frame into square preview maps identically', () {
      final mapped = mapQuadToPreview(
        corners: const [
          QuadCorner(0, 0),
          QuadCorner(100, 0),
          QuadCorner(100, 100),
          QuadCorner(0, 100),
        ],
        frameWidth: 100,
        frameHeight: 100,
        rotationDegrees: 0,
        previewSize: const Size(100, 100),
        mirror: false,
      );

      expect(mapped, hasLength(4));
      expect(mapped[0], const Offset(0, 0));
      expect(mapped[1], const Offset(100, 0));
      expect(mapped[2], const Offset(100, 100));
      expect(mapped[3], const Offset(0, 100));
    });

    test('rotation 0 scales and centers a landscape frame into a tall preview '
        'via cover (overflow cropped on the long axis)', () {
      // Frame 200x100 into preview 100x100. cover scale = max(100/200, 100/100)
      // = 1.0. Scaled frame = 200x100, centered: dx=(100-200)/2=-50, dy=0.
      final mapped = mapQuadToPreview(
        corners: const [
          QuadCorner(0, 0),
          QuadCorner(200, 0),
          QuadCorner(200, 100),
          QuadCorner(0, 100),
        ],
        frameWidth: 200,
        frameHeight: 100,
        rotationDegrees: 0,
        previewSize: const Size(100, 100),
        mirror: false,
      );

      expect(mapped[0], const Offset(-50, 0));
      expect(mapped[1], const Offset(150, 0));
      expect(mapped[2], const Offset(150, 100));
      expect(mapped[3], const Offset(-50, 100));
    });

    test('rotation 90 maps a landscape sensor frame upright into a portrait '
        'preview', () {
      // Sensor frame 200x100 rotated 90deg CW becomes upright 100x200, which
      // exactly fills a 100x200 portrait preview (cover scale 1.0, no offset).
      // Rotation 90 CW: (x,y) -> (rotatedW - y, x) where rotatedW = frameHeight.
      final mapped = mapQuadToPreview(
        corners: const [
          QuadCorner(0, 0), // -> (100, 0)
          QuadCorner(200, 0), // -> (100, 200)
          QuadCorner(200, 100), // -> (0, 200)
          QuadCorner(0, 100), // -> (0, 0)
        ],
        frameWidth: 200,
        frameHeight: 100,
        rotationDegrees: 90,
        previewSize: const Size(100, 200),
        mirror: false,
      );

      expect(mapped[0], const Offset(100, 0));
      expect(mapped[1], const Offset(100, 200));
      expect(mapped[2], const Offset(0, 200));
      expect(mapped[3], const Offset(0, 0));
    });

    test('rotation 270 maps a landscape sensor frame upright into a portrait '
        'preview', () {
      // Rotation 270 CW: (x,y) -> (y, rotatedH - x) where rotatedH = frameWidth.
      final mapped = mapQuadToPreview(
        corners: const [
          QuadCorner(0, 0), // -> (0, 200)
          QuadCorner(200, 0), // -> (0, 0)
          QuadCorner(200, 100), // -> (100, 0)
          QuadCorner(0, 100), // -> (100, 200)
        ],
        frameWidth: 200,
        frameHeight: 100,
        rotationDegrees: 270,
        previewSize: const Size(100, 200),
        mirror: false,
      );

      expect(mapped[0], const Offset(0, 200));
      expect(mapped[1], const Offset(0, 0));
      expect(mapped[2], const Offset(100, 0));
      expect(mapped[3], const Offset(100, 200));
    });

    test('rotation 180 flips both axes', () {
      // Rotation 180: (x,y) -> (frameW - x, frameH - y). 100x100 into 100x100.
      final mapped = mapQuadToPreview(
        corners: const [
          QuadCorner(10, 20),
          QuadCorner(90, 20),
          QuadCorner(90, 80),
          QuadCorner(10, 80),
        ],
        frameWidth: 100,
        frameHeight: 100,
        rotationDegrees: 180,
        previewSize: const Size(100, 100),
        mirror: false,
      );

      expect(mapped[0], const Offset(90, 80));
      expect(mapped[1], const Offset(10, 80));
      expect(mapped[2], const Offset(10, 20));
      expect(mapped[3], const Offset(90, 20));
    });

    test('mirror reflects across the preview vertical axis (front camera)', () {
      // Rotation 0, 100x100 into 100x100, mirrored: x -> previewWidth - x.
      final mapped = mapQuadToPreview(
        corners: const [
          QuadCorner(0, 0),
          QuadCorner(100, 0),
          QuadCorner(100, 100),
          QuadCorner(0, 100),
        ],
        frameWidth: 100,
        frameHeight: 100,
        rotationDegrees: 0,
        previewSize: const Size(100, 100),
        mirror: true,
      );

      expect(mapped[0], const Offset(100, 0));
      expect(mapped[1], const Offset(0, 0));
      expect(mapped[2], const Offset(0, 100));
      expect(mapped[3], const Offset(100, 100));
    });

    test('empty corners map to empty list', () {
      final mapped = mapQuadToPreview(
        corners: const [],
        frameWidth: 100,
        frameHeight: 100,
        rotationDegrees: 0,
        previewSize: const Size(100, 100),
        mirror: false,
      );

      expect(mapped, isEmpty);
    });
  });
}
