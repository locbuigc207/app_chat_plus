import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';





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

  static PlaybackProgress get initial => PlaybackProgress(
        position: Duration.zero,
        duration: Duration.zero,
      );
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

  FlutterSoundRecorder? _recorder;
  FlutterSoundPlayer? _player;

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

  Stream<PlaybackProgress> get playbackStream => _playbackController.stream;
  Stream<RecordingState> get recordingStream => _recordingController.stream;

  VoiceMessageProvider({required this.firebaseStorage}) {
    _recorder = FlutterSoundRecorder();
    _player = FlutterSoundPlayer();
  }

  
  
  

  Future<bool> initRecorder() async {
    if (_isRecorderInitialized) return true;
    try {
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        debugPrint('❌ Microphone permission denied');
        return false;
      }
      await _recorder?.openRecorder();
      await _recorder?.setSubscriptionDuration(const Duration(milliseconds: 80));
      _isRecorderInitialized = true;
      debugPrint('✅ Recorder initialized');
      return true;
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
      if (_recorder?.isRecording ?? false) {
        debugPrint('⚠️ Already recording');
        return false;
      }

      final dir = await getTemporaryDirectory();
      final fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}.aac';
      _currentRecordingPath = '${dir.path}/$fileName';
      _recordingStartTime = DateTime.now();
      _waveformSamples.clear();

      await _recorder?.startRecorder(
        toFile: _currentRecordingPath,
        codec: Codec.aacADTS,
        bitRate: 128000,
        sampleRate: 44100,
      );

      
      _recorder?.onProgress?.listen(_handleRecorderProgress);

      debugPrint('🎤 Recording started: $_currentRecordingPath');
      return true;
    } catch (e) {
      debugPrint('❌ startRecording error: $e');
      return false;
    }
  }

  void _handleRecorderProgress(RecordingDisposition event) {
    final decibels = event.decibels ?? 0.0;
    
    final normalised = ((decibels + 60) / 60).clamp(0.0, 1.0);

    _waveformSamples.add(normalised);
    if (_waveformSamples.length > _maxWaveformSamples) {
      _waveformSamples.removeAt(0);
    }

    _recordingController.add(RecordingState(
      isRecording: true,
      duration: event.duration,
      amplitude: normalised,
      waveformData: List.unmodifiable(_waveformSamples),
    ));
  }

  Future<String?> stopRecording() async {
    try {
      if (!(_recorder?.isRecording ?? false)) {
        debugPrint('⚠️ Not recording');
        return null;
      }
      _waveformTimer?.cancel();
      await _recorder?.stopRecorder();
      final path = _currentRecordingPath;
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
      if (_recorder?.isRecording ?? false) {
        await _recorder?.stopRecorder();
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

  bool get isRecording => _recorder?.isRecording ?? false;

  
  
  

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
        contentType: 'audio/aac',
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
      final localPath = '${dir.path}/voice_$hash.aac';

      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));

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

  
  
  

  Future<bool> initPlayer() async {
    if (_isPlayerInitialized) return true;
    try {
      await _player?.openPlayer();
      await _player?.setSubscriptionDuration(const Duration(milliseconds: 80));
      _isPlayerInitialized = true;
      debugPrint('✅ Player initialized');
      return true;
    } catch (e) {
      debugPrint('❌ initPlayer error: $e');
      _isPlayerInitialized = false;
      return false;
    }
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

      if (_player?.isPlaying ?? false) {
        await _player?.stopPlayer();
      }

      _currentPlayingUrl = url;
      _playbackSpeed = speed.clamp(0.5, 3.0);

      
      final localPath = await downloadVoiceMessage(url);
      final playUri = localPath ?? url;

      await _player?.startPlayer(
        fromURI: playUri,
        codec: Codec.aacADTS,
        whenFinished: () {
          _currentPlayingUrl = null;
          _playbackController.add(PlaybackProgress.initial);
        },
      );

      
      await _player?.setSpeed(_playbackSpeed);

      
      if (startPosition != null) {
        await _player?.seekToPlayer(startPosition);
      }

      
      _player?.onProgress?.listen((event) {
        _playbackController.add(PlaybackProgress(
          position: event.position,
          duration: event.duration,
          isPlaying: true,
          speed: _playbackSpeed,
        ));
      });

      debugPrint('🔊 Playing: $url at ${_playbackSpeed}x');
      return true;
    } catch (e) {
      debugPrint('❌ playVoiceMessage error: $e');
      return false;
    }
  }

  Future<void> pausePlayback() async {
    try {
      if (_player?.isPlaying ?? false) {
        await _player?.pausePlayer();
        debugPrint('⏸ Paused');
      }
    } catch (e) {
      debugPrint('❌ pausePlayback error: $e');
    }
  }

  Future<void> resumePlayback() async {
    try {
      if (_player?.isPaused ?? false) {
        await _player?.resumePlayer();
        debugPrint('▶️ Resumed');
      }
    } catch (e) {
      debugPrint('❌ resumePlayback error: $e');
    }
  }

  Future<void> stopPlayback() async {
    try {
      await _player?.stopPlayer();
      _currentPlayingUrl = null;
      _playbackController.add(PlaybackProgress.initial);
      debugPrint('⏹ Stopped');
    } catch (e) {
      debugPrint('❌ stopPlayback error: $e');
    }
  }

  Future<void> seekTo(Duration position) async {
    try {
      await _player?.seekToPlayer(position);
    } catch (e) {
      debugPrint('❌ seekTo error: $e');
    }
  }

  
  Future<void> setPlaybackSpeed(double speed) async {
    try {
      _playbackSpeed = speed.clamp(0.5, 3.0);
      await _player?.setSpeed(_playbackSpeed);
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

  bool get isPlaying => _player?.isPlaying ?? false;
  bool get isPaused => _player?.isPaused ?? false;
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
        if (_recorder?.isRecording ?? false) await _recorder?.stopRecorder();
        await _recorder?.closeRecorder();
      } catch (_) {}
      _isRecorderInitialized = false;
    }

    if (_isPlayerInitialized) {
      try {
        if (_player?.isPlaying ?? false) await _player?.stopPlayer();
        await _player?.closePlayer();
      } catch (_) {}
      _isPlayerInitialized = false;
    }

    await _playbackController.close();
    await _recordingController.close();
    _downloadCache.clear();
    debugPrint('✅ VoiceMessageProvider disposed');
  }
}
