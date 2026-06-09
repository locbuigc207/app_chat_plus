// lib/services/bubble_settings_service.dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════════════════
// BUBBLE SETTINGS MODEL
// ═══════════════════════════════════════════════════════════════════════════

class BubbleSettings {
  final bool enabled;
  final bool soundEnabled;
  final bool vibrationEnabled;
  final bool showOnLockScreen;
  final bool persistAcrossRestart;
  final bool autoHideWhenChatOpen;
  final bool showUnreadBadge;
  final bool showOnlineIndicator;
  final bool showTypingIndicator;
  final bool contextualHeaderEnabled;
  final int maxBubbles;
  final int autoHideMinutes;
  final BubbleSize bubbleSize;
  final BubblePosition defaultPosition;

  const BubbleSettings({
    this.enabled = true,
    this.soundEnabled = true,
    this.vibrationEnabled = true,
    this.showOnLockScreen = false,
    this.persistAcrossRestart = true,
    this.autoHideWhenChatOpen = true,
    this.showUnreadBadge = true,
    this.showOnlineIndicator = true,
    this.showTypingIndicator = true,
    this.contextualHeaderEnabled = true,
    this.maxBubbles = 5,
    this.autoHideMinutes = 0, // 0 = never auto-hide
    this.bubbleSize = BubbleSize.medium,
    this.defaultPosition = BubblePosition.right,
  });

  BubbleSettings copyWith({
    bool? enabled,
    bool? soundEnabled,
    bool? vibrationEnabled,
    bool? showOnLockScreen,
    bool? persistAcrossRestart,
    bool? autoHideWhenChatOpen,
    bool? showUnreadBadge,
    bool? showOnlineIndicator,
    bool? showTypingIndicator,
    bool? contextualHeaderEnabled,
    int? maxBubbles,
    int? autoHideMinutes,
    BubbleSize? bubbleSize,
    BubblePosition? defaultPosition,
  }) =>
      BubbleSettings(
        enabled: enabled ?? this.enabled,
        soundEnabled: soundEnabled ?? this.soundEnabled,
        vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
        showOnLockScreen: showOnLockScreen ?? this.showOnLockScreen,
        persistAcrossRestart: persistAcrossRestart ?? this.persistAcrossRestart,
        autoHideWhenChatOpen: autoHideWhenChatOpen ?? this.autoHideWhenChatOpen,
        showUnreadBadge: showUnreadBadge ?? this.showUnreadBadge,
        showOnlineIndicator: showOnlineIndicator ?? this.showOnlineIndicator,
        showTypingIndicator: showTypingIndicator ?? this.showTypingIndicator,
        contextualHeaderEnabled:
            contextualHeaderEnabled ?? this.contextualHeaderEnabled,
        maxBubbles: maxBubbles ?? this.maxBubbles,
        autoHideMinutes: autoHideMinutes ?? this.autoHideMinutes,
        bubbleSize: bubbleSize ?? this.bubbleSize,
        defaultPosition: defaultPosition ?? this.defaultPosition,
      );
}

enum BubbleSize { small, medium, large }

enum BubblePosition { left, right, auto }

// ═══════════════════════════════════════════════════════════════════════════
// SERVICE
// ═══════════════════════════════════════════════════════════════════════════

class BubbleSettingsService extends ChangeNotifier {
  // ── Singleton ────────────────────────────────────────────────────────────
  static final BubbleSettingsService _instance = BubbleSettingsService._();
  factory BubbleSettingsService() => _instance;
  BubbleSettingsService._();

  // ── State ─────────────────────────────────────────────────────────────────
  BubbleSettings _settings = const BubbleSettings();
  BubbleSettings get settings => _settings;

  bool _loaded = false;
  bool get isLoaded => _loaded;

  // ── SharedPreferences keys ────────────────────────────────────────────────
  static const _ns = 'bubble_settings_';
  static const _kEnabled = '${_ns}enabled';
  static const _kSound = '${_ns}sound';
  static const _kVibration = '${_ns}vibration';
  static const _kLockScreen = '${_ns}lockScreen';
  static const _kPersist = '${_ns}persist';
  static const _kAutoHideChat = '${_ns}autoHideChat';
  static const _kBadge = '${_ns}badge';
  static const _kOnline = '${_ns}online';
  static const _kTyping = '${_ns}typing';
  static const _kContextual = '${_ns}contextual';
  static const _kMaxBubbles = '${_ns}maxBubbles';
  static const _kAutoHideMin = '${_ns}autoHideMin';
  static const _kBubbleSize = '${_ns}bubbleSize';
  static const _kPosition = '${_ns}position';

  // ─── Load / Save ─────────────────────────────────────────────────────────

