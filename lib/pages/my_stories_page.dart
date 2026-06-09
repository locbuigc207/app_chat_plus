import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart'; // Đảm bảo định nghĩa Story, StoryType, UserStories có trong này
import 'package:flutter_chat_demo/pages/story_creator_page.dart';
import 'package:flutter_chat_demo/pages/story_viewer_page.dart';
import 'package:flutter_chat_demo/providers/story_provider.dart';
import 'package:flutter_chat_demo/providers/theme_provider.dart';

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

class _MyStoriesPageState extends State<MyStoriesPage> with SingleTickerProviderStateMixin {
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

  // ─── Điều hướng ─────────────────────────────────────────────────────────────

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

  // ─── Quản lý chọn mục (Selection) ───────────────────────────────────────────

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
    final ok = await _confirmDelete('Xóa $count story?', 'Hành động này không thể hoàn tác.');
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
      _showSnack('🗑️ Đã xóa $count story', isError: true);
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
      _showSnack('📦 Đã lưu trữ $count story');
    }
  }

  Future<bool> _confirmDelete(String title, String body) async {
    final theme = context.read<ThemeProvider>();
    final p = theme.palette;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: p.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700, fontSize: 18)),
        content: Text(body, style: TextStyle(color: p.textSecondary, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Hủy', style: TextStyle(color: p.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade400),
            child: const Text('Xóa', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _singleDelete(String id) async {
    final ok = await _confirmDelete('Xóa story?', 'Hành động này không thể hoàn tác.');
    if (ok && mounted) {
      await context.read<StoryProvider>().deleteStory(id);
      _showSnack('🗑️ Story đã được xóa', isError: true);
    }
  }

  Future<void> _singleArchive(String id) async {
    await context.read<StoryProvider>().archiveStory(id);
    if (mounted) _showSnack('📦 Story đã được chuyển vào kho lưu trữ');
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

  // ─── Giao diện chính ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final p = theme.palette;

    return Theme(
      data: theme.isDark ? theme.darkTheme : theme.lightTheme,
      child: Scaffold(
        backgroundColor: p.background,
        body: NestedScrollView(
          headerSliverBuilder: (_, __) => [_buildSliverAppBar(p, theme)],
          body: _buildBody(p, theme),
        ),
        floatingActionButton: _selecting ? null : FloatingActionButton.extended(
          onPressed: _openCreator,
          elevation: 4,
          extendedPadding: const EdgeInsets.symmetric(horizontal: 22),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          backgroundColor: theme.primaryColor,
          icon: const Icon(Icons.add_rounded, color: Colors.white),
          label: const Text('Story mới', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
        ),
        bottomNavigationBar: _selecting && _selected.isNotEmpty
            ? _SelectionBar(
          count: _selected.length,
          palette: p,
          primary: theme.primaryColor,
          onDelete: _deleteSelected,
          onArchive: _archiveSelected,
          onCancel: () => setState(() {
            _selected.clear();
            _selecting = false;
          }),
        )
            : null,
      ),
    );
  }

  Widget _buildSliverAppBar(ThemePalette p, ThemeProvider theme) {
    return SliverAppBar(
      expandedHeight: 180,
      floating: false,
      pinned: true,
      snap: false,
      backgroundColor: p.appBarBackground,
      surfaceTintColor: Colors.transparent,
      leading: _selecting
          ? IconButton(
        icon: Icon(Icons.close_rounded, color: p.textPrimary),
        onPressed: () => setState(() {
          _selected.clear();
          _selecting = false;
        }),
      )
          : IconButton(
        icon: Icon(Icons.arrow_back_ios_new_rounded, color: theme.primaryColor, size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      title: _selecting
          ? Text(
        '${_selected.length} đã chọn',
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: p.textPrimary),
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
              color: theme.primaryColor,
            ),
          ),
          onPressed: () {
            HapticFeedback.selectionClick();
            setState(() => _gridView = !_gridView);
          },
        ),
        IconButton(
          icon: Icon(Icons.add_circle_rounded, color: theme.primaryColor),
          onPressed: _openCreator,
        ),
        const SizedBox(width: 4),
      ],
      flexibleSpace: _selecting
          ? null
          : FlexibleSpaceBar(
        background: _buildHeroHeader(p, theme),
      ),
      bottom: TabBar(
        controller: _tabCtrl,
        labelColor: theme.primaryColor,
        unselectedLabelColor: p.textSecondary,
        indicatorColor: theme.primaryColor,
        indicatorWeight: 3,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
        tabs: const [
          Tab(text: 'Đang hoạt động'),
          Tab(text: 'Lưu trữ'),
        ],
      ),
    );
  }

  Widget _buildHeroHeader(ThemePalette p, ThemeProvider theme) {
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
              colors: [
                theme.primaryColor,
                theme.primaryLightColor.withValues(alpha: 0.7),
              ],
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 50, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'My Stories',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.8,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _HeroStat(icon: Icons.auto_stories_rounded, value: '${stories.length}', label: 'Stories'),
                      const SizedBox(width: 10),
                      _HeroStat(
                        icon: Icons.remove_red_eye_rounded,
                        value: totalViews > 999 ? '${(totalViews / 1000).toStringAsFixed(1)}k' : '$totalViews',
                        label: 'Lượt xem',
                      ),
                      const SizedBox(width: 10),
                      _HeroStat(icon: Icons.favorite_rounded, value: '$totalReactions', label: 'Reactions'),
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

  Widget _buildBody(ThemePalette p, ThemeProvider theme) {
    return TabBarView(
      controller: _tabCtrl,
      children: [
        _buildActiveTab(p, theme),
        _buildArchiveTab(p, theme),
      ],
    );
  }

  Widget _buildActiveTab(ThemePalette p, ThemeProvider theme) {
    return StreamBuilder<List<Story>>(
      stream: context.read<StoryProvider>().getMyStoriesStream(widget.userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildShimmer(p);
        }

        final stories = snapshot.data ?? [];

        if (stories.isEmpty) {
          return _EmptyState(onAdd: _openCreator, primary: theme.primaryColor, palette: p);
        }

        if (_gridView) {
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
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
              onTap: () => _selecting ? _toggleSelect(stories[i].id) : _openViewer(stories, i),
              onLongPress: () => _selecting ? _toggleSelect(stories[i].id) : _startSelecting(stories[i].id),
              onDelete: () => _singleDelete(stories[i].id),
              onArchive: () => _singleArchive(stories[i].id),
              palette: p,
              primary: theme.primaryColor,
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          itemCount: stories.length,
          itemBuilder: (_, i) => _StoryListCard(
            story: stories[i],
            isSelected: _selected.contains(stories[i].id),
            selecting: _selecting,
            onTap: () => _selecting ? _toggleSelect(stories[i].id) : _openViewer(stories, i),
            onLongPress: () => _selecting ? _toggleSelect(stories[i].id) : _startSelecting(stories[i].id),
            onDelete: () => _singleDelete(stories[i].id),
            onArchive: () => _singleArchive(stories[i].id),
            palette: p,
            primary: theme.primaryColor,
          ),
        );
      },
    );
  }

  Widget _buildArchiveTab(ThemePalette p, ThemeProvider theme) {
    return StreamBuilder<List<Story>>(
      stream: context.read<StoryProvider>().getArchivedStoriesStream(widget.userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildShimmer(p);
        }

        final stories = snapshot.data ?? [];

        if (stories.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.archive_rounded, size: 64, color: p.textSecondary),
                const SizedBox(height: 16),
                Text(
                  'Không có story đã lưu trữ',
                  style: TextStyle(color: p.textSecondary, fontSize: 15, fontWeight: FontWeight.w500),
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
            palette: p,
          ),
        );
      },
    );
  }

  Widget _buildShimmer(ThemePalette p) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      itemBuilder: (_, __) => _ShimmerCard(palette: p),
    );
  }
}

