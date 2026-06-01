import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/providers/story_provider.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

// ─── Page ─────────────────────────────────────────────────────────────────────

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
  late PageController _pageCtrl;
  late AnimationController _progressCtrl;
  late AnimationController _enterCtrl;
  late Animation<double> _enterFade;
  late Animation<double> _enterScale;

  late int _userIdx;
  late int _storyIdx;
  bool _isPaused = false;

  final _replyCtrl = TextEditingController();
  bool _replyVisible = false;
  final _replyFocus = FocusNode();

  // Swipe-down to close
  double _dragOffset = 0;
  bool _isDragging = false;

  // Double-tap reaction
  OverlayEntry? _heartOverlay;

  @override
  void initState() {
    super.initState();
    _userIdx = widget.initialUserIndex;
    _storyIdx = 0;

    _pageCtrl = PageController(initialPage: _userIdx);
    _progressCtrl = AnimationController(vsync: this)
      ..addStatusListener(_onProgressEnd);

    _enterCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _enterFade = CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOut);
    _enterScale = Tween<double>(begin: 0.92, end: 1.0).animate(
        CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOutCubic));

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _enterCtrl.forward();
        _startCurrentStory();
      }
    });

    _replyFocus.addListener(() {
      if (!_replyFocus.hasFocus && _replyCtrl.text.isEmpty && mounted) {
        setState(() => _replyVisible = false);
        _resume();
      }
    });
  }

  @override
  void dispose() {
    _progressCtrl.removeStatusListener(_onProgressEnd);
    _progressCtrl.dispose();
    _enterCtrl.dispose();
    _pageCtrl.dispose();
    _replyCtrl.dispose();
    _replyFocus.dispose();
    _removeHeartOverlay();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  UserStories get _currentUser => widget.allUserStories[_userIdx];
  List<Story> get _stories => _currentUser.activeStories;
  Story get _story =>
      _stories[_storyIdx.clamp(0, math.max(0, _stories.length - 1)).toInt()];

  void _onProgressEnd(AnimationStatus status) {
    if (status == AnimationStatus.completed) _advance();
  }

  void _startCurrentStory() {
    if (!mounted || _stories.isEmpty) return;
    _progressCtrl.stop();
    _progressCtrl.reset();
    _progressCtrl.duration = _story.displayDuration;
    _progressCtrl.forward();
    _trackView();
  }

  void _trackView() {
    final s = _story;
    if (s.userId == widget.currentUserId) return;
    context.read<StoryProvider>().markStoryViewed(
          storyId: s.id,
          viewerId: widget.currentUserId,
          viewerName: widget.currentUserName,
          viewerPhotoUrl: widget.currentUserPhotoUrl,
        );
  }

  void _advance() {
    if (!mounted) return;
    if (_storyIdx < _stories.length - 1) {
      setState(() => _storyIdx++);
      _startCurrentStory();
    } else {
      _nextUser();
    }
  }

  void _goBack() {
    if (!mounted) return;
    if (_storyIdx > 0) {
      setState(() => _storyIdx--);
      _startCurrentStory();
    } else if (_userIdx > 0) {
      _pageCtrl.previousPage(
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  void _nextUser() {
    if (_userIdx < widget.allUserStories.length - 1) {
      _pageCtrl.nextPage(
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    } else {
      _closeViewer();
    }
  }

  void _closeViewer() {
    if (mounted) Navigator.of(context).pop();
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

  void _onPageChanged(int idx) {
    if (!mounted) return;
    setState(() {
      _userIdx = idx;
      _storyIdx = 0;
    });
    _startCurrentStory();
  }

  void _openReply() {
    if (!_story.allowReplies) return;
    _pause();
    setState(() => _replyVisible = true);
    Future.delayed(
        const Duration(milliseconds: 100), () => _replyFocus.requestFocus());
  }

  Future<void> _sendReply() async {
    final msg = _replyCtrl.text.trim();
    if (msg.isEmpty) return;
    final s = _story;
    _replyCtrl.clear();
    _replyFocus.unfocus();
    setState(() => _replyVisible = false);
    _resume();

    await context.read<StoryProvider>().replyToStory(
          storyId: s.id,
          senderId: widget.currentUserId,
          senderName: widget.currentUserName,
          senderPhotoUrl: widget.currentUserPhotoUrl,
          message: msg,
        );

    if (mounted) {
      _showSnack('Reply sent ✉️');
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        backgroundColor: Colors.black87,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showReactions() {
    if (!_story.allowReactions) return;
    _pause();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      useRootNavigator: true,
      builder: (_) => _ReactionsSheet(
        storyId: _story.id,
        onSelect: (emoji) async {
          await context.read<StoryProvider>().reactToStory(
                storyId: _story.id,
                reactorId: widget.currentUserId,
                reactorName: widget.currentUserName,
                reactorPhotoUrl: widget.currentUserPhotoUrl,
                emoji: emoji,
              );
          _showFloatingEmoji(emoji);
        },
      ),
    ).then((_) => _resume());
  }

  void _showFloatingEmoji(String emoji) {
    _removeHeartOverlay();
    _heartOverlay = OverlayEntry(
        builder: (_) =>
            _FloatingEmojiOverlay(emoji: emoji, onDone: _removeHeartOverlay));
    Overlay.of(context).insert(_heartOverlay!);
  }

  void _removeHeartOverlay() {
    try {
      _heartOverlay?.remove();
    } catch (_) {}
    _heartOverlay = null;
  }

  void _onDoubleTap() {
    HapticFeedback.lightImpact();
    _showFloatingEmoji('❤️');
    final s = _story;
    if (s.userId != widget.currentUserId && s.allowReactions) {
      context.read<StoryProvider>().reactToStory(
            storyId: s.id,
            reactorId: widget.currentUserId,
            reactorName: widget.currentUserName,
            reactorPhotoUrl: widget.currentUserPhotoUrl,
            emoji: '❤️',
          );
    }
  }

  Future<void> _deleteStory() async {
    _pause();
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (_) => _DeleteDialog(),
    );
    if (!mounted) return;
    if (ok == true) {
      await context.read<StoryProvider>().deleteStory(_story.id);
      if (mounted) _closeViewer();
    } else {
      _resume();
    }
  }

  void _showOptions() {
    _pause();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _StoryOptionsSheet(
        story: _story,
        isOwner: _story.userId == widget.currentUserId,
        onDelete: () {
          Navigator.pop(context);
          _deleteStory();
        },
        onCopyLink: () {
          Navigator.pop(context);
          Clipboard.setData(const ClipboardData(text: 'Story link'));
          _showSnack('Link copied!');
          _resume();
        },
        onReport: () {
          Navigator.pop(context);
          _showSnack('Reported');
          _resume();
        },
      ),
    ).then((_) => _resume());
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final dy = _isDragging ? _dragOffset : 0.0;
    final scale = (_isDragging
        ? (1.0 - (_dragOffset / size.height).abs() * 0.2).clamp(0.8, 1.0)
        : 1.0);

    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: FadeTransition(
        opacity: _enterFade,
        child: ScaleTransition(
          scale: _enterScale,
          child: GestureDetector(
            onVerticalDragStart: (d) {
              if (!_replyVisible) {
                _isDragging = true;
                _pause();
              }
            },
            onVerticalDragUpdate: (d) {
              if (_isDragging) setState(() => _dragOffset += d.delta.dy);
            },
            onVerticalDragEnd: (d) {
              if (_dragOffset > 120 || (d.primaryVelocity ?? 0) > 600) {
                _closeViewer();
              } else {
                setState(() {
                  _dragOffset = 0;
                  _isDragging = false;
                });
                _resume();
              }
            },
            child: Transform.translate(
              offset: Offset(0, dy),
              child: Transform.scale(
                scale: scale,
                child: Stack(
                  children: [
                    // Stories pager
                    PageView.builder(
                      controller: _pageCtrl,
                      onPageChanged: _onPageChanged,
                      itemCount: widget.allUserStories.length,
                      itemBuilder: (_, uIdx) {
                        final us = widget.allUserStories[uIdx];
                        final isActive = uIdx == _userIdx;
                        final si = isActive
                            ? _storyIdx
                                .clamp(
                                    0, math.max(0, us.activeStories.length - 1))
                                .toInt()
                            : 0;
                        return _UserStoryView(
                          userStories: us,
                          storyIndex: si,
                          progressCtrl: isActive ? _progressCtrl : null,
                          isCurrentUser: us.userId == widget.currentUserId,
                          onTapLeft: _goBack,
                          onTapRight: _advance,
                          onHoldStart: _pause,
                          onHoldEnd: _resume,
                          onClose: _closeViewer,
                          onDelete: _deleteStory,
                          onReply: _openReply,
                          onReact: _showReactions,
                          onDoubleTap: _onDoubleTap,
                          onOptions: _showOptions,
                          currentUserId: widget.currentUserId,
                        );
                      },
                    ),

                    // Reply bar
                    if (_replyVisible)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: _ReplyBar(
                          ctrl: _replyCtrl,
                          focus: _replyFocus,
                          ownerName: _currentUser.userName,
                          onSend: _sendReply,
                          onDismiss: () {
                            _replyFocus.unfocus();
                            setState(() => _replyVisible = false);
                            _resume();
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── User Story View ──────────────────────────────────────────────────────────

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
  final VoidCallback onReply;
  final VoidCallback onReact;
  final VoidCallback onDoubleTap;
  final VoidCallback onOptions;
  final String currentUserId;

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
    required this.onReply,
    required this.onReact,
    required this.onDoubleTap,
    required this.onOptions,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    final stories = userStories.activeStories;
    if (stories.isEmpty) return const SizedBox.shrink();

    final si = storyIndex.clamp(0, math.max(0, stories.length - 1)).toInt();
    final story = stories[si];

    return Stack(
      fit: StackFit.expand,
      children: [
        // Content
        GestureDetector(
          onDoubleTap: onDoubleTap,
          onLongPressStart: (_) => onHoldStart(),
          onLongPressEnd: (_) => onHoldEnd(),
          child: _StoryContent(story: story),
        ),

        // Gradients
        const _StoryGradients(),

        // Progress bars
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 12,
          right: 12,
          child: _ProgressBars(
            total: stories.length,
            current: si,
            controller: progressCtrl,
          ),
        ),

        // Header
        Positioned(
          top: MediaQuery.of(context).padding.top + 22,
          left: 12,
          right: 12,
          child: _StoryHeader(
            story: story,
            isCurrentUser: isCurrentUser,
            onClose: onClose,
            onDelete: onDelete,
            onOptions: onOptions,
          ),
        ),

        // Tap areas (left/right)
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

        // Footer
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _StoryFooter(
            story: story,
            isCurrentUser: isCurrentUser,
            currentUserId: currentUserId,
            onReply: onReply,
            onReact: onReact,
          ),
        ),
      ],
    );
  }
}

// ─── Story Content ────────────────────────────────────────────────────────────

class _StoryContent extends StatefulWidget {
  final Story story;
  const _StoryContent({required this.story});

  @override
  State<_StoryContent> createState() => _StoryContentState();
}

class _StoryContentState extends State<_StoryContent> {
  VideoPlayerController? _videoCtrl;
  bool _videoReady = false;

  @override
  void initState() {
    super.initState();
    if (widget.story.type == StoryType.video && widget.story.mediaUrl != null)
      _initVideo();
  }

  Future<void> _initVideo() async {
    final ctrl =
        VideoPlayerController.networkUrl(Uri.parse(widget.story.mediaUrl!));
    _videoCtrl = ctrl;
    await ctrl.initialize();
    if (mounted) {
      ctrl.setLooping(false);
      await ctrl.play();
      setState(() => _videoReady = true);
    }
  }

  @override
  void dispose() {
    _videoCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final story = widget.story;

    if (story.type == StoryType.video) {
      if (_videoReady && _videoCtrl != null) {
        return Container(
          color: Colors.black,
          child: Center(
            child: AspectRatio(
              aspectRatio: _videoCtrl!.value.aspectRatio,
              child: VideoPlayer(_videoCtrl!),
            ),
          ),
        );
      }
      return const ColoredBox(
        color: Colors.black,
        child: Center(
            child:
                CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
      );
    }

    if (story.type == StoryType.image && story.mediaUrl != null) {
      return Image.network(
        story.mediaUrl!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        loadingBuilder: (_, child, prog) => prog == null
            ? child
            : const ColoredBox(
                color: Colors.black87,
                child: Center(
                    child: CircularProgressIndicator(
                        color: Colors.white38, strokeWidth: 2)),
              ),
        errorBuilder: (_, __, ___) => const ColoredBox(
          color: Colors.black87,
          child: Center(
              child: Icon(Icons.broken_image_rounded,
                  color: Colors.white24, size: 72)),
        ),
      );
    }

    // Text story
    final colors = story.gradientColors;
    final bg = story.backgroundColor ?? const Color(0xFF1A1A2E);
    final bg2 = Color.lerp(bg, Colors.black, 0.35)!;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: (colors != null && colors.length >= 2) ? colors : [bg, bg2],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            story.textContent ?? '',
            style: TextStyle(
              color: story.textColor ?? Colors.white,
              fontSize: story.fontSize,
              fontFamily: story.fontFamily,
              fontWeight: FontWeight.w800,
              height: 1.3,
              shadows: const [
                Shadow(
                    color: Colors.black45, blurRadius: 12, offset: Offset(0, 2))
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

// ─── Gradients ────────────────────────────────────────────────────────────────

class _StoryGradients extends StatelessWidget {
  const _StoryGradients();

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Container(
            height: 180,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.7),
                  Colors.transparent
                ],
              ),
            ),
          ),
          const Spacer(),
          Container(
            height: 240,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.8),
                  Colors.transparent
                ],
              ),
            ),
          ),
        ],
      );
}

// ─── Progress Bars ────────────────────────────────────────────────────────────

class _ProgressBars extends StatelessWidget {
  final int total;
  final int current;
  final AnimationController? controller;

  const _ProgressBars(
      {required this.total, required this.current, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(total.clamp(1, 12).toInt(), (i) {
        return Expanded(
          child: Container(
            height: 2.0,
            margin: EdgeInsets.only(right: i < total - 1 ? 3 : 0),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(1),
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
                      gradient: const LinearGradient(
                        colors: [Colors.white, Color(0xFFE0E0E0)],
                      ),
                      borderRadius: BorderRadius.circular(1),
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

// ─── Header ───────────────────────────────────────────────────────────────────

class _StoryHeader extends StatelessWidget {
  final Story story;
  final bool isCurrentUser;
  final VoidCallback onClose;
  final VoidCallback onDelete;
  final VoidCallback onOptions;

  const _StoryHeader({
    required this.story,
    required this.isCurrentUser,
    required this.onClose,
    required this.onDelete,
    required this.onOptions,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Avatar
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.8), width: 1.5),
          ),
          child: ClipOval(
            child: story.userPhotoUrl.isNotEmpty
                ? Image.network(story.userPhotoUrl,
                    fit: BoxFit.cover, errorBuilder: (_, __, ___) => _avatar())
                : _avatar(),
          ),
        ),
        const SizedBox(width: 10),

        // Name + time
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                story.userName,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14),
              ),
              Row(
                children: [
                  Text(
                    _timeAgo(story.createdAt),
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 11),
                  ),
                  const SizedBox(width: 6),
                  _PrivacyChip(privacy: story.privacy),
                ],
              ),
            ],
          ),
        ),

        // Actions
        _HeaderIconBtn(icon: Icons.more_horiz_rounded, onTap: onOptions),
        const SizedBox(width: 4),
        _HeaderIconBtn(icon: Icons.close_rounded, onTap: onClose),
      ],
    );
  }

  Widget _avatar() => Container(
        color: Colors.grey.shade800,
        child: const Icon(Icons.person_rounded, color: Colors.white54),
      );

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return DateFormat('MMM d').format(dt);
  }
}

class _PrivacyChip extends StatelessWidget {
  final StoryPrivacy privacy;
  const _PrivacyChip({required this.privacy});

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (privacy) {
      StoryPrivacy.everyone => (Icons.public_rounded, 'Public'),
      StoryPrivacy.friends => (Icons.people_rounded, 'Friends'),
      StoryPrivacy.closeFriends => (Icons.star_rounded, 'Close'),
      StoryPrivacy.onlyMe => (Icons.lock_rounded, 'Only me'),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 10, color: Colors.white60),
        const SizedBox(width: 2),
        Text(label,
            style: const TextStyle(color: Colors.white60, fontSize: 10)),
      ],
    );
  }
}

