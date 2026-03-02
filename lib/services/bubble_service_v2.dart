// lib/services/bubble_service_v2.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/models/bubble_models.dart'; // ✅ Import shared models
import 'package:shared_preferences/shared_preferences.dart';

class BubbleServiceV2 {
  static const MethodChannel _channel = MethodChannel('chat_bubbles_v2');
  static const EventChannel _eventChannel =
  EventChannel('chat_bubble_events_v2');

  static final BubbleServiceV2 _instance = BubbleServiceV2._internal();
  factory BubbleServiceV2() => _instance;

  BubbleServiceV2._internal() {
    _initialize();
  }

  bool _isInitialized = false;
  bool _isBubbleApiSupported = false;
  StreamSubscription? _eventSubscription;
  SharedPreferences? _prefs;

  final Map<String, BubbleData> _activeBubbles = {};

  final _bubbleClickController = StreamController<BubbleClickEvent>.broadcast();
  Stream<BubbleClickEvent> get bubbleClickStream =>
      _bubbleClickController.stream;

  final _activeBubblesController =
  StreamController<Map<String, BubbleData>>.broadcast();
  Stream<Map<String, BubbleData>> get activeBubblesStream =>
      _activeBubblesController.stream;

  Future<void> _initialize() async {
    if (_isInitialized) return;

    try {
      _isBubbleApiSupported = await checkBubbleApiSupport();

      if (!_isBubbleApiSupported) {
        print('⚠️ Bubble API not supported on this device');
        return;
      }

      print('✅ Bubble API is supported');
      _setupEventListener();
      _prefs = await SharedPreferences.getInstance();
      await _restoreBubbles();

      _isInitialized = true;
      print('✅ BubbleServiceV2 initialized');
    } catch (e) {
      print('❌ BubbleServiceV2 initialization failed: $e');
    }
  }

  Future<bool> checkBubbleApiSupport() async {
    if (!Platform.isAndroid) return false;

    try {
      final result = await _channel.invokeMethod<bool>('checkBubbleApiSupport');
      return result ?? false;
    } catch (e) {
      print('❌ Error checking Bubble API support: $e');
      return false;
    }
  }

