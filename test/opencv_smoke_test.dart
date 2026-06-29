@Tags(['native'])
library;

import 'package:dartcv4/dartcv.dart' as cv;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('opencv_dart native binding smoke (PR2)', () {
    test('core: Mat.zeros allocates a matrix with the requested shape', () {
      final mat = cv.Mat.zeros(4, 6, cv.MatType.CV_8UC3);
      addTearDown(mat.dispose);

      expect(mat.rows, 4);
      expect(mat.cols, 6);
      expect(mat.channels, 3);
    });

    test('imgproc: cvtColor BGR->GRAY collapses to a single channel', () {
      final bgr = cv.Mat.zeros(4, 6, cv.MatType.CV_8UC3);
      addTearDown(bgr.dispose);

      final gray = cv.cvtColor(bgr, cv.COLOR_BGR2GRAY);
      addTearDown(gray.dispose);

      expect(gray.channels, 1);
      expect(gray.rows, 4);
      expect(gray.cols, 6);
    });
  });
}
