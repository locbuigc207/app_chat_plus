import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_chat_demo/pages/story_creator_page.dart';
import 'package:flutter_chat_demo/pages/story_viewer_page.dart';
import 'package:flutter_chat_demo/providers/story_provider.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class MyStoriesPage extends StatefulWidget {
  final String userId;
  final String userName;
  final String userPhotoUrl;

  const MyStoriesPage({
    super.key,
    required this.userId,
    required this.userName,
    required this.userPhotoUrl,
  });

  @override
  State<MyStoriesPage> createState() => _MyStoriesPageState();
}

class _MyStoriesPageState extends State<MyStoriesPage>
    with SingleTickerProviderStateMixin {
  bool _gridView = false;
  final Set<String> _selected = {};
  bool _selecting = false;

  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  // ── Navigation ──────────────────────────────────────────────────────────────

  void _openCreator() {
    Navigator.push(
      context,
      _slideRoute(StoryCreatorPage(
        userId: widget.userId,
        userName: widget.userName,
        userPhotoUrl: widget.userPhotoUrl,
      )),
    );
  }

  void _openViewer(List<Story> stories, int startIndex) {
    final active = stories.where((s) => s.isActive).toList();
    if (active.isEmpty) return;
    final idx = startIndex.clamp(0, active.length - 1);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoryViewerPage(
          allUserStories: [
            UserStories(
              userId: widget.userId,
              userName: widget.userName,
              userPhotoUrl: widget.userPhotoUrl,
              stories: active,
              isCurrentUser: true,
            ),
          ],
          initialUserIndex: 0,
          currentUserId: widget.userId,
          currentUserName: widget.userName,
          currentUserPhotoUrl: widget.userPhotoUrl,
        ),
      ),
    );
  }

  // ── Selection ───────────────────────────────────────────────────────────────

  void _toggleSelect(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
        if (_selected.isEmpty) _selecting = false;
      } else {
        _selected.add(id);
      }
    });
    HapticFeedback.selectionClick();
  }

  void _startSelecting(String id) {
    setState(() {
      _selecting = true;
      _selected.add(id);
    });
    HapticFeedback.mediumImpact();
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final count = _selected.length;
    final ok = await _confirmDelete(
      'Delete $count ${count == 1 ? 'story' : 'stories'}?',
      'They will be permanently removed.',
    );
    if (!ok || !mounted) return;

    final ids = {..._selected};
    setState(() {
      _selected.clear();
      _selecting = false;
    });

    for (final id in ids) {
      await context.read<StoryProvider>().deleteStory(id);
    }

    if (mounted) {
      _showSnack('🗑️ Deleted $count ${count == 1 ? 'story' : 'stories'}', isError: true);
    }
  }

  Future<void> _archiveSelected() async {
    if (_selected.isEmpty) return;
    final count = _selected.length;
    final ids = {..._selected};
    setState(() {
      _selected.clear();
      _selecting = false;
    });

    for (final id in ids) {
      await context.read<StoryProvider>().archiveStory(id);
    }

    if (mounted) {
      _showSnack('📦 Archived $count ${count == 1 ? 'story' : 'stories'}');
    }
  }

  Future<bool> _confirmDelete(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        backgroundColor: const Color(0xFF1C1C1E),
        title: Text(title,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
        content: Text(body, style: const TextStyle(color: Colors.white54, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        backgroundColor: isError ? Colors.red.shade800 : Colors.grey.shade900,
        duration: const Duration(seconds: 2),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      ),
    );
  }

  PageRoute _slideRoute(Widget page) => PageRouteBuilder(
    pageBuilder: (_, a, __) => page,
    transitionsBuilder: (_, a, __, child) => SlideTransition(
      position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
          .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
      child: child,
    ),
    transitionDuration: const Duration(milliseconds: 280),
  );

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF5F5F7);

    return Scaffold(
      backgroundColor: bg,
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [_buildSliverAppBar(isDark)],
        body: _buildBody(isDark),
      ),
      floatingActionButton: _selecting ? null : _buildFAB(),
      bottomNavigationBar: _selecting && _selected.isNotEmpty
          ? _SelectionBar(
        count: _selected.length,
        onDelete: _deleteSelected,
        onArchive: _archiveSelected,
        onCancel: () => setState(() {
          _selected.clear();
          _selecting = false;
        }),
      )
          : null,
    );
  }

  Widget _buildSliverAppBar(bool isDark) {
    return SliverAppBar(
      expandedHeight: 200,
      floating: false,
      pinned: true,
      snap: false,
      backgroundColor: isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF5F5F7),
      surfaceTintColor: Colors.transparent,
      leading: _selecting
          ? IconButton(
        icon: const Icon(Icons.close_rounded),
        onPressed: () => setState(() {
          _selected.clear();
          _selecting = false;
        }),
      )
          : IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded),
        onPressed: () => Navigator.pop(context),
      ),
      title: _selecting
          ? Text(
        '${_selected.length} selected',
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
      )
          : null,
      actions: _selecting
          ? []
          : [
        IconButton(
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Icon(
              _gridView ? Icons.view_list_rounded : Icons.grid_view_rounded,
              key: ValueKey(_gridView),
            ),
          ),
          onPressed: () {
            HapticFeedback.selectionClick();
            setState(() => _gridView = !_gridView);
          },
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_rounded),
          onPressed: _openCreator,
        ),
      ],
      flexibleSpace: _selecting
          ? null
          : FlexibleSpaceBar(
        background: _buildHeroHeader(isDark),
      ),
      bottom: TabBar(
        controller: _tabCtrl,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        unselectedLabelStyle:
        const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
        indicatorSize: TabBarIndicatorSize.label,
        indicatorWeight: 3,
        tabs: const [
          Tab(text: 'Active'),
          Tab(text: 'Archive'),
        ],
      ),
    );
  }

  Widget _buildHeroHeader(bool isDark) {
    return StreamBuilder<List<Story>>(
      stream: context.read<StoryProvider>().getMyStoriesStream(widget.userId),
      builder: (_, snap) {
        final stories = snap.data ?? [];
        final totalViews = stories.fold<int>(0, (s, st) => s + st.viewCount);
        final totalReactions = stories.fold<int>(0, (s, st) => s + st.reactions.length);

        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [const Color(0xFF1A1A2E), const Color(0xFF16213E)]
                  : [const Color(0xFF6C63FF).withValues(alpha: 0.9), const Color(0xFF2196F3).withValues(alpha: 0.8)],
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 54, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'My Stories',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.8,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _HeroStat(
                          icon: Icons.auto_stories_rounded,
                          value: '${stories.length}',
                          label: 'Stories',
                          color: const Color(0xFFB8B8FF)),
                      const SizedBox(width: 12),
                      _HeroStat(
                          icon: Icons.remove_red_eye_rounded,
                          value: totalViews > 999
                              ? '${(totalViews / 1000).toStringAsFixed(1)}k'
                              : '$totalViews',
                          label: 'Views',
                          color: const Color(0xFF86EFAC)),
                      const SizedBox(width: 12),
                      _HeroStat(
                          icon: Icons.favorite_rounded,
                          value: '$totalReactions',
                          label: 'Reactions',
                          color: const Color(0xFFFCA5A5)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody(bool isDark) {
    return TabBarView(
      controller: _tabCtrl,
      children: [
        _buildActiveTab(isDark),
        _buildArchiveTab(isDark),
      ],
    );
  }

  Widget _buildActiveTab(bool isDark) {
    return StreamBuilder<List<Story>>(
      stream: context.read<StoryProvider>().getMyStoriesStream(widget.userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildShimmer(isDark);
        }

        final stories = snapshot.data ?? [];

        if (stories.isEmpty) {
          return _EmptyState(onAdd: _openCreator);
        }

        if (_gridView) {
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 120),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.68,
            ),
            itemCount: stories.length,
            itemBuilder: (_, i) => _StoryGridCard(
              story: stories[i],
              isSelected: _selected.contains(stories[i].id),
              selecting: _selecting,
              onTap: () => _selecting
                  ? _toggleSelect(stories[i].id)
                  : _openViewer(stories, i),
              onLongPress: () => _selecting
                  ? _toggleSelect(stories[i].id)
                  : _startSelecting(stories[i].id),
              onDelete: () => _singleDelete(stories[i].id),
              onArchive: () => _singleArchive(stories[i].id),
              isDark: isDark,
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
          itemCount: stories.length,
          itemBuilder: (_, i) => _StoryListCard(
            story: stories[i],
            isSelected: _selected.contains(stories[i].id),
            selecting: _selecting,
            onTap: () => _selecting
                ? _toggleSelect(stories[i].id)
                : _openViewer(stories, i),
            onLongPress: () => _selecting
                ? _toggleSelect(stories[i].id)
                : _startSelecting(stories[i].id),
            onDelete: () => _singleDelete(stories[i].id),
            onArchive: () => _singleArchive(stories[i].id),
            isDark: isDark,
          ),
        );
      },
    );
  }

  Widget _buildArchiveTab(bool isDark) {
    return StreamBuilder<List<Story>>(
      stream: context.read<StoryProvider>().getArchivedStoriesStream(widget.userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildShimmer(isDark);
        }

        final stories = snapshot.data ?? [];

        if (stories.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.archive_rounded, size: 64, color: Colors.grey.shade500),
                const SizedBox(height: 16),
                const Text(
                  'No archived stories',
                  style: TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Archived stories appear here',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ],
            ),
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 0.6,
          ),
          itemCount: stories.length,
          itemBuilder: (_, i) => _ArchiveCard(
            story: stories[i],
            onTap: () {},
            isDark: isDark,
          ),
        );
      },
    );
  }

  Future<void> _singleDelete(String id) async {
    final ok = await _confirmDelete('Delete story?', 'This cannot be undone.');
    if (ok && mounted) {
      await context.read<StoryProvider>().deleteStory(id);
      _showSnack('🗑️ Story deleted', isError: true);
    }
  }

  Future<void> _singleArchive(String id) async {
    await context.read<StoryProvider>().archiveStory(id);
    if (mounted) _showSnack('📦 Story archived');
  }

  Widget _buildShimmer(bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 6,
      itemBuilder: (_, __) => _ShimmerCard(isDark: isDark),
    );
  }

  Widget _buildFAB() {
    return FloatingActionButton.extended(
      onPressed: _openCreator,
      elevation: 6,
      extendedPadding: const EdgeInsets.symmetric(horizontal: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      backgroundColor: const Color(0xFF6C63FF),
      icon: const Icon(Icons.add_rounded, color: Colors.white),
      label: const Text(
        'Add Story',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
      ),
    );
  }
}

