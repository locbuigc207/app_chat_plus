// lib/utils/audio_feature_extractor.dart
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../models/deepfake_models.dart';

class AudioFeatureExtractor {
  AudioFeatureExtractor._();
  static final AudioFeatureExtractor _instance = AudioFeatureExtractor._();
  factory AudioFeatureExtractor() => _instance;

  static const int _sampleRate = 16000;
  static const int _frameSize = 512;
  static const int _hopSize = 256;

  Future<AudioFeatures?> extractFromBuffer(
    Int16List audioBuffer, {
    int sampleRate = _sampleRate,
  }) async {
    if (audioBuffer.length < _frameSize * 4) return null;

    try {
      return await compute(_extractFeaturesIsolate, {
        'buffer': audioBuffer,
        'sampleRate': sampleRate,
      });
    } catch (e) {
      debugPrint('[AudioFeatureExtractor] Error: $e');
      return null;
    }
  }

  static AudioFeatures _extractFeaturesIsolate(Map<String, dynamic> args) {
    final buffer = args['buffer'] as Int16List;
    final sampleRate = args['sampleRate'] as int;

    final floatBuffer = Float64List(buffer.length);
    for (int i = 0; i < buffer.length; i++) {
      floatBuffer[i] = buffer[i] / 32768.0;
    }

    final pitch = _estimatePitch(floatBuffer, sampleRate);
    final zcr = _computeZCR(floatBuffer);
    final energy = _computeEnergyVariance(floatBuffer);
    final spectralFlatness = _computeSpectralFlatness(floatBuffer);
    final pauseRatio = _computePauseRatio(floatBuffer);
    final bgNoise = _estimateBackgroundNoise(floatBuffer);

    return AudioFeatures(
      pitchMean: pitch['mean']!,
      pitchVariance: pitch['variance']!,
      spectralFlatness: spectralFlatness,
      zeroCrossingRate: zcr,
      energyVariance: energy,
      pauseRatio: pauseRatio,
      formants: [],
      backgroundNoiseLevel: bgNoise,
      capturedAt: DateTime.now(),
    );
  }

  static Map<String, double> _estimatePitch(
      Float64List signal, int sampleRate) {
    final pitches = <double>[];
    final frameCount = (signal.length - _frameSize) ~/ _hopSize;

    for (int f = 0; f < frameCount; f++) {
      final start = f * _hopSize;
      final frame = signal.sublist(start, start + _frameSize);
      final pitch = _autocorrelationPitch(frame, sampleRate);
      if (pitch > 50 && pitch < 500) pitches.add(pitch);
    }

    if (pitches.isEmpty) return {'mean': 0.0, 'variance': 0.0};
    final mean = pitches.reduce((a, b) => a + b) / pitches.length;
    final variance = pitches
            .map((p) => math.pow(p - mean, 2).toDouble())
            .reduce((a, b) => a + b) /
        pitches.length;
    return {'mean': mean, 'variance': math.sqrt(variance)};
  }

  static double _autocorrelationPitch(List<double> frame, int sampleRate) {
    final minLag = sampleRate ~/ 500;
    final maxLag = sampleRate ~/ 50;
    double maxCorr = 0;
    int bestLag = minLag;

    for (int lag = minLag; lag < maxLag && lag < frame.length; lag++) {
      double corr = 0;
      for (int i = 0; i < frame.length - lag; i++) {
        corr += frame[i] * frame[i + lag];
      }
      if (corr > maxCorr) {
        maxCorr = corr;
        bestLag = lag;
      }
    }
    return sampleRate / bestLag.toDouble();
  }

  static double _computeZCR(Float64List signal) {
    int crossings = 0;
    for (int i = 1; i < signal.length; i++) {
      if ((signal[i] >= 0) != (signal[i - 1] >= 0)) crossings++;
    }
    return crossings / signal.length.toDouble();
  }

  static double _computeEnergyVariance(Float64List signal) {
    final frameEnergies = <double>[];
    for (int i = 0; i < signal.length - _frameSize; i += _hopSize) {
      double energy = 0;
      for (int j = i; j < i + _frameSize; j++) {
        energy += signal[j] * signal[j];
      }
      frameEnergies.add(energy / _frameSize);
    }
    if (frameEnergies.isEmpty) return 0;
    final mean = frameEnergies.reduce((a, b) => a + b) / frameEnergies.length;
    return frameEnergies
            .map((e) => math.pow(e - mean, 2).toDouble())
            .reduce((a, b) => a + b) /
        frameEnergies.length;
  }

  static double _computeSpectralFlatness(Float64List signal) {
    final frameSize = math.min(_frameSize, signal.length);
    double geometricSum = 0;
    double arithmeticSum = 0;
    int validFrames = 0;

    for (int i = 0; i < frameSize; i++) {
      final power = signal[i] * signal[i];
      if (power > 1e-10) {
        geometricSum += math.log(power);
        arithmeticSum += power;
        validFrames++;
      }
    }
    if (validFrames == 0 || arithmeticSum == 0) return 0.5;
    return (math.exp(geometricSum / validFrames) /
            (arithmeticSum / validFrames))
        .clamp(0.0, 1.0);
  }

  static double _computePauseRatio(Float64List signal) {
    const silenceThreshold = 0.01;
    int silentSamples = 0;
    for (final sample in signal) {
      if (sample.abs() < silenceThreshold) silentSamples++;
    }
    return silentSamples / signal.length.toDouble();
  }

  static double _estimateBackgroundNoise(Float64List signal) {
    final energies = signal.map((s) => s.abs()).toList()..sort();
    final noiseFloorSamples = energies.take(signal.length ~/ 10).toList();
    if (noiseFloorSamples.isEmpty) return 0;
    return noiseFloorSamples.reduce((a, b) => a + b) / noiseFloorSamples.length;
  }
}
