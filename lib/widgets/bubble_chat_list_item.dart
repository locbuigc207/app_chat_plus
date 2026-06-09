// lib/widgets/bubble_chat_list_item.dart
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart'; // Chứa AsyncCallback
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/widgets.dart';

// ═══════════════════════════════════════════════════════════════════════════
// DATA MODEL
// ═══════════════════════════════════════════════════════════════════════════

class BubbleConversationData {
  final String peerId;
  final String peerName;
  final String peerAvatar;
  final String lastMessage;
  final String lastMessageType; // text | image | voice | location | file
  final DateTime timestamp;
  final int unreadCount;
  final bool isOnline;
  final bool isMuted;
  final bool isPinned;
  final bool isFromMe;
  final bool isRead;
  final bool isTyping;

  const BubbleConversationData({
    required this.peerId,
    required this.peerName,
    required this.peerAvatar,
    required this.lastMessage,
    this.lastMessageType = 'text',
    required this.timestamp,
    this.unreadCount = 0,
    this.isOnline = false,
    this.isMuted = false,
    this.isPinned = false,
    this.isFromMe = false,
    this.isRead = false,
    this.isTyping = false,
  });

  bool get hasUnread => unreadCount > 0 && !isMuted;
}

// ═══════════════════════════════════════════════════════════════════════════
// CHAT LIST ITEM
// ═══════════════════════════════════════════════════════════════════════════

/// Swipeable conversation list item with integrated bubble controls.
///
/// Swipe right → show/hide bubble.
/// Swipe left  → mute / pin options.
/// Tap         → open full chat.
/// Long press  → context menu.
class BubbleChatListItem extends StatefulWidget {
  final BubbleConversationData item;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onMute;
  final VoidCallback? onPin;
  final VoidCallback? onDelete;

  const BubbleChatListItem({
    super.key,
    required this.item,
    this.onTap,
    this.onLongPress,
    this.onMute,
    this.onPin,
    this.onDelete,
  });

  @override
  State<BubbleChatListItem> createState() => _BubbleChatListItemState();
}

