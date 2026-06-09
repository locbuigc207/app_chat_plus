import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service that wraps the Android Bubble API (Android 11+ / API 30+).
/// Uses [MethodChannel] for imperative calls and [EventChannel] for
/// native → Dart events (bubble click, dismiss, expand, etc.).
class BubbleServiceV2 {
  // ── Channels ──────────────────────────────────────────────────────────────
  static const _method = MethodChannel('chat_bubbles_v2');
  static const _event = EventChannel('chat_bubble_events_v2');

  // ── Singleton ─────────────────────────────────────────────────────────────
  static final BubbleServiceV2 _instance = BubbleServiceV2._internal();
  factory BubbleServiceV2() => _instance;
  BubbleServiceV2._internal();

  // ── State ─────────────────────────────────────────────────────────────────
  bool _isInitialized = false;
  bool _isDisposing = false;
  bool _isBubbleApiSupported = false;

  StreamSubscription<dynamic>? _eventSubscription;
  SharedPreferences? _prefs;

  final Map<String, BubbleData> _activeBubbles = {};

  // ── Stream controllers ────────────────────────────────────────────────────
  StreamController<BubbleClickEvent>? _clickCtrl;
  StreamController<Map<String, BubbleData>>? _bubblesCtrl;

  Stream<BubbleClickEvent> get bubbleClickStream {
    _ensureClickCtrl();
    return _clickCtrl!.stream;
  }

  Stream<Map<String, BubbleData>> get activeBubblesStream {
    _ensureBubblesCtrl();
    return _bubblesCtrl!.stream;
  }

  void _ensureClickCtrl() {
    if (_clickCtrl == null || _clickCtrl!.isClosed) {
      _clickCtrl = StreamController<BubbleClickEvent>.broadcast();
    }
  }

