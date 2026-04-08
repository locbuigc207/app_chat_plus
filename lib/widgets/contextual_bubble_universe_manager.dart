// lib/widgets/contextual_bubble_universe_manager.dart
// Contextual Bubble Universe - Root Manager
// Thay thế / bổ sung cho MiniChatOverlayManager trong main.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../pages/chat_page.dart'; // import từ project gốc
import '../services/contextual_bubble_service.dart';
import 'contextual_mini_chat_overlay.dart';

/// Manager widget cho toàn bộ Contextual Bubble Universe system.
/// Đặt bên trong MaterialApp như MiniChatOverlayManager.
///
/// Usage trong main.dart:
/// ```dart
/// home: ContextualBubbleUniverseManager(
///   child: /* existing widgets */,
/// ),
/// ```
class ContextualBubbleUniverseManager extends StatefulWidget {
  final Widget child;

  const ContextualBubbleUniverseManager({
    super.key,
    required this.child,
  });

  @override
  State<ContextualBubbleUniverseManager> createState() =>
      ContextualBubbleUniverseManagerState();
}

class ContextualBubbleUniverseManagerState
    extends State<ContextualBubbleUniverseManager> {
  static const MethodChannel _miniChatChannel =
      MethodChannel('mini_chat_channel');

  final _contextService = ContextualBubbleService();

  OverlayEntry? _overlayEntry;

  // Current chat state
  String? _currentUserId;
  String? _currentUserName;
  String? _currentAvatarUrl;
  String? _currentConversationId;
  String? _myUserId;

  @override
  void initState() {
    super.initState();
    _setupChannel();
  }

  @override
  void dispose() {
    _hideOverlay();
    _miniChatChannel.setMethodCallHandler(null);
    _contextService.dispose();
    super.dispose();
  }

  void _setupChannel() {
    _miniChatChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'navigateToMiniChat':
          final peerId = call.arguments['peerId'] as String?;
          final peerNickname = call.arguments['peerNickname'] as String?;
          final peerAvatar = call.arguments['peerAvatar'] as String?;
          if (peerId != null && peerNickname != null && mounted) {
            _showContextualOverlay(
              userId: peerId,
              userName: peerNickname,
              avatarUrl: peerAvatar ?? '',
            );
          }
          break;
        case 'minimize':
        case 'close':
          _hideOverlay();
          break;
      }
      return null;
    });
  }

  /// Hiện overlay với ContextualMiniChatOverlay
  void _showContextualOverlay({
    required String userId,
    required String userName,
    required String avatarUrl,
    String? myUserId,
  }) {
    _hideOverlay();

    _currentUserId = userId;
    _currentUserName = userName;
    _currentAvatarUrl = avatarUrl;
    _currentConversationId = _buildConversationId(myUserId ?? '', userId);
    _myUserId = myUserId ?? '';

    _overlayEntry = OverlayEntry(
      builder: (overlayCtx) => _buildOverlay(overlayCtx),
    );

    if (mounted) {
      Overlay.of(context).insert(_overlayEntry!);
    }
  }

  Widget _buildOverlay(BuildContext overlayCtx) {
    return Material(
      color: Colors.transparent,
      child: ContextualMiniChatOverlay(
        userId: _currentUserId!,
        userName: _currentUserName!,
        avatarUrl: _currentAvatarUrl!,
        conversationId: _currentConversationId ?? '',
        currentUserId: _myUserId ?? '',
        chatContent: _buildChatContent(),
        onMinimize: () {
          _miniChatChannel.invokeMethod('minimize', {'userId': _currentUserId});
          _hideOverlay();
        },
        onClose: () {
          _miniChatChannel.invokeMethod('close', {'userId': _currentUserId});
          _hideOverlay();
        },
      ),
    );
  }

  Widget _buildChatContent() {
    // Sử dụng ChatPage từ project gốc với isMiniChat = true
    return ChatPage(
      arguments: ChatPageArguments(
        peerId: _currentUserId!,
        peerNickname: _currentUserName!,
        peerAvatar: _currentAvatarUrl!,
      ),
      isMiniChat: true,
    );
  }

  void _hideOverlay() {
    try {
      _overlayEntry?.remove();
      _overlayEntry = null;
    } catch (_) {}
  }

  String _buildConversationId(String uid1, String uid2) {
    final ids = [uid1, uid2]..sort();
    return ids.join('-');
  }

  /// Public method để trigger overlay từ bên ngoài
  void showOverlay({
    required String userId,
    required String userName,
    required String avatarUrl,
    String? myUserId,
  }) {
    _showContextualOverlay(
      userId: userId,
      userName: userName,
      avatarUrl: avatarUrl,
      myUserId: myUserId,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ─── CONTEXT AWARE CHAT PAGE WRAPPER ─────────────────────────────────────────

/// Mixin cho ChatPage để tự động báo context service khi gửi tin nhắn
mixin ContextualBubbleMixin<T extends StatefulWidget> on State<T> {
  final _contextService = ContextualBubbleService();

  /// Gọi khi gửi tin nhắn để cập nhật context
  void reportMessageToContext({
    required String content,
    required int messageType,
    bool isFromCurrentUser = true,
  }) {
    _contextService.analyzeMessage(
      content: content,
      messageType: messageType,
      isFromCurrentUser: isFromCurrentUser,
    );
  }

  /// Gọi khi nhận tin nhắn từ peer
  void reportIncomingMessage({
    required String content,
    required int messageType,
  }) {
    _contextService.analyzeMessage(
      content: content,
      messageType: messageType,
      isFromCurrentUser: false,
    );
  }
}
