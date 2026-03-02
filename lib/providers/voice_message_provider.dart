// lib/providers/voice_message_provider.dart - COMPLETE FIXED
import 'dart:async';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class VoiceMessageProvider {
  final FirebaseStorage firebaseStorage;
  FlutterSoundRecorder? _recorder;
  FlutterSoundPlayer? _player;

  bool _isRecorderInitialized = false;
  bool _isPlayerInitialized = false;
  String? _currentRecordingPath;

  // Stream controllers for playback progress
  final _playbackProgressController =
      StreamController<PlaybackProgress>.broadcast();
  Stream<PlaybackProgress> get playbackProgressStream =>
      _playbackProgressController.stream;

  VoiceMessageProvider({required this.firebaseStorage}) {
    _recorder = FlutterSoundRecorder();
    _player = FlutterSoundPlayer();
  }

  Future<bool> initRecorder() async {
    if (_isRecorderInitialized) return true;

    try {
      // Request microphone permission
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        print('❌ Microphone permission denied');
        return false;
      }

      // Open recorder
      await _recorder?.openRecorder();

      // Set subscription duration for progress updates
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

  Future<bool> startRecording() async {
    try {
      if (!_isRecorderInitialized) {
        final initialized = await initRecorder();
        if (!initialized) return false;
      }

      // Check if already recording
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
        if (await file.exists()) {
          await file.delete();
        }
      }
      _currentRecordingPath = null;
      print('🎤 Recording cancelled');
    } catch (e) {
      print('❌ Error cancelling recording: $e');
    }
  }

  Stream<RecordingDisposition>? get recordingStream => _recorder?.onProgress;

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

      // Clean up local file
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

  Future<void> playVoiceMessage(String url) async {
    try {
      if (!_isPlayerInitialized) {
        final initialized = await initPlayer();
        if (!initialized) return;
      }

      // Stop any current playback
      if (_player?.isPlaying ?? false) {
        await _player?.stopPlayer();
      }

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

      // Listen to progress
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

  Future<void> dispose() async {
    try {
      if (_isRecorderInitialized) {
        if (_recorder?.isRecording ?? false) {
          await _recorder?.stopRecorder();
        }
        await _recorder?.closeRecorder();
        _isRecorderInitialized = false;
      }

      if (_isPlayerInitialized) {
        if (_player?.isPlaying ?? false) {
          await _player?.stopPlayer();
        }
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
