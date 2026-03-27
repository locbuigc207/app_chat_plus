// lib/services/unified_bubble_service.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/models/bubble_models.dart';
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
  Completer<void>? _initCompleter; // FIX-C: prevent concurrent inits
  BubbleImplementation _currentImplementation = BubbleImplementation.unknown;

  // FIX-A: Operation queue với proper completion tracking
  final List<_QueuedOperation> _operationQueue = [];
  bool _isProcessingQueue = false;

  // FIX-B: Track subscriptions để cancel khi setup ulang
  final List<StreamSubscription> _streamSubscriptions = [];

  // FIX-B: Controllers riêng để có thể close và recreate
  StreamController<BubbleClickEvent>? _clickController;
  StreamController<Map<String, dynamic>>? _bubblesController;

  Stream<BubbleClickEvent> get bubbleClickStream {
    _ensureControllers();
    return _clickController!.stream;
  }

  Stream<Map<String, dynamic>> get activeBubblesStream {
    _ensureControllers();
    return _bubblesController!.stream;
  }

  void _ensureControllers() {
    if (_clickController == null || _clickController!.isClosed) {
      _clickController = StreamController<BubbleClickEvent>.broadcast();
    }
    if (_bubblesController == null || _bubblesController!.isClosed) {
      _bubblesController = StreamController<Map<String, dynamic>>.broadcast();
    }
  }

  // ========================================
  // INITIALIZATION (FIX-C)
  // ========================================

  Future<void> _initialize() async {
    // FIX-C: prevent concurrent initializations
    if (_isInitialized) return;
    if (_initCompleter != null) {
      return _initCompleter!.future;
    }

    _initCompleter = Completer<void>();
    try {
      _currentImplementation = await _detectBestImplementation();
      debugPrint('✅ UnifiedBubble: using ${_currentImplementation.name}');
      _ensureControllers();
      _setupStreamForwarding();
      _isInitialized = true;
      _initCompleter!.complete();
    } catch (e) {
      debugPrint('❌ UnifiedBubble init failed: $e');
      _initCompleter!.completeError(e);
    } finally {
      _initCompleter = null;
    }
  }

  Future<BubbleImplementation> _detectBestImplementation() async {
    if (!Platform.isAndroid) return BubbleImplementation.none;
    final supportsBubbleApi = await _bubbleApiService.checkBubbleApiSupport();
    return supportsBubbleApi
        ? BubbleImplementation.bubbleApi
        : BubbleImplementation.windowManager;
  }

  // ========================================
  // FIX-B: STREAM FORWARDING (no leak)
  // ========================================

  void _setupStreamForwarding() {
    // FIX-B: Cancel subscriptions cũ trước khi setup mới
    for (final sub in _streamSubscriptions) {
      sub.cancel();
    }
    _streamSubscriptions.clear();

    _ensureControllers();

    if (_currentImplementation == BubbleImplementation.bubbleApi) {
      _streamSubscriptions.add(
        _bubbleApiService.bubbleClickStream.listen(
          (event) {
            if (!(_clickController?.isClosed ?? true)) {
              _clickController!.add(event);
            }
          },
          onError: (e) => debugPrint('⚠️ bubbleApi click stream error: $e'),
          cancelOnError: false,
        ),
      );
      _streamSubscriptions.add(
        _bubbleApiService.activeBubblesStream.listen(
          (bubbles) {
            if (!(_bubblesController?.isClosed ?? true)) {
              final converted = bubbles.map((k, v) => MapEntry(k, v.toJson()));
              _bubblesController!.add(converted);
            }
          },
          onError: (e) => debugPrint('⚠️ bubbleApi active stream error: $e'),
          cancelOnError: false,
        ),
      );
    } else if (_currentImplementation == BubbleImplementation.windowManager) {
      _streamSubscriptions.add(
        _windowManagerService.bubbleClickStream.listen(
          (event) {
            if (!(_clickController?.isClosed ?? true)) {
              _clickController!.add(event);
            }
          },
          onError: (e) => debugPrint('⚠️ windowManager click stream error: $e'),
          cancelOnError: false,
        ),
      );
      _streamSubscriptions.add(
        _windowManagerService.activeBubblesStream.listen(
          (bubbles) {
            if (!(_bubblesController?.isClosed ?? true)) {
              final converted = bubbles.map((k, v) => MapEntry(k, v.toJson()));
              _bubblesController!.add(converted);
            }
          },
          onError: (e) =>
              debugPrint('⚠️ windowManager active stream error: $e'),
          cancelOnError: false,
        ),
      );
    }
  }

  // ========================================
  // PERMISSIONS
  // ========================================

  Future<bool> hasOverlayPermission() async {
    if (_currentImplementation == BubbleImplementation.bubbleApi) return true;
    return _windowManagerService.hasOverlayPermission();
  }

  Future<bool> requestOverlayPermission() async {
    if (_currentImplementation == BubbleImplementation.bubbleApi) return true;
    return _windowManagerService.requestOverlayPermission();
  }

  // ========================================
  // BUBBLE OPERATIONS (queued)
  // ========================================

  Future<bool> showChatBubble({
    required String userId,
    required String userName,
    required String avatarUrl,
    String? lastMessage,
  }) async {
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

  Future<void> updateBubbleMessage({
    required String userId,
    required String message,
  }) async {
    await _queueOperation(() async {
      if (_currentImplementation == BubbleImplementation.bubbleApi) {
        await _bubbleApiService.updateBubble(userId: userId, message: message);
      } else if (_currentImplementation == BubbleImplementation.windowManager) {
        await _windowManagerService.updateBubbleMessage(
            userId: userId, message: message);
      }
    });
  }

  Future<bool> hideChatBubble(String userId) async {
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

  Future<void> hideAllBubbles() async {
    await _queueOperation(() async {
      if (_currentImplementation == BubbleImplementation.bubbleApi) {
        await _bubbleApiService.hideAllBubbles();
      } else if (_currentImplementation == BubbleImplementation.windowManager) {
        await _windowManagerService.hideAllBubbles();
      }
    });
  }

  Future<bool> showMiniChat({
    required String userId,
    required String userName,
    required String avatarUrl,
  }) async {
    return await _queueOperation<bool>(() async {
          if (_currentImplementation == BubbleImplementation.windowManager) {
            return await _windowManagerService.showMiniChat(
                userId: userId, userName: userName, avatarUrl: avatarUrl);
          }
          debugPrint('⚠️ Mini chat only supported with WindowManager');
          return false;
        }) ??
        false;
  }

  Future<bool> hideMiniChat() async {
    return await _queueOperation<bool>(() async {
          if (_currentImplementation == BubbleImplementation.windowManager) {
            return await _windowManagerService.hideMiniChat();
          }
          return false;
        }) ??
        false;
  }

  // ========================================
  // MIGRATION (FIX-B: close old streams)
  // ========================================

  Future<bool> migrateToModernApi() async {
    if (_currentImplementation == BubbleImplementation.bubbleApi) return true;

    final supportsBubbleApi = await _bubbleApiService.checkBubbleApiSupport();
    if (!supportsBubbleApi) return false;

    return await _queueOperation<bool>(() async {
          try {
            final currentBubbles = _windowManagerService.activeBubbles;
            await _windowManagerService.hideAllBubbles();

            _currentImplementation = BubbleImplementation.bubbleApi;

            // FIX-B: close old stream subscriptions và setup mới
            _setupStreamForwarding();

            for (final bubble in currentBubbles.values) {
              await _bubbleApiService.showBubble(
                userId: bubble.userId,
                userName: bubble.userName,
                message: bubble.lastMessage ?? 'New message',
                avatarUrl: bubble.avatarUrl,
              );
            }
            debugPrint('✅ Migrated to Bubble API');
            return true;
          } catch (e) {
            debugPrint('❌ Migration failed: $e');
            return false;
          }
        }) ??
        false;
  }

  // ========================================
  // MESSAGING
  // ========================================

  Future<bool> sendMessage({
    required String userId,
    required String userName,
    required String message,
    required String avatarUrl,
    String messageType = 'text',
  }) async {
    if (_currentImplementation != BubbleImplementation.bubbleApi) return false;
    try {
      final result = await const MethodChannel('chat_bubbles_v2')
          .invokeMethod<bool>('sendMessage', {
        'userId': userId,
        'userName': userName,
        'message': message,
        'avatarUrl': avatarUrl,
        'messageType': messageType,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('❌ sendMessage: $e');
      return false;
    }
  }

  Future<int> getMessageCount(String userId) async {
    if (_currentImplementation != BubbleImplementation.bubbleApi) return 0;
    try {
      final result = await const MethodChannel('chat_bubbles_v2')
          .invokeMethod<int>('getMessageCount', {'userId': userId});
      return result ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<Map<String, dynamic>> getBubbleStats() async {
    try {
      final result = await const MethodChannel('chat_bubbles_v2')
          .invokeMethod<Map>('getBubbleStats');
      return result?.cast<String, dynamic>() ?? {};
    } catch (_) {
      return {};
    }
  }

  Future<bool> clearMessageHistory(String userId) async {
    if (_currentImplementation != BubbleImplementation.bubbleApi) return false;
    try {
      final result = await const MethodChannel('chat_bubbles_v2')
          .invokeMethod<bool>('clearMessageHistory', {'userId': userId});
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> logBubbleState() async {
    try {
      await const MethodChannel('chat_bubbles_v2')
          .invokeMethod('logBubbleState');
    } catch (_) {}
  }

  // ========================================
  // QUERY
  // ========================================

  bool isBubbleActive(String userId) {
    if (_currentImplementation == BubbleImplementation.bubbleApi) {
      return _bubbleApiService.isBubbleActive(userId);
    } else if (_currentImplementation == BubbleImplementation.windowManager) {
      return _windowManagerService.isBubbleActive(userId);
    }
    return false;
  }

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

  bool get isSupported => _currentImplementation != BubbleImplementation.none;

  BubbleImplementation get currentImplementation => _currentImplementation;

  String getMessageTypeFromContent(String content, int typeCode) =>
      _getMessageType(content, typeCode);

  String _getMessageType(String content, int typeCode) {
    switch (typeCode) {
      case 1:
        return 'image';
      case 2:
        return 'text';
      case 3:
        return 'voice';
      case 4:
        return 'location';
      case 0:
      default:
        if (content.contains('maps.google.com') ||
            content.contains('Location:') ||
            content.contains('📍')) return 'location';
        return 'text';
    }
  }

  Future<bool> sendMessageAuto({
    required String userId,
    required String userName,
    required String message,
    required String avatarUrl,
    required int typeCode,
  }) async =>
      sendMessage(
        userId: userId,
        userName: userName,
        message: message,
        avatarUrl: avatarUrl,
        messageType: _getMessageType(message, typeCode),
      );

  // ========================================
  // FIX-A: OPERATION QUEUE (no race condition)
  // ========================================

  Future<T?> _queueOperation<T>(Future<T> Function() operation) {
    final completer = Completer<T?>();
    _operationQueue.add(_QueuedOperation(
      run: () async {
        try {
          completer.complete(await operation());
        } catch (e) {
          completer.completeError(e);
        }
      },
    ));

    // FIX-A: unawaited() để không block caller, tránh recursive await
    if (!_isProcessingQueue) {
      _processQueue(); // fire and forget, nhưng _isProcessingQueue guard đảm bảo 1 loop
    }

    return completer.future;
  }

  // FIX-A: try-finally đảm bảo flag reset kể cả khi có error
  Future<void> _processQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;
    try {
      while (_operationQueue.isNotEmpty) {
        final op = _operationQueue.removeAt(0);
        try {
          await op.run();
        } catch (e) {
          debugPrint('❌ Queue operation failed: $e');
          // Tiếp tục xử lý các operation tiếp theo
        }
      }
    } finally {
      _isProcessingQueue = false;
    }
  }

  // ========================================
  // FIX-D: DISPOSE đầy đủ
  // ========================================

  void dispose() {
    // FIX-B: cancel tất cả stream subscriptions
    for (final sub in _streamSubscriptions) {
      sub.cancel();
    }
    _streamSubscriptions.clear();

    // Close stream controllers
    if (!(_clickController?.isClosed ?? true)) {
      _clickController!.close();
    }
    if (!(_bubblesController?.isClosed ?? true)) {
      _bubblesController!.close();
    }
    _clickController = null;
    _bubblesController = null;

    // Clear queue
    _operationQueue.clear();
    _isProcessingQueue = false;

    // Dispose child services
    _bubbleApiService.dispose();
    _windowManagerService.dispose();

    _isInitialized = false;
    debugPrint('✅ UnifiedBubbleService disposed');
  }
}

// Helper class cho operation queue
class _QueuedOperation {
  final Future<void> Function() run;
  _QueuedOperation({required this.run});
}

enum BubbleImplementation {
  bubbleApi,
  windowManager,
  none,
  unknown,
}
