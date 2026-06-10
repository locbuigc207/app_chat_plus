// lib/services/voice_fingerprint_service.dart
import 'dart:math' as math;

import '../models/deepfake_models.dart';

class VoiceSimilarityResult {
  final double similarity;
  final double pitchScore;
  final double varianceScore;
  final double flatnessScore;
  final bool isMismatch;
  final VoiceBaseline baseline;
  final AudioFeatures liveFeatures;

  const VoiceSimilarityResult({
    required this.similarity,
    required this.pitchScore,
    required this.varianceScore,
    required this.flatnessScore,
    required this.isMismatch,
    required this.baseline,
    required this.liveFeatures,
  });

  double get deepfakeProbability => (1.0 - similarity).clamp(0.0, 1.0);
}

class VoiceFingerprintService {
  VoiceFingerprintService._();
  static final VoiceFingerprintService _instance = VoiceFingerprintService._();
  factory VoiceFingerprintService() => _instance;

  VoiceBaseline? _currentBaseline;
  final List<AudioFeatures> _enrollSamples = [];
  EnrollmentStatus _status = EnrollmentStatus.notStarted;

  static const int _enrollSampleTarget = 4;
  static const double _mismatchThreshold = 0.35;

  EnrollmentStatus get status => _status;
  VoiceBaseline? get baseline => _currentBaseline;

  void reset() {
    _currentBaseline = null;
    _enrollSamples.clear();
    _status = EnrollmentStatus.notStarted;
  }

  bool addEnrollSample(AudioFeatures features, String callId) {
    if (_status == EnrollmentStatus.enrolled) return true;
    if (features.pitchMean == 0) return false;

    _status = EnrollmentStatus.enrolling;
    _enrollSamples.add(features);

    if (_enrollSamples.length >= _enrollSampleTarget) {
      _buildBaseline(callId);
      return true;
    }
    return false;
  }

  void _buildBaseline(String callId) {
    final validSamples = _enrollSamples.where((s) => s.pitchMean > 0).toList();
    if (validSamples.isEmpty) {
      _status = EnrollmentStatus.insufficient;
      return;
    }

    final avgPitch =
        validSamples.map((s) => s.pitchMean).reduce((a, b) => a + b) /
            validSamples.length;
    final avgVariance =
        validSamples.map((s) => s.pitchVariance).reduce((a, b) => a + b) /
            validSamples.length;
    final avgFlatness =
        validSamples.map((s) => s.spectralFlatness).reduce((a, b) => a + b) /
            validSamples.length;

    _currentBaseline = VoiceBaseline(
      callId: callId,
      samples: List.unmodifiable(validSamples),
      avgPitch: avgPitch,
      avgPitchVariance: avgVariance,
      avgSpectralFlatness: avgFlatness,
      enrolledAt: DateTime.now(),
      enrollDurationMs: validSamples.length * 2000,
    );
    _status = EnrollmentStatus.enrolled;
  }

  VoiceSimilarityResult? compareLive(AudioFeatures liveFeatures) {
    if (_currentBaseline == null ||
        !_currentBaseline!.isValid ||
        liveFeatures.pitchMean == 0) return null;
    final baseline = _currentBaseline!;

    final pitchDiff = (liveFeatures.pitchMean - baseline.avgPitch).abs();
    final pitchRange = baseline.avgPitch * 0.3;
    final pitchScore = math.max(0.0, 1.0 - pitchDiff / pitchRange);

    final varDiff =
        (liveFeatures.pitchVariance - baseline.avgPitchVariance).abs();
    final varRange = math.max(baseline.avgPitchVariance, 5.0);
    final varianceScore = math.max(0.0, 1.0 - varDiff / varRange);

    final flatDiff =
        (liveFeatures.spectralFlatness - baseline.avgSpectralFlatness).abs();
    final flatnessScore = math.max(0.0, 1.0 - flatDiff / 0.3);

    final zcrNormal = liveFeatures.zeroCrossingRate > 0.02 &&
        liveFeatures.zeroCrossingRate < 0.35;
    final zcrScore = zcrNormal ? 1.0 : 0.5;

    final similarity = (pitchScore * 0.45) +
        (varianceScore * 0.30) +
        (flatnessScore * 0.15) +
        (zcrScore * 0.10);

    return VoiceSimilarityResult(
      similarity: similarity.clamp(0.0, 1.0),
      pitchScore: pitchScore,
      varianceScore: varianceScore,
      flatnessScore: flatnessScore,
      isMismatch: similarity < _mismatchThreshold,
      baseline: baseline,
      liveFeatures: liveFeatures,
    );
  }
}