class _HeaderIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _HeaderIconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

// ─── Footer ───────────────────────────────────────────────────────────────────

class _StoryFooter extends StatelessWidget {
  final Story story;
  final bool isCurrentUser;
  final String currentUserId;
  final VoidCallback onReply;
  final VoidCallback onReact;

  const _StoryFooter({
    required this.story,
    required this.isCurrentUser,
    required this.currentUserId,
    required this.onReply,
    required this.onReact,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Music info
            if (story.music != null) _MusicBanner(music: story.music!),

            // Caption
            if (story.caption?.isNotEmpty == true) ...[
              const SizedBox(height: 6),
              Text(
                story.caption!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                  height: 1.4,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 12),

            // Owner: views + time
            if (isCurrentUser)
              _OwnerFooter(story: story, context: context)
            else
              _ViewerFooter(
                story: story,
                currentUserId: currentUserId,
                onReply: onReply,
                onReact: onReact,
              ),
          ],
        ),
      ),
    );
  }
}

class _OwnerFooter extends StatelessWidget {
  final Story story;
  final BuildContext context;

  const _OwnerFooter({required this.story, required this.context});

  @override
  Widget build(BuildContext _) {
    final remaining = story.remainingTime;
    return Row(
      children: [
        GestureDetector(
          onTap: () => _showViewers(context, story),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.remove_red_eye_rounded,
                    color: Colors.white, size: 16),
                const SizedBox(width: 6),
                Text(
                  '${story.viewCount}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13),
                ),
                if (story.reactions.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(story.reactions.take(3).map((r) => r.emoji).join(),
                      style: const TextStyle(fontSize: 14)),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          context.read<StoryProvider>().formatTimeRemaining(remaining),
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55), fontSize: 12),
        ),
      ],
    );
  }

  void _showViewers(BuildContext ctx, Story story) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ViewersSheet(story: story),
    );
  }
}

