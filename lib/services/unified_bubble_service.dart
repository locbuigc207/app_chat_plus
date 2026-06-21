import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_chat_demo/models/bubble_models.dart';
import 'package:flutter_chat_demo/services/bubble_service_v2.dart';
import 'package:flutter_chat_demo/services/chat_bubble_service.dart';

/// Single entry-point for bubble operations across the whole app.
///
/// Automatically selects:
///  • [BubbleServiceV2]   → Android 11+ (Bubble API, no overlay permission needed)
///  • [ChatBubbleService] → Android < 11 (WindowManager overlay)
///  • none                → Non-Android / Web
///
/// Mutation methods (showChatBubble, updateBubbleMessage, hideChatBubble,
/// hideAllBubbles, clearUnread, onAppHidden, showMiniChat, hideMiniChat,
/// migrateToModernApi) đi qua [_queue] nên an toàn để gọi trước khi init
/// xong — chúng tự chờ và được replay sau khi phát hiện implementation.
///
/// Các method async KHÔNG đi qua queue (hasOverlayPermission,
/// requestOverlayPermission, sendMessage, getBubbleStats, logBubbleState)
/// giờ tự chờ init qua [_ensureInitialized] trước khi đọc [_impl], để
/// tránh đọc nhầm giá trị "unknown" và rẽ sai nhánh implementation.
///
/// Các getter đồng bộ (isBubbleActive, activeBubbleCount, activeBubbles,
/// implementationInfo...) phản ánh trạng thái tốt nhất tại thời điểm gọi —
/// về bản chất không thể "chờ" bên trong một getter đồng bộ, nên nếu gọi
/// rất sớm (trước khi init xong) có thể trả về giá trị mặc định/rỗng.
class UnifiedBubbleService {
  // ── Implementations ───────────────────────────────────────────────────────
  late final BubbleServiceV2 _bubbleApi;
  late final ChatBubbleService _windowMgr;

  // ── Singleton ─────────────────────────────────────────────────────────────
  static final UnifiedBubbleService _instance =
      UnifiedBubbleService._internal();
  factory UnifiedBubbleService() => _instance;

  UnifiedBubbleService._internal() {
    _bubbleApi = BubbleServiceV2();
    _windowMgr = ChatBubbleService();
    _initialize();
  }

  // ── State ─────────────────────────────────────────────────────────────────
  bool _isInitialized = false;
  Completer<void>? _initCompleter;
  BubbleImplementation _impl = BubbleImplementation.unknown;

  final List<_QueuedOp> _opQueue = [];
  bool _processingQueue = false;

  final List<StreamSubscription> _subs = [];

  // ── Controllers ───────────────────────────────────────────────────────────
  StreamController<BubbleClickEvent>? _clickCtrl;
  StreamController<Map<String, BubbleData>>? _bubblesCtrl;
  StreamController<MiniChatMessage>? _miniMsgCtrl;

  Stream<BubbleClickEvent> get bubbleClickStream {
    _ensureCtrl();
    return _clickCtrl!.stream;
  }

  Stream<Map<String, BubbleData>> get activeBubblesStream {
    _ensureCtrl();
    return _bubblesCtrl!.stream;
  }

  Stream<MiniChatMessage> get miniChatMessageStream {
    _ensureCtrl();
    return _miniMsgCtrl!.stream;
  }

