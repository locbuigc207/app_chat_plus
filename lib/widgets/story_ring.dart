import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter_chat_demo/models/story_model.dart';

// ─── Story Ring ───────────────────────────────────────────────────────────────

class StoryRing extends StatefulWidget {
  final Widget child;
  final bool hasUnseenStories;
  final bool isCurrentUser;
  final int totalSegments;
  final int seenSegments;
  final double ringWidth;
  final double gap;
  final double segmentGap;
  final bool animating;

  const StoryRing({
    super.key,
    required this.child,
    required this.hasUnseenStories,
    this.isCurrentUser = false,
    this.totalSegments = 1,
    this.seenSegments = 0,
    this.ringWidth = 2.5,
    this.gap = 2.5,
    this.segmentGap = 3.0,
    this.animating = true,
  });

  @override
  State<StoryRing> createState() => _StoryRingState();
}

class _StoryRingState extends State<StoryRing> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 3));
    if (widget.animating && (widget.hasUnseenStories || widget.isCurrentUser)) {
      _ctrl.repeat();
    }
  }

  @override
  void didUpdateWidget(StoryRing old) {
    super.didUpdateWidget(old);
    final shouldAnimate = widget.animating && (widget.hasUnseenStories || widget.isCurrentUser);
    if (shouldAnimate && !_ctrl.isAnimating) {
      _ctrl.repeat();
    } else if (!shouldAnimate && _ctrl.isAnimating) {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showRing = widget.hasUnseenStories || widget.isCurrentUser || widget.seenSegments > 0;
    if (!showRing) return widget.child;

    final totalPad = widget.ringWidth + widget.gap;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => CustomPaint(
        painter: _SegmentedRingPainter(
          progress: _ctrl.value,
          ringWidth: widget.ringWidth,
          totalSegments: widget.totalSegments,
          seenSegments: widget.seenSegments,
          hasUnseen: widget.hasUnseenStories,
          isCurrentUser: widget.isCurrentUser,
          segmentGapDeg: widget.segmentGap,
        ),
        child: Padding(
          padding: EdgeInsets.all(totalPad),
          child: widget.child,
        ),
      ),
    );
  }
}

class _SegmentedRingPainter extends CustomPainter {
  final double progress;
  final double ringWidth;
  final int totalSegments;
  final int seenSegments;
  final bool hasUnseen;
  final bool isCurrentUser;
  final double segmentGapDeg;

  // Premium gradient for unseen stories
  static const List<Color> _unseenGradient = [
    Color(0xFFFF6B35),
    Color(0xFFFF2D55),
    Color(0xFFBF5FFF),
    Color(0xFF5B5EFF),
    Color(0xFF00C6FF),
    Color(0xFFFF6B35),
  ];

  // Close friends green gradient
  static const List<Color> _closeFriendGradient = [
    Color(0xFF00E676),
    Color(0xFF00BFA5),
    Color(0xFF00E676),
  ];

  static const Color _seenColor = Color(0xFF9E9E9E);
  static const Color _currentUserColor = Color(0xFF2196F3);

  const _SegmentedRingPainter({
    required this.progress,
    required this.ringWidth,
    required this.totalSegments,
    required this.seenSegments,
    required this.hasUnseen,
    required this.isCurrentUser,
    required this.segmentGapDeg,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final half = ringWidth / 2;
    final rect = Rect.fromLTWH(half, half, size.width - ringWidth, size.height - ringWidth);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    if (totalSegments <= 1) {
      _paintSingleRing(canvas, rect, paint);
      return;
    }

    _paintSegmentedRing(canvas, rect, paint);
  }

  void _paintSingleRing(Canvas canvas, Rect rect, Paint paint) {
    if (isCurrentUser) {
      paint
        ..shader = SweepGradient(
          startAngle: -math.pi / 2 + progress * 2 * math.pi,
          endAngle: 3 * math.pi / 2 + progress * 2 * math.pi,
          colors: _unseenGradient,
        ).createShader(rect);
      canvas.drawOval(rect, paint);
      return;
    }
    if (!hasUnseen) {
      paint
        ..shader = null
        ..color = _seenColor.withOpacity(0.45);
      canvas.drawOval(rect, paint);
      return;
    }
    paint.shader = SweepGradient(
      startAngle: -math.pi / 2 + progress * 2 * math.pi,
      endAngle: 3 * math.pi / 2 + progress * 2 * math.pi,
      colors: _unseenGradient,
    ).createShader(rect);
    canvas.drawOval(rect, paint);
  }

  void _paintSegmentedRing(Canvas canvas, Rect rect, Paint paint) {
    final total = totalSegments;
    final gapRad = segmentGapDeg * math.pi / 180;
    final segSweep = (2 * math.pi - gapRad * total) / total;

    for (int i = 0; i < total; i++) {
      final startAngle = -math.pi / 2 + i * (segSweep + gapRad) + gapRad / 2;
      final isSeen = i < seenSegments;

      if (isSeen) {
        paint
          ..shader = null
          ..color = _seenColor.withOpacity(0.4);
      } else if (isCurrentUser) {
        paint.shader = SweepGradient(
          startAngle: -math.pi / 2 + progress * 2 * math.pi,
          endAngle: 3 * math.pi / 2 + progress * 2 * math.pi,
          colors: _unseenGradient,
        ).createShader(rect);
      } else {
        paint.shader = SweepGradient(
          startAngle: -math.pi / 2 + progress * 2 * math.pi,
          endAngle: 3 * math.pi / 2 + progress * 2 * math.pi,
          colors: _unseenGradient,
        ).createShader(rect);
      }

      canvas.drawArc(rect, startAngle, segSweep, false, paint);
    }
  }

  @override
  bool shouldRepaint(_SegmentedRingPainter old) =>
      old.progress != progress ||
          old.hasUnseen != hasUnseen ||
          old.isCurrentUser != isCurrentUser ||
          old.seenSegments != seenSegments ||
          old.totalSegments != totalSegments;
}

// ─── StoriesBar ───────────────────────────────────────────────────────────────

class StoriesBar extends StatelessWidget {
  final List<UserStories> storiesList;
  final String currentUserId;
  final VoidCallback onAddStory;
  final void Function(UserStories userStories) onViewStories;

