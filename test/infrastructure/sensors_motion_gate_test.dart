import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'package:dni_peru_ocr/src/domain/capture/motion_stillness_gate.dart';
import 'package:dni_peru_ocr/src/infrastructure/sensors_motion_gate.dart';

UserAccelerometerEvent _accel(double magnitude) =>
    UserAccelerometerEvent(magnitude, 0, 0, DateTime.now());

GyroscopeEvent _gyro(double magnitude) =>
    GyroscopeEvent(magnitude, 0, 0, DateTime.now());

void main() {
  group('SensorsMotionGate', () {
    test('is a MotionStillnessGate', () {
      final accel = StreamController<UserAccelerometerEvent>();
      final gyro = StreamController<GyroscopeEvent>();
      final gate = SensorsMotionGate(
        accelerometerStream: accel.stream,
        gyroscopeStream: gyro.stream,
      );

      expect(gate, isA<MotionStillnessGate>());

      gate.dispose();
      unawaited(accel.close());
      unawaited(gyro.close());
    });

    test('starts unstable until enough still samples accumulate', () {
      final accel = StreamController<UserAccelerometerEvent>();
      final gyro = StreamController<GyroscopeEvent>();
      final gate = SensorsMotionGate(
        accelerometerStream: accel.stream,
        gyroscopeStream: gyro.stream,
      );

      expect(gate.isStill, isFalse);

      gate.dispose();
      unawaited(accel.close());
      unawaited(gyro.close());
    });

    test('sustained low motion below thresholds becomes still', () async {
      final accel = StreamController<UserAccelerometerEvent>();
      final gyro = StreamController<GyroscopeEvent>();
      final gate = SensorsMotionGate(
        accelerometerStream: accel.stream,
        gyroscopeStream: gyro.stream,
      );

      final emitted = <bool>[];
      final watch = gate.watchStillness().listen(emitted.add);

      for (var i = 0; i < MotionStillnessGate.emaWindow + 2; i++) {
        accel.add(_accel(0.05));
        gyro.add(_gyro(0.05));
        await Future<void>.delayed(Duration.zero);
      }

      expect(gate.isStill, isTrue);
      expect(emitted.last, isTrue);

      await watch.cancel();
      gate.dispose();
      unawaited(accel.close());
      unawaited(gyro.close());
    });

    test('jitter above accel threshold keeps the gate unstable', () async {
      final accel = StreamController<UserAccelerometerEvent>();
      final gyro = StreamController<GyroscopeEvent>();
      final gate = SensorsMotionGate(
        accelerometerStream: accel.stream,
        gyroscopeStream: gyro.stream,
      );

      for (var i = 0; i < MotionStillnessGate.emaWindow + 2; i++) {
        accel.add(_accel(3.0));
        gyro.add(_gyro(0.05));
        await Future<void>.delayed(Duration.zero);
      }

      expect(gate.isStill, isFalse);

      gate.dispose();
      unawaited(accel.close());
      unawaited(gyro.close());
    });

    test('rotation above gyro threshold keeps the gate unstable', () async {
      final accel = StreamController<UserAccelerometerEvent>();
      final gyro = StreamController<GyroscopeEvent>();
      final gate = SensorsMotionGate(
        accelerometerStream: accel.stream,
        gyroscopeStream: gyro.stream,
      );

      for (var i = 0; i < MotionStillnessGate.emaWindow + 2; i++) {
        accel.add(_accel(0.05));
        gyro.add(_gyro(2.0));
        await Future<void>.delayed(Duration.zero);
      }

      expect(gate.isStill, isFalse);

      gate.dispose();
      unawaited(accel.close());
      unawaited(gyro.close());
    });

    test('transition from jitter to stillness flips isStill via EMA decay',
        () async {
      final accel = StreamController<UserAccelerometerEvent>();
      final gyro = StreamController<GyroscopeEvent>();
      final gate = SensorsMotionGate(
        accelerometerStream: accel.stream,
        gyroscopeStream: gyro.stream,
      );

      for (var i = 0; i < MotionStillnessGate.emaWindow; i++) {
        accel.add(_accel(4.0));
        gyro.add(_gyro(0.05));
        await Future<void>.delayed(Duration.zero);
      }
      expect(gate.isStill, isFalse);

      for (var i = 0; i < MotionStillnessGate.emaWindow * 3; i++) {
        accel.add(_accel(0.02));
        gyro.add(_gyro(0.02));
        await Future<void>.delayed(Duration.zero);
      }

      expect(gate.isStill, isTrue);

      gate.dispose();
      unawaited(accel.close());
      unawaited(gyro.close());
    });

    test('dispose stops emitting and closes the stillness stream', () async {
      final accel = StreamController<UserAccelerometerEvent>();
      final gyro = StreamController<GyroscopeEvent>();
      final gate = SensorsMotionGate(
        accelerometerStream: accel.stream,
        gyroscopeStream: gyro.stream,
      );

      var closed = false;
      gate.watchStillness().listen(null, onDone: () => closed = true);

      gate.dispose();
      await Future<void>.delayed(Duration.zero);

      expect(closed, isTrue);

      unawaited(accel.close());
      unawaited(gyro.close());
    });
  });
}
