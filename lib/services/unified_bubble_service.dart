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
      _drainQueue(); // Kích hoạt chạy lại hàng đợi sau khi đã init xong
    }
  }

  /// Đảm bảo quá trình phát hiện implementation (_detectImpl) đã hoàn tất
  /// trước khi đọc [_impl]. Áp dụng cho các method async không đi qua
  /// [_queue] nhưng vẫn cần biết chính xác implementation đang dùng trước
  /// khi quyết định gọi xuống native bên nào.
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
    // ĐÃ SỬA: Gọi thẳng initialize() — bên trong nó đã tự gọi
    // checkBubbleApiSupport() và lưu kết quả vào _bubbleApi.isSupported.
    // Trước đây gọi checkBubbleApiSupport() ở đây RỒI initialize() lại gọi
    // lần nữa → 2 lượt round-trip MethodChannel cho cùng một câu hỏi mỗi
    // lần khởi động app. Giờ chỉ còn 1 lượt.
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
      _subs.add(src.listen(
            (e) {
          if (!(_clickCtrl?.isClosed ?? true)) _clickCtrl!.add(e);
        },
        onError: (Object err) => debugPrint('⚠️ click stream error: $err'),
        cancelOnError: false,
      ));
    }

    void forwardBubbles(Stream<Map<String, BubbleData>> src) {
      _subs.add(src.listen(
            (b) {
          if (!(_bubblesCtrl?.isClosed ?? true)) _bubblesCtrl!.add(b);
        },
        onError: (Object err) => debugPrint('⚠️ bubbles stream error: $err'),
        cancelOnError: false,
      ));
    }

    if (_impl == BubbleImplementation.bubbleApi) {
      forwardClick(_bubbleApi.bubbleClickStream);
      forwardBubbles(_bubbleApi.activeBubblesStream);
    } else if (_impl == BubbleImplementation.windowManager) {
      forwardClick(_windowMgr.bubbleClickStream);
      forwardBubbles(_windowMgr.activeBubblesStream);
      _subs.add(_windowMgr.miniChatMessageStream.listen(
            (m) {
          if (!(_miniMsgCtrl?.isClosed ?? true)) _miniMsgCtrl!.add(m);
        },
        cancelOnError: false,
      ));
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PERMISSIONS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<bool> hasOverlayPermission() async {
    // ĐÃ SỬA: chờ init xong trước khi đọc _impl, tránh rẽ nhầm nhánh khi
    // gọi quá sớm (lúc _impl vẫn còn là BubbleImplementation.unknown).
    await _ensureInitialized();
    if (_impl == BubbleImplementation.bubbleApi) return true;
    return _windowMgr.hasOverlayPermission();
  }

  Future<bool> requestOverlayPermission() async {
    await _ensureInitialized();
    if (_impl == BubbleImplementation.bubbleApi) return true;
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
  }) =>
      _queue<bool>(() async {
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
  ///
  /// LƯU Ý QUAN TRỌNG (chưa thể tự đóng kín trong file này):
  /// Ở nhánh [BubbleImplementation.bubbleApi], hàm này chỉ gửi xuống
  /// `userId` + `message` vì chữ ký hiện tại của
  /// `BubbleServiceV2.updateBubble()` (file bubble_service_v2.dart) chưa
  /// có tham số `userName`/`avatarUrl` để nhận và chuyển tiếp xuống
  /// native. Việc native (MainActivity.kt) đang hard-code "" cho hai
  /// trường này khi xử lý lệnh `updateBubble` ở kênh V2 là một lỗi nằm ở
  /// các file khác (bubble_service_v2.dart + 3 file Kotlin), không thể
  /// sửa dứt điểm chỉ bằng cách đổi file này — xem giải thích đầy đủ ở
  /// phần trả lời kèm theo.
  Future<void> updateBubbleMessage({
    required String userId,
    required String message,
  }) =>
      _queue(() async {
        if (_impl == BubbleImplementation.bubbleApi) {
          await _bubbleApi.updateBubble(userId: userId, message: message);
        } else if (_impl == BubbleImplementation.windowManager) {
          await _windowMgr.updateBubbleMessage(
              userId: userId, message: message);
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
  // Chỉ áp dụng cho nhánh windowManager — bubble native (bubbleApi) do hệ
  // thống quản lý độc lập với tiến trình app, không cần can thiệp ở đây.
  Future<void> onAppHidden() => _queue(() async {
    if (_impl == BubbleImplementation.windowManager) {
      await _windowMgr.hideAllBubbles();
      debugPrint(
          '🙈 App hidden (Split screen) - WindowManager Bubbles auto-hidden');
    }
  });

  // ── Mini Chat (WindowManager only) ────────────────────────────────────────
  //
  // Lưu ý: đây KHÔNG phải đường dẫn chính cho Mini Chat trong app. Đường
  // chính là BubbleManager (widget) tự dựng OverlayEntry thuần Flutter
  // (Overlay.of(navigatorContext)) và hoạt động trên mọi phiên bản Android.
  // Hai method dưới đây chỉ là fallback được gọi khi BubbleManager.of(context)
  // trả về null, và đúng theo thiết kế chỉ có tác dụng ở nhánh windowManager.

  Future<bool> showMiniChat({
    required String userId,
    required String userName,
    required String avatarUrl,
  }) =>
      _queue<bool>(() async {
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
    // ĐÃ SỬA: chờ init xong trước khi kiểm tra _impl.
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
  }) =>
      sendMessage(
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
    _opQueue.add(_QueuedOp(run: () async {
      try {
        // Giới hạn timeout 5s để Queue không bị kẹt vĩnh viễn nếu native
        // không bao giờ trả lời (ví dụ MethodChannel bị treo).
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
    }));
    if (!_processingQueue) _drainQueue();
    return completer.future;
  }

  Future<void> _drainQueue() async {
    if (_processingQueue) return;
    _processingQueue = true;
    try {
      // Chờ _initialize hoàn tất để tránh xả hàng đợi khi hệ thống chưa
      // ready (tức là _impl vẫn đang ở trạng thái unknown).
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