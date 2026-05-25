import 'dart:async';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class VoiceMessageProvider {
  final FirebaseStorage firebaseStorage;
  FlutterSoundRecorder? _recorder;
  FlutterSoundPlayer? _player;

  bool _isRecorderInitialized = false;
  bool _isPlayerInitialized = false;
  String? _currentRecordingPath;

  // Cache: url → local path, tránh download lại nhiều lần
  final Map<String, String> _downloadCache = {};

  final _playbackProgressController =
      StreamController<PlaybackProgress>.broadcast();
  Stream<PlaybackProgress> get playbackProgressStream =>
      _playbackProgressController.stream;

  VoiceMessageProvider({required this.firebaseStorage}) {
    _recorder = FlutterSoundRecorder();
    _player = FlutterSoundPlayer();
  }

  // ─────────────────────────────────────────────
  // Download
  // ─────────────────────────────────────────────

  /// Download voice message từ [url] về bộ nhớ tạm, trả về local path.
  /// Kết quả được cache — cùng URL sẽ không download lại.
  Future<String?> downloadVoiceMessage(String url) async {
    if (_downloadCache.containsKey(url)) {
      final cached = _downloadCache[url]!;
      if (await File(cached).exists()) return cached;
      _downloadCache.remove(url); // file bị xoá ngoài app, xoá cache
    }

    try {
      final directory = await getTemporaryDirectory();
      final fileName = 'voice_${Uri.encodeComponent(url).hashCode.abs()}.aac';
      final localPath = '${directory.path}/$fileName';

      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        print('❌ Failed to download voice message: ${response.statusCode}');
        return null;
      }

      await File(localPath).writeAsBytes(response.bodyBytes);
      _downloadCache[url] = localPath;
      print('✅ Voice message downloaded: $localPath');
      return localPath;
    } catch (e) {
      print('❌ Error downloading voice message: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────
  // Recorder
  // ─────────────────────────────────────────────

  Future<bool> initRecorder() async {
    if (_isRecorderInitialized) return true;

    try {
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        print('❌ Microphone permission denied');
        return false;
      }

      await _recorder?.openRecorder();
      await _recorder
          ?.setSubscriptionDuration(const Duration(milliseconds: 100));

      _isRecorderInitialized = true;
      print('✅ Voice recorder initialized');
      return true;
    } catch (e) {
      print('❌ Error initializing recorder: $e');
      _isRecorderInitialized = false;
      return false;
    }
  }

  Future<bool> startRecording() async {
    try {
      if (!_isRecorderInitialized) {
        final initialized = await initRecorder();
        if (!initialized) return false;
      }

      if (_recorder?.isRecording ?? false) {
        print('⚠️ Already recording');
        return false;
      }

      final directory = await getTemporaryDirectory();
      final fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}.aac';
      _currentRecordingPath = '${directory.path}/$fileName';

      await _recorder?.startRecorder(
        toFile: _currentRecordingPath,
        codec: Codec.aacADTS,
      );

      print('🎤 Recording started: $_currentRecordingPath');
      return true;
    } catch (e) {
      print('❌ Error starting recording: $e');
      return false;
    }
  }

  Future<String?> stopRecording() async {
    try {
      if (_recorder == null || !(_recorder!.isRecording)) {
        print('⚠️ Not recording');
        return null;
      }

      final path = await _recorder?.stopRecorder();
      final recordingPath = _currentRecordingPath;
      _currentRecordingPath = null;

      print('🎤 Recording stopped: $recordingPath');
      return recordingPath ?? path;
    } catch (e) {
      print('❌ Error stopping recording: $e');
      return null;
    }
  }

  Future<void> cancelRecording() async {
    try {
      if (_recorder?.isRecording ?? false) {
        await _recorder?.stopRecorder();
      }

      if (_currentRecordingPath != null) {
        final file = File(_currentRecordingPath!);
        if (await file.exists()) await file.delete();
      }
      _currentRecordingPath = null;
      print('🎤 Recording cancelled');
    } catch (e) {
      print('❌ Error cancelling recording: $e');
    }
  }

  Stream<RecordingDisposition>? get recordingStream => _recorder?.onProgress;

  // ─────────────────────────────────────────────
  // Upload
  // ─────────────────────────────────────────────

  Future<String?> uploadVoiceMessage(String filePath, String fileName) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        print('❌ File does not exist: $filePath');
        return null;
      }

      final reference = firebaseStorage.ref().child('voice_messages/$fileName');
      final uploadTask = reference.putFile(
        file,
        SettableMetadata(contentType: 'audio/aac'),
      );

      final snapshot = await uploadTask;
      final url = await snapshot.ref.getDownloadURL();

      try {
        await file.delete();
      } catch (_) {}

      print('✅ Voice message uploaded: $url');
      return url;
    } catch (e) {
      print('❌ Error uploading voice message: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────
  // Player (flutter_sound — dùng cho các nơi khác nếu cần)
  // ─────────────────────────────────────────────

  Future<bool> initPlayer() async {
    if (_isPlayerInitialized) return true;

    try {
      await _player?.openPlayer();
      await _player?.setSubscriptionDuration(const Duration(milliseconds: 100));
      _isPlayerInitialized = true;
      print('✅ Voice player initialized');
      return true;
    } catch (e) {
      print('❌ Error initializing player: $e');
      _isPlayerInitialized = false;
      return false;
    }
  }

  Future<void> playVoiceMessage(String url) async {
    try {
      if (!_isPlayerInitialized) {
        final initialized = await initPlayer();
        if (!initialized) return;
      }

      if (_player?.isPlaying ?? false) await _player?.stopPlayer();

      await _player?.startPlayer(
        fromURI: url,
        codec: Codec.aacADTS,
        whenFinished: () {
          _playbackProgressController.add(PlaybackProgress(
            position: Duration.zero,
            duration: Duration.zero,
            isPlaying: false,
          ));
        },
      );

      _player?.onProgress?.listen((event) {
        _playbackProgressController.add(PlaybackProgress(
          position: event.position,
          duration: event.duration,
          isPlaying: true,
        ));
      });

      print('🔊 Playing voice message');
    } catch (e) {
      print('❌ Error playing voice message: $e');
    }
  }

  Future<void> stopPlayback() async {
    try {
      await _player?.stopPlayer();
      print('🔊 Playback stopped');
    } catch (e) {
      print('❌ Error stopping playback: $e');
    }
  }

  Future<void> pausePlayback() async {
    try {
      await _player?.pausePlayer();
      print('🔊 Playback paused');
    } catch (e) {
      print('❌ Error pausing playback: $e');
    }
  }

  Future<void> resumePlayback() async {
    try {
      await _player?.resumePlayer();
      print('🔊 Playback resumed');
    } catch (e) {
      print('❌ Error resuming playback: $e');
    }
  }

  Stream<PlaybackDisposition>? get playbackStream => _player?.onProgress;

  bool get isRecording => _recorder?.isRecording ?? false;
  bool get isPlaying => _player?.isPlaying ?? false;
  bool get isPaused => _player?.isPaused ?? false;

  // ─────────────────────────────────────────────
  // Dispose
  // ─────────────────────────────────────────────

  Future<void> dispose() async {
    try {
      if (_isRecorderInitialized) {
        if (_recorder?.isRecording ?? false) await _recorder?.stopRecorder();
        await _recorder?.closeRecorder();
        _isRecorderInitialized = false;
      }

      if (_isPlayerInitialized) {
        if (_player?.isPlaying ?? false) await _player?.stopPlayer();
        await _player?.closePlayer();
        _isPlayerInitialized = false;
      }

      await _playbackProgressController.close();
      print('✅ Voice provider disposed');
    } catch (e) {
      print('❌ Error disposing voice provider: $e');
    }
  }
}

// ─────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────

class PlaybackProgress {
  final Duration position;
  final Duration duration;
  final bool isPlaying;

  PlaybackProgress({
    required this.position,
    required this.duration,
    required this.isPlaying,
  });
}
