import 'package:flutter/material.dart';

import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';

class ConversationItem extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onTap;
  final Function(BuildContext) onLongPress;

  const ConversationItem({
    super.key,
    required this.conversation,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasUnread = (conversation.unreadCount ?? 0) > 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: () => onLongPress(context),
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: conversation.isPinned
                  ? ColorConstants.primaryColor.withValues(alpha: isDark ? 0.12 : 0.06)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                _buildAvatar(isDark),
                const SizedBox(width: 12),
                Expanded(child: _buildContent(isDark, hasUnread)),
                _buildMeta(isDark, hasUnread),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(bool isDark) {
    final photoUrl = conversation.peerPhotoUrl ?? '';
    return Stack(
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade100,
          ),
          child: ClipOval(
            child: photoUrl.isNotEmpty
                ? Image.network(
                    photoUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _avatarFallback(),
                  )
                : _avatarFallback(),
          ),
        ),
        if (conversation.isOnline ?? false)
          Positioned(
            right: 2,
            bottom: 2,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.green,
                border:
                    Border.all(color: isDark ? const Color(0xFF0D0D0D) : Colors.white, width: 2),
              ),
            ),
          ),
        if (conversation.isMuted && !(conversation.isOnline ?? false))
          Positioned(
            right: 2,
            bottom: 2,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark ? const Color(0xFF2C2C3E) : Colors.white,
                border: Border.all(
                    color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey.shade200,
                    width: 1),
              ),
              child: Icon(Icons.volume_off_rounded,
                  size: 10, color: isDark ? Colors.white38 : Colors.grey.shade400),
            ),
          ),
      ],
    );
  }

  Widget _avatarFallback() {
    final name = conversation.peerName ?? 'U';
    final initial = name.isNotEmpty ? name.substring(0, 1).toUpperCase() : 'U';
    return Container(
      color: ColorConstants.primaryColor.withValues(alpha: 0.15),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
              fontSize: 20, fontWeight: FontWeight.bold, color: ColorConstants.primaryColor),
        ),
      ),
    );
  }

  Widget _buildContent(bool isDark, bool hasUnread) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (conversation.isPinned)
              Padding(
                padding: const EdgeInsets.only(right: 5),
                child: Icon(Icons.push_pin_rounded, size: 13, color: ColorConstants.primaryColor),
              ),
            Expanded(
              child: Text(
                conversation.peerName ?? 'Conversation',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w500,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            if (conversation.isTyping ?? false)
              _TypingIndicator()
            else
              Expanded(
                child: Row(
                  children: [
                    if (conversation.isSentByMe ?? false)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(
                          conversation.isRead ?? false
                              ? Icons.done_all_rounded
                              : Icons.done_rounded,
                          size: 14,
                          color: conversation.isRead ?? false
                              ? ColorConstants.primaryColor
                              : Colors.grey.shade400,
                        ),
                      ),
                    Expanded(
                      child: Text(
                        conversation.lastMessage.isEmpty
                            ? 'Bắt đầu cuộc trò chuyện'
                            : conversation.lastMessage,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: hasUnread
                              ? (isDark ? Colors.white70 : Colors.black87)
                              : (isDark ? Colors.white38 : Colors.grey.shade500),
                          fontWeight: hasUnread ? FontWeight.w500 : FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildMeta(bool isDark, bool hasUnread) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _formatTimestamp(conversation.lastMessageTime),
          style: TextStyle(
            fontSize: 11.5,
            color: hasUnread
                ? ColorConstants.primaryColor
                : (isDark ? Colors.white24 : Colors.grey.shade400),
            fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        const SizedBox(height: 6),
        if (hasUnread)
          Container(
            constraints: const BoxConstraints(minWidth: 20),
            height: 20,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: conversation.isMuted ? Colors.grey.shade400 : ColorConstants.primaryColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                '${conversation.unreadCount! > 99 ? '99+' : conversation.unreadCount}',
                style:
                    const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ),
          )
        else if (conversation.isArchived ?? false)
          Icon(Icons.archive_rounded,
              size: 16, color: isDark ? Colors.white24 : Colors.grey.shade400)
        else
          const SizedBox(height: 20),
      ],
    );
  }

  String _formatTimestamp(String? timestampStr) {
    if (timestampStr == null || timestampStr.isEmpty || timestampStr == '0') {
      return '';
    }

    final timestamp = int.tryParse(timestampStr);
    if (timestamp == null) return '';

    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inDays == 0) {
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    } else if (diff.inDays == 1) {
      return 'Hôm qua';
    } else if (diff.inDays < 7) {
      const days = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
      return days[dt.weekday - 1];
    } else {
      return '${dt.day}/${dt.month}';
    }
  }
}

class _TypingIndicator extends StatefulWidget {
  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Row(
          children: List.generate(3, (i) {
            final delay = i / 3;
            final value = ((_ctrl.value - delay) % 1.0).clamp(0.0, 1.0);
            final opacity = value < 0.5 ? value * 2 : (1 - value) * 2;
            return Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ColorConstants.primaryColor
                    .withValues(alpha: 0.4 + 0.6 * opacity.clamp(0.0, 1.0)),
              ),
            );
          }),
        );
      },
    );
  }
}
