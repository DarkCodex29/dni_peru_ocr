abstract class MotionStillnessGate {
  static const double accelJoltThreshold = 2.5;
  static const double gyroJoltThreshold = 1.5;
  static const int emaWindow = 5;

  bool get isStill;

  Stream<bool> watchStillness();

  void dispose();
}
