import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/providers/providers.dart';





class LoadingView extends StatefulWidget {
  final String? message;

  const LoadingView({super.key, this.message});

  @override
  State<LoadingView> createState() => _LoadingViewState();
}

class _LoadingViewState extends State<LoadingView> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return FadeTransition(
      opacity: _fade,
      child: Container(
        color: Colors.black.withValues(alpha: 0.3),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C2E) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _AnimatedSpinner(),
                if (widget.message != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    widget.message!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white54 : Colors.grey.shade600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedSpinner extends StatefulWidget {
  @override
  State<_AnimatedSpinner> createState() => _AnimatedSpinnerState();
}

class _AnimatedSpinnerState extends State<_AnimatedSpinner> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
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
      builder: (_, __) => SizedBox(
        width: 36,
        height: 36,
        child: CustomPaint(
          painter: _SpinnerPainter(_ctrl.value),
        ),
      ),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  final double progress;
  _SpinnerPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2 - 3;
    final trackPaint = Paint()
      ..color = ColorConstants.primaryColor.withValues(alpha: 0.15)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(Offset(cx, cy), r, trackPaint);

    final arcPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          ColorConstants.primaryColor.withValues(alpha: 0.1),
          ColorConstants.primaryColor,
        ],
        startAngle: 0,
        endAngle: math.pi * 1.6,
        transform: GradientRotation(progress * math.pi * 2),
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r))
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      progress * math.pi * 2,
      math.pi * 1.5,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(_SpinnerPainter old) => old.progress != progress;
}





class ReactionPicker extends StatelessWidget {
  final Function(String emoji) onEmojiSelected;

  const ReactionPicker({super.key, required this.onEmojiSelected});

  static const availableEmojis = [
    '❤️',
    '👍',
    '😂',
    '😮',
    '😢',
    '🔥',
    '👏',
    '🎉',
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF252A3D) : Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.14),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.07) : Colors.grey.shade100,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: availableEmojis
            .map((emoji) => _EmojiBtn(
                  emoji: emoji,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onEmojiSelected(emoji);
                  },
                ))
            .toList(),
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