class _ViewerFooter extends StatelessWidget {
  final Story story;
  final String currentUserId;
  final VoidCallback onReply;
  final VoidCallback onReact;

  const _ViewerFooter({
    required this.story,
    required this.currentUserId,
    required this.onReply,
    required this.onReact,
  });

  @override
  Widget build(BuildContext context) {
    final myReaction = story.reactionBy(currentUserId);

    return Row(
      children: [
        // My reaction badge
        if (myReaction != null)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white30),
            ),
            child: Text(myReaction, style: const TextStyle(fontSize: 22)),
          ),

        // React button
        if (story.allowReactions)
          _FooterButton(
            icon: Icons.emoji_emotions_rounded,
            label: 'React',
            onTap: onReact,
          ),

        const SizedBox(width: 8),

        // Reply input
        if (story.allowReplies)
          Expanded(
            child: GestureDetector(
              onTap: onReply,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  children: [
                    Text(
                      'Reply to ${story.userName.split(' ').first}…',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 13.5),
                    ),
                    const Spacer(),
                    const Icon(Icons.send_rounded,
                        color: Colors.white30, size: 18),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _FooterButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _FooterButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 5),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ─── Music Banner ─────────────────────────────────────────────────────────────

class _MusicBanner extends StatelessWidget {
  final StoryMusicInfo music;
  const _MusicBanner({required this.music});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.music_note_rounded, color: Colors.white70, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  music.title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  music.artist,
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Reply Bar ────────────────────────────────────────────────────────────────

class _ReplyBar extends StatelessWidget {
  final TextEditingController ctrl;
  final FocusNode focus;
  final String ownerName;
  final VoidCallback onSend;
  final VoidCallback onDismiss;

  const _ReplyBar({
    required this.ctrl,
    required this.focus,
    required this.ownerName,
    required this.onSend,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          12, 10, 12, MediaQuery.of(context).viewInsets.bottom + 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.95)],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            GestureDetector(
              onTap: onDismiss,
              child: const Icon(Icons.close_rounded,
                  color: Colors.white54, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white24),
                ),
                child: TextField(
                  controller: ctrl,
                  focusNode: focus,
                  style: const TextStyle(color: Colors.white, fontSize: 14.5),
                  maxLines: 3,
                  minLines: 1,
                  decoration: InputDecoration(
                    hintText: 'Reply to ${ownerName.split(' ').first}…',
                    hintStyle:
                        const TextStyle(color: Colors.white38, fontSize: 14.5),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: onSend,
              child: Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF7B61FF), Color(0xFF2196F3)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.send_rounded,
                    color: Colors.white, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Reactions Sheet ──────────────────────────────────────────────────────────

class _ReactionsSheet extends StatelessWidget {
  final String storyId;
  final Future<void> Function(String emoji) onSelect;

  static const _emojis = [
    '❤️',
    '😂',
    '😮',
    '😢',
    '😡',
    '👏',
    '🔥',
    '💯',
    '🥰',
    '🤩',
    '😭',
    '✨'
  ];

  const _ReactionsSheet({required this.storyId, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2))),
          const Text('React',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: _emojis
                .map((e) => GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.pop(context);
                        onSelect(e);
                      },
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.3, end: 1.0),
                        duration: Duration(
                            milliseconds: 300 + _emojis.indexOf(e) * 30),
                        curve: Curves.elasticOut,
                        builder: (_, v, child) =>
                            Transform.scale(scale: v, child: child),
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Center(
                              child: Text(e,
                                  style: const TextStyle(fontSize: 30))),
                        ),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ─── Viewers Sheet ────────────────────────────────────────────────────────────

class _ViewersSheet extends StatelessWidget {
  final Story story;
  const _ViewersSheet({required this.story});

  @override
  Widget build(BuildContext context) {
    final views = story.views;
    final reactions = story.reactions;

    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.65),
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Icon(Icons.remove_red_eye_rounded,
                    color: Colors.white70, size: 20),
                const SizedBox(width: 8),
                Text('${views.length} viewer${views.length != 1 ? 's' : ''}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                if (reactions.isNotEmpty) ...[
                  Text(reactions.take(4).map((r) => r.emoji).join(''),
                      style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 4),
                  Text('${reactions.length}',
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 14)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          Divider(color: Colors.white.withValues(alpha: 0.06), height: 1),
          Flexible(
            child: views.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.remove_red_eye_rounded,
                            color: Colors.white24, size: 48),
                        const SizedBox(height: 16),
                        const Text('No viewers yet',
                            style:
                                TextStyle(color: Colors.white54, fontSize: 15)),
                      ],
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: views.length,
                    itemBuilder: (_, i) {
                      final v = views[i];
                      final reaction = reactions
                          .where((r) => r.userId == v.userId)
                          .map((r) => r.emoji)
                          .firstOrNull;
                      final diff = DateTime.now().difference(v.viewedAt);
                      final timeStr = diff.inMinutes < 1
                          ? 'now'
                          : diff.inMinutes < 60
                              ? '${diff.inMinutes}m'
                              : '${diff.inHours}h';

                      return ListTile(
                        leading: CircleAvatar(
                          radius: 22,
                          backgroundImage: v.photoUrl.isNotEmpty
                              ? NetworkImage(v.photoUrl)
                              : null,
                          backgroundColor: Colors.grey.shade800,
                          child: v.photoUrl.isEmpty
                              ? const Icon(Icons.person_rounded,
                                  color: Colors.white38)
                              : null,
                        ),
                        title: Text(v.userName,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                        subtitle: Text(timeStr,
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 12)),
                        trailing: reaction != null
                            ? Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                    color: Colors.white10,
                                    borderRadius: BorderRadius.circular(10)),
                                child: Center(
                                    child: Text(reaction,
                                        style: const TextStyle(fontSize: 20))),
                              )
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── Options Sheet ────────────────────────────────────────────────────────────

class _StoryOptionsSheet extends StatelessWidget {
  final Story story;
  final bool isOwner;
  final VoidCallback onDelete;
  final VoidCallback onCopyLink;
  final VoidCallback onReport;

  const _StoryOptionsSheet({
    required this.story,
    required this.isOwner,
    required this.onDelete,
    required this.onCopyLink,
    required this.onReport,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2))),
          _OptionTile(
              icon: Icons.link_rounded, label: 'Copy Link', onTap: onCopyLink),
          if (!isOwner)
            _OptionTile(
                icon: Icons.flag_rounded,
                label: 'Report',
                color: Colors.orangeAccent,
                onTap: onReport),
          if (isOwner)
            _OptionTile(
                icon: Icons.delete_rounded,
                label: 'Delete Story',
                color: Colors.redAccent,
                onTap: onDelete),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _OptionTile(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.white;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: c, size: 20),
            ),
            const SizedBox(width: 14),
            Text(label,
                style: TextStyle(
                    color: c, fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ─── Delete Dialog ────────────────────────────────────────────────────────────

class _DeleteDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      backgroundColor: const Color(0xFF1C1C1E),
      title: const Text('Delete Story',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      content: const Text('This story will be permanently deleted.',
          style: TextStyle(color: Colors.white54)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
          child: const Text('Delete',
              style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

// ─── Floating Emoji Overlay ────────────────────────────────────────────────────

class _FloatingEmojiOverlay extends StatefulWidget {
  final String emoji;
  final VoidCallback onDone;

  const _FloatingEmojiOverlay({required this.emoji, required this.onDone});

  @override
  State<_FloatingEmojiOverlay> createState() => _FloatingEmojiOverlayState();
}

class _FloatingEmojiOverlayState extends State<_FloatingEmojiOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _opacity;
  late Animation<Offset> _position;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _scale = Tween<double>(begin: 0.5, end: 1.4).animate(CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0, 0.4, curve: Curves.elasticOut)));
    _opacity = Tween<double>(begin: 1.0, end: 0.0).animate(
        CurvedAnimation(parent: _ctrl, curve: const Interval(0.6, 1.0)));
    _position = Tween<Offset>(begin: Offset.zero, end: const Offset(0, -0.15))
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward().then((_) => widget.onDone());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) => SlideTransition(
            position: _position,
            child: FadeTransition(
              opacity: _opacity,
              child: ScaleTransition(
                scale: _scale,
                child: Text(widget.emoji, style: const TextStyle(fontSize: 80)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
