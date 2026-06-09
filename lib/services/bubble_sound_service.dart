// lib/services/bubble_sound_service.dart
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SOUND PROFILE — maps BubbleMode to audio + haptic behaviour
// ═══════════════════════════════════════════════════════════════════════════

class _SoundProfile {
  final String? asset; // null = system default
  final double volume;
  final List<Duration> hapticPattern; // vibration sequence
  final bool playOnReceive;
  final bool playOnSend;

  const _SoundProfile({
    this.asset,
    this.volume = 1.0,
    this.hapticPattern = const [],
    this.playOnReceive = true,
    this.playOnSend = false,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// SERVICE
// ═══════════════════════════════════════════════════════════════════════════

class BubbleSoundService {
  // ── Singleton ────────────────────────────────────────────────────────────
  static final BubbleSoundService _i = BubbleSoundService._();
  factory BubbleSoundService() => _i;
  BubbleSoundService._();

  // ── Audio player pool ─────────────────────────────────────────────────────
  final _players = <String, AudioPlayer>{};
  bool _initialized = false;
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;

  // ── Sound profiles per BubbleMode ─────────────────────────────────────────
  static const _profiles = <BubbleMode, _SoundProfile>{
    BubbleMode.normal: _SoundProfile(
      asset: 'assets/sounds/bubble_pop.mp3',
      volume: 0.85,
      hapticPattern: [Duration(milliseconds: 40)],
      playOnReceive: true,
      playOnSend: false,
    ),
    BubbleMode.work: _SoundProfile(
      asset: 'assets/sounds/work_ping.mp3',
      volume: 0.6,
      hapticPattern: [Duration(milliseconds: 20)],
      playOnReceive: true,
      playOnSend: false,
    ),
    BubbleMode.secure: _SoundProfile(
      asset: 'assets/sounds/secure_chime.mp3',
      volume: 0.5,
      hapticPattern: [
        Duration(milliseconds: 20),
        Duration(milliseconds: 60),
        Duration(milliseconds: 20),
      ],
      playOnReceive: true,
      playOnSend: true,
    ),
    BubbleMode.location: _SoundProfile(
      asset: 'assets/sounds/location_ping.mp3',
      volume: 0.75,
      hapticPattern: [Duration(milliseconds: 30), Duration(milliseconds: 30)],
      playOnReceive: true,
      playOnSend: false,
    ),
    BubbleMode.media: _SoundProfile(
      asset: 'assets/sounds/media_chime.mp3',
      volume: 0.7,
      hapticPattern: [Duration(milliseconds: 50)],
      playOnReceive: true,
      playOnSend: false,
    ),
    BubbleMode.shared: _SoundProfile(
      asset: 'assets/sounds/shared_join.mp3',
      volume: 0.65,
      hapticPattern: [Duration(milliseconds: 35), Duration(milliseconds: 35)],
      playOnReceive: true,
      playOnSend: true,
    ),
  };

  // ─── Init ─────────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    if (_initialized || kIsWeb) return;
    try {
      await _loadPreferences();
      // Pre-create players for each mode
      for (final mode in BubbleMode.values) {
        final player = AudioPlayer();
        await player.setReleaseMode(ReleaseMode.stop);
        _players[mode.name] = player;
      }
      _initialized = true;
      debugPrint('✅ BubbleSoundService initialized');
    } catch (e) {
      debugPrint('❌ BubbleSoundService init: $e');
    }
  }

  Future<void> _loadPreferences() async {
    final p = await SharedPreferences.getInstance();
    _soundEnabled = p.getBool('bubble_sound') ?? true;
    _vibrationEnabled = p.getBool('bubble_vibration') ?? true;
  }

  // ─── Public API ───────────────────────────────────────────────────────────

  /// Play notification sound for an incoming message.
  Future<void> playReceive(BubbleMode mode) async {
    if (!_initialized) await initialize();
    final profile = _profiles[mode] ?? _profiles[BubbleMode.normal]!;
    if (!profile.playOnReceive) return;
    await _play(mode, profile);
  }

  /// Play send confirmation sound.
  Future<void> playSend(BubbleMode mode) async {
    if (!_initialized) await initialize();
    final profile = _profiles[mode] ?? _profiles[BubbleMode.normal]!;
    if (!profile.playOnSend) return;
    await _play(mode, profile, volume: profile.volume * 0.5);
  }

  /// Play bubble appear animation sound.
  Future<void> playBubbleAppear() => playReceive(BubbleMode.normal);

  /// Play tap/click sound.
  Future<void> playTap() async {
    if (!_soundEnabled) return;
    HapticFeedback.lightImpact();
    await _playAsset('assets/sounds/tap.mp3', 0.4);
  }

  /// Play error sound.
  Future<void> playError() async {
    if (!_soundEnabled) return;
    HapticFeedback.vibrate();
    await _playAsset('assets/sounds/error.mp3', 0.6);
  }

  // ─── Settings ────────────────────────────────────────────────────────────

  Future<void> setSoundEnabled(bool enabled) async {
    _soundEnabled = enabled;
    final p = await SharedPreferences.getInstance();
    await p.setBool('bubble_sound', enabled);
  }

  Future<void> setVibrationEnabled(bool enabled) async {
    _vibrationEnabled = enabled;
    final p = await SharedPreferences.getInstance();
    await p.setBool('bubble_vibration', enabled);
  }

  bool get isSoundEnabled => _soundEnabled;
  bool get isVibrationEnabled => _vibrationEnabled;

  // ─── Implementation ───────────────────────────────────────────────────────

  Future<void> _play(
    BubbleMode mode,
    _SoundProfile profile, {
    double? volume,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    // Sound
    if (_soundEnabled && profile.asset != null) {
      await _playAsset(profile.asset!, volume ?? profile.volume);
    }

    // Haptic
    if (_vibrationEnabled && profile.hapticPattern.isNotEmpty) {
      await _doHaptic(profile.hapticPattern);
    }
  }

  Future<void> _playAsset(String asset, double volume) async {
    try {
      final key = asset.split('/').last;
      final player = _players[key] ?? AudioPlayer();
      if (!_players.containsKey(key)) _players[key] = player;

      await player.setVolume(volume);
      await player.play(AssetSource(asset.replaceFirst('assets/', '')));
    } catch (e) {
      // Sound asset missing in dev — silent fail
      debugPrint('⚠️ Sound missing: $asset ($e)');
    }
  }

  Future<void> _doHaptic(List<Duration> pattern) async {
    for (var i = 0; i < pattern.length; i++) {
      if (i % 2 == 0) {
        await HapticFeedback.lightImpact();
      } else {
        await Future.delayed(pattern[i]);
      }
    }
  }

  // ─── Dispose ─────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    for (final p in _players.values) await p.dispose();
    _players.clear();
    _initialized = false;
  }
}
