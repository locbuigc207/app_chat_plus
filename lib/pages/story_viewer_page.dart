// lib/pages/story_viewer_page.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/providers/story_provider.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

export 'package:flutter_chat_demo/models/story_model.dart';

class StoryViewerPage extends StatefulWidget {
  final List<UserStories> allUserStories;
  final int initialUserIndex;
  final String currentUserId;
  final String currentUserName;
  final String currentUserPhotoUrl;

  const StoryViewerPage({
    super.key,
    required this.allUserStories,
    required this.initialUserIndex,
    required this.currentUserId,
    required this.currentUserName,
    required this.currentUserPhotoUrl,
  });

  @override
  State<StoryViewerPage> createState() => _StoryViewerPageState();
}

class _StoryViewerPageState extends State<StoryViewerPage>
    with TickerProviderStateMixin {
  late PageController _pageController;
  late int _currentUserIndex;
  late int _currentStoryIndex;

  late AnimationController _progressController;
  Timer? _storyTimer;

  bool _isPaused = false;
  bool _isDragging = false;
  bool _showViewers = false;

  static const Duration _storyDuration = Duration(seconds: 5);
  static const Duration _imageDuration = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _currentUserIndex = widget.initialUserIndex;
    _currentStoryIndex = 0;

    _pageController = PageController(initialPage: _currentUserIndex);
    _progressController = AnimationController(vsync: this);

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    WidgetsBinding.instance.addPostFrameCallback((_) => _startStory());
  }

  @override
  void dispose() {
    _storyTimer?.cancel();
    _progressController.dispose();
    _pageController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  UserStories get _currentUserStories =>
      widget.allUserStories[_currentUserIndex];

  Story get _currentStory =>
      _currentUserStories.activeStories[_currentStoryIndex];

  int get _totalStories => _currentUserStories.activeStories.length;

  void _startStory() {
    _storyTimer?.cancel();
    _progressController.stop();
    _progressController.reset();

    _markCurrentStoryViewed();

    final duration = _imageDuration;
    _progressController.duration = duration;
    _progressController.forward();

    _progressController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _nextStory();
      }
    });
  }

  void _markCurrentStoryViewed() {
    if (_currentStory.userId == widget.currentUserId) return;
    context.read<StoryProvider>().markStoryViewed(
          storyId: _currentStory.id,
          viewerId: widget.currentUserId,
          viewerName: widget.currentUserName,
          viewerPhotoUrl: widget.currentUserPhotoUrl,
        );
  }

  void _nextStory() {
    if (_currentStoryIndex < _totalStories - 1) {
      setState(() {
        _currentStoryIndex++;
      });
      _startStory();
    } else {
      _nextUser();
    }
  }

  void _prevStory() {
    if (_currentStoryIndex > 0) {
      setState(() {
        _currentStoryIndex--;
      });
      _startStory();
    } else {
      _prevUser();
    }
  }

  void _nextUser() {
    if (_currentUserIndex < widget.allUserStories.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      Navigator.of(context).pop();
    }
  }

  void _prevUser() {
    if (_currentUserIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  void _pause() {
    if (!_isPaused) {
      _isPaused = true;
      _progressController.stop();
    }
  }

  void _resume() {
    if (_isPaused) {
      _isPaused = false;
      _progressController.forward();
    }
  }

  void _onUserPageChanged(int index) {
    setState(() {
      _currentUserIndex = index;
      _currentStoryIndex = 0;
    });
    _startStory();
  }

  Future<void> _deleteCurrentStory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Story'),
        content:
            const Text('This story will be permanently deleted. Continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await context.read<StoryProvider>().deleteStory(_currentStory.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageController,
        onPageChanged: _onUserPageChanged,
        itemCount: widget.allUserStories.length,
        itemBuilder: (context, userIndex) {
          final userStories = widget.allUserStories[userIndex];
          final isActive = userIndex == _currentUserIndex;

          return _StoryUserView(
            userStories: userStories,
            storyIndex: isActive ? _currentStoryIndex : 0,
            progressController: isActive ? _progressController : null,
            isCurrentUser: userStories.userId == widget.currentUserId,
            onTapLeft: _prevStory,
            onTapRight: _nextStory,
            onLongPressStart: _pause,
            onLongPressEnd: _resume,
            onClose: () => Navigator.of(context).pop(),
            onDelete: _deleteCurrentStory,
            currentUserId: widget.currentUserId,
          );
        },
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────
class _StoryUserView extends StatelessWidget {
  final UserStories userStories;
  final int storyIndex;
  final AnimationController? progressController;
  final bool isCurrentUser;
  final VoidCallback onTapLeft;
  final VoidCallback onTapRight;
  final VoidCallback onLongPressStart;
  final VoidCallback onLongPressEnd;
  final VoidCallback onClose;
  final VoidCallback onDelete;
  final String currentUserId;

  const _StoryUserView({
    required this.userStories,
    required this.storyIndex,
    required this.progressController,
    required this.isCurrentUser,
    required this.onTapLeft,
    required this.onTapRight,
    required this.onLongPressStart,
    required this.onLongPressEnd,
    required this.onClose,
    required this.onDelete,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    final stories = userStories.activeStories;
    if (stories.isEmpty) return const SizedBox.shrink();
    final safeIndex = storyIndex.clamp(0, stories.length - 1);
    final story = stories[safeIndex];

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Background / Content ──
        _StoryContent(story: story),

        // ── Gradient overlays ──
        const _GradientOverlays(),

        // ── Progress bars ──
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 12,
          right: 12,
          child: _ProgressBars(
            total: stories.length,
            current: safeIndex,
            controller: progressController,
          ),
        ),

        // ── Header ──
        Positioned(
          top: MediaQuery.of(context).padding.top + 28,
          left: 12,
          right: 12,
          child: _StoryHeader(
            story: story,
            isCurrentUser: isCurrentUser,
            onClose: onClose,
            onDelete: onDelete,
          ),
        ),

        // ── Touch areas (left / right) ──
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: onTapLeft,
                onLongPressStart: (_) => onLongPressStart(),
                onLongPressEnd: (_) => onLongPressEnd(),
                behavior: HitTestBehavior.translucent,
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTap: onTapRight,
                onLongPressStart: (_) => onLongPressStart(),
                onLongPressEnd: (_) => onLongPressEnd(),
                behavior: HitTestBehavior.translucent,
              ),
            ),
          ],
        ),

        // ── Caption + Footer ──
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _StoryFooter(
            story: story,
            isCurrentUser: isCurrentUser,
          ),
        ),
      ],
    );
  }
}