  void _ensureBubblesCtrl() {
    if (_bubblesCtrl == null || _bubblesCtrl!.isClosed) {
      _bubblesCtrl = StreamController<Map<String, BubbleData>>.broadcast();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INITIALISATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Must be called once (e.g. from [UnifiedBubbleService]).
  Future<void> initialize() async {
    if (_isInitialized || _isDisposing) return;
    try {
      _isBubbleApiSupported = await checkBubbleApiSupport();
      if (!_isBubbleApiSupported) {
        debugPrint('⚠️ BubbleServiceV2: Bubble API not supported on device');
        return;
      }
      _ensureClickCtrl();
      _ensureBubblesCtrl();
      _setupEventListener();
      _prefs = await SharedPreferences.getInstance();
      await _restoreBubbles();
      _isInitialized = true;
      debugPrint('✅ BubbleServiceV2 initialized');
    } catch (e, st) {
      debugPrint('❌ BubbleServiceV2 init failed: $e\n$st');
    }
  }

  Future<bool> checkBubbleApiSupport() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _method.invokeMethod<bool>('checkBubbleApiSupport') ?? false;
    } catch (e) {
      debugPrint('❌ checkBubbleApiSupport: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EVENT LISTENER
  // ═══════════════════════════════════════════════════════════════════════════

  void _setupEventListener() {
    _eventSubscription?.cancel();
    try {
      _eventSubscription = _event.receiveBroadcastStream().listen(
        (raw) {
          if (_isDisposing || raw is! Map) return;
          _handleEvent(Map<String, dynamic>.from(raw as Map));
        },
        onError: (Object err) =>
            debugPrint('❌ BubbleServiceV2 event error: $err'),
        cancelOnError: false,
      );
      debugPrint('✅ BubbleServiceV2 event listener active');
    } catch (e) {
      debugPrint('❌ Event listener setup failed: $e');
    }
  }

  void _handleEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    switch (type) {
      case 'click':
        _onBubbleClick(event);
        break;
      case 'dismiss':
        _onBubbleDismiss(event);
        break;
      case 'expand':
        debugPrint('🔔 Bubble expanded: ${event['userId']}');
        break;
      default:
        debugPrint('⚠️ Unknown bubble event type: $type');
    }
  }

  void _onBubbleClick(Map<String, dynamic> event) {
    final userId = event['userId'] as String?;
    if (userId == null) return;
    _ensureClickCtrl();
    if (!(_clickCtrl?.isClosed ?? true)) {
      _clickCtrl!.add(BubbleClickEvent(
        userId: userId,
        userName: event['userName'] as String? ?? '',
        avatarUrl: event['avatarUrl'] as String? ?? '',
        message: event['message'] as String? ?? '',
      ));
    }
  }

  void _onBubbleDismiss(Map<String, dynamic> event) {
    final userId = event['userId'] as String?;
    if (userId != null) {
      _activeBubbles.remove(userId);
      _emitActiveBubbles();
      _saveBubbles();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUBBLE MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  Future<bool> showBubble({
    required String userId,
    required String userName,
    required String message,
    String? avatarUrl,
    bool isOnline = false,
  }) async {
    if (!_isBubbleApiSupported) return false;

    try {
      // If already active, just update
      if (_activeBubbles.containsKey(userId)) {
        return await updateBubble(userId: userId, message: message);
      }

      final success = await _method.invokeMethod<bool>('showBubble', {
            'userId': userId,
            'userName': userName,
            'message': message,
            'avatarUrl': avatarUrl ?? '',
            'isOnline': isOnline,
          }) ??
          false;

      if (success) {
        _activeBubbles[userId] = BubbleData(
          userId: userId,
          userName: userName,
          avatarUrl: avatarUrl ?? '',
          lastMessage: message,
          timestamp: DateTime.now(),
          isOnline: isOnline,
        );
        _emitActiveBubbles();
        await _saveBubbles();
        debugPrint('🫧 Bubble shown for $userName');
      }
      return success;
    } catch (e) {
      debugPrint('❌ showBubble: $e');
      return false;
    }
  }

  Future<bool> updateBubble({
    required String userId,
    required String message,
    bool incrementUnread = true,
  }) async {
    if (!_isBubbleApiSupported) return false;
    final existing = _activeBubbles[userId];
    if (existing == null) return false;

    try {
      final success = await _method.invokeMethod<bool>('updateBubble', {
            'userId': userId,
            'message': message,
          }) ??
          false;

      if (success) {
        _activeBubbles[userId] = existing.copyWith(
          lastMessage: message,
          timestamp: DateTime.now(),
          unreadCount:
              incrementUnread ? existing.unreadCount + 1 : existing.unreadCount,
        );
        _emitActiveBubbles();
        await _saveBubbles();
      }
      return success;
    } catch (e) {
      debugPrint('❌ updateBubble: $e');
      return false;
    }
  }

  Future<bool> hideBubble(String userId) async {
    if (!_isBubbleApiSupported) return false;
    try {
      final success =
          await _method.invokeMethod<bool>('hideBubble', {'userId': userId}) ??
              false;
      if (success) {
        _activeBubbles.remove(userId);
        _emitActiveBubbles();
        await _saveBubbles();
      }
      return success;
    } catch (e) {
      debugPrint('❌ hideBubble: $e');
      return false;
    }
  }

  Future<void> hideAllBubbles() async {
    if (!_isBubbleApiSupported) return;
    try {
      await _method.invokeMethod('hideAllBubbles');
      _activeBubbles.clear();
      _emitActiveBubbles();
      await _clearSavedBubbles();
    } catch (e) {
      debugPrint('❌ hideAllBubbles: $e');
    }
  }

  Future<bool> clearUnread(String userId) async {
    final existing = _activeBubbles[userId];
    if (existing == null) return false;
    _activeBubbles[userId] = existing.copyWith(unreadCount: 0);
    _emitActiveBubbles();
    await _saveBubbles();
    return true;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ADVANCED NATIVE METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<bool> sendMessage({
    required String userId,
    required String userName,
    required String message,
    required String avatarUrl,
    String messageType = 'text',
  }) async {
    try {
      return await _method.invokeMethod<bool>('sendMessage', {
            'userId': userId,
            'userName': userName,
            'message': message,
            'avatarUrl': avatarUrl,
            'messageType': messageType,
          }) ??
          false;
    } catch (e) {
      debugPrint('❌ sendMessage: $e');
      return false;
    }
  }

  Future<int> getShortcutCount() async {
    try {
      return await _method.invokeMethod<int>('getShortcutCount') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<bool> verifyShortcut(String userId) async {
    try {
      return await _method
              .invokeMethod<bool>('verifyShortcut', {'userId': userId}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> getBubbleStats() async {
    try {
      final result = await _method.invokeMethod<Map>('getBubbleStats');
      return result?.cast<String, dynamic>() ?? {};
    } catch (_) {
      return {};
    }
  }

  Future<void> logBubbleState() async {
    try {
      await _method.invokeMethod('logBubbleState');
    } catch (_) {}
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PERSISTENCE
  // ═══════════════════════════════════════════════════════════════════════════

  static const _prefKey = 'bubbles_v2';

  Future<void> _saveBubbles() async {
    try {
      await _initPrefs();
      if (_activeBubbles.isEmpty) {
        await _prefs?.remove(_prefKey);
        return;
      }
      final data = _activeBubbles.map((k, v) => MapEntry(k, v.toJson()));
      await _prefs?.setString(_prefKey, jsonEncode(data));
    } catch (e) {
      debugPrint('❌ _saveBubbles: $e');
    }
  }

  Future<void> _restoreBubbles() async {
    try {
      await _initPrefs();
      final raw = _prefs?.getString(_prefKey);
      if (raw == null || raw.isEmpty) return;

      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      int restored = 0;
      for (final entry in decoded.entries) {
        try {
          final data = BubbleData.fromJson(
              Map<String, dynamic>.from(entry.value as Map));
          if (!data.isValid || data.isStale) continue;
          _activeBubbles[entry.key] = data;
          restored++;
        } catch (e) {
          debugPrint('⚠️ Failed to restore bubble ${entry.key}: $e');
        }
      }
      if (restored > 0) {
        _emitActiveBubbles();
        debugPrint('📦 Restored $restored bubble(s)');
      }
    } catch (e) {
      debugPrint('❌ _restoreBubbles: $e');
      await _clearSavedBubbles();
    }
  }

  Future<void> _clearSavedBubbles() async {
    try {
      await _initPrefs();
      await _prefs?.remove(_prefKey);
    } catch (e) {
      debugPrint('❌ _clearSavedBubbles: $e');
    }
  }

  Future<void> _initPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  void _emitActiveBubbles() {
    _ensureBubblesCtrl();
    if (!(_bubblesCtrl?.isClosed ?? true)) {
      _bubblesCtrl!.add(Map.unmodifiable(_activeBubbles));
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  bool get isSupported => _isBubbleApiSupported;
  bool get isInitialized => _isInitialized;
  bool isBubbleActive(String userId) => _activeBubbles.containsKey(userId);
  Map<String, BubbleData> get activeBubbles => Map.unmodifiable(_activeBubbles);
  int get activeBubbleCount => _activeBubbles.length;
  BubbleData? getBubble(String userId) => _activeBubbles[userId];

  // ═══════════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═══════════════════════════════════════════════════════════════════════════

  void dispose() {
    if (_isDisposing) return;
    _isDisposing = true;
    debugPrint('🗑️ BubbleServiceV2 disposing...');

    _eventSubscription?.cancel();
    _eventSubscription = null;

    if (!(_clickCtrl?.isClosed ?? true)) _clickCtrl!.close();
    if (!(_bubblesCtrl?.isClosed ?? true)) _bubblesCtrl!.close();
    _clickCtrl = null;
    _bubblesCtrl = null;

    _isInitialized = false;
    _isDisposing = false;
    debugPrint('✅ BubbleServiceV2 disposed');
  }

  Future<void> reinitialize() async {
    if (_isInitialized) return;
    await initialize();
  }
}
