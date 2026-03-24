// lib/widgets/story_ring.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/models/story_model.dart';

/// Animated gradient ring shown around avatars with unseen stories
class StoryRing extends StatefulWidget {
  final Widget child;
  final bool hasUnseenStories;
  final bool isCurrentUser;
  final double ringWidth;
  final double padding;

  const StoryRing({
    super.key,
    required this.child,
    required this.hasUnseenStories,
    this.isCurrentUser = false,
    this.ringWidth = 2.5,
    this.padding = 2.0,
  });

  @override
  State<StoryRing> createState() => _StoryRingState();
}

class _StoryRingState extends State<StoryRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.hasUnseenStories && !widget.isCurrentUser) {
      return widget.child;
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _StoryRingPainter(
            progress: widget.hasUnseenStories ? _controller.value : 0,
            ringWidth: widget.ringWidth,
            padding: widget.padding,
            isSeen: !widget.hasUnseenStories,
            isCurrentUser: widget.isCurrentUser,
          ),
          child: Padding(
            padding: EdgeInsets.all(widget.ringWidth + widget.padding),
            child: widget.child,
          ),
        );
      },
    );
  }
}

class _StoryRingPainter extends CustomPainter {
  final double progress;
  final double ringWidth;
  final double padding;
  final bool isSeen;
  final bool isCurrentUser;

  _StoryRingPainter({
    required this.progress,
    required this.ringWidth,
    required this.padding,
    required this.isSeen,
    required this.isCurrentUser,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      ringWidth / 2,
      ringWidth / 2,
      size.width - ringWidth,
      size.height - ringWidth,
    );

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth
      ..strokeCap = StrokeCap.round;

    if (isCurrentUser && !isSeen) {
      // Current user: simple blue ring with + indicator
      paint.color = const Color(0xFF2196F3);
      canvas.drawOval(rect, paint);
      return;
    }

    if (isSeen) {
      // Seen stories: grey ring
      paint.color = Colors.grey.withOpacity(0.4);
      canvas.drawOval(rect, paint);
      return;
    }

    // Unseen stories: animated gradient ring
    final gradient = SweepGradient(
      startAngle: -math.pi / 2 + (progress * 2 * math.pi),
      endAngle: 3 * math.pi / 2 + (progress * 2 * math.pi),
      colors: const [
        Color(0xFFFF6B35),
        Color(0xFFFF2D55),
        Color(0xFFBF5FFF),
        Color(0xFF2196F3),
        Color(0xFF00C6FF),
        Color(0xFFFF6B35),
      ],
    );

    paint.shader = gradient.createShader(rect);
    canvas.drawOval(rect, paint);
  }

  @override
  bool shouldRepaint(_StoryRingPainter old) => old.progress != progress;
}

// ──────────────────────────────────────────────────────────
// STORIES BAR (horizontal scroll in home page)
// ──────────────────────────────────────────────────────────

class StoriesBar extends StatelessWidget {
  final List<UserStories> storiesList;
  final String currentUserId;
  final VoidCallback onAddStory;
  final void Function(UserStories, int initialIndex) onViewStories;

  const StoriesBar({
    super.key,
    required this.storiesList,
    required this.currentUserId,
    required this.onAddStory,
    required this.onViewStories,
  });

  @override
  Widget build(BuildContext context) {
    final myStories =
        storiesList.where((s) => s.userId == currentUserId).firstOrNull;
    final otherStories =
        storiesList.where((s) => s.userId != currentUserId).toList();

    return Container(
      height: 106,
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          // Add/My story tile
          _MyStoryTile(
            myStories: myStories,
            onAdd: onAddStory,
            onView:
                myStories != null ? () => onViewStories(myStories, 0) : null,
          ),

          // Divider
          if (otherStories.isNotEmpty)
            Container(
              width: 0.5,
              height: 70,
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              color: Colors.grey.withOpacity(0.3),
            ),

          // Friends' stories
          ...otherStories.map((userStories) => _FriendStoryTile(
                userStories: userStories,
                viewerId: currentUserId,
                onTap: () => onViewStories(userStories, 0),
              )),
        ],
      ),
    );
  }
}

class _MyStoryTile extends StatelessWidget {
  final UserStories? myStories;
  final VoidCallback onAdd;
  final VoidCallback? onView;

  const _MyStoryTile({
    required this.myStories,
    required this.onAdd,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: myStories != null ? onView : onAdd,
      onLongPress: myStories != null ? onAdd : null,
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                StoryRing(
                  hasUnseenStories: myStories != null,
                  isCurrentUser: true,
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.grey.shade200,
                    ),
                    child: myStories?.latestStory?.type == StoryType.image
                        ? ClipOval(
                            child: Image.network(
                              myStories!.latestStory!.mediaUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.person, color: Colors.grey),
                            ),
                          )
                        : const Icon(Icons.person,
                            color: Colors.grey, size: 32),
                  ),
                ),
                // + button overlay
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: GestureDetector(
                    onTap: onAdd,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: const BoxDecoration(
                        color: Color(0xFF2196F3),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white,
                            spreadRadius: 1.5,
                          ),
                        ],
                      ),
                      child:
                          const Icon(Icons.add, color: Colors.white, size: 14),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              myStories != null ? 'My Status' : 'Add Status',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).textTheme.bodySmall?.color,
                fontWeight: FontWeight.w500,
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

class _FriendStoryTile extends StatelessWidget {
  final UserStories userStories;
  final String viewerId;
  final VoidCallback onTap;

  const _FriendStoryTile({
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
        width: 72,
        margin: const EdgeInsets.only(right: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            StoryRing(
              hasUnseenStories: hasUnseen,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey.shade200,
                ),
                child: ClipOval(
                  child: userStories.userPhotoUrl.isNotEmpty
                      ? Image.network(
                          userStories.userPhotoUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.person, color: Colors.grey),
                        )
                      : const Icon(Icons.person, color: Colors.grey, size: 32),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              userStories.userName,
              style: TextStyle(
                fontSize: 11,
                color: hasUnseen
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).textTheme.bodySmall?.color,
                fontWeight: hasUnseen ? FontWeight.w600 : FontWeight.w400,
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
