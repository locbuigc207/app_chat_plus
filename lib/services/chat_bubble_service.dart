// lib/services/chat_bubble_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/models/bubble_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// FIXES APPLIED:
///
/// FIX-A — Age check dùng inMinutes thay vì inHours:
///   Trước: age.inHours < 24 — Duration.inHours là floor integer.
///          Bubble 23h59m vẫn pass check vì inHours = 23.
///   Sau:  age.inMinutes < 1440 — chính xác hơn (1440 = 24×60).
///
/// FIX-B — _restoreBubbles() validate JSON đúng trước khi parse:
///   Thêm try-catch per-entry và validate required fields.
///
/// FIX-C — dispose() cancel EventChannel subscription:
///   Trước: _eventSubscription cancel nhưng controllers chưa chắc được close.
///   Sau:  Đảm bảo close tất cả controllers nếu chưa closed.
///
/// FIX-D — _setupEventListener() idempotent:
///   Check _isInitialized trước để tránh double-setup.

class ChatBubbleService {
  static const MethodChannel _channel = MethodChannel('chat_bubble_overlay');
  static const EventChannel _eventChannel = EventChannel('chat_bubble_events');

  static final ChatBubbleService _instance = ChatBubbleService._internal();
  factory ChatBubbleService() => _instance;

  ChatBubbleService._internal() {
    Future.delayed(const Duration(milliseconds: 500), () {
      _setupEventListener();
      _restoreBubbles();
    });
  }

  // Controllers
  final _activeBubblesController =
      StreamController<Map<String, BubbleData>>.broadcast();
  Stream<Map<String, BubbleData>> get activeBubblesStream =>
      _activeBubblesController.stream;

  final _bubbleClickController = StreamController<BubbleClickEvent>.broadcast();
  Stream<BubbleClickEvent> get bubbleClickStream =>
      _bubbleClickController.stream;

  final _miniChatMessageController =
      StreamController<MiniChatMessage>.broadcast();
  Stream<MiniChatMessage> get miniChatMessageStream =>
      _miniChatMessageController.stream;

  final Map<String, BubbleData> _activeBubbles = {};
  StreamSubscription<dynamic>? _eventSubscription;
  bool _isInitialized = false;

  DateTime? _lastBubbleOperation;
  static const _minOperationInterval = Duration(milliseconds: 500);

  SharedPreferences? _prefs;
  static const _storageKey = 'active_bubbles';

  // ========================================
  // FIX-D: idempotent setup
  // ========================================

