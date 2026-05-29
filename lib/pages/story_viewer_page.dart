import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_chat_demo/providers/story_provider.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';





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

class _StoryViewerPageState extends State<StoryViewerPage> with TickerProviderStateMixin {
  late PageController _pageController;
  late AnimationController _progressCtrl;

  late int _userIndex;
  late int _storyIndex;
  bool _isPaused = false;

  
  final _replyCtrl = TextEditingController();
  bool _replyVisible = false;
  final _replyFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _userIndex = widget.initialUserIndex;
    _storyIndex = 0;

    _pageController = PageController(initialPage: _userIndex);
    _progressCtrl = AnimationController(vsync: this)..addStatusListener(_onProgressStatus);

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startCurrentStory();
    });

    _replyFocus.addListener(() {
      if (!_replyFocus.hasFocus && _replyCtrl.text.isEmpty) {
        setState(() => _replyVisible = false);
        _resume();
      }
    });
  }

  @override
  void dispose() {
    _progressCtrl.removeStatusListener(_onProgressStatus);
    _progressCtrl.dispose();
    _pageController.dispose();
    _replyCtrl.dispose();
    _replyFocus.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  
  
  

  UserStories get _currentUser => widget.allUserStories[_userIndex];
  List<Story> get _stories => _currentUser.activeStories;
  Story get _currentStory => _stories[_storyIndex.clamp(0, _stories.length - 1)];

  
  
  

  void _onProgressStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _advance();
  }

  void _startCurrentStory() {
    if (!mounted || _stories.isEmpty) return;
    _progressCtrl.stop();
    _progressCtrl.reset();
    _progressCtrl.duration = _currentStory.displayDuration;
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Delete Status'),
        content: const Text('Delete this story permanently?'),
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
    if (!mounted) return;
    if (ok == true) {
      await context.read<StoryProvider>().deleteStory(_currentStory.id);
      if (mounted) Navigator.of(context).pop();
    } else {
      _resume();
    }
  }

  
  
  

  void _openReply() {
    _pause();
    setState(() => _replyVisible = true);
    Future.delayed(const Duration(milliseconds: 100), () {
      _replyFocus.requestFocus();
    });
  }

  Future<void> _sendReply() async {
    final msg = _replyCtrl.text.trim();
    if (msg.isEmpty) return;
    final story = _currentStory;
    _replyCtrl.clear();
    _replyFocus.unfocus();
    setState(() => _replyVisible = false);
    _resume();

    await context.read<StoryProvider>().replyToStory(
          storyId: story.id,
          senderId: widget.currentUserId,
          senderName: widget.currentUserName,
          senderPhotoUrl: widget.currentUserPhotoUrl,
          message: msg,
        );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✉️ Reply sent!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  
  
  

  void _showReactions() {
    _pause();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReactionsSheet(
        storyId: _currentStory.id,
        senderId: widget.currentUserId,
        senderName: widget.currentUserName,
        senderPhotoUrl: widget.currentUserPhotoUrl,
        onSelect: (emoji) async {
          await context.read<StoryProvider>().reactToStory(
                storyId: _currentStory.id,
                reactorId: widget.currentUserId,
                reactorName: widget.currentUserName,
                reactorPhotoUrl: widget.currentUserPhotoUrl,
                emoji: emoji,
              );
        },
      ),
    ).then((_) => _resume());
  }

  
  
  

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: GestureDetector(
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity != null && details.primaryVelocity! > 300) {
            Navigator.of(context).pop();
          }
        },
        child: Stack(
          children: [
            PageView.builder(
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
                  onReply: _openReply,
                  onReact: _showReactions,
                  currentUserId: widget.currentUserId,
                );
              },
            ),

            
            if (_replyVisible)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _ReplyBar(
                  ctrl: _replyCtrl,
                  focus: _replyFocus,
                  storyOwnerName: _currentUser.userName,
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
    );
  }
}





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
    required this.currentUserId,
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
        
        _StoryContent(story: story, onPause: onHoldStart, onResume: onHoldEnd),

        
        const _Gradients(),

        
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

        
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _Footer(
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





class _StoryContent extends StatefulWidget {
  final Story story;
  final VoidCallback onPause;
  final VoidCallback onResume;

  const _StoryContent({
    required this.story,
    required this.onPause,
    required this.onResume,
  });

  @override
  State<_StoryContent> createState() => _StoryContentState();
}

class _StoryContentState extends State<_StoryContent> {
  VideoPlayerController? _videoCtrl;
  bool _videoReady = false;

  @override
  void initState() {
    super.initState();
    if (widget.story.type == StoryType.video && widget.story.mediaUrl != null) {
      _initVideo();
    }
  }

  Future<void> _initVideo() async {
    final ctrl = VideoPlayerController.networkUrl(
      Uri.parse(widget.story.mediaUrl!),
    );
    _videoCtrl = ctrl;
    await ctrl.initialize();
    if (mounted) {
      ctrl.setLooping(false);
      ctrl.play();
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
        return Center(
          child: AspectRatio(
            aspectRatio: _videoCtrl!.value.aspectRatio,
            child: VideoPlayer(_videoCtrl!),
          ),
        );
      }
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    
    if (story.type == StoryType.image && story.mediaUrl != null) {
      return Image.network(
        story.mediaUrl!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        loadingBuilder: (_, child, progress) => progress == null
            ? child
            : const ColoredBox(
                color: Colors.black87,
                child: Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
        errorBuilder: (_, __, ___) => const ColoredBox(
          color: Colors.black87,
          child: Center(
            child: Icon(Icons.broken_image, color: Colors.white38, size: 64),
          ),
        ),
      );
    }

    
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





class _Gradients extends StatelessWidget {
  const _Gradients();

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Container(
            height: 160,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.65),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          const Spacer(),
          Container(
            height: 220,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.75),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ],
      );
}





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
              color: Colors.white.withValues(alpha: 0.35),
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
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white70, width: 1.5),
          ),
          child: ClipOval(
            child: story.userPhotoUrl.isNotEmpty
                ? Image.network(
                    story.userPhotoUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _defaultAvatar(),
                  )
                : _defaultAvatar(),
          ),
        ),
        const SizedBox(width: 10),
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
                  fontSize: 14,
                ),
              ),
              Text(
                _timeAgo(story.createdAt),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 11,
                ),
              ),
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





