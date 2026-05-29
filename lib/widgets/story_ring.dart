import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter_chat_demo/models/story_model.dart';





class StoryRing extends StatefulWidget {
  final Widget child;
  final bool hasUnseenStories;
  final bool isCurrentUser;
  final int totalSegments;
  final int seenSegments;

  
  final double ringWidth;

  
  final double gap;

  
  final double segmentGap;

  const StoryRing({
    super.key,
    required this.child,
    required this.hasUnseenStories,
    this.isCurrentUser = false,
    this.totalSegments = 1,
    this.seenSegments = 0,
    this.ringWidth = 2.5,
    this.gap = 2.5,
    this.segmentGap = 2.0,
  });

  @override
  State<StoryRing> createState() => _StoryRingState();
}

class _StoryRingState extends State<StoryRing> with SingleTickerProviderStateMixin {
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
    final showRing = widget.hasUnseenStories || widget.isCurrentUser;
    if (!showRing && widget.seenSegments == 0) return widget.child;

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

  static const _unseenColors = [
    Color(0xFFFF6B35),
    Color(0xFFFF2D55),
    Color(0xFFBF5FFF),
    Color(0xFF2196F3),
    Color(0xFF00C6FF),
    Color(0xFFFF6B35),
  ];

  static const _seenColor = Color(0xFF9E9E9E);
  static const _currentUserColor = Color(0xFF2196F3);

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
      if (isCurrentUser) {
        paint.color = _currentUserColor;
        canvas.drawOval(rect, paint);
        return;
      }
      if (!hasUnseen) {
        paint.color = _seenColor.withValues(alpha: 0.45);
        canvas.drawOval(rect, paint);
        return;
      }

      
      paint.shader = SweepGradient(
        startAngle: -math.pi / 2 + progress * 2 * math.pi,
        endAngle: 3 * math.pi / 2 + progress * 2 * math.pi,
        colors: _unseenColors,
      ).createShader(rect);
      canvas.drawOval(rect, paint);
      return;
    }

    
    final total = totalSegments;
    final gapRad = segmentGapDeg * math.pi / 180;
    final segSweep = (2 * math.pi - gapRad * total) / total;

    for (int i = 0; i < total; i++) {
      final startAngle = -math.pi / 2 + i * (segSweep + gapRad) + gapRad / 2;
      final isSeen = i < seenSegments;

      if (isSeen) {
        paint
          ..shader = null
          ..color = _seenColor.withValues(alpha: 0.45);
      } else if (isCurrentUser) {
        paint
          ..shader = null
          ..color = _currentUserColor;
      } else {
        
        paint.shader = SweepGradient(
          startAngle: -math.pi / 2 + progress * 2 * math.pi,
          endAngle: 3 * math.pi / 2 + progress * 2 * math.pi,
          colors: _unseenColors,
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
          _MyStatusTile(
            myStories: myStories,
            currentUserId: currentUserId,
            onAdd: onAddStory,
            onView: myStories != null ? () => onViewStories(myStories!) : null,
          ),
          if (others.isNotEmpty)
            Container(
              width: 0.5,
              height: 64,
              margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
              color: Theme.of(context).dividerColor,
            ),
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





class _MyStatusTile extends StatelessWidget {
  final UserStories? myStories;
  final String currentUserId;
  final VoidCallback onAdd;
  final VoidCallback? onView;

  const _MyStatusTile({
    required this.myStories,
    required this.currentUserId,
    required this.onAdd,
    required this.onView,
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
                  totalSegments: active.length.clamp(1, 10),
                  seenSegments: seen,
                  child: SizedBox(
                    width: 54,
                    height: 54,
                    child: ClipOval(
                      child: _AvatarImage(
                        photoUrl: myStories?.latestStory?.type == StoryType.image
                            ? (myStories?.latestStory?.mediaUrl ?? '')
                            : (myStories?.userPhotoUrl ?? ''),
                      ),
                    ),
                  ),
                ),
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
    final active = userStories.activeStories;
    final seen = active.where((s) => s.isViewedBy(viewerId)).length;
    final hasUnseen = seen < active.length;

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
              totalSegments: active.length.clamp(1, 10),
              seenSegments: seen,
              child: SizedBox(
                width: 54,
                height: 54,
                child: ClipOval(
                  child: _AvatarImage(photoUrl: userStories.userPhotoUrl),
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
        color: Colors.grey.shade300,
        child: const Icon(Icons.person, color: Colors.grey, size: 28),
      ),
    );
  }
}