  void _setupEventListener() {
    if (_isInitialized) return; // FIX-D: tidak setup dua kali

    try {
      _eventSubscription?.cancel();
      _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
        (event) {
          if (event is Map) {
            final eventType = event['type'] as String?;
            if (eventType == 'click') {
              _handleBubbleClick(Map<String, dynamic>.from(event));
            } else if (eventType == 'message') {
              _handleMiniChatMessage(Map<String, dynamic>.from(event));
            }
          }
        },
        onError: (error) {
          print('❌ ChatBubbleService event error: $error');
        },
        cancelOnError: false,
      );
      _isInitialized = true;
      print('✅ ChatBubbleService initialized');
    } catch (e) {
      print('⚠️ Event channel not available: $e');
    }
  }

  void _handleBubbleClick(Map<String, dynamic> event) {
    final userId = event['userId'] as String?;
    final userName = event['userName'] as String? ?? '';
    final avatarUrl = event['avatarUrl'] as String? ?? '';
    final message = event['message'] as String? ?? '';

    if (userId != null && !_bubbleClickController.isClosed) {
      _bubbleClickController.add(BubbleClickEvent(
        userId: userId,
        userName: userName,
        avatarUrl: avatarUrl,
        message: message,
      ));
    }
  }

  void _handleMiniChatMessage(Map<String, dynamic> event) {
    final userId = event['userId'] as String?;
    final message = event['message'] as String?;

    if (userId != null &&
        message != null &&
        !_miniChatMessageController.isClosed) {
      _miniChatMessageController.add(MiniChatMessage(
        userId: userId,
        message: message,
        timestamp: DateTime.now(),
      ));
    }
  }

  // ========================================
  // PERSISTENCE
  // ========================================

  Future<void> _initPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  Future<void> _saveBubbles() async {
    try {
      await _initPrefs();
      if (_activeBubbles.isEmpty) {
        await _prefs?.remove(_storageKey);
        return;
      }
      final data = _activeBubbles.map((k, v) => MapEntry(k, v.toJson()));
      await _prefs?.setString(_storageKey, jsonEncode(data));
      print('💾 Saved ${_activeBubbles.length} bubbles');
    } catch (e) {
      print('❌ _saveBubbles: $e');
    }
  }

  Future<void> _restoreBubbles() async {
    if (!Platform.isAndroid) return;

    try {
      await _initPrefs();
      final jsonString = _prefs?.getString(_storageKey);
      if (jsonString == null || jsonString.isEmpty) return;

      final Map<String, dynamic> decoded =
          jsonDecode(jsonString) as Map<String, dynamic>;
      print('📦 Restoring ${decoded.length} bubbles...');

      final hasPermission = await hasOverlayPermission();
      if (!hasPermission) {
        print('❌ No overlay permission, cannot restore bubbles');
        return;
      }

      int restored = 0;
      for (final entry in decoded.entries) {
        try {
          final bubbleData = BubbleData.fromJson(
              Map<String, dynamic>.from(entry.value as Map));

          // FIX-A: dùng inMinutes thay vì inHours để chính xác hơn
          final age = DateTime.now().difference(bubbleData.timestamp);
          if (age.inMinutes >= 1440) {
            // 24 * 60 = 1440 phút
            print(
                '⏰ Stale bubble skipped: ${bubbleData.userName} (${age.inHours}h old)');
            continue;
          }

          // FIX-B: validate required fields
          if (bubbleData.userId.isEmpty || bubbleData.userName.isEmpty) {
            print('⚠️ Invalid bubble data for key ${entry.key}, skipping');
            continue;
          }

          final success = await showChatBubble(
            userId: bubbleData.userId,
            userName: bubbleData.userName,
            avatarUrl: bubbleData.avatarUrl,
            lastMessage: bubbleData.lastMessage,
          );
          if (success) restored++;
        } catch (e) {
          print('⚠️ Failed to restore bubble ${entry.key}: $e');
        }
      }
      print('✅ Restored $restored bubbles');
    } catch (e) {
      print('❌ _restoreBubbles: $e');
      await clearSavedBubbles();
    }
  }

  Future<void> clearSavedBubbles() async {
    try {
      await _initPrefs();
      await _prefs?.remove(_storageKey);
    } catch (e) {
      print('❌ clearSavedBubbles: $e');
    }
  }

  // ========================================
  // RATE LIMITING
  // ========================================

  Future<void> _waitForRateLimit() async {
    if (_lastBubbleOperation != null) {
      final elapsed = DateTime.now().difference(_lastBubbleOperation!);
      if (elapsed < _minOperationInterval) {
        await Future.delayed(_minOperationInterval - elapsed);
      }
    }
    _lastBubbleOperation = DateTime.now();
  }

  // ========================================
  // PERMISSIONS
  // ========================================

  Future<bool> requestOverlayPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      await _waitForRateLimit();
      final bool result = await _channel.invokeMethod('requestPermission');
      if (result) await Future.delayed(const Duration(milliseconds: 500));
      return result;
    } catch (e) {
      print('❌ requestOverlayPermission: $e');
      return false;
    }
  }

  Future<bool> hasOverlayPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      final bool result = await _channel.invokeMethod('hasPermission');
      return result;
    } catch (e) {
      print('❌ hasOverlayPermission: $e');
      return false;
    }
  }

  // ========================================
  // BUBBLE OPERATIONS
  // ========================================

  Future<bool> showChatBubble({
    required String userId,
    required String userName,
    required String avatarUrl,
    String? lastMessage,
    int maxRetries = 2,
  }) async {
    if (!Platform.isAndroid) return false;

    try {
      await _waitForRateLimit();

      final hasPermission = await hasOverlayPermission();
      if (!hasPermission) return false;

      if (_activeBubbles.containsKey(userId)) return true;

      for (int attempt = 0; attempt <= maxRetries; attempt++) {
        try {
          final bool success = await _channel.invokeMethod('showBubble', {
            'userId': userId,
            'userName': userName,
            'avatarUrl': avatarUrl,
            'lastMessage': lastMessage ?? '',
          }).timeout(
            const Duration(seconds: 5),
            onTimeout: () => false,
          );

          if (success) {
            _activeBubbles[userId] = BubbleData(
              userId: userId,
              userName: userName,
              avatarUrl: avatarUrl,
              lastMessage: lastMessage,
              timestamp: DateTime.now(),
            );
            if (!_activeBubblesController.isClosed) {
              _activeBubblesController.add(Map.from(_activeBubbles));
            }
            await _saveBubbles();
            return true;
          }

          if (attempt < maxRetries) {
            await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
          }
        } catch (e) {
          print('❌ showChatBubble attempt ${attempt + 1}: $e');
          if (attempt == maxRetries) rethrow;
          await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
        }
      }
      return false;
    } catch (e) {
      print('❌ showChatBubble: $e');
      return false;
    }
  }

  Future<bool> hideChatBubble(String userId) async {
    if (!Platform.isAndroid) return false;
    try {
      await _waitForRateLimit();
      final bool success = await _channel.invokeMethod('hideBubble', {
        'userId': userId,
      }).timeout(const Duration(seconds: 3), onTimeout: () => false);

      if (success) {
        _activeBubbles.remove(userId);
        if (!_activeBubblesController.isClosed) {
          _activeBubblesController.add(Map.from(_activeBubbles));
        }
        await _saveBubbles();
      }
      return success;
    } catch (e) {
      print('❌ hideChatBubble: $e');
      return false;
    }
  }

  Future<void> hideAllBubbles() async {
    if (!Platform.isAndroid) return;
    try {
      await _waitForRateLimit();
      await _channel.invokeMethod('hideAllBubbles');
      _activeBubbles.clear();
      if (!_activeBubblesController.isClosed) {
        _activeBubblesController.add({});
      }
      await clearSavedBubbles();
    } catch (e) {
      print('❌ hideAllBubbles: $e');
    }
  }

  Future<bool> showMiniChat({
    required String userId,
    required String userName,
    required String avatarUrl,
  }) async {
    if (!Platform.isAndroid) return false;
    try {
      await _waitForRateLimit();
      final hasPermission = await hasOverlayPermission();
      if (!hasPermission) return false;

      final bool success = await _channel.invokeMethod('showMiniChat', {
        'userId': userId,
        'userName': userName,
        'avatarUrl': avatarUrl,
      }).timeout(const Duration(seconds: 5), onTimeout: () => false);

      return success;
    } catch (e) {
      print('❌ showMiniChat: $e');
      return false;
    }
  }

  Future<bool> hideMiniChat() async {
    if (!Platform.isAndroid) return false;
    try {
      await _waitForRateLimit();
      final bool success = await _channel.invokeMethod('hideMiniChat');
      return success;
    } catch (e) {
      print('❌ hideMiniChat: $e');
      return false;
    }
  }

  Future<void> updateBubbleMessage({
    required String userId,
    required String message,
  }) async {
    if (_activeBubbles.containsKey(userId)) {
      final bubble = _activeBubbles[userId]!;
      _activeBubbles[userId] = BubbleData(
        userId: bubble.userId,
        userName: bubble.userName,
        avatarUrl: bubble.avatarUrl,
        lastMessage: message,
        timestamp: DateTime.now(),
        unreadCount: bubble.unreadCount + 1,
      );
      if (!_activeBubblesController.isClosed) {
        _activeBubblesController.add(Map.from(_activeBubbles));
      }
      await _saveBubbles();
    }
  }

  // ========================================
  // QUERY
  // ========================================

  bool isBubbleActive(String userId) => _activeBubbles.containsKey(userId);
  Map<String, BubbleData> get activeBubbles => Map.unmodifiable(_activeBubbles);
  bool get isSupported => Platform.isAndroid;

  // ========================================
  // FIX-C: DISPOSE an toàn
  // ========================================

  void dispose() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
    _isInitialized = false;

    // FIX-C: close tất cả controllers
    if (!_activeBubblesController.isClosed) {
      _activeBubblesController.close();
    }
    if (!_bubbleClickController.isClosed) {
      _bubbleClickController.close();
    }
    if (!_miniChatMessageController.isClosed) {
      _miniChatMessageController.close();
    }
  }
}