class _Footer extends StatelessWidget {
  final Story story;
  final bool isCurrentUser;
  final String currentUserId;
  final VoidCallback onReply;
  final VoidCallback onReact;

  const _Footer({
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
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
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
                      const Icon(Icons.remove_red_eye_outlined, color: Colors.white70, size: 18),
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
                      const Icon(Icons.keyboard_arrow_up, color: Colors.white70, size: 18),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                context.read<StoryProvider>().formatTimeRemaining(story.remainingTime),
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
              ),
            ],

            
            if (!isCurrentUser) ...[
              Row(
                children: [
                  
                  if (story.reactionBy(currentUserId) != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Text(
                        story.reactionBy(currentUserId)!,
                        style: const TextStyle(fontSize: 20),
                      ),
                    ),

                  
                  GestureDetector(
                    onTap: onReact,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.emoji_emotions_outlined, color: Colors.white, size: 18),
                          SizedBox(width: 6),
                          Text('React', style: TextStyle(color: Colors.white, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(width: 10),

                  
                  Expanded(
                    child: GestureDetector(
                      onTap: onReply,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.reply_rounded, color: Colors.white, size: 18),
                            const SizedBox(width: 6),
                            Text(
                              'Reply to ${story.userName.split(' ').first}…',
                              style: const TextStyle(color: Colors.white54, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
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
      builder: (_) => _ViewersSheet(story: story),
    );
  }
}





class _ReplyBar extends StatelessWidget {
  final TextEditingController ctrl;
  final FocusNode focus;
  final String storyOwnerName;
  final VoidCallback onSend;
  final VoidCallback onDismiss;

  const _ReplyBar({
    required this.ctrl,
    required this.focus,
    required this.storyOwnerName,
    required this.onSend,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 8,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white54, size: 22),
              onPressed: onDismiss,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: ctrl,
                focusNode: focus,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                maxLines: 3,
                minLines: 1,
                decoration: InputDecoration(
                  hintText: 'Reply to ${storyOwnerName.split(' ').first}…',
                  hintStyle: const TextStyle(color: Colors.white38),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onSend,
              child: Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: Color(0xFF2196F3),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}





class _ReactionsSheet extends StatelessWidget {
  final String storyId;
  final String senderId;
  final String senderName;
  final String senderPhotoUrl;
  final Future<void> Function(String emoji) onSelect;

  static const _emojis = ['❤️', '😂', '😮', '😢', '😡', '👏', '🔥', '💯'];

  const _ReactionsSheet({
    required this.storyId,
    required this.senderId,
    required this.senderName,
    required this.senderPhotoUrl,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Text(
            'React',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: _emojis.map((e) {
              return GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  onSelect(e);
                },
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.5, end: 1.0),
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.elasticOut,
                  builder: (_, v, child) => Transform.scale(scale: v, child: child),
                  child: Text(e, style: const TextStyle(fontSize: 36)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}





class _ViewersSheet extends StatelessWidget {
  final Story story;
  const _ViewersSheet({required this.story});

  @override
  Widget build(BuildContext context) {
    final views = story.views;
    final reactions = story.reactions;

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
                const Icon(Icons.remove_red_eye_outlined, color: Colors.white70, size: 20),
                const SizedBox(width: 8),
                Text(
                  '${views.length} Viewer${views.length != 1 ? 's' : ''}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (reactions.isNotEmpty)
                  Text(
                    '${reactions.length} reaction${reactions.length != 1 ? 's' : ''}',
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
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
                    child: Text('No viewers yet', style: TextStyle(color: Colors.white54)),
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
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage: v.photoUrl.isNotEmpty ? NetworkImage(v.photoUrl) : null,
                          backgroundColor: Colors.grey.shade700,
                          child: v.photoUrl.isEmpty
                              ? const Icon(Icons.person, color: Colors.white)
                              : null,
                        ),
                        title: Text(v.userName, style: const TextStyle(color: Colors.white)),
                        subtitle: Text(
                          _fmt(v.viewedAt),
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                        trailing: reaction != null
                            ? Text(reaction, style: const TextStyle(fontSize: 22))
                            : null,
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