class _EmojiBtnState extends State<_EmojiBtn> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _lift;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scale = Tween<double>(begin: 1.0, end: 1.5).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
    _lift = Tween<double>(begin: 0, end: -10).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
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
        animation: _ctrl,
        builder: (_, child) => Transform.translate(
          offset: Offset(0, _lift.value),
          child: Transform.scale(scale: _scale.value, child: child),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Text(widget.emoji, style: const TextStyle(fontSize: 22)),
        ),
      ),
    );
  }
}





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
      spacing: 5,
      runSpacing: 5,
      children: reactions.entries.map((entry) {
        final hasReacted = userReactions[entry.key] ?? false;
        return GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onReactionTap(entry.key);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: hasReacted
                  ? ColorConstants.primaryColor.withValues(alpha: isDark ? 0.25 : 0.12)
                  : (isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade100),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: hasReacted
                    ? ColorConstants.primaryColor.withValues(alpha: 0.5)
                    : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(entry.key, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 5),
                Text(
                  '${entry.value}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: hasReacted
                        ? ColorConstants.primaryColor
                        : (isDark ? Colors.white54 : Colors.grey.shade600),
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
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Color(0xFF6C63FF), Color(0xFF3B82F6)],
                ).createShader(bounds),
                child: const Icon(Icons.auto_awesome_rounded, size: 13, color: Colors.white),
              ),
              const SizedBox(width: 5),
              Text(
                'Gợi ý trả lời nhanh',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white38 : Colors.grey.shade500,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: replies.asMap().entries.map((entry) {
                final i = entry.key;
                final reply = entry.value;
                return _SmartReplyChip(
                  text: reply.text,
                  isDark: isDark,
                  index: i,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onReplySelected(reply.text);
                  },
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _SmartReplyChip extends StatefulWidget {
  final String text;
  final bool isDark;
  final int index;
  final VoidCallback onTap;

  const _SmartReplyChip({
    required this.text,
    required this.isDark,
    required this.index,
    required this.onTap,
  });

  @override
  State<_SmartReplyChip> createState() => _SmartReplyChipState();
}

class _SmartReplyChipState extends State<_SmartReplyChip> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 130));
    _scale = Tween<double>(begin: 1.0, end: 0.95)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeIn));
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
        builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
        child: Container(
          margin: EdgeInsets.only(right: 8, left: widget.index == 0 ? 0 : 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: widget.isDark
                ? ColorConstants.primaryColor.withValues(alpha: 0.15)
                : ColorConstants.primaryColor.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: ColorConstants.primaryColor.withValues(alpha: 0.25),
              width: 1,
            ),
          ),
          child: Text(
            widget.text,
            style: const TextStyle(
              fontSize: 13.5,
              color: ColorConstants.primaryColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}





class TypingIndicator extends StatefulWidget {
  final String userName;
  final String? avatarUrl;

  const TypingIndicator({
    super.key,
    required this.userName,
    this.avatarUrl,
  });

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _fade = CurvedAnimation(
        parent: AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 250),
        )..forward(),
        curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 12, top: 4, bottom: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            
            Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(right: 8, bottom: 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ColorConstants.primaryColor.withValues(alpha: 0.12),
                border:
                    Border.all(color: ColorConstants.primaryColor.withValues(alpha: 0.2), width: 1),
              ),
              child: ClipOval(
                child: widget.avatarUrl != null && widget.avatarUrl!.isNotEmpty
                    ? Image.network(widget.avatarUrl!,
                        fit: BoxFit.cover, errorBuilder: (_, __, ___) => _initials(widget.userName))
                    : _initials(widget.userName),
              ),
            ),
            
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF252A3D) : Colors.white,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                  bottomLeft: Radius.circular(4),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.07),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...List.generate(3, (i) {
                    return AnimatedBuilder(
                      animation: _ctrl,
                      builder: (_, __) {
                        final offset = i * 0.22;
                        final val = (_ctrl.value - offset) % 1.0;
                        final t = val < 0.5 ? val * 2 : 2 - (val * 2);
                        return Container(
                          margin: EdgeInsets.only(right: i < 2 ? 5 : 0),
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: ColorConstants.primaryColor.withValues(alpha: 0.25 + t * 0.75),
                            shape: BoxShape.circle,
                          ),
                        );
                      },
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _initials(String name) {
    return Container(
      color: ColorConstants.primaryColor.withValues(alpha: 0.1),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(
              color: ColorConstants.primaryColor, fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}





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
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Icon(
        key: ValueKey(isRead),
        isRead ? Icons.done_all_rounded : Icons.done_rounded,
        size: size,
        color: isRead ? const Color(0xFF80DEEA) : Colors.white54,
      ),
    );
  }
}





class UserAvatarWidget extends StatelessWidget {
  final String photoUrl;
  final String name;
  final double size;
  final bool showOnline;

  const UserAvatarWidget({
    super.key,
    required this.photoUrl,
    required this.name,
    this.size = 50,
    this.showOnline = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorIndex = name.isEmpty ? 0 : name.codeUnitAt(0) % ColorConstants.avatarColors.length;
    final avatarColor = ColorConstants.avatarColors[colorIndex];

    return Stack(
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: avatarColor.withValues(alpha: 0.1),
            border: Border.all(
              color: avatarColor.withValues(alpha: 0.2),
              width: 1.5,
            ),
          ),
          child: ClipOval(
            child: photoUrl.isNotEmpty
                ? Image.network(
                    photoUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _buildInitials(avatarColor),
                    loadingBuilder: (_, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        color: avatarColor.withValues(alpha: 0.08),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: avatarColor,
                            strokeWidth: 1.5,
                          ),
                        ),
                      );
                    },
                  )
                : _buildInitials(avatarColor),
          ),
        ),
        if (showOnline)
          Positioned(
            right: 1,
            bottom: 1,
            child: Container(
              width: size * 0.26,
              height: size * 0.26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.green,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildInitials(Color color) {
    return Container(
      color: color.withValues(alpha: 0.1),
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





class PulsingDot extends StatefulWidget {
  final Color color;
  final double size;

  const PulsingDot({
    super.key,
    this.color = ColorConstants.accentRed,
    this.size = 10,
  });

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: Color.lerp(
            widget.color.withValues(alpha: 0.5),
            widget.color,
            _anim.value,
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: _anim.value * 0.4),
              blurRadius: 6,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}





class EmptyStateWidget extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  const EmptyStateWidget({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: ColorConstants.primaryColor.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: ColorConstants.primaryColor),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black87),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(
                  fontSize: 14, height: 1.5, color: isDark ? Colors.white38 : Colors.grey.shade500),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              const SizedBox(height: 24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
