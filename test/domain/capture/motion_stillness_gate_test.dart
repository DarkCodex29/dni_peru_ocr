import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:dni_peru_ocr/src/domain/capture/motion_stillness_gate.dart';

class _FakeMotionStillnessGate implements MotionStillnessGate {
  _FakeMotionStillnessGate(Stream<bool> source) {
    _sub = source.listen((value) {
      _isStill = value;
      _controller.add(value);
    });
  }

  final StreamController<bool> _controller = StreamController<bool>.broadcast();
  late final StreamSubscription<bool> _sub;
  bool _isStill = false;

  @override
  bool get isStill => _isStill;

  @override
  Stream<bool> watchStillness() => _controller.stream;

  @override
  void dispose() {
    unawaited(_sub.cancel());
    unawaited(_controller.close());
  }
}

void main() {
  group('MotionStillnessGate contract', () {
    test('isStill reflects the latest emitted stillness value', () async {
      final source = StreamController<bool>();
      final gate = _FakeMotionStillnessGate(source.stream);

      expect(gate.isStill, isFalse);

      source.add(true);
      await Future<void>.delayed(Duration.zero);
      expect(gate.isStill, isTrue);

      source.add(false);
      await Future<void>.delayed(Duration.zero);
      expect(gate.isStill, isFalse);

      gate.dispose();
      await source.close();
    });

    test('watchStillness streams each stillness transition', () async {
      final source = StreamController<bool>();
      final gate = _FakeMotionStillnessGate(source.stream);

      final emitted = <bool>[];
      final watch = gate.watchStillness().listen(emitted.add);

      source.add(true);
      source.add(false);
      source.add(true);
      await Future<void>.delayed(Duration.zero);

      expect(emitted, equals([true, false, true]));

      await watch.cancel();
      gate.dispose();
      await source.close();
    });
  });

  group('MotionStillnessGate jolt thresholds', () {
    test('accelJoltThreshold tolerates hand tremor and only trips on a jolt',
        () {
      expect(MotionStillnessGate.accelJoltThreshold, closeTo(2.5, 1e-9));
    });

    test('gyroJoltThreshold tolerates hand rotation and only trips on a jolt',
        () {
      expect(MotionStillnessGate.gyroJoltThreshold, closeTo(1.5, 1e-9));
    });

    test('jolt thresholds are far more permissive than laboratory stillness',
        () {
      expect(MotionStillnessGate.accelJoltThreshold, greaterThan(0.6));
      expect(MotionStillnessGate.gyroJoltThreshold, greaterThan(0.4));
    });

    test('emaWindow smooths over the documented sample count', () {
      expect(MotionStillnessGate.emaWindow, equals(5));
    });
  });
}
