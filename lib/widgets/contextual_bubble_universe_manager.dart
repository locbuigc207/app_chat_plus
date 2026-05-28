import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/services/services.dart';
import 'package:flutter_chat_demo/widgets/widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PUBLIC INTERFACE
// ─────────────────────────────────────────────────────────────────────────────

/// Wraps your app's widget tree and manages the bubble mini-chat overlay.
///
/// Place this at the root of your widget tree, above [MaterialApp] or as a
/// direct child of it:
///
/// ```dart
/// ContextualBubbleUniverseManager(
///   child: MaterialApp(...),
/// )
/// ```
///
/// To open the mini-chat programmatically, call:
/// ```dart
/// ContextualBubbleUniverseManager.of(context)?.showOverlay(...)
/// ```
class ContextualBubbleUniverseManager extends StatefulWidget {
  final Widget child;

  const ContextualBubbleUniverseManager({
    super.key,
    required this.child,
  });

  /// Returns the nearest [ContextualBubbleUniverseManagerState] ancestor,
  /// or null if none found.
  static ContextualBubbleUniverseManagerState? of(BuildContext context) {
    return context
        .findAncestorStateOfType<ContextualBubbleUniverseManagerState>();
  }

  @override
  State<ContextualBubbleUniverseManager> createState() =>
      ContextualBubbleUniverseManagerState();
}

// ─────────────────────────────────────────────────────────────────────────────
// STATE
// ─────────────────────────────────────────────────────────────────────────────