  void _setupEventListener() {
    try {
      _eventSubscription?.cancel();
      _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
            (event) {
          if (event is Map) {
            _handleBubbleEvent(event);
          }
        },
        onError: (error) {
          print('❌ Bubble event error: $error');
        },
      );
      print('✅ Event listener setup complete');
    } catch (e) {
      print('❌ Event listener setup failed: $e');
    }
  }

  void _handleBubbleEvent(Map event) {
    final type = event['type'] as String?;

    if (type == 'click') {
      final userId = event['userId'] as String?;
      final userName = event['userName'] as String?;
      final avatarUrl = event['avatarUrl'] as String?;
      final message = event['message'] as String? ?? '';

      if (userId != null) {
        _bubbleClickController.add(BubbleClickEvent(
          userId: userId,
          userName: userName ?? '',
          avatarUrl: avatarUrl ?? '',
          message: message,
        ));
      }
    }
  }

  Future<bool> showBubble({
    required String userId,
    required String userName,
    required String message,
    String? avatarUrl,
  }) async {
    if (!_isBubbleApiSupported) {
      print('⚠️ Bubble API not supported, cannot show bubble');
      return false;
    }

    try {
      print('🎈 Showing bubble for: $userName');

      if (_activeBubbles.containsKey(userId)) {
        print('ℹ️ Bubble already exists, updating message');
        return await updateBubble(userId: userId, message: message);
      }

      final result = await _channel.invokeMethod<bool>('showBubble', {
        'userId': userId,
        'userName': userName,
        'message': message,
        'avatarUrl': avatarUrl ?? '',
      });

      if (result == true) {
        _activeBubbles[userId] = BubbleData(
          userId: userId,
          userName: userName,
          avatarUrl: avatarUrl ?? '',
          lastMessage: message,
          timestamp: DateTime.now(),
        );

        _activeBubblesController.add(Map.from(_activeBubbles));
        await _saveBubbles();

        print('✅ Bubble created successfully');
        return true;
      }

      print('❌ Failed to create bubble');
      return false;
    } catch (e) {
      print('❌ Error showing bubble: $e');
      return false;
    }
  }

  Future<bool> updateBubble({
    required String userId,
    required String message,
  }) async {
    if (!_isBubbleApiSupported) return false;

    try {
      final bubble = _activeBubbles[userId];
      if (bubble == null) {
        print('⚠️ Bubble not found: $userId');
        return false;
      }

      final result = await _channel.invokeMethod<bool>('updateBubble', {
        'userId': userId,
        'message': message,
      });

      if (result == true) {
        _activeBubbles[userId] = BubbleData(
          userId: bubble.userId,
          userName: bubble.userName,
          avatarUrl: bubble.avatarUrl,
          lastMessage: message,
          timestamp: DateTime.now(),
          unreadCount: bubble.unreadCount + 1,
        );

        _activeBubblesController.add(Map.from(_activeBubbles));
        await _saveBubbles();

        print('✅ Bubble updated');
        return true;
      }

      return false;
    } catch (e) {
      print('❌ Error updating bubble: $e');
      return false;
    }
  }

  Future<bool> hideBubble(String userId) async {
    if (!_isBubbleApiSupported) return false;

    try {
      print('🗑️ Hiding bubble: $userId');

      final result = await _channel.invokeMethod<bool>('hideBubble', {
        'userId': userId,
      });

      if (result == true) {
        _activeBubbles.remove(userId);
        _activeBubblesController.add(Map.from(_activeBubbles));
        await _saveBubbles();

        print('✅ Bubble hidden');
        return true;
      }

      return false;
    } catch (e) {
      print('❌ Error hiding bubble: $e');
      return false;
    }
  }

  Future<void> hideAllBubbles() async {
    if (!_isBubbleApiSupported) return;

    try {
      await _channel.invokeMethod('hideAllBubbles');

      _activeBubbles.clear();
      _activeBubblesController.add({});
      await _clearSavedBubbles();

      print('✅ All bubbles hidden');
    } catch (e) {
      print('❌ Error hiding all bubbles: $e');
    }
  }

  Future<int> getShortcutCount() async {
    try {
      final result = await _channel.invokeMethod<int>('getShortcutCount');
      return result ?? 0;
    } catch (e) {
      print('❌ Error getting shortcut count: $e');
      return 0;
    }
  }

  Future<bool> canCreateMoreShortcuts() async {
    try {
      final count = await getShortcutCount();
      return count < 5;
    } catch (e) {
      return false;
    }
  }

  Future<bool> verifyShortcut(String userId) async {
    try {
      final result = await _channel.invokeMethod<bool>('verifyShortcut', {
        'userId': userId,
      });
      return result ?? false;
    } catch (e) {
      print('❌ Error verifying shortcut: $e');
      return false;
    }
  }

  Future<void> _saveBubbles() async {
    try {
      final bubblesData = _activeBubbles.map(
            (key, value) => MapEntry(key, value.toJson()),
      );

      await _prefs?.setString('bubbles_v2', bubblesData.toString());
      print('💾 Saved ${_activeBubbles.length} bubbles');
    } catch (e) {
      print('❌ Error saving bubbles: $e');
    }
  }

  Future<void> _restoreBubbles() async {
    try {
      final savedData = _prefs?.getString('bubbles_v2');
      if (savedData == null) return;

      print('📦 Restoring saved bubbles');
    } catch (e) {
      print('❌ Error restoring bubbles: $e');
    }
  }

  Future<void> _clearSavedBubbles() async {
    try {
      await _prefs?.remove('bubbles_v2');
      print('🗑️ Cleared saved bubbles');
    } catch (e) {
      print('❌ Error clearing bubbles: $e');
    }
  }

  bool get isSupported => _isBubbleApiSupported;
  bool get isInitialized => _isInitialized;

  bool isBubbleActive(String userId) => _activeBubbles.containsKey(userId);

  Map<String, BubbleData> get activeBubbles => Map.unmodifiable(_activeBubbles);

  int get activeBubbleCount => _activeBubbles.length;

  void dispose() {
    _eventSubscription?.cancel();
    _bubbleClickController.close();
    _activeBubblesController.close();
    _isInitialized = false;
  }
}