  const StoriesBar({
    super.key,
    required this.storiesList,
    required this.currentUserId,
    required this.onAddStory,
    required this.onViewStories,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    UserStories? myStories;
    final others = <UserStories>[];

    for (final s in storiesList) {
      if (s.userId == currentUserId) {
        myStories = s;
      } else {
        others.add(s);
      }
    }

    return Container(
      height: 106,
      color: isDark ? const Color(0xFF0F0F0F) : Colors.white,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          _MyStatusTile(
            myStories: myStories,
            currentUserId: currentUserId,
            onAdd: onAddStory,
            onView: myStories != null ? () => onViewStories(myStories!) : null,
            isDark: isDark,
          ),
          if (others.isNotEmpty)
            Container(
              width: 0.5,
              height: 56,
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
              color: isDark ? Colors.white12 : Colors.black12,
            ),
          for (final us in others)
            _FriendTile(
              userStories: us,
              viewerId: currentUserId,
              onTap: () => onViewStories(us),
              isDark: isDark,
            ),
        ],
      ),
    );
  }
}

class _MyStatusTile extends StatelessWidget {
  final UserStories? myStories;
  final String currentUserId;
  final VoidCallback onAdd;
  final VoidCallback? onView;
  final bool isDark;

  const _MyStatusTile({
    required this.myStories,
    required this.currentUserId,
    required this.onAdd,
    required this.onView,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final hasStories = myStories != null && myStories!.activeStories.isNotEmpty;
    final active = myStories?.activeStories ?? [];
    final seen = active.where((s) => s.isViewedBy(currentUserId)).length;

    return GestureDetector(
      onTap: hasStories ? onView : onAdd,
      onLongPress: hasStories ? onAdd : null,
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                StoryRing(
                  hasUnseenStories: hasStories,
                  isCurrentUser: true,
                  totalSegments: active.length.clamp(1, 12),
                  seenSegments: seen,
                  ringWidth: 2.0,
                  gap: 2.0,
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: ClipOval(child: _AvatarImage(photoUrl: myStories?.userPhotoUrl ?? '')),
                  ),
                ),
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: GestureDetector(
                    onTap: onAdd,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF2196F3), Color(0xFF7B61FF)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark ? const Color(0xFF0F0F0F) : Colors.white,
                          width: 2,
                        ),
                      ),
                      child: const Icon(Icons.add, color: Colors.white, size: 12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              hasStories ? 'My Status' : 'Add Status',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : const Color(0xFF374151),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _FriendTile extends StatelessWidget {
  final UserStories userStories;
  final String viewerId;
  final VoidCallback onTap;
  final bool isDark;

  const _FriendTile({
    required this.userStories,
    required this.viewerId,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final active = userStories.activeStories;
    final seen = active.where((s) => s.isViewedBy(viewerId)).length;
    final hasUnseen = seen < active.length;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        margin: const EdgeInsets.only(right: 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            StoryRing(
              hasUnseenStories: hasUnseen,
              totalSegments: active.length.clamp(1, 12),
              seenSegments: seen,
              ringWidth: 2.0,
              gap: 2.0,
              child: SizedBox(
                width: 56,
                height: 56,
                child: ClipOval(child: _AvatarImage(photoUrl: userStories.userPhotoUrl)),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              userStories.userName.split(' ').first,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: hasUnseen ? FontWeight.w700 : FontWeight.w500,
                color: hasUnseen
                    ? (isDark ? Colors.white : const Color(0xFF0D1117))
                    : (isDark ? Colors.white54 : const Color(0xFF9CA3AF)),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _AvatarImage extends StatelessWidget {
  final String photoUrl;
  const _AvatarImage({required this.photoUrl});

  @override
  Widget build(BuildContext context) {
    if (photoUrl.isEmpty) {
      return Container(
        color: Colors.grey.shade300,
        child: const Icon(Icons.person, color: Colors.grey, size: 28),
      );
    }
    return Image.network(
      photoUrl,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        color: Colors.grey.shade800,
        child: const Icon(Icons.person, color: Colors.white38, size: 28),
      ),
    );
  }
}