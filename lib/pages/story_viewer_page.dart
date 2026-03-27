// lib/pages/story_viewer_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:flutter_chat_demo/models/story_model.dart';
import 'package:flutter_chat_demo/providers/story_provider.dart';

// ─────────────────────────────────────────────────────────────
// STORY VIEWER PAGE
// ─────────────────────────────────────────────────────────────

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
  late AnimationController _progressCtrl;

  late int _userIndex;
  late int _storyIndex;
  bool _isPaused = false;

  @override
  void initState() {
    super.initState();
    _userIndex = widget.initialUserIndex;
    _storyIndex = 0;

    _pageController = PageController(initialPage: _userIndex);
    _progressCtrl = AnimationController(vsync: this)
      ..addStatusListener(_onProgressStatus);

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Start after first frame so context is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startCurrentStory();
    });
  }

  @override
  void dispose() {
    _progressCtrl.removeStatusListener(_onProgressStatus);
    _progressCtrl.dispose();
    _pageController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ── Getters ────────────────────────────────────────────────

  UserStories get _currentUser => widget.allUserStories[_userIndex];
  List<Story> get _stories => _currentUser.activeStories;
  Story get _currentStory => _stories[_storyIndex.clamp(0, _stories.length - 1)];

  // ── Progress listener (called once on completion) ──────────

  void _onProgressStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _advance();
    }
  }

  // ── Story control ──────────────────────────────────────────

  void _startCurrentStory() {
    if (!mounted || _stories.isEmpty) return;

    _progressCtrl.stop();
    _progressCtrl.reset();
    _progressCtrl.duration = const Duration(seconds: 5);
    _progressCtrl.forward();

    _trackView();
  }

  void _trackView() {
    final story = _currentStory;
    if (story.userId == widget.currentUserId) return;
    context.read<StoryProvider>().markStoryViewed(
      storyId: story.id,
      viewerId: widget.currentUserId,
      viewerName: widget.currentUserName,
      viewerPhotoUrl: widget.currentUserPhotoUrl,
    );
  }

  void _advance() {
    if (!mounted) return;
    if (_storyIndex < _stories.length - 1) {
      setState(() => _storyIndex++);
      _startCurrentStory();
    } else {
      _nextUser();
    }
  }

  void _goBack() {
    if (!mounted) return;
    if (_storyIndex > 0) {
      setState(() => _storyIndex--);
      _startCurrentStory();
    } else if (_userIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _nextUser() {
    if (_userIndex < widget.allUserStories.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      if (mounted) Navigator.of(context).pop();
    }
  }

  void _pause() {
    if (_isPaused) return;
    _isPaused = true;
    _progressCtrl.stop();
  }

  void _resume() {
    if (!_isPaused) return;
    _isPaused = false;
    _progressCtrl.forward();
  }

  void _onPageChanged(int index) {
    if (!mounted) return;
    setState(() {
      _userIndex = index;
      _storyIndex = 0;
    });
    _startCurrentStory();
  }

  Future<void> _deleteStory() async {
    _pause();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Status'),
        content: const Text('Delete this story permanently?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete')),
        ],
      ),
    );
    if (!mounted) return;
    if (ok == true) {
      await context.read<StoryProvider>().deleteStory(_currentStory.id);
      if (mounted) Navigator.of(context).pop();
    } else {
      _resume();
    }
  }

  // ── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        itemCount: widget.allUserStories.length,
        itemBuilder: (_, userIdx) {
          final us = widget.allUserStories[userIdx];
          final isActive = userIdx == _userIndex;
          final si = isActive ? _storyIndex.clamp(0, us.activeStories.length - 1) : 0;

          return _UserStoryView(
            userStories: us,
            storyIndex: si,
            progressCtrl: isActive ? _progressCtrl : null,
            isCurrentUser: us.userId == widget.currentUserId,
            onTapLeft: _goBack,
            onTapRight: _advance,
            onHoldStart: _pause,
            onHoldEnd: _resume,
            onClose: () => Navigator.of(context).pop(),
            onDelete: _deleteStory,
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// _UserStoryView — one "card" in the PageView
// ─────────────────────────────────────────────────────────────

class _UserStoryView extends StatelessWidget {
  final UserStories userStories;
  final int storyIndex;
  final AnimationController? progressCtrl;
  final bool isCurrentUser;
  final VoidCallback onTapLeft;
  final VoidCallback onTapRight;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;
  final VoidCallback onClose;
  final VoidCallback onDelete;

  const _UserStoryView({
    required this.userStories,
    required this.storyIndex,
    required this.progressCtrl,
    required this.isCurrentUser,
    required this.onTapLeft,
    required this.onTapRight,
    required this.onHoldStart,
    required this.onHoldEnd,
    required this.onClose,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final stories = userStories.activeStories;
    if (stories.isEmpty) return const SizedBox.shrink();

    final si = storyIndex.clamp(0, stories.length - 1);
    final story = stories[si];

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Content ──
        _StoryContent(story: story),

        // ── Gradient overlays ──
        const _Gradients(),

        // ── Progress bars ──
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 10,
          right: 10,
          child: _ProgressBars(
            total: stories.length,
            current: si,
            controller: progressCtrl,
          ),
        ),

        // ── Header ──
        Positioned(
          top: MediaQuery.of(context).padding.top + 26,
          left: 10,
          right: 10,
          child: _Header(
            story: story,
            isCurrentUser: isCurrentUser,
            onClose: onClose,
            onDelete: onDelete,
          ),
        ),

        // ── Touch zones ──
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: onTapLeft,
                onLongPressStart: (_) => onHoldStart(),
                onLongPressEnd: (_) => onHoldEnd(),
              ),
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: onTapRight,
                onLongPressStart: (_) => onHoldStart(),
                onLongPressEnd: (_) => onHoldEnd(),
              ),
            ),
          ],
        ),

        // ── Footer ──
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _Footer(story: story, isCurrentUser: isCurrentUser),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Content
// ─────────────────────────────────────────────────────────────