// ─── Hero Stat ────────────────────────────────────────────────────────────────

class _HeroStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _HeroStat({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 7),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
              Text(
                label,
                style: const TextStyle(color: Colors.white60, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Story List Card ──────────────────────────────────────────────────────────

class _StoryListCard extends StatelessWidget {
  final Story story;
  final bool isSelected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onDelete;
  final VoidCallback onArchive;
  final bool isDark;

  const _StoryListCard({
    required this.story,
    required this.isSelected,
    required this.selecting,
    required this.onTap,
    required this.onLongPress,
    required this.onDelete,
    required this.onArchive,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final remaining = story.remainingTime;
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes % 60;
    final expiringSoon = hours < 3;
    final surfaceColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final borderColor = isSelected
        ? const Color(0xFF6C63FF)
        : (isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06));

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6C63FF).withValues(alpha: 0.08) : surfaceColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: isSelected ? 1.5 : 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Thumbnail
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      width: 76,
                      height: 100,
                      child: _Thumbnail(story: story),
                    ),
                  ),
                  if (selecting)
                    Positioned(
                      top: 4, right: 4,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected ? const Color(0xFF6C63FF) : Colors.white.withValues(alpha: 0.7),
                          border: Border.all(
                            color: isSelected ? const Color(0xFF6C63FF) : Colors.grey.shade400,
                            width: 2,
                          ),
                        ),
                        child: isSelected
                            ? const Icon(Icons.check_rounded, color: Colors.white, size: 13)
                            : null,
                      ),
                    ),
                ],
              ),

              const SizedBox(width: 14),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _TypeBadge(type: story.type),
                        const Spacer(),
                        if (expiringSoon)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.schedule_rounded, size: 10, color: Colors.orange),
                                const SizedBox(width: 3),
                                Text(
                                  hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.orange,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          Text(
                            hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white38 : Colors.grey.shade500,
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    Text(
                      story.type == StoryType.text
                          ? (story.textContent ?? '')
                          : (story.caption?.isNotEmpty == true
                          ? story.caption!
                          : story.type == StoryType.video
                          ? 'Video story'
                          : 'Photo story'),
                      style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF0D1117),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                    const SizedBox(height: 10),

                    // Stats row
                    Row(
                      children: [
                        _MiniStat(
                          icon: Icons.remove_red_eye_rounded,
                          value: story.viewCount,
                          color: Colors.blue,
                          isDark: isDark,
                        ),
                        const SizedBox(width: 10),
                        _MiniStat(
                          icon: Icons.favorite_rounded,
                          value: story.reactions.length,
                          color: Colors.pink,
                          isDark: isDark,
                        ),
                        const Spacer(),
                        Text(
                          DateFormat('HH:mm').format(story.createdAt),
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white30 : Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    // Action buttons
                    if (!selecting)
                      Row(
                        children: [
                          Expanded(
                            child: _CardBtn(
                              icon: Icons.archive_outlined,
                              label: 'Archive',
                              onTap: onArchive,
                              isDark: isDark,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _CardBtn(
                              icon: Icons.delete_outline_rounded,
                              label: 'Delete',
                              onTap: onDelete,
                              isDark: isDark,
                              isDestructive: true,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Story Grid Card ──────────────────────────────────────────────────────────

class _StoryGridCard extends StatelessWidget {
  final Story story;
  final bool isSelected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onDelete;
  final VoidCallback onArchive;
  final bool isDark;

  const _StoryGridCard({
    required this.story,
    required this.isSelected,
    required this.selecting,
    required this.onTap,
    required this.onLongPress,
    required this.onDelete,
    required this.onArchive,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final remaining = story.remainingTime;
    final expiringSoon = remaining.inHours < 3;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? const Color(0xFF6C63FF) : Colors.transparent,
            width: isSelected ? 2.5 : 0,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: _Thumbnail(story: story, fillParent: true),
            ),

            // Gradient overlay
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.75)],
                    stops: const [0.4, 1.0],
                  ),
                ),
              ),
            ),

            // Type badge
            Positioned(
              top: 8, left: 8,
              child: _TypeBadge(type: story.type),
            ),

            // Selection circle
            if (selecting)
              Positioned(
                top: 8, right: 8,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? const Color(0xFF6C63FF) : Colors.white.withValues(alpha: 0.7),
                    border: Border.all(
                      color: isSelected ? const Color(0xFF6C63FF) : Colors.grey,
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check_rounded, color: Colors.white, size: 15)
                      : null,
                ),
              ),

            // Delete / archive quick actions
            if (!selecting)
              Positioned(
                top: 6, right: 6,
                child: _QuickActionsMenu(
                  onDelete: onDelete,
                  onArchive: onArchive,
                ),
              ),

            // Bottom stats
            Positioned(
              bottom: 8, left: 10, right: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.remove_red_eye_rounded, color: Colors.white70, size: 12),
                      const SizedBox(width: 3),
                      Text(
                        '${story.viewCount}',
                        style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 8),
                      if (story.reactions.isNotEmpty) ...[
                        Text(
                          story.reactions.take(2).map((r) => r.emoji).join(),
                          style: const TextStyle(fontSize: 11),
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${story.reactions.length}',
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                      const Spacer(),
                      Text(
                        expiringSoon
                            ? '${remaining.inMinutes}m'
                            : '${remaining.inHours}h',
                        style: TextStyle(
                          color: expiringSoon ? Colors.orange : Colors.white54,
                          fontSize: 10,
                          fontWeight: expiringSoon ? FontWeight.w800 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Archive Card ─────────────────────────────────────────────────────────────

class _ArchiveCard extends StatelessWidget {
  final Story story;
  final VoidCallback onTap;
  final bool isDark;

  const _ArchiveCard({required this.story, required this.onTap, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: _Thumbnail(story: story, fillParent: true),
          ),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withValues(alpha: 0.6)],
              ),
            ),
          ),
          Positioned(
            bottom: 6, left: 6, right: 6,
            child: Text(
              DateFormat('MMM d').format(story.createdAt),
              style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Quick Actions Menu ────────────────────────────────────────────────────────

class _QuickActionsMenu extends StatelessWidget {
  final VoidCallback onDelete;
  final VoidCallback onArchive;

  const _QuickActionsMenu({required this.onDelete, required this.onArchive});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (v) {
        if (v == 'delete') onDelete();
        if (v == 'archive') onArchive();
      },
      color: const Color(0xFF1C1C1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.more_vert_rounded, color: Colors.white, size: 16),
      ),
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'archive',
          child: Row(
            children: [
              Icon(Icons.archive_rounded, color: Colors.white70, size: 18),
              SizedBox(width: 10),
              Text('Archive', style: TextStyle(color: Colors.white, fontSize: 14)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_rounded, color: Colors.redAccent, size: 18),
              SizedBox(width: 10),
              Text('Delete', style: TextStyle(color: Colors.redAccent, fontSize: 14)),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Selection Bar ─────────────────────────────────────────────────────────────

class _SelectionBar extends StatelessWidget {
  final int count;
  final VoidCallback onDelete;
  final VoidCallback onArchive;
  final VoidCallback onCancel;

  const _SelectionBar({
    required this.count,
    required this.onDelete,
    required this.onArchive,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          border: Border(top: BorderSide(color: isDark ? Colors.white10 : Colors.black12)),
        ),
        child: Row(
          children: [
            TextButton.icon(
              onPressed: onCancel,
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text('Cancel'),
              style: TextButton.styleFrom(foregroundColor: Colors.grey),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: onArchive,
              icon: const Icon(Icons.archive_rounded, size: 16),
              label: const Text('Archive'),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                side: BorderSide(color: Colors.grey.shade500),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_rounded, size: 16),
              label: Text('Delete $count'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Empty State ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6C63FF), Color(0xFF2196F3)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6C63FF).withValues(alpha: 0.35),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Icon(Icons.auto_stories_rounded, size: 52, color: Colors.white),
            ),
            const SizedBox(height: 28),
            const Text(
              'No Stories Yet',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.5),
            ),
            const SizedBox(height: 10),
            Text(
              'Share moments that disappear in 24 hours — photos, videos, or text.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 36),
            GestureDetector(
              onTap: onAdd,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6C63FF), Color(0xFF2196F3)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6C63FF).withValues(alpha: 0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Create your first story',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Thumbnail ────────────────────────────────────────────────────────────────

class _Thumbnail extends StatelessWidget {
  final Story story;
  final bool fillParent;

  const _Thumbnail({required this.story, this.fillParent = false});

  @override
  Widget build(BuildContext context) {
    if (story.type == StoryType.image && story.mediaUrl != null) {
      return Image.network(
        story.mediaUrl!,
        width: fillParent ? double.infinity : null,
        height: fillParent ? double.infinity : null,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallback(),
      );
    }

    if (story.type == StoryType.video) {
      return Container(
        color: const Color(0xFF1A1A2E),
        child: const Center(
          child: Icon(Icons.play_circle_fill_rounded, color: Colors.white54, size: 42),
        ),
      );
    }

    final bg = story.backgroundColor ?? const Color(0xFF1A1A2E);
    final colors = story.gradientColors;
    final bg2 = Color.lerp(bg, Colors.black, 0.35)!;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: (colors != null && colors.length >= 2) ? colors : [bg, bg2],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8),
      child: Text(
        story.textContent ?? '',
        style: TextStyle(
          color: story.textColor ?? Colors.white,
          fontSize: fillParent ? 12 : 9,
          fontFamily: story.fontFamily,
          fontWeight: FontWeight.w800,
          height: 1.3,
          shadows: const [Shadow(color: Colors.black38, blurRadius: 6)],
        ),
        textAlign: TextAlign.center,
        maxLines: fillParent ? 6 : 4,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _fallback() => Container(
    color: const Color(0xFF1C1C1E),
    child: const Icon(Icons.image_not_supported_rounded, color: Colors.white24, size: 32),
  );
}

// ─── Type Badge ───────────────────────────────────────────────────────────────

class _TypeBadge extends StatelessWidget {
  final StoryType type;
  const _TypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = switch (type) {
      StoryType.image => (Icons.image_rounded, 'Photo', const Color(0xFF2196F3)),
      StoryType.text => (Icons.text_fields_rounded, 'Text', const Color(0xFF9C27B0)),
      StoryType.video => (Icons.videocam_rounded, 'Video', const Color(0xFFE91E63)),
      StoryType.boomerang => (Icons.loop_rounded, 'Loop', const Color(0xFFFF9800)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }
}

// ─── Mini Stat ────────────────────────────────────────────────────────────────

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final int value;
  final Color color;
  final bool isDark;

  const _MiniStat({
    required this.icon,
    required this.value,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color.withValues(alpha: 0.8)),
        const SizedBox(width: 4),
        Text(
          '$value',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white60 : Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}

// ─── Card Button ──────────────────────────────────────────────────────────────

class _CardBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDark;
  final bool isDestructive;

  const _CardBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.isDark,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? Colors.red.shade400 : (isDark ? Colors.white60 : Colors.grey.shade600);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: isDestructive
              ? Colors.red.withValues(alpha: 0.08)
              : (isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.withValues(alpha: 0.08)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Shimmer Card ─────────────────────────────────────────────────────────────

class _ShimmerCard extends StatefulWidget {
  final bool isDark;
  const _ShimmerCard({required this.isDark});

  @override
  State<_ShimmerCard> createState() => _ShimmerCardState();
}

class _ShimmerCardState extends State<_ShimmerCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat(reverse: true);
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
      builder: (_, __) {
        final c = widget.isDark
            ? Color.lerp(const Color(0xFF1C1C1E), const Color(0xFF2A2A2E), _anim.value)!
            : Color.lerp(const Color(0xFFE8E8E8), const Color(0xFFF5F5F5), _anim.value)!;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: widget.isDark ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Container(
                width: 76, height: 100,
                decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(14)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(height: 12, width: 80, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(6))),
                    const SizedBox(height: 10),
                    Container(height: 14, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(6))),
                    const SizedBox(height: 6),
                    Container(height: 14, width: 150, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(6))),
                    const SizedBox(height: 14),
                    Container(height: 10, width: 100, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(6))),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}