class ContextualBubbleUniverseManagerState
    extends State<ContextualBubbleUniverseManager> {
  // ── Method channel (mirrors BubbleOverlayService) ─────────────────────────
  static const _channel = MethodChannel('mini_chat_channel');

  // ── Services ──────────────────────────────────────────────────────────────
  final _contextService = ContextualBubbleService();

  // ── Overlay state ─────────────────────────────────────────────────────────
  OverlayEntry? _overlayEntry;

  String? _currentUserId;
  String? _currentUserName;
  String? _currentAvatarUrl;
  String? _currentConversationId;
  String? _myUserId;

  bool get isOverlayVisible => _overlayEntry != null;

  // ─────────────────────────────────────────────────────────────────────────
  // LIFECYCLE
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_handleNativeChannelCall);
  }

  @override
  void dispose() {
    _safeRemoveOverlay();
    _channel.setMethodCallHandler(null);
    _contextService.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // NATIVE CHANNEL
  // ─────────────────────────────────────────────────────────────────────────

  Future<dynamic> _handleNativeChannelCall(MethodCall call) async {
    switch (call.method) {
      case 'navigateToMiniChat':
        final args = call.arguments as Map<dynamic, dynamic>? ?? {};
        final peerId = args['peerId'] as String?;
        final peerNickname = args['peerNickname'] as String?;
        final peerAvatar = args['peerAvatar'] as String?;
        if (peerId != null && peerNickname != null && mounted) {
          showOverlay(
            userId: peerId,
            userName: peerNickname,
            avatarUrl: peerAvatar ?? '',
          );
        }
        break;

      case 'minimize':
        _safeRemoveOverlay();
        break;

      case 'close':
        _safeRemoveOverlay();
        break;

      case 'updateBubble':
        // Forward to context service if needed
        break;
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PUBLIC API
  // ─────────────────────────────────────────────────────────────────────────

  /// Opens (or replaces) the mini-chat overlay for the given user.
  void showOverlay({
    required String userId,
    required String userName,
    required String avatarUrl,
    String? myUserId,
    String? conversationId,
  }) {
    if (!mounted) return;
    _safeRemoveOverlay();

    _currentUserId = userId;
    _currentUserName = userName;
    _currentAvatarUrl = avatarUrl;
    _myUserId = myUserId ?? '';
    _currentConversationId =
        conversationId ?? _buildConversationId(myUserId ?? '', userId);

    _overlayEntry = OverlayEntry(
      builder: (ctx) => _BubbleOverlayWrapper(
        userId: _currentUserId!,
        userName: _currentUserName!,
        avatarUrl: _currentAvatarUrl!,
        conversationId: _currentConversationId!,
        currentUserId: _myUserId!,
        chatContentBuilder: _buildChatContent,
        onMinimize: _onMinimize,
        onClose: _onClose,
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  /// Hides the overlay without notifying native side.
  void hideOverlay() => _safeRemoveOverlay();

  // ─────────────────────────────────────────────────────────────────────────
  // CALLBACKS
  // ─────────────────────────────────────────────────────────────────────────

  void _onMinimize() {
    _safeRemoveOverlay();
    _channel.invokeMethod(
        'minimize', {'userId': _currentUserId}).catchError((_) {});
  }

  void _onClose() {
    _safeRemoveOverlay();
    _channel
        .invokeMethod('close', {'userId': _currentUserId}).catchError((_) {});
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  void _safeRemoveOverlay() {
    try {
      _overlayEntry?.remove();
    } catch (_) {}
    _overlayEntry = null;
  }

  /// Override this to inject your actual ChatPage.
  Widget _buildChatContent() {
    // Replace with your real ChatPage:
    // return ChatPage(
    //   arguments: ChatPageArguments(
    //     peerId: _currentUserId!,
    //     peerNickname: _currentUserName!,
    //     peerAvatar: _currentAvatarUrl!,
    //   ),
    //   isMiniChat: true,
    // );
    return _FallbackChatContent(
      userId: _currentUserId ?? '',
      userName: _currentUserName ?? '',
    );
  }

  static String _buildConversationId(String uid1, String uid2) {
    final ids = [uid1, uid2]..sort();
    return ids.join('_');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) => widget.child;
}

// ─────────────────────────────────────────────────────────────────────────────
// OVERLAY WRAPPER (isolates ContextualMiniChatOverlay from Manager rebuild)
// ─────────────────────────────────────────────────────────────────────────────

class _BubbleOverlayWrapper extends StatelessWidget {
  final String userId;
  final String userName;
  final String avatarUrl;
  final String conversationId;
  final String currentUserId;
  final Widget Function() chatContentBuilder;
  final VoidCallback onMinimize;
  final VoidCallback onClose;

  const _BubbleOverlayWrapper({
    required this.userId,
    required this.userName,
    required this.avatarUrl,
    required this.conversationId,
    required this.currentUserId,
    required this.chatContentBuilder,
    required this.onMinimize,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ContextualMiniChatOverlay(
        userId: userId,
        userName: userName,
        avatarUrl: avatarUrl,
        conversationId: conversationId,
        currentUserId: currentUserId,
        chatContent: chatContentBuilder(),
        onMinimize: onMinimize,
        onClose: onClose,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FALLBACK CONTENT (replace with your real ChatPage)
// ─────────────────────────────────────────────────────────────────────────────

class _FallbackChatContent extends StatelessWidget {
  final String userId;
  final String userName;

  const _FallbackChatContent({
    required this.userId,
    required this.userName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8F9FE),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFFE3F2FD),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                color: Color(0xFF1E88E5),
                size: 28,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Chat với $userName',
              style: const TextStyle(
                color: Color(0xFF1A2340),
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'userId: $userId',
              style: const TextStyle(color: Color(0xFF9AA5B8), fontSize: 11),
            ),
            const SizedBox(height: 16),
            const Text(
              'Thay thế bằng ChatPage thực tế.',
              style: TextStyle(color: Color(0xFFB0BAD0), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MIXIN — convenience helpers for StatefulWidgets inside a chat
// ─────────────────────────────────────────────────────────────────────────────

/// Mix into any [State] that processes chat messages so they feed the
/// [ContextualBubbleService] automatically.
///
/// ```dart
/// class _MyChatState extends State<MyChat> with ContextualBubbleMixin { ... }
/// ```
mixin ContextualBubbleMixin<T extends StatefulWidget> on State<T> {
  final _ctxSvc = ContextualBubbleService();

  /// Call this whenever an outgoing or incoming message is processed.
  void notifyBubbleOfMessage({
    required String content,
    required int messageType,
    bool isFromCurrentUser = true,
    Map<String, dynamic>? extra,
  }) {
    _ctxSvc.analyzeMessage(
      content: content,
      messageType: messageType,
      isFromCurrentUser: isFromCurrentUser,
      extra: extra,
    );
  }
}
