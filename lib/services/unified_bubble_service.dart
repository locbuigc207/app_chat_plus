// lib/services/unified_bubble_service.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/models/bubble_models.dart'; // ✅ Import shared models
import 'package:flutter_chat_demo/services/bubble_service_v2.dart';
import 'package:flutter_chat_demo/services/chat_bubble_service.dart';

class UnifiedBubbleService {
  late final BubbleServiceV2 _bubbleApiService;
  late final ChatBubbleService _windowManagerService;

  static final UnifiedBubbleService _instance =
      UnifiedBubbleService._internal();
  factory UnifiedBubbleService() => _instance;

  UnifiedBubbleService._internal() {
    _bubbleApiService = BubbleServiceV2();
    _windowManagerService = ChatBubbleService();
    _initialize();
  }

  // ========================================
  // STATE
  // ========================================
  bool _isInitialized = false;
  BubbleImplementation _currentImplementation = BubbleImplementation.unknown;

  // ✅ FIX 6: Operation queue to prevent race conditions
  final List<Future<void> Function()> _operationQueue = [];
  bool _isProcessingQueue = false;

  // Forwarded streams
  StreamController<BubbleClickEvent>? _clickController;
  StreamController<Map<String, dynamic>>? _bubblesController;

  Stream<BubbleClickEvent> get bubbleClickStream {
    return _clickController?.stream ?? Stream.empty();
  }

  Stream<Map<String, dynamic>> get activeBubblesStream {
    return _bubblesController?.stream ?? Stream.empty();
  }

  Future<void> _initialize() async {
    if (_isInitialized) return;

    try {
      _currentImplementation = await _detectBestImplementation();

      print('✅ Using implementation: ${_currentImplementation.name}');

      _setupStreamForwarding();

      _isInitialized = true;
      print('✅ UnifiedBubbleService initialized');
    } catch (e) {
      print('❌ UnifiedBubbleService initialization failed: $e');
    }
  }

  Future<BubbleImplementation> _detectBestImplementation() async {
    if (!Platform.isAndroid) {
      return BubbleImplementation.none;
    }

    final supportsBubbleApi = await _bubbleApiService.checkBubbleApiSupport();

    if (supportsBubbleApi) {
      print('✅ Device supports Bubble API');
      return BubbleImplementation.bubbleApi;
    }

    print('⚠️ Falling back to WindowManager');
    return BubbleImplementation.windowManager;
  }

  void _setupStreamForwarding() {
    _clickController = StreamController<BubbleClickEvent>.broadcast();
    _bubblesController = StreamController<Map<String, dynamic>>.broadcast();

    if (_currentImplementation == BubbleImplementation.bubbleApi) {
      _bubbleApiService.bubbleClickStream.listen(
        (event) => _clickController?.add(event),
      );

      _bubbleApiService.activeBubblesStream.listen(
        (bubbles) {
          final converted = bubbles.map(
            (key, value) => MapEntry(key, value.toJson()),
          );
          _bubblesController?.add(converted);
        },
      );
    } else if (_currentImplementation == BubbleImplementation.windowManager) {
      _windowManagerService.bubbleClickStream.listen(
        (event) => _clickController?.add(event),
      );

      _windowManagerService.activeBubblesStream.listen(
        (bubbles) {
          final converted = bubbles.map(
            (key, value) => MapEntry(key, value.toJson()),
          );
          _bubblesController?.add(converted);
        },
      );
    }
  }

  Future<bool> hasOverlayPermission() async {
    if (_currentImplementation == BubbleImplementation.bubbleApi) {
      return true;
    }

    return await _windowManagerService.hasOverlayPermission();
  }

  Future<bool> requestOverlayPermission() async {
    if (_currentImplementation == BubbleImplementation.bubbleApi) {
      return true;
    }

    return await _windowManagerService.requestOverlayPermission();
  }

  Future<bool> showChatBubble({
    required String userId,
    required String userName,
    required String avatarUrl,
    String? lastMessage,
  }) async {
    // ✅ FIX 6: Queue operation to prevent race conditions
    return await _queueOperation<bool>(() async {
          if (_currentImplementation == BubbleImplementation.bubbleApi) {
            return await _bubbleApiService.showBubble(
              userId: userId,
              userName: userName,
              message: lastMessage ?? 'New message',
              avatarUrl: avatarUrl,
            );
          } else if (_currentImplementation ==
              BubbleImplementation.windowManager) {
            return await _windowManagerService.showChatBubble(
              userId: userId,
              userName: userName,
              avatarUrl: avatarUrl,
              lastMessage: lastMessage,
            );
          }
          return false;
        }) ??
        false;
  }

  /// Update bubble with new message
  Future<void> updateBubbleMessage({
    required String userId,
    required String message,
  }) async {
    // ✅ FIX 6: Queue operation to prevent race conditions
    await _queueOperation(() async {
      if (_currentImplementation == BubbleImplementation.bubbleApi) {
        await _bubbleApiService.updateBubble(
          userId: userId,
          message: message,
        );
      } else if (_currentImplementation == BubbleImplementation.windowManager) {
        await _windowManagerService.updateBubbleMessage(
          userId: userId,
          message: message,
        );
      }
    });
  }

