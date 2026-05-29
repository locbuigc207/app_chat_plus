import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_chat_demo/models/bubble_models.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_chat_demo/pages/pages.dart';
import 'package:flutter_chat_demo/services/unified_bubble_service.dart';
import 'package:flutter_chat_demo/widgets/widgets.dart';











class BubbleManager extends StatefulWidget {
  final Widget child;
  const BubbleManager({super.key, required this.child});

  @override
  State<BubbleManager> createState() => _BubbleManagerState();

  
  static BubbleManagerController? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_BubbleManagerScope>()?.controller;
  }
}

class _BubbleManagerState extends State<BubbleManager> with WidgetsBindingObserver {
  late final UnifiedBubbleService _service;
  late final BubbleManagerController _controller;

  final List<StreamSubscription> _subs = [];

  
  OverlayEntry? _miniOverlay;
  String? _miniUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _service = UnifiedBubbleService();
    _controller = BubbleManagerController._(
      service: _service,
      showMiniChat: _showMiniChatOverlay,
      hideMiniChat: _hideMiniChatOverlay,
    );

    _attachListeners();
  }

  

  void _attachListeners() {
    if (kIsWeb || !Platform.isAndroid) return;

    _subs.add(
      _service.bubbleClickStream.listen(
        _onBubbleClick,
        onError: (Object e) => debugPrint('❌ BubbleManager click stream: $e'),
        cancelOnError: false,
      ),
    );

    _subs.add(
      _service.miniChatMessageStream.listen(
        _onMiniChatMessage,
        onError: (Object e) => debugPrint('❌ BubbleManager miniChat stream: $e'),
        cancelOnError: false,
      ),
    );

    _subs.add(
      _service.activeBubblesStream.listen(
        (bubbles) => debugPrint('🫧 Active bubbles: ${bubbles.length}'),
        cancelOnError: false,
      ),
    );
  }

  

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.paused:
        debugPrint('📱 App paused — bubbles remain active');
        break;
      case AppLifecycleState.resumed:
        debugPrint('📱 App resumed');
        _hideMiniChatOverlay(); 
        break;
      case AppLifecycleState.detached:
        _service.hideAllBubbles();
        break;
      default:
        break;
    }
  }

  

  void _onBubbleClick(BubbleClickEvent event) {
    if (!mounted) return;
    debugPrint('🫧 Bubble tapped: ${event.userName}');
    _showBubbleActionSheet(event);
  }

  void _showBubbleActionSheet(BubbleClickEvent event) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _BubbleActionSheet(
        event: event,
        onOpenFullChat: () {
          Navigator.pop(context);
          _service.hideChatBubble(event.userId);
          _hideMiniChatOverlay();
          Navigator.of(context).push(
            _fadeRoute(
              ChatPage(
                arguments: ChatPageArguments(
                  peerId: event.userId,
                  peerAvatar: event.avatarUrl,
                  peerNickname: event.userName,
                ),
              ),
            ),
          );
        },
        onOpenMiniChat: () async {
          Navigator.pop(context);
          await Future.delayed(const Duration(milliseconds: 180));
          await _showMiniChatOverlay(
            userId: event.userId,
            userName: event.userName,
            avatarUrl: event.avatarUrl,
          );
        },
        onDismiss: () {
          Navigator.pop(context);
          _service.hideChatBubble(event.userId);
        },
      ),
    );
  }

  

  void _onMiniChatMessage(MiniChatMessage msg) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.message_rounded, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                msg.message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: const Color(0xFF323232),
      ),
    );
  }

  

  Future<void> _showMiniChatOverlay({
    required String userId,
    required String userName,
    required String avatarUrl,
  }) async {
    if (_miniUserId == userId) {
      
      return;
    }
    _hideMiniChatOverlay();

    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;

    _miniUserId = userId;
    _miniOverlay = OverlayEntry(
      builder: (_) => MiniChatOverlayWidget(
        key: ValueKey('mini_$userId'),
        peerId: userId,
        peerNickname: userName,
        peerAvatar: avatarUrl,
        onMinimize: _minimizeMiniChat,
        onClose: _hideMiniChatOverlay,
        onExpand: () {
          _hideMiniChatOverlay();
          Navigator.of(context).push(
            _fadeRoute(
              ChatPage(
                arguments: ChatPageArguments(
                  peerId: userId,
                  peerAvatar: avatarUrl,
                  peerNickname: userName,
                ),
              ),
            ),
          );
        },
      ),
    );
    Overlay.of(context).insert(_miniOverlay!);
    debugPrint('✅ Mini-chat overlay shown for $userName');
  }

  void _hideMiniChatOverlay() {
    _miniOverlay?.remove();
    _miniOverlay = null;
    _miniUserId = null;
  }

  void _minimizeMiniChat() {
    
    _hideMiniChatOverlay();
    debugPrint('⬇️ Mini-chat minimized');
  }

  

  Route<T> _fadeRoute<T>(Widget page) => PageRouteBuilder(
        pageBuilder: (_, __, ___) => page,
        transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 250),
      );

  

  @override
  Widget build(BuildContext context) {
    return _BubbleManagerScope(
      controller: _controller,
      child: widget.child,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _hideMiniChatOverlay();
    super.dispose();
  }
}






