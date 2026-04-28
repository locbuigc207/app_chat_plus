import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/constants/constants.dart';

// ── LOADING VIEW ──────────────────────────────────────────────────────────────
class LoadingView extends StatelessWidget {
  final String? message;

  const LoadingView({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.25),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? ColorConstants.surfaceDark
                : Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 34,
                height: 34,
                child: CircularProgressIndicator(
                  color: ColorConstants.primaryColor,
                  strokeWidth: 3,
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: 12),
                Text(
                  message!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: ColorConstants.greyColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── IMPROVED REACTION PICKER ──────────────────────────────────────────────────
class ReactionPicker extends StatelessWidget {
  final Function(String emoji) onEmojiSelected;

  const ReactionPicker({super.key, required this.onEmojiSelected});

  static const availableEmojis = [
    '❤️', '👍', '😂', '😮', '😢', '🔥', '👏', '🎉'
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? ColorConstants.surfaceDark2 : Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: availableEmojis.map((emoji) {
          return _EmojiBtn(emoji: emoji, onTap: () => onEmojiSelected(emoji));
        }).toList(),
      ),
    );
  }
}

class _EmojiBtn extends StatefulWidget {
  final String emoji;
  final VoidCallback onTap;
  const _EmojiBtn({required this.emoji, required this.onTap});

  @override
  State<_EmojiBtn> createState() => _EmojiBtnState();
}

class _EmojiBtnState extends State<_EmojiBtn>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scale = Tween<double>(begin: 1.0, end: 1.4).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) => Transform.scale(
          scale: _scale.value,
          child: child,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          child: Text(widget.emoji, style: const TextStyle(fontSize: 22)),
        ),
      ),
    );
  }
}

// ── MESSAGE REACTIONS DISPLAY ─────────────────────────────────────────────────
class MessageReactionsDisplay extends StatelessWidget {
  final Map<String, int> reactions;
  final String currentUserId;
  final Map<String, bool> userReactions;
  final Function(String emoji) onReactionTap;

  const MessageReactionsDisplay({
    super.key,
    required this.reactions,
    required this.currentUserId,
    required this.userReactions,
    required this.onReactionTap,
  });

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: reactions.entries.map((entry) {
        final hasReacted = userReactions[entry.key] ?? false;
        return GestureDetector(
          onTap: () => onReactionTap(entry.key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: hasReacted
                  ? ColorConstants.primaryColor.withOpacity(0.15)
                  : (isDark
                  ? ColorConstants.surfaceDark2
                  : ColorConstants.greyColor2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: hasReacted
                    ? ColorConstants.primaryColor.withOpacity(0.5)
                    : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(entry.key, style: const TextStyle(fontSize: 13)),
                const SizedBox(width: 4),
                Text(
                  '${entry.value}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: hasReacted
                        ? ColorConstants.primaryColor
                        : ColorConstants.greyColor,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── SMART REPLY WIDGET ────────────────────────────────────────────────────────
class SmartReplyWidget extends StatelessWidget {
  final List<SmartReply> replies;
  final Function(String) onReplySelected;

  const SmartReplyWidget({
    super.key,
    required this.replies,
    required this.onReplySelected,
  });

  @override
  Widget build(BuildContext context) {
    if (replies.isEmpty) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          Icon(
            Icons.auto_awesome_rounded,
            size: 14,
            color: ColorConstants.primaryColor.withOpacity(0.7),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: replies.map((reply) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => onReplySelected(reply.text),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isDark
                              ? ColorConstants.primaryColor.withOpacity(0.12)
                              : ColorConstants.primaryColor.withOpacity(0.07),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: ColorConstants.primaryColor.withOpacity(0.2),
                          ),
                        ),
                        child: Text(
                          reply.text,
                          style: TextStyle(
                            fontSize: 13,
                            color: ColorConstants.primaryColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── TYPING INDICATOR ──────────────────────────────────────────────────────────
class TypingIndicator extends StatefulWidget {
  final String userName;
  const TypingIndicator({super.key, required this.userName});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(left: 12, top: 4, bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? ColorConstants.surfaceDark2 : Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...List.generate(3, (i) {
              return AnimatedBuilder(
                animation: _controller,
                builder: (_, __) {
                  final offset = i * 0.2;
                  final val = (_controller.value - offset) % 1.0;
                  final t = val < 0.5 ? val * 2 : 2 - (val * 2);
                  return Container(
                    margin: EdgeInsets.only(right: i < 2 ? 4 : 0),
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: ColorConstants.primaryColor
                          .withOpacity(0.3 + (t * 0.7)),
                      shape: BoxShape.circle,
                    ),
                  );
                },
              );
            }),
            const SizedBox(width: 8),
            Text(
              '${widget.userName} is typing',
              style: const TextStyle(
                fontSize: 12,
                color: ColorConstants.greyColor,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── READ RECEIPT WIDGET ───────────────────────────────────────────────────────
class ReadReceiptWidget extends StatelessWidget {
  final bool isRead;
  final bool isSent;
  final double size;

  const ReadReceiptWidget({
    super.key,
    required this.isRead,
    this.isSent = true,
    this.size = 16,
  });

  @override
  Widget build(BuildContext context) {
    if (!isSent) {
      return Icon(Icons.schedule_rounded, size: size, color: Colors.white54);
    }
    return Icon(
      isRead ? Icons.done_all_rounded : Icons.done_rounded,
      size: size,
      color: isRead ? const Color(0xFF80DEEA) : Colors.white54,
    );
  }
}

// ── ONLINE FRIENDS BAR AVATAR ─────────────────────────────────────────────────
class UserAvatarWidget extends StatelessWidget {
  final String photoUrl;
  final String name;
  final double size;

  const UserAvatarWidget({
    super.key,
    required this.photoUrl,
    required this.name,
    this.size = 50,
  });

  @override
  Widget build(BuildContext context) {
    final colorIndex = name.isEmpty
        ? 0
        : name.codeUnitAt(0) % ColorConstants.avatarColors.length;
    final avatarColor = ColorConstants.avatarColors[colorIndex];

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: avatarColor.withOpacity(0.12),
        border: Border.all(
          color: avatarColor.withOpacity(0.25),
          width: 1.5,
        ),
      ),
      child: ClipOval(
        child: photoUrl.isNotEmpty
            ? Image.network(
          photoUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildInitials(avatarColor),
        )
            : _buildInitials(avatarColor),
      ),
    );
  }

  Widget _buildInitials(Color color) {
    return Container(
      color: color.withOpacity(0.12),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: size * 0.35,
          ),
        ),
      ),
    );
  }
}