class _BubbleChatListItemState extends State<BubbleChatListItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _entryCtrl;
  late Animation<double> _entryFade;
  late Animation<Offset> _entrySlide;

  double _dragX = 0;
  bool _bubbleOn = false; // reflects actual bubble state

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 320));
    _entryFade = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut));
    _entrySlide = Tween<Offset>(begin: const Offset(-0.05, 0), end: Offset.zero)
        .animate(
            CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));
    _entryCtrl.forward();

    // Reflect current bubble state
    final ctrl = BubbleManager.of(context);
    _bubbleOn = ctrl?.isBubbleActive(widget.item.peerId) ?? false;
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    super.dispose();
  }

  // ─── Drag ────────────────────────────────────────────────────────────────

  void _onDragUpdate(DragUpdateDetails d) {
    setState(() => _dragX = (_dragX + d.delta.dx).clamp(-80.0, 80.0));
  }

  Future<void> _onDragEnd(DragEndDetails d) async {
    final vel = d.velocity.pixelsPerSecond.dx;
    if (_dragX > 50 || vel > 400) {
      await _toggleBubble();
    }
    setState(() => _dragX = 0);
  }

  Future<void> _toggleBubble() async {
    HapticFeedback.mediumImpact();
    final ctrl = BubbleManager.of(context);
    if (ctrl == null) return;

    if (_bubbleOn) {
      await ctrl.hideBubble(widget.item.peerId);
      setState(() => _bubbleOn = false);
    } else {
      await ctrl.showBubble(
        userId: widget.item.peerId,
        userName: widget.item.peerName,
        avatarUrl: widget.item.peerAvatar,
        lastMessage: widget.item.lastMessage,
        isOnline: widget.item.isOnline,
      );
      setState(() => _bubbleOn = true);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_bubbleOn
            ? '🫧 Bong bóng bật — ${widget.item.peerName}'
            : '💬 Bong bóng tắt — ${widget.item.peerName}'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor:
            _bubbleOn ? const Color(0xFF2979FF) : Colors.grey.shade700,
      ));
    }
  }

  // ═════════════════════════════════════════════════════════════════════
  // BUILD
  // ═════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return FadeTransition(
      opacity: _entryFade,
      child: SlideTransition(
        position: _entrySlide,
        child: GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            widget.onTap?.call();
          },
          onLongPress: () {
            HapticFeedback.mediumImpact();
            _showContextMenu();
          },
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: _onDragEnd,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            transform: Matrix4.translationValues(_dragX * 0.3, 0, 0),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF1A1A2E)
                      .withValues(alpha: item.hasUnread ? 1 : 0.9)
                  : (item.hasUnread ? const Color(0xFFF0F4FF) : Colors.white),
            ),
            child: Stack(
              children: [
                // ── Swipe indicator ─────────────────────────────────
                _SwipeIndicator(
                  dragX: _dragX,
                  bubbleOn: _bubbleOn,
                ),
                // ── Main row ─────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Row(
                    children: [
                      _AvatarSection(item: item, bubbleOn: _bubbleOn),
                      const SizedBox(width: 12),
                      Expanded(child: _ContentSection(item: item)),
                      const SizedBox(width: 8),
                      _TrailingSection(
                          item: item,
                          bubbleOn: _bubbleOn,
                          onBubbleTap: _toggleBubble),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showContextMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ContextMenu(
        item: widget.item,
        bubbleOn: _bubbleOn,
        onBubble: _toggleBubble,
        onMute: widget.onMute,
        onPin: widget.onPin,
        onDelete: widget.onDelete,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SWIPE INDICATOR
// ═══════════════════════════════════════════════════════════════════════════

class _SwipeIndicator extends StatelessWidget {
  final double dragX;
  final bool bubbleOn;
  const _SwipeIndicator({required this.dragX, required this.bubbleOn});

  @override
  Widget build(BuildContext context) {
    final progress = (dragX.abs() / 80).clamp(0.0, 1.0);
    if (progress < 0.1) return const SizedBox.shrink();

    return Positioned(
      left: dragX > 0 ? 0 : null,
      right: dragX < 0 ? 0 : null,
      top: 0,
      bottom: 0,
      child: Container(
        width: 60,
        color: bubbleOn
            ? Colors.grey.shade200
            : const Color(0xFF2979FF).withValues(alpha: 0.15),
        child: Opacity(
          opacity: progress,
          child: Center(
            child: Icon(
              bubbleOn
                  ? Icons.chat_bubble_outline_rounded
                  : Icons.chat_bubble_rounded,
              color: bubbleOn ? Colors.grey.shade500 : const Color(0xFF2979FF),
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// AVATAR SECTION
// ═══════════════════════════════════════════════════════════════════════════

class _AvatarSection extends StatefulWidget {
  final BubbleConversationData item;
  final bool bubbleOn;
  const _AvatarSection({required this.item, required this.bubbleOn});

  @override
  State<_AvatarSection> createState() => _AvatarSectionState();
}

class _AvatarSectionState extends State<_AvatarSection>
    with SingleTickerProviderStateMixin {
  late AnimationController _onlineCtrl;

  @override
  void initState() {
    super.initState();
    _onlineCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400));
    if (widget.item.isOnline) _onlineCtrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_AvatarSection old) {
    super.didUpdateWidget(old);
    if (widget.item.isOnline && !_onlineCtrl.isAnimating) {
      _onlineCtrl.repeat(reverse: true);
    } else if (!widget.item.isOnline) {
      _onlineCtrl.stop();
    }
  }

  @override
  void dispose() {
    _onlineCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Avatar
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: widget.bubbleOn
                ? Border.all(color: const Color(0xFF2979FF), width: 2.5)
                : null,
          ),
          child: CircleAvatar(
            radius: 26,
            backgroundColor: const Color(0xFF2979FF).withValues(alpha: 0.12),
            backgroundImage: item.peerAvatar.isNotEmpty
                ? CachedNetworkImageProvider(item.peerAvatar)
                : null,
            child: item.peerAvatar.isEmpty
                ? Text(
                    item.peerName.isNotEmpty
                        ? item.peerName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: Color(0xFF2979FF),
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                    ))
                : null,
          ),
        ),

        // Online indicator
        if (item.isOnline)
          Positioned(
            bottom: 1,
            right: 1,
            child: AnimatedBuilder(
              animation: _onlineCtrl,
              builder: (_, __) => Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color.lerp(const Color(0xFF4CAF50),
                      const Color(0xFF69F0AE), _onlineCtrl.value),
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4CAF50)
                          .withValues(alpha: 0.5 * _onlineCtrl.value),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Bubble-on indicator
        if (widget.bubbleOn)
          Positioned(
            top: -2,
            right: -2,
            child: Container(
              width: 16,
              height: 16,
              decoration: const BoxDecoration(
                color: Color(0xFF2979FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.chat_bubble_rounded,
                  size: 9, color: Colors.white),
            ),
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CONTENT SECTION
// ═══════════════════════════════════════════════════════════════════════════

class _ContentSection extends StatelessWidget {
  final BubbleConversationData item;
  const _ContentSection({required this.item});

  String get _preview {
    if (item.isTyping) return '';
    switch (item.lastMessageType) {
      case 'image':
        return '📷 Hình ảnh';
      case 'voice':
        return '🎤 Tin nhắn thoại';
      case 'location':
        return '📍 Vị trí';
      case 'file':
        return '📎 Tệp đính kèm';
      case 'sticker':
        return '😊 Nhãn dán';
      default:
        return item.isFromMe ? 'Bạn: ${item.lastMessage}' : item.lastMessage;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Name row
        Row(
          children: [
            if (item.isPinned)
              Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(Icons.push_pin_rounded,
                      size: 12, color: Colors.grey.shade400)),
            Expanded(
              child: Text(
                item.peerName,
                style: TextStyle(
                  fontWeight:
                      item.hasUnread ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 15.5,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),

        // Message preview or typing indicator
        if (item.isTyping)
          const BubbleTypingIndicator.list()
        else
          Row(
            children: [
              // Delivery status
              if (item.isFromMe)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(
                    item.isRead ? Icons.done_all_rounded : Icons.done_rounded,
                    size: 14,
                    color: item.isRead
                        ? const Color(0xFF2979FF)
                        : Colors.grey.shade400,
                  ),
                ),
              Expanded(
                child: Text(
                  _preview,
                  style: TextStyle(
                    fontSize: 13,
                    color: item.hasUnread
                        ? (isDark ? Colors.white70 : Colors.black54)
                        : Colors.grey.shade500,
                    fontWeight:
                        item.hasUnread ? FontWeight.w600 : FontWeight.normal,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TRAILING SECTION
// ═══════════════════════════════════════════════════════════════════════════

class _TrailingSection extends StatelessWidget {
  final BubbleConversationData item;
  final bool bubbleOn;
  final AsyncCallback onBubbleTap;
  const _TrailingSection(
      {required this.item, required this.bubbleOn, required this.onBubbleTap});

  String _formatTime(DateTime t) {
    final now = DateTime.now();
    if (now.difference(t).inDays == 0) {
      final h = t.hour.toString().padLeft(2, '0');
      final m = t.minute.toString().padLeft(2, '0');
      return '$h:$m';
    } else if (now.difference(t).inDays == 1) {
      return 'Hôm qua';
    } else if (now.difference(t).inDays < 7) {
      const days = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
      return days[t.weekday - 1];
    } else {
      return '${t.day}/${t.month}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Timestamp
        Text(
          _formatTime(item.timestamp),
          style: TextStyle(
            fontSize: 11.5,
            color:
                item.hasUnread ? const Color(0xFF2979FF) : Colors.grey.shade400,
            fontWeight: item.hasUnread ? FontWeight.w700 : FontWeight.normal,
          ),
        ),
        const SizedBox(height: 6),

        // Unread badge OR muted icon
        if (item.hasUnread)
          _UnreadBadge(count: item.unreadCount)
        else if (item.isMuted)
          Icon(Icons.volume_off_rounded, size: 14, color: Colors.grey.shade400)
        else
          // Bubble toggle button
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              onBubbleTap();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: bubbleOn
                    ? const Color(0xFF2979FF).withValues(alpha: 0.12)
                    : Colors.grey.withValues(alpha: 0.08),
                shape: BoxShape.circle,
                border: Border.all(
                  color: bubbleOn
                      ? const Color(0xFF2979FF).withValues(alpha: 0.4)
                      : Colors.grey.withValues(alpha: 0.2),
                ),
              ),
              child: Icon(
                bubbleOn
                    ? Icons.chat_bubble_rounded
                    : Icons.chat_bubble_outline_rounded,
                size: 14,
                color:
                    bubbleOn ? const Color(0xFF2979FF) : Colors.grey.shade400,
              ),
            ),
          ),
      ],
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  final int count;
  const _UnreadBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF2979FF),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2979FF).withValues(alpha: 0.4),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          height: 1.2,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CONTEXT MENU
// ═══════════════════════════════════════════════════════════════════════════

class _ContextMenu extends StatelessWidget {
  final BubbleConversationData item;
  final bool bubbleOn;
  final AsyncCallback onBubble;
  final VoidCallback? onMute;
  final VoidCallback? onPin;
  final VoidCallback? onDelete;
  const _ContextMenu(
      {required this.item,
      required this.bubbleOn,
      required this.onBubble,
      this.onMute,
      this.onPin,
      this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          // Peer info
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundImage: item.peerAvatar.isNotEmpty
                      ? CachedNetworkImageProvider(item.peerAvatar)
                      : null,
                  child: item.peerAvatar.isEmpty
                      ? Text(item.peerName[0].toUpperCase(),
                          style: const TextStyle(fontWeight: FontWeight.w700))
                      : null,
                ),
                const SizedBox(width: 12),
                Text(item.peerName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16)),
              ],
            ),
          ),
          const Divider(height: 0, thickness: 0.5, indent: 16, endIndent: 16),
          const SizedBox(height: 4),
          _MenuItem(
            icon: bubbleOn
                ? Icons.chat_bubble_outline_rounded
                : Icons.chat_bubble_rounded,
            color: const Color(0xFF2979FF),
            label: bubbleOn ? 'Tắt bong bóng' : 'Bật bong bóng',
            onTap: () {
              Navigator.pop(context);
              onBubble();
            },
          ),
          _MenuItem(
            icon: item.isPinned
                ? Icons.push_pin_outlined
                : Icons.push_pin_rounded,
            color: Colors.orange,
            label: item.isPinned ? 'Bỏ ghim' : 'Ghim hội thoại',
            onTap: () {
              Navigator.pop(context);
              onPin?.call();
            },
          ),
          _MenuItem(
            icon: item.isMuted
                ? Icons.volume_up_rounded
                : Icons.volume_off_rounded,
            color: Colors.grey,
            label: item.isMuted ? 'Bật thông báo' : 'Tắt thông báo',
            onTap: () {
              Navigator.pop(context);
              onMute?.call();
            },
          ),
          if (onDelete != null)
            _MenuItem(
              icon: Icons.delete_outline_rounded,
              color: Colors.red,
              label: 'Xoá hội thoại',
              onTap: () {
                Navigator.pop(context);
                onDelete?.call();
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  const _MenuItem(
      {required this.icon,
      required this.color,
      required this.label,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Text(label,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