  /// Hide a specific bubble
  Future<bool> hideChatBubble(String userId) async {
    // ✅ FIX 6: Queue operation to prevent race conditions
    return await _queueOperation<bool>(() async {
          if (_currentImplementation == BubbleImplementation.bubbleApi) {
            return await _bubbleApiService.hideBubble(userId);
          } else if (_currentImplementation ==
              BubbleImplementation.windowManager) {
            return await _windowManagerService.hideChatBubble(userId);
          }
          return false;
        }) ??
        false;
  }

  /// Hide all bubbles
  Future<void> hideAllBubbles() async {
    // ✅ FIX 6: Queue operation to prevent race conditions
    await _queueOperation(() async {
      if (_currentImplementation == BubbleImplementation.bubbleApi) {
        await _bubbleApiService.hideAllBubbles();
      } else if (_currentImplementation == BubbleImplementation.windowManager) {
        await _windowManagerService.hideAllBubbles();
      }
    });
  }

  /// Show mini chat window
  Future<bool> showMiniChat({
    required String userId,
    required String userName,
    required String avatarUrl,
  }) async {
    // Mini chat only works with WindowManager for now
    // TODO: Implement mini chat for Bubble API
    // ✅ FIX 6: Queue operation to prevent race conditions
    return await _queueOperation<bool>(() async {
          if (_currentImplementation == BubbleImplementation.windowManager) {
            return await _windowManagerService.showMiniChat(
              userId: userId,
              userName: userName,
              avatarUrl: avatarUrl,
            );
          }
          print('⚠️ Mini chat not supported with Bubble API yet');
          return false;
        }) ??
        false;
  }

  /// Hide mini chat
  Future<bool> hideMiniChat() async {
    // ✅ FIX 6: Queue operation to prevent race conditions
    return await _queueOperation<bool>(() async {
          if (_currentImplementation == BubbleImplementation.windowManager) {
            return await _windowManagerService.hideMiniChat();
          }
          return false;
        }) ??
        false;
  }

  // ========================================
  // UTILITY METHODS
  // ========================================

  /// Check if bubble is active
  bool isBubbleActive(String userId) {
    if (_currentImplementation == BubbleImplementation.bubbleApi) {
      return _bubbleApiService.isBubbleActive(userId);
    } else if (_currentImplementation == BubbleImplementation.windowManager) {
      return _windowManagerService.isBubbleActive(userId);
    }

    return false;
  }

  /// Get active bubble count
  int getActiveBubbleCount() {
    if (_currentImplementation == BubbleImplementation.bubbleApi) {
      return _bubbleApiService.activeBubbleCount;
    } else if (_currentImplementation == BubbleImplementation.windowManager) {
      return _windowManagerService.activeBubbles.length;
    }

    return 0;
  }

  String getImplementationInfo() {
    switch (_currentImplementation) {
      case BubbleImplementation.bubbleApi:
        return 'Bubble API (Android 11+)';
      case BubbleImplementation.windowManager:
        return 'WindowManager (Android < 11)';
      case BubbleImplementation.none:
        return 'Not supported';
      case BubbleImplementation.unknown:
        return 'Detecting...';
    }
  }

  bool get isSupported {
    return _currentImplementation != BubbleImplementation.none;
  }

  BubbleImplementation get currentImplementation => _currentImplementation;

  Future<bool> migrateToModernApi() async {
    if (_currentImplementation == BubbleImplementation.bubbleApi) {
      print('✅ Already using Bubble API');
      return true;
    }

    // Check if can migrate
    final supportsBubbleApi = await _bubbleApiService.checkBubbleApiSupport();
    if (!supportsBubbleApi) {
      print('⚠️ Cannot migrate: Bubble API not supported');
      return false;
    }

    print('🔄 Migrating to Bubble API...');

    // ✅ FIX 6: Queue operation to prevent race conditions during migration
    return await _queueOperation<bool>(() async {
          try {
            // Get current bubbles from WindowManager
            final currentBubbles = _windowManagerService.activeBubbles;

            // Hide all WindowManager bubbles
            await _windowManagerService.hideAllBubbles();

            // Switch implementation
            _currentImplementation = BubbleImplementation.bubbleApi;
            _setupStreamForwarding();

            // Recreate bubbles with Bubble API
            for (var bubble in currentBubbles.values) {
              await _bubbleApiService.showBubble(
                userId: bubble.userId,
                userName: bubble.userName,
                message: bubble.lastMessage ?? 'New message',
                avatarUrl: bubble.avatarUrl,
              );
            }

            print('✅ Migration complete');
            return true;
          } catch (e) {
            print('❌ Migration failed: $e');
            return false;
          }
        }) ??
        false;
  }

