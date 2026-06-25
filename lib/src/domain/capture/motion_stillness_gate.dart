abstract class MotionStillnessGate {
  static const double accelStillnessThreshold = 0.6;
  static const double gyroStillnessThreshold = 0.4;
  static const int emaWindow = 5;

  bool get isStill;

  Stream<bool> watchStillness();

  void dispose();
}
