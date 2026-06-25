import 'dart:async';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';

import '../domain/capture/motion_stillness_gate.dart';

class SensorsMotionGate implements MotionStillnessGate {
  SensorsMotionGate({
    Stream<UserAccelerometerEvent>? accelerometerStream,
    Stream<GyroscopeEvent>? gyroscopeStream,
  })  : _alpha = 2 / (MotionStillnessGate.emaWindow + 1) {
    final accel = accelerometerStream ?? userAccelerometerEventStream();
    final gyro = gyroscopeStream ?? gyroscopeEventStream();
    _accelSub = accel.listen(_onAccel, onError: _onError, cancelOnError: false);
    _gyroSub = gyro.listen(_onGyro, onError: _onError, cancelOnError: false);
  }

  final double _alpha;
  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  StreamSubscription<UserAccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;

  double? _accelEma;
  double? _gyroEma;
  int _samples = 0;
  bool _isStill = false;
  bool _disposed = false;

  @override
  bool get isStill => _isStill;

  @override
  Stream<bool> watchStillness() => _controller.stream;

  void _onAccel(UserAccelerometerEvent event) {
    final magnitude = _magnitude(event.x, event.y, event.z);
    _accelEma = _nextEma(_accelEma, magnitude);
    _evaluate();
  }

  void _onGyro(GyroscopeEvent event) {
    final magnitude = _magnitude(event.x, event.y, event.z);
    _gyroEma = _nextEma(_gyroEma, magnitude);
    _evaluate();
  }

  void _onError(Object _) {}

  double _magnitude(double x, double y, double z) =>
      math.sqrt(x * x + y * y + z * z);

  double _nextEma(double? previous, double sample) =>
      previous == null ? sample : previous + _alpha * (sample - previous);

  void _evaluate() {
    if (_disposed) return;
    _samples++;
    final warmedUp = _samples >= MotionStillnessGate.emaWindow;
    final accelStill = (_accelEma ?? double.infinity) <
        MotionStillnessGate.accelStillnessThreshold;
    final gyroStill = (_gyroEma ?? double.infinity) <
        MotionStillnessGate.gyroStillnessThreshold;
    final next = warmedUp && accelStill && gyroStill;
    if (next != _isStill) {
      _isStill = next;
      _controller.add(next);
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_accelSub?.cancel());
    unawaited(_gyroSub?.cancel());
    unawaited(_controller.close());
  }
}
