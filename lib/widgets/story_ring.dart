// lib/widgets/story_ring.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter_chat_demo/models/story_model.dart';

// ─────────────────────────────────────────────────────────────
// STORY RING WIDGET
// ─────────────────────────────────────────────────────────────

/// Animated gradient ring around an avatar that has unseen stories.
/// Pass [hasUnseenStories] = false to show a grey "already seen" ring.
/// Pass [isCurrentUser] = true to show a static blue ring (Add Story).
class StoryRing extends StatefulWidget {
  final Widget child;
  final bool hasUnseenStories;
  final bool isCurrentUser;
  /// Thickness of the ring stroke
  final double ringWidth;
  /// Gap between ring and child
  final double gap;

  const StoryRing({
    super.key,
    required this.child,
    required this.hasUnseenStories,
    this.isCurrentUser = false,
    this.ringWidth = 2.5,
    this.gap = 2.5,
  });

  @override
  State<StoryRing> createState() => _StoryRingState();
}

class _StoryRingState extends State<StoryRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // No ring needed: no stories and not current user
    if (!widget.hasUnseenStories && !widget.isCurrentUser) {
      return widget.child;
    }

    final totalPad = widget.ringWidth + widget.gap;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => CustomPaint(
        painter: _RingPainter(
          progress: widget.hasUnseenStories ? _ctrl.value : 0,
          ringWidth: widget.ringWidth,
          isSeen: !widget.hasUnseenStories && !widget.isCurrentUser,
          isCurrentUser: widget.isCurrentUser,
        ),
        child: Padding(
          padding: EdgeInsets.all(totalPad),
          child: widget.child,
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final double ringWidth;
  final bool isSeen;
  final bool isCurrentUser;

  const _RingPainter({
    required this.progress,
    required this.ringWidth,
    required this.isSeen,
    required this.isCurrentUser,
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

    if (isSeen) {
      paint.color = Colors.grey.withOpacity(0.45);
      canvas.drawOval(rect, paint);
      return;
    }

    if (isCurrentUser) {
      paint.color = const Color(0xFF2196F3);
      canvas.drawOval(rect, paint);
      return;
    }

    // Animated gradient ring for unseen stories
    paint.shader = SweepGradient(
      startAngle: -math.pi / 2 + progress * 2 * math.pi,
      endAngle:    3 * math.pi / 2 + progress * 2 * math.pi,
      colors: const [
        Color(0xFFFF6B35),
        Color(0xFFFF2D55),
        Color(0xFFBF5FFF),
        Color(0xFF2196F3),
        Color(0xFF00C6FF),
        Color(0xFFFF6B35),
      ],
    ).createShader(rect);

    canvas.drawOval(rect, paint);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
          old.isSeen != isSeen ||
          old.isCurrentUser != isCurrentUser;
}

// ─────────────────────────────────────────────────────────────
// STORIES BAR  (horizontal strip in home page)
// ─────────────────────────────────────────────────────────────

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
    // Find my stories (nullable — may not exist yet)
    UserStories? myStories;
    final others = <UserStories>[];

    for (final s in storiesList) {
      if (s.userId == currentUserId) {
        myStories = s;
      } else {
        others.add(s);
      }
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 110,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 0.5,
          ),
        ),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        children: [
          // ── My Status tile ──────────────────────────
          _MyStatusTile(
            myStories: myStories,
            onAdd: onAddStory,
            onView: myStories != null
                ? () => onViewStories(myStories!)
                : null,
          ),

          // Vertical divider
          if (others.isNotEmpty)
            Container(
              width: 0.5,
              height: 64,
              margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
              color: Theme.of(context).dividerColor,
            ),

          // ── Friends' stories ─────────────────────────
          for (final us in others)
            _FriendTile(
              userStories: us,
              viewerId: currentUserId,
              onTap: () => onViewStories(us),
            ),
        ],
      ),
    );
  }
}

// ── My Status Tile ────────────────────────────────────────────

class _MyStatusTile extends StatelessWidget {
  final UserStories? myStories;
  final VoidCallback onAdd;
  final VoidCallback? onView;

  const _MyStatusTile({
    required this.myStories,
    required this.onAdd,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    final hasStories = myStories != null && myStories!.activeStories.isNotEmpty;
    final latest = myStories?.latestStory;

    return GestureDetector(
      onTap: hasStories ? onView : onAdd,
      onLongPress: hasStories ? onAdd : null,
      child: SizedBox(
        width: 70,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                StoryRing(
                  hasUnseenStories: hasStories,
                  isCurrentUser: true,
                  child: SizedBox(
                    width: 54,
                    height: 54,
                    child: ClipOval(
                      child: _AvatarContent(
                        photoUrl: latest?.type == StoryType.image
                            ? (latest?.mediaUrl ?? '')
                            : '',
                      ),
                    ),
                  ),
                ),
                // + badge
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: GestureDetector(
                    onTap: onAdd,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2196F3),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          width: 2,
                        ),
                      ),
                      child: const Icon(Icons.add, color: Colors.white, size: 13),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              hasStories ? 'My Status' : 'Add Status',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).textTheme.bodySmall?.color,
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

// ── Friend Tile ───────────────────────────────────────────────

class _FriendTile extends StatelessWidget {
  final UserStories userStories;
  final String viewerId;
  final VoidCallback onTap;

  const _FriendTile({
    required this.userStories,
    required this.viewerId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasUnseen = userStories.hasUnseenStoriesBy(viewerId);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 70,
        margin: const EdgeInsets.only(right: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            StoryRing(
              hasUnseenStories: hasUnseen,
              child: SizedBox(
                width: 54,
                height: 54,
                child: ClipOval(
                  child: _AvatarContent(
                    photoUrl: userStories.userPhotoUrl,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              userStories.userName,
              style: TextStyle(
                fontSize: 11,
                fontWeight: hasUnseen ? FontWeight.w700 : FontWeight.w400,
                color: hasUnseen
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).textTheme.bodySmall?.color,
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

// ── Shared avatar helper ──────────────────────────────────────

class _AvatarContent extends StatelessWidget {
  final String photoUrl;
  const _AvatarContent({required this.photoUrl});

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
        color: Colors.grey.shade300,
        child: const Icon(Icons.person, color: Colors.grey, size: 28),
      ),
    );
  }
}