// ─── Hero Stat ────────────────────────────────────────────────────────────────

class _HeroStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _HeroStat({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white.withValues(alpha: 0.9), size: 16),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
              Text(
                label,
                style: const TextStyle(color: Colors.white70, fontSize: 10),
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
  final ThemePalette palette;
  final Color primary;

  const _StoryListCard({
    required this.story,
    required this.isSelected,
    required this.selecting,
    required this.onTap,
    required this.onLongPress,
    required this.onDelete,
    required this.onArchive,
    required this.palette,
    required this.primary,
  });

  @override
  Widget build(BuildContext context) {
    final remaining = story.remainingTime;
    final hours = remaining.inHours;
    final expiringSoon = hours < 3;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: isSelected ? primary.withValues(alpha: 0.08) : palette.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: isSelected ? primary : palette.divider, width: isSelected ? 1.5 : 0.6),
          boxShadow: [
            BoxShadow(
              color: palette.shadow,
              blurRadius: 8,
              offset: const Offset(0, 2),
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
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 76,
                      height: 100,
                      child: _Thumbnail(story: story),
                    ),
                  ),
                  if (selecting)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected ? primary : Colors.white.withValues(alpha: 0.8),
                          border: Border.all(
                            color: isSelected ? primary : Colors.grey.shade400,
                            width: 2,
                          ),
                        ),
                        child: isSelected ? const Icon(Icons.check_rounded, color: Colors.white, size: 13) : null,
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
                        _TypeBadge(type: story.type, primary: primary),
                        const Spacer(),
                        if (expiringSoon)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.schedule_rounded, size: 10, color: Colors.orange),
                                const SizedBox(width: 3),
                                Text(
                                  hours > 0 ? '$hours\h ${remaining.inMinutes % 60}m' : '${remaining.inMinutes}m',
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
                            hours > 0 ? '${hours}h' : '${remaining.inMinutes}m',
                            style: TextStyle(fontSize: 11, color: palette.textSecondary),
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
                        color: palette.textPrimary,
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
                          palette: palette,
                        ),
                        const SizedBox(width: 10),
                        _MiniStat(
                          icon: Icons.favorite_rounded,
                          value: story.reactions.length,
                          color: Colors.pink,
                          palette: palette,
                        ),
                        const Spacer(),
                        Text(
                          DateFormat('HH:mm').format(story.createdAt),
                          style: TextStyle(fontSize: 11, color: palette.textSecondary),
                        ),
                      ],
                    ),
                    if (!selecting) ...[
                      const SizedBox(height: 10),
                      // Action buttons
                      Row(
                        children: [
                          Expanded(
                            child: _CardBtn(
                              icon: Icons.archive_outlined,
                              label: 'Lưu trữ',
                              onTap: onArchive,
                              palette: palette,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _CardBtn(
                              icon: Icons.delete_outline_rounded,
                              label: 'Xóa',
                              onTap: onDelete,
                              palette: palette,
                              isDestructive: true,
                            ),
                          ),
                        ],
                      ),
                    ],
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
  final ThemePalette palette;
  final Color primary;

  const _StoryGridCard({
    required this.story,
    required this.isSelected,
    required this.selecting,
    required this.onTap,
    required this.onLongPress,
    required this.onDelete,
    required this.onArchive,
    required this.palette,
    required this.primary,
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
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? primary : Colors.transparent,
            width: isSelected ? 2.5 : 0,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: _Thumbnail(story: story, fillParent: true),
            ),
            // Gradient overlay
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
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
              top: 8,
              left: 8,
              child: _TypeBadge(type: story.type, primary: primary),
            ),
            // Selection circle
            if (selecting)
              Positioned(
                top: 8,
                right: 8,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? primary : Colors.white.withValues(alpha: 0.7),
                    border: Border.all(
                      color: isSelected ? primary : Colors.grey,
                      width: 2,
                    ),
                  ),
                  child: isSelected ? const Icon(Icons.check_rounded, color: Colors.white, size: 15) : null,
                ),
              ),
            // Quick actions menu
            if (!selecting)
              Positioned(
                top: 6,
                right: 6,
                child: _QuickActionsMenu(
                  onDelete: onDelete,
                  onArchive: onArchive,
                  palette: palette,
                ),
              ),
            // Bottom stats
            Positioned(
              bottom: 8,
              left: 10,
              right: 10,
              child: Row(
                children: [
                  const Icon(Icons.remove_red_eye_rounded, color: Colors.white70, size: 12),
                  const SizedBox(width: 3),
                  Text(
                    '${story.viewCount}',
                    style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                  if (story.reactions.isNotEmpty) ...[
                    const SizedBox(width: 7),
                    Text(
                      story.reactions.take(2).map((r) => r.emoji).join(),
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    expiringSoon ? '${remaining.inMinutes}m' : '${remaining.inHours}h',
                    style: TextStyle(
                      color: expiringSoon ? Colors.orange : Colors.white54,
                      fontSize: 10,
                      fontWeight: expiringSoon ? FontWeight.w800 : FontWeight.normal,
                    ),
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
  final ThemePalette palette;

  const _ArchiveCard({required this.story, required this.palette});

  @override
  Widget build(BuildContext context) {
    return Stack(
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
          bottom: 6,
          left: 6,
          right: 6,
          child: Text(
            DateFormat('MMM d').format(story.createdAt),
            style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

// ─── Trình hiển thị hình thu nhỏ (Thumbnail) ──────────────────────────────────

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
    final bg2 = Color.lerp(bg, Colors.black, 0.35)!;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: (story.gradientColors?.length ?? 0) >= 2 ? story.gradientColors! : [bg, bg2],
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
        maxLines: 6,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _fallback() => Container(
    color: const Color(0xFF1C1C1E),
    child: const Icon(Icons.image_not_supported_rounded, color: Colors.white24, size: 32),
  );
}

// ─── Badge phân loại Story (TypeBadge) ────────────────────────────────────────

class _TypeBadge extends StatelessWidget {
  final StoryType type;
  final Color primary;

  const _TypeBadge({required this.type, required this.primary});

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = switch (type) {
      StoryType.image => (Icons.image_rounded, 'Ảnh', const Color(0xFF2196F3)),
      StoryType.text => (Icons.text_fields_rounded, 'Text', const Color(0xFF9C27B0)),
      StoryType.video => (Icons.videocam_rounded, 'Video', const Color(0xFFE91E63)),
      StoryType.boomerang => (Icons.loop_rounded, 'Loop', const Color(0xFFFF9800)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
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
  final ThemePalette palette;

  const _MiniStat({
    required this.icon,
    required this.value,
    required this.color,
    required this.palette,
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
            color: palette.textSecondary,
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
  final ThemePalette palette;
  final bool isDestructive;

  const _CardBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.palette,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? Colors.red.shade400 : palette.textSecondary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: isDestructive ? Colors.red.withValues(alpha: 0.08) : palette.surfaceVariant,
          borderRadius: BorderRadius.circular(9),
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

// ─── Menu tác vụ nhanh (Quick Actions) ────────────────────────────────────────

class _QuickActionsMenu extends StatelessWidget {
  final VoidCallback onDelete;
  final VoidCallback onArchive;
  final ThemePalette palette;

  const _QuickActionsMenu({
    required this.onDelete,
    required this.onArchive,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (v) {
        if (v == 'delete') onDelete();
        if (v == 'archive') onArchive();
      },
      color: palette.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.more_vert_rounded, color: Colors.white, size: 16),
      ),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'archive',
          child: Row(
            children: [
              Icon(Icons.archive_rounded, color: palette.textSecondary, size: 18),
              const SizedBox(width: 10),
              Text('Lưu trữ', style: TextStyle(color: palette.textPrimary, fontSize: 14)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_rounded, color: Colors.redAccent, size: 18),
              const SizedBox(width: 10),
              Text('Xóa', style: TextStyle(color: Colors.redAccent, fontSize: 14)),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Thanh công cụ lựa chọn (Selection Bar) ───────────────────────────────────

class _SelectionBar extends StatelessWidget {
  final int count;
  final ThemePalette palette;
  final Color primary;
  final VoidCallback onDelete;
  final VoidCallback onArchive;
  final VoidCallback onCancel;

  const _SelectionBar({
    required this.count,
    required this.palette,
    required this.primary,
    required this.onDelete,
    required this.onArchive,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: palette.surface,
          border: Border(top: BorderSide(color: palette.divider, width: 0.5)),
        ),
        child: Row(
          children: [
            TextButton.icon(
              onPressed: onCancel,
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text('Hủy'),
              style: TextButton.styleFrom(foregroundColor: Colors.grey),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: onArchive,
              icon: const Icon(Icons.archive_rounded, size: 16),
              label: const Text('Lưu trữ'),
              style: OutlinedButton.styleFrom(
                foregroundColor: palette.textSecondary,
                side: BorderSide(color: palette.divider),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_rounded, size: 16),
              label: Text('Xóa $count'),
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
  final Color primary;
  final ThemePalette palette;

  const _EmptyState({
    required this.onAdd,
    required this.primary,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [primary, primary.withValues(alpha: 0.6)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: primary.withValues(alpha: 0.3),
                    blurRadius: 28,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(Icons.auto_stories_rounded, size: 50, color: Colors.white),
            ),
            const SizedBox(height: 24),
            Text(
              'Chưa có Story nào',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: palette.textPrimary, letterSpacing: -0.5),
            ),
            const SizedBox(height: 10),
            Text(
              'Chia sẻ những khoảnh khắc biến mất sau 24 giờ — ảnh, video hoặc text.',
              style: TextStyle(
                fontSize: 14,
                color: palette.textSecondary,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Tạo story đầu tiên', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Shimmer Loading Card ─────────────────────────────────────────────────────

class _ShimmerCard extends StatefulWidget {
  final ThemePalette palette;
  const _ShimmerCard({required this.palette});

  @override
  State<_ShimmerCard> createState() => _ShimmerCardState();
}

class _ShimmerCardState extends State<_ShimmerCard> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);
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
        final c = Color.lerp(widget.palette.surface, widget.palette.surfaceVariant, _anim.value)!;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: widget.palette.surface,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Container(
                width: 76,
                height: 100,
                decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(12)),
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