class BubbleManagerController {
  final UnifiedBubbleService _service;
  final Future<void> Function({
    required String userId,
    required String userName,
    required String avatarUrl,
  }) showMiniChat;
  final void Function() hideMiniChat;

  BubbleManagerController._({
    required UnifiedBubbleService service,
    required this.showMiniChat,
    required this.hideMiniChat,
  }) : _service = service;

  Future<bool> showBubble({
    required String userId,
    required String userName,
    required String avatarUrl,
    String? lastMessage,
    bool isOnline = false,
  }) =>
      _service.showChatBubble(
        userId: userId,
        userName: userName,
        avatarUrl: avatarUrl,
        lastMessage: lastMessage,
        isOnline: isOnline,
      );

  Future<bool> hideBubble(String userId) => _service.hideChatBubble(userId);

  Future<void> hideAll() => _service.hideAllBubbles();

  Future<void> updateMessage({required String userId, required String message}) =>
      _service.updateBubbleMessage(userId: userId, message: message);

  Future<void> clearUnread(String userId) => _service.clearUnread(userId);

  bool isBubbleActive(String userId) => _service.isBubbleActive(userId);

  int get activeBubbleCount => _service.activeBubbleCount;

  bool get isSupported => _service.isSupported;

  String get implementationInfo => _service.implementationInfo;

  Future<bool> hasPermission() => _service.hasOverlayPermission();

  Future<bool> requestPermission() => _service.requestOverlayPermission();

  Stream<BubbleClickEvent> get clickStream => _service.bubbleClickStream;

  Stream<Map<String, BubbleData>> get bubblesStream => _service.activeBubblesStream;
}





class _BubbleManagerScope extends InheritedWidget {
  final BubbleManagerController controller;

  const _BubbleManagerScope({
    required this.controller,
    required super.child,
  });

  @override
  bool updateShouldNotify(_BubbleManagerScope old) => controller != old.controller;
}





class _BubbleActionSheet extends StatelessWidget {
  final BubbleClickEvent event;
  final VoidCallback onOpenFullChat;
  final VoidCallback onOpenMiniChat;
  final VoidCallback onDismiss;

  const _BubbleActionSheet({
    required this.event,
    required this.onOpenFullChat,
    required this.onOpenMiniChat,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                _AvatarChip(url: event.avatarUrl, name: event.userName),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.userName,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (event.message.isNotEmpty)
                        Text(
                          event.message,
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Divider(height: 0, thickness: 0.5, color: theme.dividerColor),
          const SizedBox(height: 6),

          
          _SheetAction(
            icon: Icons.chat_bubble_rounded,
            iconColor: const Color(0xFF2196F3),
            label: 'Mở cửa sổ chat đầy đủ',
            subtitle: 'Chuyển sang màn hình chat',
            onTap: onOpenFullChat,
          ),
          _SheetAction(
            icon: Icons.picture_in_picture_alt_rounded,
            iconColor: const Color(0xFF9C27B0),
            label: 'Mở mini chat',
            subtitle: 'Chat trong cửa sổ nhỏ nổi',
            onTap: onOpenMiniChat,
          ),
          _SheetAction(
            icon: Icons.close_rounded,
            iconColor: Colors.red.shade400,
            label: 'Đóng bubble',
            subtitle: 'Xóa bong bóng chat này',
            onTap: onDismiss,
            isDestructive: true,
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _AvatarChip extends StatelessWidget {
  final String url;
  final String name;
  const _AvatarChip({required this.url, required this.name});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 24,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      backgroundImage: url.isNotEmpty ? NetworkImage(url) : null,
      child: url.isEmpty
          ? Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.primary,
              ),
            )
          : null,
    );
  }
}

class _SheetAction extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  final bool isDestructive;

