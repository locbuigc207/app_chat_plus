// ============================================================
// IMPROVED CHAT PAGE - Key UI/UX changes:
// 1. Modern message bubbles with tail, soft shadows
// 2. Improved input bar with smooth animations
// 3. Beautiful date separators
// 4. Read receipts with blue ticks
// 5. Smooth scroll-to-bottom FAB
// 6. Message reactions display improved
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/constants/constants.dart';

// ── MESSAGE BUBBLE ────────────────────────────────────────────────────────────
class ImprovedMessageBubble extends StatelessWidget {
  final String content;
  final bool isMe;
  final String timestamp;
  final bool isRead;
  final bool isDeleted;
  final bool isPinned;
  final bool isDark;
  final String? editedAt;
  final Widget? reactions;
  final VoidCallback? onLongPress;
  final VoidCallback? onDoubleTap;

  const ImprovedMessageBubble({
    super.key,
    required this.content,
    required this.isMe,
    required this.timestamp,
    required this.isDark,
    this.isRead = false,
    this.isDeleted = false,
    this.isPinned = false,
    this.editedAt,
    this.reactions,
    this.onLongPress,
    this.onDoubleTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.72,
          ),
          child: Column(
            crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onLongPress: onLongPress,
                onDoubleTap: onDoubleTap,
                child: _BubbleBody(
                  content: content,
                  isMe: isMe,
                  isDeleted: isDeleted,
                  isDark: isDark,
                  isPinned: isPinned,
                  editedAt: editedAt,
                  timestamp: timestamp,
                  isRead: isRead,
                ),
              ),
              if (reactions != null) ...[
                const SizedBox(height: 4),
                reactions!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BubbleBody extends StatelessWidget {
  final String content;
  final bool isMe;
  final bool isDeleted;
  final bool isDark;
  final bool isPinned;
  final String? editedAt;
  final String timestamp;
  final bool isRead;

  const _BubbleBody({
    required this.content,
    required this.isMe,
    required this.isDeleted,
    required this.isDark,
    required this.isPinned,
    required this.timestamp,
    required this.isRead,
    this.editedAt,
  });

  Color get _bubbleBg {
    if (isMe) {
      return isDark ? const Color(0xFF1565C0) : const Color(0xFF1976D2);
    }
    return isDark ? const Color(0xFF252A3D) : Colors.white;
  }

  Color get _textColor {
    if (isMe) return Colors.white;
    return isDark ? const Color(0xFFF0F2F8) : const Color(0xFF1A1D2E);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _bubbleBg,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isMe ? 18 : 4),
          bottomRight: Radius.circular(isMe ? 4 : 18),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isPinned) ...[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.push_pin_rounded,
                  size: 11,
                  color: isMe ? Colors.white60 : ColorConstants.greyColor,
                ),
                const SizedBox(width: 4),
                Text(
                  'Pinned',
                  style: TextStyle(
                    fontSize: 10,
                    color: isMe ? Colors.white60 : ColorConstants.greyColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],
          if (isDeleted)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.block_rounded,
                  size: 13,
                  color: isMe ? Colors.white60 : ColorConstants.greyColor,
                ),
                const SizedBox(width: 6),
                Text(
                  'Message deleted',
                  style: TextStyle(
                    color: isMe ? Colors.white60 : ColorConstants.greyColor,
                    fontStyle: FontStyle.italic,
                    fontSize: 13,
                  ),
                ),
              ],
            )
          else
            Text(
              content,
              style: TextStyle(
                color: _textColor,
                fontSize: 14.5,
                height: 1.4,
              ),
            ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (editedAt != null) ...[
                Text(
                  'edited',
                  style: TextStyle(
                    fontSize: 10,
                    color: isMe ? Colors.white54 : ColorConstants.greyColor,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Text(
                _formatTime(timestamp),
                style: TextStyle(
                  fontSize: 11,
                  color: isMe ? Colors.white60 : ColorConstants.greyColor,
                  fontWeight: FontWeight.w400,
                ),
              ),
              if (isMe) ...[
                const SizedBox(width: 4),
                Icon(
                  isRead ? Icons.done_all_rounded : Icons.done_rounded,
                  size: 14,
                  color: isRead ? const Color(0xFF80DEEA) : Colors.white54,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(String ts) {
    try {
      final dt = DateTime.fromMillisecondsSinceEpoch(int.parse(ts));
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }
}

// ── DATE SEPARATOR ────────────────────────────────────────────────────────────
class DateSeparator extends StatelessWidget {
  final String label;
  final bool isDark;

  const DateSeparator({
    super.key,
    required this.label,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 1,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    isDark
                        ? Colors.white.withOpacity(0.08)
                        : Colors.black.withOpacity(0.08),
                  ],
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.06)
                  : ColorConstants.primaryColor.withOpacity(0.06),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark
                    ? Colors.white.withOpacity(0.08)
                    : ColorConstants.primaryColor.withOpacity(0.12),
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? Colors.white.withOpacity(0.5)
                    : ColorConstants.primaryColor.withOpacity(0.7),
                letterSpacing: 0.3,
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 1,
              margin: const EdgeInsets.only(left: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    isDark
                        ? Colors.white.withOpacity(0.08)
                        : Colors.black.withOpacity(0.08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── IMPROVED CHAT INPUT BAR ───────────────────────────────────────────────────
class ImprovedChatInput extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isDark;
  final bool isMiniChat;
  final bool isBubbleMode;
  final bool isRecording;
  final String recordingDuration;
  final bool showFeatures;
  final MessageChat? replyingTo;
  final Function(String) onTextChanged;
  final VoidCallback onSend;
  final VoidCallback onImagePick;
  final VoidCallback onSticker;
  final VoidCallback onRecord;
  final VoidCallback onStopRecord;
  final VoidCallback onCancelRecord;
  final VoidCallback onToggleFeatures;
  final VoidCallback? onClearReply;

  const ImprovedChatInput({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.isDark,
    this.isMiniChat = false,
    this.isBubbleMode = false,
    this.isRecording = false,
    this.recordingDuration = '0:00',
    this.showFeatures = false,
    this.replyingTo,
    required this.onTextChanged,
    required this.onSend,
    required this.onImagePick,
    required this.onSticker,
    required this.onRecord,
    required this.onStopRecord,
    required this.onCancelRecord,
    required this.onToggleFeatures,
    this.onClearReply,
  });

  @override
  State<ImprovedChatInput> createState() => _ImprovedChatInputState();
}

class _ImprovedChatInputState extends State<ImprovedChatInput>
    with SingleTickerProviderStateMixin {
  late AnimationController _sendController;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _sendController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    widget.controller.addListener(_onTextChange);
  }

  void _onTextChange() {
    final hasText = widget.controller.text.isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
      if (hasText) {
        _sendController.forward();
      } else {
        _sendController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _sendController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showFull = !widget.isMiniChat && !widget.isBubbleMode;

    return Container(
      decoration: BoxDecoration(
        color: widget.isDark ? ColorConstants.surfaceDark : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(widget.isDark ? 0.2 : 0.06),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Reply preview
          if (widget.replyingTo != null) _buildReplyPreview(),

          // Recording bar
          if (widget.isRecording) _buildRecordingBar(),

          // Main input row
          if (!widget.isRecording)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Feature toggle
                  if (showFull)
                    _InputIconBtn(
                      icon: widget.showFeatures
                          ? Icons.close_rounded
                          : Icons.add_rounded,
                      isDark: widget.isDark,
                      onTap: widget.onToggleFeatures,
                      filled: widget.showFeatures,
                    ),

                  // Text field container
                  Expanded(
                    child: Container(
                      constraints: const BoxConstraints(
                        minHeight: 44,
                        maxHeight: 120,
                      ),
                      margin:
                          EdgeInsets.symmetric(horizontal: showFull ? 6 : 4),
                      decoration: BoxDecoration(
                        color: widget.isDark
                            ? ColorConstants.surfaceDark2
                            : ColorConstants.greyColor2,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: widget.isDark
                              ? ColorConstants.borderDark
                              : Colors.transparent,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                              child: TextField(
                                controller: widget.controller,
                                focusNode: widget.focusNode,
                                maxLines: 6,
                                minLines: 1,
                                onChanged: widget.onTextChanged,
                                autofocus:
                                    widget.isMiniChat || widget.isBubbleMode,
                                style: TextStyle(
                                  color: widget.isDark
                                      ? Colors.white
                                      : const Color(0xFF1A1D2E),
                                  fontSize: 14.5,
                                  height: 1.4,
                                ),
                                decoration: InputDecoration(
                                  hintText:
                                      widget.isMiniChat || widget.isBubbleMode
                                          ? 'Message...'
                                          : 'Type a message...',
                                  hintStyle: TextStyle(
                                    color: widget.isDark
                                        ? Colors.white38
                                        : ColorConstants.greyColor,
                                    fontSize: 14.5,
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                textInputAction: TextInputAction.newline,
                                keyboardType: TextInputType.multiline,
                              ),
                            ),
                          ),
                          // Sticker btn (only full)
                          if (showFull)
                            Padding(
                              padding:
                                  const EdgeInsets.only(right: 6, bottom: 8),
                              child: GestureDetector(
                                onTap: widget.onSticker,
                                child: Icon(
                                  Icons.emoji_emotions_outlined,
                                  size: 22,
                                  color: widget.isDark
                                      ? Colors.white38
                                      : ColorConstants.greyColor,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  // Send / Image / Voice
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, anim) => ScaleTransition(
                      scale: anim,
                      child: child,
                    ),
                    child: _hasText
                        ? _SendButton(
                            key: const ValueKey('send'),
                            onTap: widget.onSend,
                          )
                        : _buildMediaButtons(showFull),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReplyPreview() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: widget.isDark
            ? ColorConstants.primaryColor.withOpacity(0.12)
            : ColorConstants.primaryColor.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(
            color: ColorConstants.primaryColor,
            width: 3,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Reply',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: ColorConstants.primaryColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.replyingTo!.content,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: widget.isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: widget.onClearReply,
            child: Icon(Icons.close_rounded,
                size: 16, color: ColorConstants.greyColor),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          const _PulsingDot(),
          const SizedBox(width: 10),
          Text(
            'Recording  ${widget.recordingDuration}',
            style: const TextStyle(
              color: ColorConstants.accentRed,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const Spacer(),
          _InputIconBtn(
            icon: Icons.delete_outline_rounded,
            isDark: widget.isDark,
            onTap: widget.onCancelRecord,
            iconColor: ColorConstants.accentRed,
          ),
          const SizedBox(width: 4),
          _SendButton(onTap: widget.onStopRecord),
        ],
      ),
    );
  }

  Widget _buildMediaButtons(bool showFull) {
    return Row(
      key: const ValueKey('media'),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showFull)
          _InputIconBtn(
            icon: Icons.image_outlined,
            isDark: widget.isDark,
            onTap: widget.onImagePick,
          ),
        if (showFull) const SizedBox(width: 4),
        _InputIconBtn(
          icon: Icons.mic_none_rounded,
          isDark: widget.isDark,
          onTap: widget.onRecord,
          filled: true,
        ),
      ],
    );
  }
}

class _InputIconBtn extends StatelessWidget {
  final IconData icon;
  final bool isDark;
  final VoidCallback onTap;
  final bool filled;
  final Color? iconColor;

  const _InputIconBtn({
    required this.icon,
    required this.isDark,
    required this.onTap,
    this.filled = false,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: filled
              ? ColorConstants.primaryColor.withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          size: 22,
          color: iconColor ??
              (isDark ? Colors.white54 : ColorConstants.primaryColor),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  final VoidCallback onTap;

  const _SendButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: ColorConstants.primaryGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(13),
          boxShadow: [
            BoxShadow(
              color: ColorConstants.primaryColor.withOpacity(0.35),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: const Icon(
          Icons.send_rounded,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: Color.lerp(
            ColorConstants.accentRed.withOpacity(0.6),
            ColorConstants.accentRed,
            _controller.value,
          ),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ── CHAT APP BAR ──────────────────────────────────────────────────────────────
class ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String peerName;
  final String peerAvatar;
  final String peerId;
  final bool isDark;
  final VoidCallback? onBackPressed;
  final List<Widget> actions;

  const ChatAppBar({
    super.key,
    required this.peerName,
    required this.peerAvatar,
    required this.peerId,
    required this.isDark,
    this.onBackPressed,
    this.actions = const [],
  });

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64 + MediaQuery.of(context).padding.top,
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      decoration: BoxDecoration(
        color: isDark ? ColorConstants.surfaceDark : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              color: isDark ? Colors.white70 : ColorConstants.primaryColor,
              onPressed: onBackPressed ?? () => Navigator.pop(context),
            ),
            _buildAvatar(),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    peerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF1A1D2E),
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 1),
                  _OnlineStatus(userId: peerId, isDark: isDark),
                ],
              ),
            ),
            ...actions,
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    final colorIndex = peerName.isEmpty
        ? 0
        : peerName.codeUnitAt(0) % ColorConstants.avatarColors.length;
    final avatarColor = ColorConstants.avatarColors[colorIndex];

    return Stack(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: avatarColor.withOpacity(0.15),
            border: Border.all(color: avatarColor.withOpacity(0.2), width: 1.5),
          ),
          child: ClipOval(
            child: peerAvatar.isNotEmpty
                ? Image.network(
                    peerAvatar,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Center(
                      child: Text(
                        peerName.isNotEmpty ? peerName[0].toUpperCase() : '?',
                        style: TextStyle(
                          color: avatarColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  )
                : Center(
                    child: Text(
                      peerName.isNotEmpty ? peerName[0].toUpperCase() : '?',
                      style: TextStyle(
                        color: avatarColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _OnlineStatus extends StatelessWidget {
  final String userId;
  final bool isDark;
  const _OnlineStatus({required this.userId, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final presenceProvider = context.read<UserPresenceProvider>();
    return StreamBuilder<Map<String, dynamic>>(
      stream: presenceProvider.getUserOnlineStatus(userId),
      builder: (_, snap) {
        final isOnline = snap.data?['isOnline'] as bool? ?? false;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isOnline
                    ? ColorConstants.accentGreen
                    : ColorConstants.greyColor.withOpacity(0.5),
              ),
            ),
            const SizedBox(width: 5),
            Text(
              isOnline ? 'Online' : 'Offline',
              style: TextStyle(
                fontSize: 12,
                color: isOnline
                    ? ColorConstants.accentGreen
                    : ColorConstants.greyColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── SCROLL TO BOTTOM BUTTON ───────────────────────────────────────────────────
class ScrollToBottomButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool isDark;

  const ScrollToBottomButton({
    super.key,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: isDark ? ColorConstants.surfaceDark2 : Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
          border: Border.all(
            color:
                isDark ? ColorConstants.borderDark : ColorConstants.greyColor2,
          ),
        ),
        child: Icon(
          Icons.keyboard_arrow_down_rounded,
          color: ColorConstants.primaryColor,
          size: 22,
        ),
      ),
    );
  }
}