// ── Story Content ───────────────────────────────────────
class _StoryContent extends StatelessWidget {
  final Story story;
  const _StoryContent({required this.story});

  @override
  Widget build(BuildContext context) {
    switch (story.type) {
      case StoryType.image:
        return _ImageContent(story: story);
      case StoryType.text:
        return _TextContent(story: story);
      default:
        return Container(color: Colors.black);
    }
  }
}

class _ImageContent extends StatelessWidget {
  final Story story;
  const _ImageContent({required this.story});

  @override
  Widget build(BuildContext context) {
    return Image.network(
      story.mediaUrl ?? '',
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      loadingBuilder: (_, child, progress) {
        if (progress == null) return child;
        return Container(
          color: Colors.black87,
          child: const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
        );
      },
      errorBuilder: (_, __, ___) => Container(
        color: Colors.black87,
        child: const Center(
          child: Icon(Icons.broken_image, color: Colors.white54, size: 64),
        ),
      ),
    );
  }
}

class _TextContent extends StatelessWidget {
  final Story story;
  const _TextContent({required this.story});

  @override
  Widget build(BuildContext context) {
    final bg = story.backgroundColor ?? const Color(0xFF1A1A2E);
    final tc = story.textColor ?? Colors.white;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            bg,
            Color.lerp(bg, Colors.black, 0.4)!,
          ],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            story.textContent ?? '',
            style: TextStyle(
              color: tc,
              fontSize: story.fontSize,
              fontFamily: story.fontFamily,
              fontWeight: FontWeight.w700,
              height: 1.3,
              shadows: [
                Shadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

// ── Gradient Overlays ───────────────────────────────────
class _GradientOverlays extends StatelessWidget {
  const _GradientOverlays();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Top gradient (for readability of header)
        Container(
          height: 140,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(0.65),
                Colors.transparent,
              ],
            ),
          ),
        ),
        const Spacer(),
        // Bottom gradient (for caption)
        Container(
          height: 180,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                Colors.black.withOpacity(0.75),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Progress Bars ───────────────────────────────────────
class _ProgressBars extends StatelessWidget {
  final int total;
  final int current;
  final AnimationController? controller;

  const _ProgressBars({
    required this.total,
    required this.current,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(total, (i) {
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i < total - 1 ? 3 : 0),
            child: _SingleProgressBar(
              isCurrent: i == current,
              isCompleted: i < current,
              controller: i == current ? controller : null,
            ),
          ),
        );
      }),
    );
  }
}