  void _ensureCtrl() {
    if (_clickCtrl == null || _clickCtrl!.isClosed) {
      _clickCtrl = StreamController<BubbleClickEvent>.broadcast();
    }
    if (_bubblesCtrl == null || _bubblesCtrl!.isClosed) {
      _bubblesCtrl = StreamController<Map<String, BubbleData>>.broadcast();
    }
    if (_miniMsgCtrl == null || _miniMsgCtrl!.isClosed) {
      _miniMsgCtrl = StreamController<MiniChatMessage>.broadcast();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INITIALISATION
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _initialize() async {
    if (_isInitialized) return;
    if (_initCompleter != null) return _initCompleter!.future;

    _initCompleter = Completer<void>();
    try {
      // Timeout cho _detectImpl để tránh treo hệ thống vĩnh viễn.
      _impl = await _detectImpl().timeout(const Duration(seconds: 3));
      debugPrint('✅ UnifiedBubbleService: using ${_impl.name}');
    } catch (e, st) {
      debugPrint('❌ UnifiedBubbleService init failed/timeout: $e\n$st');
      // Fallback an toàn nếu có lỗi khởi tạo
      _impl = Platform.isAndroid
          ? BubbleImplementation.windowManager
          : BubbleImplementation.none;
      debugPrint('⚠️ Falling back to ${_impl.name}');
    } finally {
      _ensureCtrl();
      _forwardStreams();
      _isInitialized = true;
      _initCompleter!.complete();
      _initCompleter = null;
      _drainQueue(); // Kích hoạt xả hàng đợi tác vụ
    }
  }

  /// Đảm bảo quá trình phát hiện implementation (_detectImpl) đã hoàn tất trước khi đọc [_impl].
  Future<void> _ensureInitialized() async {
    if (_isInitialized) return;
    if (_initCompleter != null) {
      await _initCompleter!.future.catchError((_) {});
      return;
    }
    await _initialize();
  }

  Future<BubbleImplementation> _detectImpl() async {
    if (kIsWeb || !Platform.isAndroid) return BubbleImplementation.none;
    await _bubbleApi.initialize();
    if (_bubbleApi.isSupported) {
      return BubbleImplementation.bubbleApi;
    }
    return BubbleImplementation.windowManager;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STREAM FORWARDING
  // ═══════════════════════════════════════════════════════════════════════════

  void _forwardStreams() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _ensureCtrl();

    void forwardClick(Stream<BubbleClickEvent> src) {
      _subs.add(
        src.listen(
          (e) {
            if (!(_clickCtrl?.isClosed ?? true)) _clickCtrl!.add(e);
          },
          onError: (Object err) => debugPrint('⚠️ click stream error: $err'),
          cancelOnError: false,
        ),
      );
    }

    void forwardBubbles(Stream<Map<String, BubbleData>> src) {
      _subs.add(
        src.listen(
          (b) {
            if (!(_bubblesCtrl?.isClosed ?? true)) _bubblesCtrl!.add(b);
          },
          onError: (Object err) => debugPrint('⚠️ bubbles stream error: $err'),
          cancelOnError: false,
        ),
      );
    }

    if (_impl == BubbleImplementation.bubbleApi) {
      forwardClick(_bubbleApi.bubbleClickStream);
      forwardBubbles(_bubbleApi.activeBubblesStream);
    } else if (_impl == BubbleImplementation.windowManager) {
      forwardClick(_windowMgr.bubbleClickStream);
      forwardBubbles(_windowMgr.activeBubblesStream);
      _subs.add(
        _windowMgr.miniChatMessageStream.listen((m) {
          if (!(_miniMsgCtrl?.isClosed ?? true)) _miniMsgCtrl!.add(m);
        }, cancelOnError: false),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PERMISSIONS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<bool> hasOverlayPermission() async {
    await _ensureInitialized();
    // SỬA LỖI P1: Gọi quyền kiểm tra thật từ Android Native thay vì return true cố định
    if (_impl == BubbleImplementation.bubbleApi) {
      return _bubbleApi.checkBubblesEnabled();
    }
    return _windowMgr.hasOverlayPermission();
  }

  Future<bool> requestOverlayPermission() async {
    await _ensureInitialized();
    // SỬA LỖI P1: Mở màn hình cài đặt quyền của Android Native thay vì return true cố định
    if (_impl == BubbleImplementation.bubbleApi) {
      return _bubbleApi.openBubbleSettings();
    }
    return _windowMgr.requestOverlayPermission();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUBBLE OPERATIONS (all queued for thread-safety)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<bool> showChatBubble({
    required String userId,
    required String userName,
    required String avatarUrl,
    String? lastMessage,
    bool isOnline = false,
  }) => _queue<bool>(() async {
    if (_impl == BubbleImplementation.bubbleApi) {
      return _bubbleApi.showBubble(
        userId: userId,
        userName: userName,
        message: lastMessage ?? 'New message',
        avatarUrl: avatarUrl,
        isOnline: isOnline,
      );
    } else if (_impl == BubbleImplementation.windowManager) {
      return _windowMgr.showChatBubble(
        userId: userId,
        userName: userName,
        avatarUrl: avatarUrl,
        lastMessage: lastMessage,
      );
    }
    return false;
  }).then((v) => v ?? false);

  /// Cập nhật tin nhắn mới nhất hiển thị trên bubble.
  Future<void> updateBubbleMessage({
    required String userId,
    required String message,
  }) => _queue(() async {
    if (_impl == BubbleImplementation.bubbleApi) {
      // SỬA LỖI: Đã dọn dẹp đoạn comment lỗi thời. Hàm updateBubble() phía dưới
      // hiện đã tự động đồng bộ hóa đầy đủ thông tin userName/avatarUrl
      // có sẵn từ cache Dart lên hệ điều hành.
      await _bubbleApi.updateBubble(userId: userId, message: message);
    } else if (_impl == BubbleImplementation.windowManager) {
      await _windowMgr.updateBubbleMessage(userId: userId, message: message);
    }
  });

  Future<bool> hideChatBubble(String userId) => _queue<bool>(() async {
    if (_impl == BubbleImplementation.bubbleApi) {
      return _bubbleApi.hideBubble(userId);
    } else if (_impl == BubbleImplementation.windowManager) {
      return _windowMgr.hideChatBubble(userId);
    }
    return false;
  }).then((v) => v ?? false);

  Future<void> hideAllBubbles() => _queue(() async {
    if (_impl == BubbleImplementation.bubbleApi) {
      await _bubbleApi.hideAllBubbles();
    } else if (_impl == BubbleImplementation.windowManager) {
      await _windowMgr.hideAllBubbles();
    }
  });

  Future<void> clearUnread(String userId) => _queue(() async {
    if (_impl == BubbleImplementation.bubbleApi) {
      await _bubbleApi.clearUnread(userId);
    } else if (_impl == BubbleImplementation.windowManager) {
      await _windowMgr.clearUnread(userId);
    }
  });

  // Xử lý ẩn Bubble Overlay khi rơi vào trạng thái Split-screen.
  Future<void> onAppHidden() => _queue(() async {
    if (_impl == BubbleImplementation.windowManager) {
      await _windowMgr.hideAllBubbles();
      debugPrint(
        '🙈 App hidden (Split screen) - WindowManager Bubbles auto-hidden',
      );
    }
  });

  // ── Mini Chat (WindowManager only) ────────────────────────────────────────

  Future<bool> showMiniChat({
    required String userId,
    required String userName,
    required String avatarUrl,
  }) => _queue<bool>(() async {
    if (_impl == BubbleImplementation.windowManager) {
      return _windowMgr.showMiniChat(
        userId: userId,
        userName: userName,
        avatarUrl: avatarUrl,
      );
    }
    debugPrint('⚠️ Mini chat (fallback) only available with WindowManager');
    return false;
  }).then((v) => v ?? false);

  Future<bool> hideMiniChat() => _queue<bool>(() async {
    if (_impl == BubbleImplementation.windowManager) {
      return _windowMgr.hideMiniChat();
    }
    return false;
  }).then((v) => v ?? false);

  // ── Advanced (BubbleApi only) ──────────────────────────────────────────────

  Future<bool> sendMessage({
    required String userId,
    required String userName,
    required String message,
    required String avatarUrl,
    String messageType = 'text',
  }) async {
    await _ensureInitialized();
    if (_impl != BubbleImplementation.bubbleApi) return false;
    return _bubbleApi.sendMessage(
      userId: userId,
      userName: userName,
      message: message,
      avatarUrl: avatarUrl,
      messageType: messageType,
    );
  }

  Future<bool> sendMessageAuto({
    required String userId,
    required String userName,
    required String message,
    required String avatarUrl,
    required int typeCode,
  }) => sendMessage(
    userId: userId,
    userName: userName,
    message: message,
    avatarUrl: avatarUrl,
    messageType: _resolveType(message, typeCode),
  );

  Future<Map<String, dynamic>> getBubbleStats() async {
    await _ensureInitialized();
    if (_impl == BubbleImplementation.bubbleApi) {
      return _bubbleApi.getBubbleStats();
    }
    return {};
  }

  Future<void> logBubbleState() async {
    await _ensureInitialized();
    if (_impl == BubbleImplementation.bubbleApi) {
      await _bubbleApi.logBubbleState();
    }
  }

  // ── Migration ─────────────────────────────────────────────────────────────

  /// Attempt to migrate from WindowManager → Bubble API (e.g. after OS upgrade).
  Future<bool> migrateToModernApi() async {
    if (_impl == BubbleImplementation.bubbleApi) return true;
    final supported = await _bubbleApi.checkBubbleApiSupport();
    if (!supported) return false;

    return _queue<bool>(() async {
      try {
        final current = Map<String, BubbleData>.from(_windowMgr.activeBubbles);
        await _windowMgr.hideAllBubbles();
        await _bubbleApi.initialize();
        _impl = BubbleImplementation.bubbleApi;
        _forwardStreams();
        for (final b in current.values) {
          await _bubbleApi.showBubble(
            userId: b.userId,
            userName: b.userName,
            message: b.lastMessage ?? '',
            avatarUrl: b.avatarUrl,
          );
        }
        debugPrint('✅ Migrated to Bubble API');
        return true;
      } catch (e) {
        debugPrint('❌ Migration failed: $e');
        return false;
      }
    }).then((v) => v ?? false);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  bool get isSupported => _impl != BubbleImplementation.none;
  bool get isInitialized => _isInitialized;
  BubbleImplementation get currentImplementation => _impl;

  bool isBubbleActive(String userId) {
    if (_impl == BubbleImplementation.bubbleApi) {
      return _bubbleApi.isBubbleActive(userId);
    }
    if (_impl == BubbleImplementation.windowManager) {
      return _windowMgr.isBubbleActive(userId);
    }
    return false;
  }

  int get activeBubbleCount {
    if (_impl == BubbleImplementation.bubbleApi) {
      return _bubbleApi.activeBubbleCount;
    }
    if (_impl == BubbleImplementation.windowManager) {
      return _windowMgr.activeBubbleCount;
    }
    return 0;
  }

  Map<String, BubbleData> get activeBubbles {
    if (_impl == BubbleImplementation.bubbleApi) {
      return _bubbleApi.activeBubbles;
    }
    if (_impl == BubbleImplementation.windowManager) {
      return _windowMgr.activeBubbles;
    }
    return {};
  }

  String get implementationInfo => switch (_impl) {
    BubbleImplementation.bubbleApi => 'Bubble API (Android 11+)',
    BubbleImplementation.windowManager => 'WindowManager (Android < 11)',
    BubbleImplementation.none => 'Not supported',
    BubbleImplementation.unknown => 'Detecting...',
  };

  String getMessageTypeFromContent(String content, int typeCode) =>
      _resolveType(content, typeCode);

  // ═══════════════════════════════════════════════════════════════════════════
  // OPERATION QUEUE
  // ═══════════════════════════════════════════════════════════════════════════

  Future<T?> _queue<T>(Future<T> Function() op) {
    final completer = Completer<T?>();
    _opQueue.add(
      _QueuedOp(
        run: () async {
          try {
            final result = await op().timeout(
              const Duration(seconds: 5),
              onTimeout: () {
                debugPrint('⚠️ Queue operation timeout after 5s');
                throw TimeoutException('Bubble operation timed out');
              },
            );
            completer.complete(result);
          } catch (e, st) {
            completer.completeError(e, st);
          }
        },
      ),
    );
    if (!_processingQueue) _drainQueue();
    return completer.future;
  }

  Future<void> _drainQueue() async {
    if (_processingQueue) return;
    _processingQueue = true;
    try {
      if (!_isInitialized && _initCompleter != null) {
        await _initCompleter!.future.catchError((_) {});
      }

      while (_opQueue.isNotEmpty) {
        final op = _opQueue.removeAt(0);
        try {
          await op.run();
        } catch (e) {
          debugPrint('❌ Queue op failed: $e');
        }
      }
    } finally {
      _processingQueue = false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  String _resolveType(String content, int typeCode) => switch (typeCode) {
    1 => 'image',
    2 => 'text',
    3 => 'voice',
    4 => 'location',
    _ when content.contains('maps.google') || content.contains('📍') =>
      'location',
    _ => 'text',
  };

  // ═══════════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═══════════════════════════════════════════════════════════════════════════

  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();

    if (!(_clickCtrl?.isClosed ?? true)) _clickCtrl!.close();
    if (!(_bubblesCtrl?.isClosed ?? true)) _bubblesCtrl!.close();
    if (!(_miniMsgCtrl?.isClosed ?? true)) _miniMsgCtrl!.close();
    _clickCtrl = null;
    _bubblesCtrl = null;
    _miniMsgCtrl = null;

    _opQueue.clear();
    _processingQueue = false;

    _bubbleApi.dispose();
    _windowMgr.dispose();

    _isInitialized = false;
    debugPrint('✅ UnifiedBubbleService disposed');
  }
}

class _QueuedOp {
  final Future<void> Function() run;
  const _QueuedOp({required this.run});
}