  Future<void> load() async {
    if (_loaded) return;
    try {
      final p = await SharedPreferences.getInstance();
      _settings = BubbleSettings(
        enabled: p.getBool(_kEnabled) ?? true,
        soundEnabled: p.getBool(_kSound) ?? true,
        vibrationEnabled: p.getBool(_kVibration) ?? true,
        showOnLockScreen: p.getBool(_kLockScreen) ?? false,
        persistAcrossRestart: p.getBool(_kPersist) ?? true,
        autoHideWhenChatOpen: p.getBool(_kAutoHideChat) ?? true,
        showUnreadBadge: p.getBool(_kBadge) ?? true,
        showOnlineIndicator: p.getBool(_kOnline) ?? true,
        showTypingIndicator: p.getBool(_kTyping) ?? true,
        contextualHeaderEnabled: p.getBool(_kContextual) ?? true,
        maxBubbles: p.getInt(_kMaxBubbles) ?? 5,
        autoHideMinutes: p.getInt(_kAutoHideMin) ?? 0,
        bubbleSize: BubbleSize.values[(p.getInt(_kBubbleSize) ?? 1)
            .clamp(0, BubbleSize.values.length - 1)],
        defaultPosition: BubblePosition.values[(p.getInt(_kPosition) ?? 1)
            .clamp(0, BubblePosition.values.length - 1)],
      );
      _loaded = true;
      debugPrint('✅ BubbleSettings loaded');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ BubbleSettings.load: $e');
    }
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kEnabled, _settings.enabled);
      await p.setBool(_kSound, _settings.soundEnabled);
      await p.setBool(_kVibration, _settings.vibrationEnabled);
      await p.setBool(_kLockScreen, _settings.showOnLockScreen);
      await p.setBool(_kPersist, _settings.persistAcrossRestart);
      await p.setBool(_kAutoHideChat, _settings.autoHideWhenChatOpen);
      await p.setBool(_kBadge, _settings.showUnreadBadge);
      await p.setBool(_kOnline, _settings.showOnlineIndicator);
      await p.setBool(_kTyping, _settings.showTypingIndicator);
      await p.setBool(_kContextual, _settings.contextualHeaderEnabled);
      await p.setInt(_kMaxBubbles, _settings.maxBubbles);
      await p.setInt(_kAutoHideMin, _settings.autoHideMinutes);
      await p.setInt(_kBubbleSize, _settings.bubbleSize.index);
      await p.setInt(_kPosition, _settings.defaultPosition.index);
    } catch (e) {
      debugPrint('❌ BubbleSettings.save: $e');
    }
  }

  // ─── Update helpers ───────────────────────────────────────────────────────

  Future<void> update(BubbleSettings Function(BubbleSettings) updater) async {
    _settings = updater(_settings);
    notifyListeners();
    await _save();
  }

  Future<void> setEnabled(bool v) => update((s) => s.copyWith(enabled: v));
  Future<void> setSound(bool v) => update((s) => s.copyWith(soundEnabled: v));
  Future<void> setVibration(bool v) =>
      update((s) => s.copyWith(vibrationEnabled: v));
  Future<void> setShowOnLockScreen(bool v) =>
      update((s) => s.copyWith(showOnLockScreen: v));
  Future<void> setPersist(bool v) =>
      update((s) => s.copyWith(persistAcrossRestart: v));
  Future<void> setAutoHideWhenChatOpen(bool v) =>
      update((s) => s.copyWith(autoHideWhenChatOpen: v));
  Future<void> setShowBadge(bool v) =>
      update((s) => s.copyWith(showUnreadBadge: v));
  Future<void> setShowOnline(bool v) =>
      update((s) => s.copyWith(showOnlineIndicator: v));
  Future<void> setShowTyping(bool v) =>
      update((s) => s.copyWith(showTypingIndicator: v));
  Future<void> setContextualHeader(bool v) =>
      update((s) => s.copyWith(contextualHeaderEnabled: v));
  Future<void> setMaxBubbles(int v) =>
      update((s) => s.copyWith(maxBubbles: v.clamp(1, 10)));
  Future<void> setAutoHideMinutes(int v) =>
      update((s) => s.copyWith(autoHideMinutes: v));
  Future<void> setBubbleSize(BubbleSize v) =>
      update((s) => s.copyWith(bubbleSize: v));
  Future<void> setDefaultPosition(BubblePosition v) =>
      update((s) => s.copyWith(defaultPosition: v));

  Future<void> resetToDefaults() async {
    _settings = const BubbleSettings();
    notifyListeners();
    await _save();
    debugPrint('✅ BubbleSettings reset to defaults');
  }

  // ── Convenience getters ───────────────────────────────────────────────────
  bool get isEnabled => _settings.enabled;
}