class _SingleProgressBar extends StatelessWidget {
  final bool isCurrent;
  final bool isCompleted;
  final AnimationController? controller;

  const _SingleProgressBar({
    required this.isCurrent,
    required this.isCompleted,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 2.5,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.35),
        borderRadius: BorderRadius.circular(2),
      ),
      child: AnimatedBuilder(
        animation: controller ?? const AlwaysStoppedAnimation(0),
        builder: (context, _) {
          final value = isCompleted
              ? 1.0
              : isCurrent
                  ? (controller?.value ?? 0.0)
                  : 0.0;
          return FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Story Header ─────────────────────────────────────────
class _StoryHeader extends StatelessWidget {
  final Story story;
  final bool isCurrentUser;
  final VoidCallback onClose;
  final VoidCallback onDelete;

  const _StoryHeader({
    required this.story,
    required this.isCurrentUser,
    required this.onClose,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final timeAgo = _formatTimeAgo(story.createdAt);

    return Row(
      children: [
        // Avatar
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border:
                Border.all(color: Colors.white.withOpacity(0.8), width: 1.5),
          ),
          child: ClipOval(
            child: story.userPhotoUrl.isNotEmpty
                ? Image.network(story.userPhotoUrl, fit: BoxFit.cover)
                : Container(
                    color: Colors.grey,
                    child: const Icon(Icons.person, color: Colors.white)),
          ),
        ),
        const SizedBox(width: 10),

        // Name & time
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                story.userName,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              Text(
                timeAgo,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),

        // Options
        if (isCurrentUser)
          GestureDetector(
            onTap: onDelete,
            child: Container(
              padding: const EdgeInsets.all(6),
              child: const Icon(Icons.delete_outline,
                  color: Colors.white, size: 22),
            ),
          ),

        // Close
        GestureDetector(
          onTap: onClose,
          child: Container(
            padding: const EdgeInsets.all(6),
            child: const Icon(Icons.close, color: Colors.white, size: 24),
          ),
        ),
      ],
    );
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('MMM dd').format(dt);
  }
}

// ── Story Footer ─────────────────────────────────────────
class _StoryFooter extends StatelessWidget {
  final Story story;
  final bool isCurrentUser;

  const _StoryFooter({required this.story, required this.isCurrentUser});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Caption
            if (story.caption?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  story.caption!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    shadows: [
                      Shadow(color: Colors.black54, blurRadius: 8),
                    ],
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

            // Viewers (for current user)
            if (isCurrentUser && story.viewCount > 0) ...[
              GestureDetector(
                onTap: () => _showViewers(context),
                child: Row(
                  children: [
                    const Icon(Icons.remove_red_eye_outlined,
                        color: Colors.white70, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      '${story.viewCount} viewer${story.viewCount != 1 ? 's' : ''}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.keyboard_arrow_up,
                        color: Colors.white70, size: 18),
                  ],
                ),
              ),
            ],

            // Remaining time
            if (isCurrentUser)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  context
                      .read<StoryProvider>()
                      .formatTimeRemaining(story.remainingTime),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.55),
                    fontSize: 11,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showViewers(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ViewersSheet(views: story.views),
    );
  }
}

// ── Viewers Bottom Sheet ──────────────────────────────────
class _ViewersSheet extends StatelessWidget {
  final List<StoryView> views;

  const _ViewersSheet({required this.views});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.55,
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 16),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.remove_red_eye_outlined,
                    color: Colors.white70, size: 20),
                const SizedBox(width: 8),
                Text(
                  '${views.length} Viewer${views.length != 1 ? 's' : ''}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),
          const Divider(color: Colors.white12, height: 1),

          Expanded(
            child: views.isEmpty
                ? const Center(
                    child: Text('No viewers yet',
                        style: TextStyle(color: Colors.white54)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: views.length,
                    itemBuilder: (_, i) {
                      final v = views[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage: v.photoUrl.isNotEmpty
                              ? NetworkImage(v.photoUrl)
                              : null,
                          child: v.photoUrl.isEmpty
                              ? const Icon(Icons.person)
                              : null,
                        ),
                        title: Text(v.userName,
                            style: const TextStyle(color: Colors.white)),
                        subtitle: Text(
                          _formatTime(v.viewedAt),
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
}