  Future<bool> sendMessage({
    required String userId,
    required String userName,
    required String message,
    required String avatarUrl,
    String messageType = 'text', // 'text', 'image', 'voice', 'location'
  }) async {
    if (_currentImplementation != BubbleImplementation.bubbleApi) {
      print('⚠️ Send message only supported with Bubble API');
      return false;
    }

    try {
      final result = await const MethodChannel('chat_bubbles_v2')
          .invokeMethod<bool>('sendMessage', {
        'userId': userId,
        'userName': userName,
        'message': message,
        'avatarUrl': avatarUrl,
        'messageType': messageType,
      });

      if (result == true) {
        print('✅ Message sent to bubble: $message');
      }

      return result ?? false;
    } catch (e) {
      print('❌ Error sending message: $e');
      return false;
    }
  }

  /// Get message count for a bubble conversation
  Future<int> getMessageCount(String userId) async {
    if (_currentImplementation != BubbleImplementation.bubbleApi) {
      return 0;
    }

    try {
      final result = await const MethodChannel('chat_bubbles_v2')
          .invokeMethod<int>('getMessageCount', {
        'userId': userId,
      });

      return result ?? 0;
    } catch (e) {
      print('❌ Error getting message count: $e');
      return 0;
    }
  }

  Future<Map<String, dynamic>> getBubbleStats() async {
    try {
      final result = await const MethodChannel('chat_bubbles_v2')
          .invokeMethod<Map>('getBubbleStats');

      return result?.cast<String, dynamic>() ?? {};
    } catch (e) {
      print('❌ Error getting bubble stats: $e');
      return {};
    }
  }

  /// Clear message history for a user
  Future<bool> clearMessageHistory(String userId) async {
    if (_currentImplementation != BubbleImplementation.bubbleApi) {
      return false;
    }

    try {
      final result = await const MethodChannel('chat_bubbles_v2')
          .invokeMethod<bool>('clearMessageHistory', {
        'userId': userId,
      });

      if (result == true) {
        print('✅ Message history cleared for: $userId');
      }

      return result ?? false;
    } catch (e) {
      print('❌ Error clearing history: $e');
      return false;
    }
  }

  Future<void> logBubbleState() async {
    try {
      await const MethodChannel('chat_bubbles_v2')
          .invokeMethod('logBubbleState');
      print('✅ Bubble state logged (check Android logs)');
    } catch (e) {
      print('❌ Error logging bubble state: $e');
    }
  }

  // ========================================
  // ✅ FIX 10: MESSAGE TYPE HELPER
  // ========================================

  /// Helper to determine message type from content and type code
  ///
  /// TypeMessage constants:
  /// 0 = text, 1 = image, 2 = sticker, 3 = voice, 4 = location
  String _getMessageType(String content, int typeCode) {
    switch (typeCode) {
      case 1:
        return 'image';
      case 2:
        return 'text'; // Stickers treated as text for bubble
      case 3:
        return 'voice';
      case 4:
        return 'location';
      case 0:
      default:
        // Check if content contains location data
        if (content.contains('maps.google.com') ||
            content.contains('Location:') ||
            content.contains('📍')) {
          return 'location';
        }
        return 'text';
    }
  }

  /// ✅ FIX 10: Public helper for external use
  String getMessageTypeFromContent(String content, int typeCode) {
    return _getMessageType(content, typeCode);
  }

  /// ✅ FIX 10: Send message with auto-detected type
  Future<bool> sendMessageAuto({
    required String userId,
    required String userName,
    required String message,
    required String avatarUrl,
    required int typeCode,
  }) async {
    final messageType = _getMessageType(message, typeCode);

    return await sendMessage(
      userId: userId,
      userName: userName,
      message: message,
      avatarUrl: avatarUrl,
      messageType: messageType,
    );
  }

  // ========================================
  // ✅ FIX 6: OPERATION QUEUE IMPLEMENTATION
  // ========================================

  Future<T?> _queueOperation<T>(Future<T> Function() operation) async {
    final completer = Completer<T?>();
    _operationQueue.add(() async {
      try {
        final result = await operation();
        completer.complete(result);
      } catch (e) {
        completer.completeError(e);
      }
    });

    if (!_isProcessingQueue) {
      _processQueue();
    }

    return completer.future;
  }

  Future<void> _processQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    while (_operationQueue.isNotEmpty) {
      final operation = _operationQueue.removeAt(0);
      try {
        await operation();
      } catch (e) {
        print('❌ Operation failed in queue: $e');
      }
    }

    _isProcessingQueue = false;
  }

  void dispose() {
    _bubbleApiService.dispose();
    _windowManagerService.dispose();
    _clickController?.close();
    _bubblesController?.close();
    _isInitialized = false;
  }
}

enum BubbleImplementation {
  bubbleApi, // Android 11+ Bubble API
  windowManager, // Legacy WindowManager overlays
  none, // Not supported (iOS, etc)
  unknown, // Not yet detected
}
