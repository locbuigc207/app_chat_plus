// lib/services/deepfake_detector_service.dart
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import '../models/deepfake_models.dart';
import '../utils/audio_feature_extractor.dart';
import 'voice_fingerprint_service.dart';

class DeepfakeDetectorService {
  DeepfakeDetectorService._();
  static final DeepfakeDetectorService _instance = DeepfakeDetectorService._();
  factory DeepfakeDetectorService() => _instance;

  final _fingerprint = VoiceFingerprintService();
  final _extractor = AudioFeatureExtractor();
  final _resultCtrl = StreamController<DeepfakeAnalysisResult>.broadcast();
  Stream<DeepfakeAnalysisResult> get resultStream => _resultCtrl.stream;

  String? _activeCallId;
  bool _isActive = false;
  int _consecutiveSuspiciousFrames = 0;
  static const int _suspiciousFrameThreshold = 3;
  static const double _localAlertThreshold = 0.55;

  AudioFeatures? _lastFeatures;
  AudioFeatures? get lastFeatures => _lastFeatures;
  EnrollmentStatus get currentEnrollmentStatus => _fingerprint.status;

  void startAnalysis(String callId) {
    _activeCallId = callId;
    _isActive = true;
    _consecutiveSuspiciousFrames = 0;
    _fingerprint.reset();
  }

  void stopAnalysis() {
    _isActive = false;
    _activeCallId = null;
    _fingerprint.reset();
  }

  void dispose() {
    stopAnalysis();
    _resultCtrl.close();
  }

  Future<DeepfakeAnalysisResult?> analyzeAudioBuffer(
      Int16List audioBuffer) async {
    if (!_isActive || _activeCallId == null) return null;

    final features = await _extractor.extractFromBuffer(audioBuffer);
    if (features == null) return null;
    _lastFeatures = features;

    if (_fingerprint.status != EnrollmentStatus.enrolled) {
      _fingerprint.addEnrollSample(features, _activeCallId!);
      if (_fingerprint.status == EnrollmentStatus.enrolling) {
        _emitCalibrating();
        return null;
      }
    }

    final localResult = _runLocalHeuristics(features);
    final similarity = _fingerprint.compareLive(features);
    final combinedResult = _combineResults(
        localResult: localResult,
        similarityResult: similarity,
        features: features);

    if (combinedResult.isLikelyDeepfake) {
      _consecutiveSuspiciousFrames++;
    } else if (_consecutiveSuspiciousFrames > 0) {
      _consecutiveSuspiciousFrames--;
    }

    final finalResult =
        _consecutiveSuspiciousFrames >= _suspiciousFrameThreshold
            ? combinedResult
            : DeepfakeAnalysisResult.safe();

    if (!_resultCtrl.isClosed) _resultCtrl.add(finalResult);
    return finalResult;
  }

  DeepfakeAnalysisResult _runLocalHeuristics(AudioFeatures features) {
    final signals = <DeepfakeSignal>[];
    final weights = <DeepfakeSignal, double>{};
    double score = 0.0;

    if (features.pitchMean > 0 && features.pitchVariance < 6.0) {
      signals.add(DeepfakeSignal.pitchAnomalous);
      final weight = (6.0 - features.pitchVariance) / 6.0 * 0.35;
      weights[DeepfakeSignal.pitchAnomalous] = weight;
      score += weight;
    }

    if (features.pitchVariance > 80.0) {
      if (!signals.contains(DeepfakeSignal.pitchAnomalous))
        signals.add(DeepfakeSignal.pitchAnomalous);
      final weight = math.min(0.25, (features.pitchVariance - 80) / 100 * 0.25);
      weights[DeepfakeSignal.pitchAnomalous] =
          (weights[DeepfakeSignal.pitchAnomalous] ?? 0) + weight;
      score += weight;
    }

    if (features.spectralFlatness > 0.65) {
      signals.add(DeepfakeSignal.spectralFlat);
      final weight = (features.spectralFlatness - 0.65) / 0.35 * 0.25;
      weights[DeepfakeSignal.spectralFlat] = weight.clamp(0, 0.25);
      score += weights[DeepfakeSignal.spectralFlat]!;
    }

    if (features.backgroundNoiseLevel < 0.001 && features.pitchMean > 80) {
      signals.add(DeepfakeSignal.backgroundArtifact);
      score += 0.15;
    }

    if (features.pauseRatio < 0.08 || features.pauseRatio > 0.75) {
      signals.add(DeepfakeSignal.pauseUnnatural);
      score += 0.10;
    }

    return DeepfakeAnalysisResult(
      isLikelyDeepfake: score >= _localAlertThreshold,
      confidenceScore: score.clamp(0.0, 1.0),
      signals: signals,
      explanation: _buildExplanation(signals, features),
      source: DeepfakeSource.local,
    );
  }

  DeepfakeAnalysisResult _combineResults({
    required DeepfakeAnalysisResult localResult,
    required VoiceSimilarityResult? similarityResult,
    required AudioFeatures features,
  }) {
    double combinedScore = localResult.confidenceScore;
    final allSignals = List<DeepfakeSignal>.from(localResult.signals);

    if (similarityResult != null && similarityResult.isMismatch) {
      allSignals.add(DeepfakeSignal.voiceprintMismatch);
      combinedScore = math.min(
          1.0, combinedScore + similarityResult.deepfakeProbability * 0.3);
    }

    return DeepfakeAnalysisResult(
      isLikelyDeepfake: combinedScore >= _localAlertThreshold,
      confidenceScore: combinedScore,
      signals: allSignals,
      explanation: _buildExplanation(allSignals, features),
      source: similarityResult != null
          ? DeepfakeSource.combined
          : DeepfakeSource.local,
    );
  }

  String _buildExplanation(
      List<DeepfakeSignal> signals, AudioFeatures features) {
    if (signals.isEmpty) return '';
    final parts = <String>[];
    for (final signal in signals) {
      switch (signal) {
        case DeepfakeSignal.pitchAnomalous:
          parts.add('Pitch giọng bất thường');
          break;
        case DeepfakeSignal.spectralFlat:
          parts.add('Âm thanh thiếu texture tự nhiên');
          break;
        case DeepfakeSignal.backgroundArtifact:
          parts.add('Background quá sạch');
          break;
        case DeepfakeSignal.pauseUnnatural:
          parts.add('Pattern ngừng nghỉ cứng nhắc');
          break;
        case DeepfakeSignal.voiceprintMismatch:
          parts.add('Giọng không khớp với ban đầu');
          break;
        default:
          parts.add(signal.name);
      }
    }
    return parts.join('; ');
  }

  void _emitCalibrating() {
    if (!_resultCtrl.isClosed) {
      _resultCtrl.add(const DeepfakeAnalysisResult(
        isLikelyDeepfake: false,
        confidenceScore: 0,
        signals: [],
        explanation: 'Đang phân tích giọng nói...',
        source: DeepfakeSource.local,
      ));
    }
  }
}