  const _SheetAction({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: isDestructive ? Colors.red.shade600 : null,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).hintColor,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: Theme.of(context).hintColor,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}







class BubblePermissionGate extends StatefulWidget {
  final Widget child;
  final Widget? permissionDeniedWidget;

  const BubblePermissionGate({
    super.key,
    required this.child,
    this.permissionDeniedWidget,
  });

  @override
  State<BubblePermissionGate> createState() => _BubblePermissionGateState();
}

class _BubblePermissionGateState extends State<BubblePermissionGate> with WidgetsBindingObserver {
  bool? _hasPermission;
  final _service = UnifiedBubbleService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermission();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkPermission();
  }

  Future<void> _checkPermission() async {
    if (kIsWeb || !Platform.isAndroid) {
      if (mounted) setState(() => _hasPermission = false);
      return;
    }
    final ok = await _service.hasOverlayPermission();
    if (mounted) setState(() => _hasPermission = ok);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasPermission == null) return const SizedBox.shrink();
    if (_hasPermission == true) return widget.child;
    return widget.permissionDeniedWidget ??
        _PermissionPrompt(
          onRequest: () async {
            await _service.requestOverlayPermission();
            await _checkPermission();
          },
        );
  }
}

class _PermissionPrompt extends StatelessWidget {
  final VoidCallback onRequest;
  const _PermissionPrompt({required this.onRequest});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFB300), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.bubble_chart_rounded, size: 32, color: Color(0xFFF57C00)),
          const SizedBox(height: 8),
          const Text(
            'Cần quyền hiển thị nổi',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          const Text(
            'Cho phép ứng dụng hiển thị bong bóng chat khi bạn dùng app khác.',
            style: TextStyle(fontSize: 13, color: Colors.black54),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: onRequest,
            icon: const Icon(Icons.settings_rounded, size: 16),
            label: const Text('Cấp quyền'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF57C00),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }
}






class ActiveBubblesPanel extends StatelessWidget {
  final UnifiedBubbleService service;
  const ActiveBubblesPanel({super.key, required this.service});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, BubbleData>>(
      stream: service.activeBubblesStream,
      initialData: service.activeBubbles,
      builder: (context, snap) {
        final bubbles = snap.data ?? {};
        if (bubbles.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(20),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bubble_chart_rounded, size: 40, color: Colors.grey),
                  SizedBox(height: 8),
                  Text('Không có bong bóng nào đang hoạt động',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${bubbles.length} bong bóng đang hoạt động',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  TextButton.icon(
                    onPressed: () => service.hideAllBubbles(),
                    icon: const Icon(Icons.clear_all_rounded, size: 16),
                    label: const Text('Xóa tất cả'),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                  ),
                ],
              ),
            ),
            ...bubbles.values.map((b) => _BubbleTile(
                  data: b,
                  onHide: () => service.hideChatBubble(b.userId),
                  onClearUnread: () => service.clearUnread(b.userId),
                )),
          ],
        );
      },
    );
  }
}

class _BubbleTile extends StatelessWidget {
  final BubbleData data;
  final VoidCallback onHide;
  final VoidCallback onClearUnread;

  const _BubbleTile({
    required this.data,
    required this.onHide,
    required this.onClearUnread,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Stack(
        children: [
          CircleAvatar(
            backgroundImage: data.avatarUrl.isNotEmpty ? NetworkImage(data.avatarUrl) : null,
            child: data.avatarUrl.isEmpty ? Text(data.userName[0].toUpperCase()) : null,
          ),
          if (data.unreadCount > 0)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  data.unreadCount > 99 ? '99+' : '${data.unreadCount}',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
      title: Text(data.userName, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        data.lastMessage ?? 'Không có tin nhắn',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (data.unreadCount > 0)
            IconButton(
              icon: const Icon(Icons.mark_chat_read_rounded, size: 18),
              onPressed: onClearUnread,
              tooltip: 'Đánh dấu đã đọc',
              color: Colors.blue,
            ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: onHide,
            tooltip: 'Ẩn bubble',
            color: Colors.red,
          ),
        ],
      ),
    );
  }
}
