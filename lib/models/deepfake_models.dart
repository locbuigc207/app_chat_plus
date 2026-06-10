// lib/models/deepfake_models.dart
class AudioFeatures {
  final double pitchMean;
  final double pitchVariance;
  final double spectralFlatness;
  final double zeroCrossingRate;
  final double energyVariance;
  final double pauseRatio;
  final List<double> formants;
  final double backgroundNoiseLevel;
  final DateTime capturedAt;

  const AudioFeatures({
    required this.pitchMean,
    required this.pitchVariance,
    required this.spectralFlatness,
    required this.zeroCrossingRate,
    required this.energyVariance,
    required this.pauseRatio,
    required this.formants,
    required this.backgroundNoiseLevel,
    required this.capturedAt,
  });

  Map<String, dynamic> toMap() => {
        'pitchMean': pitchMean,
        'pitchVariance': pitchVariance,
        'spectralFlatness': spectralFlatness,
        'zeroCrossingRate': zeroCrossingRate,
        'energyVariance': energyVariance,
        'pauseRatio': pauseRatio,
        'formants': formants,
        'backgroundNoiseLevel': backgroundNoiseLevel,
        'capturedAt': capturedAt.toIso8601String(),
      };
}

class VoiceBaseline {
  final String callId;
  final List<AudioFeatures> samples;
  final double avgPitch;
  final double avgPitchVariance;
  final double avgSpectralFlatness;
  final DateTime enrolledAt;
  final int enrollDurationMs;

  const VoiceBaseline({
    required this.callId,
    required this.samples,
    required this.avgPitch,
    required this.avgPitchVariance,
    required this.avgSpectralFlatness,
    required this.enrolledAt,
    required this.enrollDurationMs,
  });

  bool get isValid => samples.length >= 2 && enrollDurationMs >= 5000;
}

enum DeepfakeSignal {
  pitchAnomalous,
  spectralFlat,
  pauseUnnatural,
  formantInconsistent,
  backgroundArtifact,
  voiceprintMismatch,
  transcriptAnomaly,
}

enum DeepfakeSource { local, cloud, combined }

enum EnrollmentStatus { notStarted, enrolling, enrolled, insufficient }

class DeepfakeAnalysisResult {
  final bool isLikelyDeepfake;
  final double confidenceScore;
  final List<DeepfakeSignal> signals;
  final String explanation;
  final DeepfakeSource source;
  final Map<DeepfakeSignal, double> signalWeights;

  const DeepfakeAnalysisResult({
    required this.isLikelyDeepfake,
    required this.confidenceScore,
    required this.signals,
    required this.explanation,
    required this.source,
    this.signalWeights = const {},
  });

  factory DeepfakeAnalysisResult.safe() => const DeepfakeAnalysisResult(
        isLikelyDeepfake: false,
        confidenceScore: 0.0,
        signals: [],
        explanation: '',
        source: DeepfakeSource.local,
      );

  bool get isHighConfidence => confidenceScore >= 0.75;
  bool get isMediumConfidence =>
      confidenceScore >= 0.45 && confidenceScore < 0.75;
}
