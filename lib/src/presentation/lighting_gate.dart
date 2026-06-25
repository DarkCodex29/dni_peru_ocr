import '../domain/entities/validation_gate.dart';

class LightingResult {
  const LightingResult({
    required this.isValid,
    required this.meanLuminance,
    required this.saturatedFraction,
    this.failing,
  });

  final bool isValid;
  final double meanLuminance;
  final double saturatedFraction;
  final ValidationGate? failing;
}

class LightingGate {
  const LightingGate._();

  static const double minLuminance = 40;
  static const double maxLuminance = 235;
  static const double maxSaturatedFraction = 0.10;
  static const int saturatedLevel = 250;
  static const int sampleStride = 1;

  static LightingResult evaluate(List<int> luminance) {
    if (luminance.isEmpty) {
      return const LightingResult(
        isValid: false,
        meanLuminance: 0,
        saturatedFraction: 0,
        failing: ValidationGate.lighting,
      );
    }

    var sum = 0;
    var saturated = 0;
    var sampled = 0;
    for (var i = 0; i < luminance.length; i += sampleStride) {
      final value = luminance[i];
      sum += value;
      if (value >= saturatedLevel) saturated++;
      sampled++;
    }

    final mean = sum / sampled;
    final saturatedFraction = saturated / sampled;

    if (mean < minLuminance || mean > maxLuminance) {
      return LightingResult(
        isValid: false,
        meanLuminance: mean,
        saturatedFraction: saturatedFraction,
        failing: ValidationGate.lighting,
      );
    }

    if (saturatedFraction > maxSaturatedFraction) {
      return LightingResult(
        isValid: false,
        meanLuminance: mean,
        saturatedFraction: saturatedFraction,
        failing: ValidationGate.glare,
      );
    }

    return LightingResult(
      isValid: true,
      meanLuminance: mean,
      saturatedFraction: saturatedFraction,
    );
  }
}
