// lib/services/voice_message_provider.dart
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart' as ja;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class PlaybackProgress {
  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final bool isPaused;
  final double speed;
  final double progress;

  PlaybackProgress({
    required this.position,
    required this.duration,
    this.isPlaying = false,
    this.isPaused = false,
    this.speed = 1.0,
  }) : progress = duration.inMilliseconds > 0
           ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
           : 0.0;

  static PlaybackProgress get initial =>
      PlaybackProgress(position: Duration.zero, duration: Duration.zero);
}

class RecordingState {
  final bool isRecording;
  final Duration duration;
  final double amplitude;
  final List<double> waveformData;

  const RecordingState({
    this.isRecording = false,
    this.duration = Duration.zero,
    this.amplitude = 0.0,
    this.waveformData = const [],
  });
}

class VoiceUploadResult {
  final String url;
  final Duration duration;
  final int fileSizeBytes;

  const VoiceUploadResult({
    required this.url,
    required this.duration,
    required this.fileSizeBytes,
  });
}

class VoiceMessageProvider {
  final FirebaseStorage firebaseStorage;

  // ĐÃ SỬA: Thay thế bằng package `record` và `just_audio`
  final AudioRecorder _recorder = AudioRecorder();
  final ja.AudioPlayer _player = ja.AudioPlayer();

  bool _isRecorderInitialized = false;
  bool _isPlayerInitialized = false;

  String? _currentRecordingPath;
  DateTime? _recordingStartTime;

  final List<double> _waveformSamples = [];
  static const int _maxWaveformSamples = 60;
  Timer? _waveformTimer;

  final Map<String, String> _downloadCache = {};

  double _playbackSpeed = 1.0;
  String? _currentPlayingUrl;

  final _playbackController = StreamController<PlaybackProgress>.broadcast();
  final _recordingController = StreamController<RecordingState>.broadcast();

  StreamSubscription? _playerStateSub;
  StreamSubscription? _positionSub;

  Stream<PlaybackProgress> get playbackStream => _playbackController.stream;
  Stream<RecordingState> get recordingStream => _recordingController.stream;

  VoiceMessageProvider({required this.firebaseStorage});

