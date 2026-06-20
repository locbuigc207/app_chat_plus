// lib/widgets/contextual_bubble_universe_manager.dart
import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/services/services.dart';

/// [DEPRECATED] - ĐÃ VÔ HIỆU HÓA ĐỂ TRÁNH XUNG ĐỘT KÊNH MINI CHAT.
/// Vui lòng sử dụng [BubbleManager] và [MiniChatOverlayManager] trong main.dart.
///
/// File này được giữ lại dưới dạng pass-through widget để không làm hỏng cây widget
/// nếu bạn lỡ bọc nó ở đâu đó trong app, nhưng toàn bộ logic lắng nghe MethodChannel
/// và hiển thị Overlay giả đã bị xóa bỏ để nhường quyền cho luồng Mini Chat chuẩn.
@Deprecated('Use BubbleManager / MiniChatOverlayManager in main.dart instead')
class ContextualBubbleUniverseManager extends StatefulWidget {
  final Widget child;

  const ContextualBubbleUniverseManager({super.key, required this.child});

  static ContextualBubbleUniverseManagerState? of(BuildContext context) {
    return context
        .findAncestorStateOfType<ContextualBubbleUniverseManagerState>();
  }

  @override
  State<ContextualBubbleUniverseManager> createState() =>
      ContextualBubbleUniverseManagerState();
}

class ContextualBubbleUniverseManagerState
    extends State<ContextualBubbleUniverseManager> {
  // Trạng thái luôn trả về false do Overlay đã được vô hiệu hóa
  bool get isOverlayVisible => false;

  @override
  void initState() {
    super.initState();
    // ĐÃ XÓA: _channel.setMethodCallHandler(...) để giải phóng kênh cho main.dart
  }

  @override
  void dispose() {
    super.dispose();
  }

  void showOverlay({
    required String userId,
    required String userName,
    required String avatarUrl,
    String? myUserId,
    String? conversationId,
  }) {
    debugPrint(
      '⚠️ Cảnh báo: ContextualBubbleUniverseManager.showOverlay đã bị vô hiệu hóa do xung đột kiến trúc.',
    );
    debugPrint(
      '👉 Vui lòng sử dụng phương pháp chuẩn: BubbleManager.of(context)?.showMiniChat(...)',
    );
  }

  void hideOverlay() {
    // No-op
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ── Giữ lại Mixin vì nó giao tiếp an toàn với ContextualBubbleService ──────

mixin ContextualBubbleMixin<T extends StatefulWidget> on State<T> {
  void notifyBubbleOfMessage({
    String conversationId = 'default_conversation',
    required String content,
    required int messageType,
    bool isFromCurrentUser = true,
    Map<String, dynamic>? extra,
  }) {
    ContextualBubbleService.instance.updateContext(
      conversationId: conversationId,
      message: content,
      messageType: messageType,
      extraData: extra,
    );
  }
}