class _StoryContent extends StatelessWidget {
  final Story story;
  const _StoryContent({required this.story});

  @override
  Widget build(BuildContext context) {
    if (story.type == StoryType.image && story.mediaUrl != null) {
      return Image.network(
        story.mediaUrl!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        loadingBuilder: (_, child, p) => p == null
            ? child
            : const ColoredBox(
          color: Colors.black87,
          child: Center(child: CircularProgressIndicator(color: Colors.white)),
        ),
        errorBuilder: (_, __, ___) => const ColoredBox(
          color: Colors.black87,
          child: Center(
            child: Icon(Icons.broken_image, color: Colors.white38, size: 64),
          ),
        ),
      );
    }

    // Text story
    final bg = story.backgroundColor ?? const Color(0xFF1A1A2E);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [bg, Color.lerp(bg, Colors.black, 0.4)!],
        ),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Text(
        story.textContent ?? '',
        style: TextStyle(
          color: story.textColor ?? Colors.white,
          fontSize: story.fontSize,
          fontFamily: story.fontFamily,
          fontWeight: FontWeight.w700,
          height: 1.35,
          shadows: const [Shadow(color: Colors.black45, blurRadius: 10)],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Gradients overlay
// ─────────────────────────────────────────────────────────────

class _Gradients extends StatelessWidget {
  const _Gradients();
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        height: 150,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withOpacity(0.6), Colors.transparent],
          ),
        ),
      ),
      const Spacer(),
      Container(
        height: 200,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black.withOpacity(0.7), Colors.transparent],
          ),
        ),
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────
// Progress bars
// ─────────────────────────────────────────────────────────────

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
            height: 2.5,
            margin: EdgeInsets.only(right: i < total - 1 ? 3 : 0),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.35),
              borderRadius: BorderRadius.circular(2),
            ),
            child: AnimatedBuilder(
              animation: controller ?? const AlwaysStoppedAnimation(0),
              builder: (_, __) {
                final val = i < current
                    ? 1.0
                    : i == current
                    ? (controller?.value ?? 0.0)
                    : 0.0;
                return FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: val,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final Story story;
  final bool isCurrentUser;
  final VoidCallback onClose;
  final VoidCallback onDelete;

  const _Header({
    required this.story,
    required this.isCurrentUser,
    required this.onClose,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Avatar
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white70, width: 1.5),
          ),
          child: ClipOval(
            child: story.userPhotoUrl.isNotEmpty
                ? Image.network(story.userPhotoUrl, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _defaultAvatar())
                : _defaultAvatar(),
          ),
        ),
        const SizedBox(width: 10),

        // Name + time
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(story.userName,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14)),
              Text(_timeAgo(story.createdAt),
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.7), fontSize: 11)),
            ],
          ),
        ),

        if (isCurrentUser)
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.white, size: 22),
            onPressed: onDelete,
            tooltip: 'Delete',
            padding: EdgeInsets.zero,
          ),

        IconButton(
          icon: const Icon(Icons.close, color: Colors.white, size: 24),
          onPressed: onClose,
          padding: EdgeInsets.zero,
        ),
      ],
    );
  }

  Widget _defaultAvatar() => Container(
    color: Colors.grey.shade700,
    child: const Icon(Icons.person, color: Colors.white),
  );

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('MMM dd').format(dt);
  }
}

// ─────────────────────────────────────────────────────────────
// Footer
// ─────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  final Story story;
  final bool isCurrentUser;

  const _Footer({required this.story, required this.isCurrentUser});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (story.caption?.isNotEmpty == true) ...[
              Text(
                story.caption!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
            ],

            if (isCurrentUser) ...[
              if (story.viewCount > 0)
                GestureDetector(
                  onTap: () => _showViewers(context),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.remove_red_eye_outlined,
                          color: Colors.white70, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        '${story.viewCount} viewer${story.viewCount != 1 ? 's' : ''}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.keyboard_arrow_up,
                          color: Colors.white70, size: 18),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                context
                    .read<StoryProvider>()
                    .formatTimeRemaining(story.remainingTime),
                style:
                TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showViewers(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ViewersSheet(views: story.views),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Viewers bottom sheet
// ─────────────────────────────────────────────────────────────

class _ViewersSheet extends StatelessWidget {
  final List<StoryView> views;
  const _ViewersSheet({required this.views});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.55),
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 14),
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
                      fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),
          const Divider(color: Colors.white12, height: 1),

          Flexible(
            child: views.isEmpty
                ? const Padding(
              padding: EdgeInsets.all(32),
              child: Text('No viewers yet',
                  style: TextStyle(color: Colors.white54)),
            )
                : ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: views.length,
              itemBuilder: (_, i) {
                final v = views[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage: v.photoUrl.isNotEmpty
                        ? NetworkImage(v.photoUrl)
                        : null,
                    backgroundColor: Colors.grey.shade700,
                    child: v.photoUrl.isEmpty
                        ? const Icon(Icons.person, color: Colors.white)
                        : null,
                  ),
                  title: Text(v.userName,
                      style: const TextStyle(color: Colors.white)),
                  subtitle: Text(_fmt(v.viewedAt),
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    return '${d.inHours}h ago';
  }
}