  // ═══════════════════════════════════════════════════════════════════════════
  // THU ÂM (RECORDING)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<bool> initRecorder() async {
    if (_isRecorderInitialized) return true;
    try {
      if (await _recorder.hasPermission()) {
        _isRecorderInitialized = true;
        debugPrint('✅ Recorder initialized');
        return true;
      } else {
        debugPrint('❌ Microphone permission denied');
        return false;
      }
    } catch (e) {
      debugPrint('❌ initRecorder error: $e');
      _isRecorderInitialized = false;
      return false;
    }
  }

  Future<bool> startRecording() async {
    try {
      if (!_isRecorderInitialized) {
        if (!await initRecorder()) return false;
      }
      if (await _recorder.isRecording()) {
        debugPrint('⚠️ Already recording');
        return false;
      }

      final dir = await getTemporaryDirectory();
      final fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      _currentRecordingPath = '${dir.path}/$fileName';
      _recordingStartTime = DateTime.now();
      _waveformSamples.clear();

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc, // Chuẩn AAC/M4A tốt nhất cho mobile
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: _currentRecordingPath!,
      );

      // Theo dõi âm lượng định kỳ để vẽ Waveform UI
      _waveformTimer = Timer.periodic(const Duration(milliseconds: 100), (
        timer,
      ) async {
        if (await _recorder.isRecording()) {
          final amp = await _recorder.getAmplitude();
          _handleRecorderProgress(amp.current);
        }
      });

      debugPrint('🎤 Recording started: $_currentRecordingPath');
      return true;
    } catch (e) {
      debugPrint('❌ startRecording error: $e');
      return false;
    }
  }

  void _handleRecorderProgress(double decibels) {
    // Chuẩn hóa decibels (thường từ -160 đến 0) về 0.0 -> 1.0
    final normalised = ((decibels + 60) / 60).clamp(0.0, 1.0);

    _waveformSamples.add(normalised);
    if (_waveformSamples.length > _maxWaveformSamples) {
      _waveformSamples.removeAt(0);
    }

    final duration = _recordingStartTime != null
        ? DateTime.now().difference(_recordingStartTime!)
        : Duration.zero;

    _recordingController.add(
      RecordingState(
        isRecording: true,
        duration: duration,
        amplitude: normalised,
        waveformData: List.unmodifiable(_waveformSamples),
      ),
    );
  }

  Future<String?> stopRecording() async {
    try {
      if (!(await _recorder.isRecording())) {
        debugPrint('⚠️ Not recording');
        return null;
      }
      _waveformTimer?.cancel();
      final path = await _recorder.stop();

      _currentRecordingPath = null;
      _recordingStartTime = null;

      _recordingController.add(const RecordingState());
      debugPrint('🎤 Recording stopped: $path');
      return path;
    } catch (e) {
      debugPrint('❌ stopRecording error: $e');
      return null;
    }
  }

  Future<void> cancelRecording() async {
    try {
      _waveformTimer?.cancel();
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
      if (_currentRecordingPath != null) {
        final f = File(_currentRecordingPath!);
        if (await f.exists()) await f.delete();
      }
      _currentRecordingPath = null;
      _recordingStartTime = null;
      _waveformSamples.clear();
      _recordingController.add(const RecordingState());
      debugPrint('🎤 Recording cancelled');
    } catch (e) {
      debugPrint('❌ cancelRecording error: $e');
    }
  }

  Duration get currentRecordingDuration {
    if (_recordingStartTime == null) return Duration.zero;
    return DateTime.now().difference(_recordingStartTime!);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TẢI LÊN & TẢI XUỐNG
  // ═══════════════════════════════════════════════════════════════════════════

  Future<VoiceUploadResult?> uploadVoiceMessage(
    String filePath,
    String fileName, {
    void Function(double progress)? onProgress,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('❌ File not found: $filePath');
        return null;
      }

      final fileSize = await file.length();
      final reference = firebaseStorage.ref().child('voice_messages/$fileName');

      final metadata = SettableMetadata(
        contentType: 'audio/m4a', // Đổi sang m4a khớp với RecordConfig
        customMetadata: {
          'uploadedAt': DateTime.now().millisecondsSinceEpoch.toString(),
          'fileSizeBytes': fileSize.toString(),
        },
      );

      final uploadTask = reference.putFile(file, metadata);

      if (onProgress != null) {
        uploadTask.snapshotEvents.listen((event) {
          final progress = event.bytesTransferred / event.totalBytes;
          onProgress(progress.clamp(0.0, 1.0));
        });
      }

      final snapshot = await uploadTask;
      final url = await snapshot.ref.getDownloadURL();

      try {
        await file.delete();
      } catch (_) {}

      final estimatedDuration = Duration(seconds: (fileSize / 16000).round());

      debugPrint('✅ Voice uploaded: $url');
      return VoiceUploadResult(
        url: url,
        duration: estimatedDuration,
        fileSizeBytes: fileSize,
      );
    } catch (e) {
      debugPrint('❌ uploadVoiceMessage error: $e');
      return null;
    }
  }

  Future<String?> downloadVoiceMessage(String url) async {
    if (_downloadCache.containsKey(url)) {
      final cached = _downloadCache[url]!;
      if (await File(cached).exists()) return cached;
      _downloadCache.remove(url);
    }

    try {
      final dir = await getTemporaryDirectory();
      final hash = url.hashCode.abs();
      final localPath = '${dir.path}/voice_$hash.m4a';

      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        debugPrint('❌ Download failed: HTTP ${response.statusCode}');
        return null;
      }

      await File(localPath).writeAsBytes(response.bodyBytes);
      _downloadCache[url] = localPath;
      debugPrint('✅ Voice downloaded: $localPath');
      return localPath;
    } catch (e) {
      debugPrint('❌ downloadVoiceMessage error: $e');
      return null;
    }
  }

  void clearDownloadCache() {
    _downloadCache.clear();
    debugPrint('✅ Download cache cleared');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHÁT LẠI (PLAYBACK bằng just_audio)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<bool> initPlayer() async {
    if (_isPlayerInitialized) return true;
    try {
      _positionSub = _player.positionStream.listen(
        (_) => _updatePlaybackState(),
      );
      _playerStateSub = _player.playerStateStream.listen((state) {
        if (state.processingState == ja.ProcessingState.completed) {
          _currentPlayingUrl = null;
          _playbackController.add(PlaybackProgress.initial);
        } else {
          _updatePlaybackState();
        }
      });
      _isPlayerInitialized = true;
      debugPrint('✅ Player initialized');
      return true;
    } catch (e) {
      debugPrint('❌ initPlayer error: $e');
      _isPlayerInitialized = false;
      return false;
    }
  }

  void _updatePlaybackState() {
    final pos = _player.position;
    final dur = _player.duration ?? Duration.zero;
    final playing = _player.playing;
    final processingState = _player.processingState;
    final isPaused =
        !playing &&
        processingState != ja.ProcessingState.completed &&
        pos > Duration.zero;

    _playbackController.add(
      PlaybackProgress(
        position: pos,
        duration: dur,
        isPlaying: playing,
        isPaused: isPaused,
        speed: _playbackSpeed,
      ),
    );
  }

  Future<bool> playVoiceMessage(
    String url, {
    double speed = 1.0,
    Duration? startPosition,
  }) async {
    try {
      if (!_isPlayerInitialized) {
        if (!await initPlayer()) return false;
      }

      if (_player.playing) {
        await _player.stop();
      }

      _currentPlayingUrl = url;
      _playbackSpeed = speed.clamp(0.5, 3.0);
      await _player.setSpeed(_playbackSpeed);

      final localPath = await downloadVoiceMessage(url);

      if (localPath != null) {
        await _player.setFilePath(localPath);
      } else {
        await _player.setUrl(url);
      }

      if (startPosition != null) {
        await _player.seek(startPosition);
      }

      _player.play(); // Không await để tránh block UI

      debugPrint('🔊 Playing: $url at ${_playbackSpeed}x');
      return true;
    } catch (e) {
      debugPrint('❌ playVoiceMessage error: $e');
      _currentPlayingUrl = null;
      return false;
    }
  }

  Future<void> pausePlayback() async {
    try {
      if (_player.playing) {
        await _player.pause();
        debugPrint('⏸ Paused');
      }
    } catch (e) {
      debugPrint('❌ pausePlayback error: $e');
    }
  }

  Future<void> resumePlayback() async {
    try {
      if (!_player.playing &&
          _player.processingState != ja.ProcessingState.completed) {
        _player.play();
        debugPrint('▶️ Resumed');
      }
    } catch (e) {
      debugPrint('❌ resumePlayback error: $e');
    }
  }

  Future<void> stopPlayback() async {
    try {
      await _player.stop();
      _currentPlayingUrl = null;
      _playbackController.add(PlaybackProgress.initial);
      debugPrint('⏹ Stopped');
    } catch (e) {
      debugPrint('❌ stopPlayback error: $e');
    }
  }

  Future<void> seekTo(Duration position) async {
    try {
      await _player.seek(position);
    } catch (e) {
      debugPrint('❌ seekTo error: $e');
    }
  }

  Future<void> setPlaybackSpeed(double speed) async {
    try {
      _playbackSpeed = speed.clamp(0.5, 3.0);
      await _player.setSpeed(_playbackSpeed);
      debugPrint('⚡ Speed set to ${_playbackSpeed}x');
    } catch (e) {
      debugPrint('❌ setPlaybackSpeed error: $e');
    }
  }

  double cycleSpeed() {
    const presets = [1.0, 1.5, 2.0, 0.75];
    final idx = presets.indexOf(_playbackSpeed);
    final next = presets[(idx + 1) % presets.length];
    setPlaybackSpeed(next);
    return next;
  }

  bool get isPlaying => _player.playing;

  bool get isPaused =>
      !_player.playing &&
      _player.processingState != ja.ProcessingState.completed &&
      _player.position > Duration.zero;

  String? get currentPlayingUrl => _currentPlayingUrl;

  double get playbackSpeed => _playbackSpeed;

  bool isPlayingUrl(String url) => _currentPlayingUrl == url && isPlaying;

  static List<double> generateWaveformPreview({int bars = 30, int seed = 42}) {
    final rng = math.Random(seed);
    return List.generate(bars, (i) {
      final base = 0.2 + rng.nextDouble() * 0.6;
      final envelope = math.sin(i / bars * math.pi);
      return (base * envelope).clamp(0.05, 1.0);
    });
  }

  Future<void> dispose() async {
    _waveformTimer?.cancel();

    if (_isRecorderInitialized) {
      try {
        if (await _recorder.isRecording()) await _recorder.stop();
        await _recorder.dispose();
      } catch (_) {}
      _isRecorderInitialized = false;
    }

    if (_isPlayerInitialized) {
      try {
        _positionSub?.cancel();
        _playerStateSub?.cancel();
        if (_player.playing) await _player.stop();
        await _player.dispose();
      } catch (_) {}
      _isPlayerInitialized = false;
    }

    await _playbackController.close();
    await _recordingController.close();
    _downloadCache.clear();
    debugPrint('✅ VoiceMessageProvider disposed');
  }
}
