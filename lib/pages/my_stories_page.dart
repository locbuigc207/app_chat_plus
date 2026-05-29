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

class _MyStoriesPageState extends State<MyStoriesPage> {
  bool _gridView = false;
  final Set<String> _selected = {};
  bool _selecting = false;

  void _openCreator() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoryCreatorPage(
          userId: widget.userId,
          userName: widget.userName,
          userPhotoUrl: widget.userPhotoUrl,
        ),
      ),
    );
  }

  void _openViewer(List<Story> stories, int startIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoryViewerPage(
          allUserStories: [
            UserStories(
              userId: widget.userId,
              userName: widget.userName,
              userPhotoUrl: widget.userPhotoUrl,
              stories: stories,
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
        'Delete $count status${count > 1 ? 'es' : ''}?', 'This cannot be undone.');
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🗑️ Deleted $count status${count > 1 ? 'es' : ''}'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<bool> _confirmDelete(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(title),
        content: Text(body),
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
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _buildAppBar(),
      body: StreamBuilder<List<Story>>(
        stream: context.read<StoryProvider>().getMyStoriesStream(widget.userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final stories = snapshot.data ?? [];

          if (stories.isEmpty) {
            return _EmptyState(onAdd: _openCreator);
          }

          final totalViews = stories.fold<int>(0, (sum, s) => sum + s.viewCount);
          final totalReactions = stories.fold<int>(0, (sum, s) => sum + s.reactions.length);

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _StatsRow(
                  storyCount: stories.length,
                  totalViews: totalViews,
                  totalReactions: totalReactions,
                ),
              ),
              if (_gridView)
                SliverPadding(
                  padding: const EdgeInsets.all(12),
                  sliver: SliverGrid(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => _StoryGridCard(
                        story: stories[i],
                        isSelected: _selected.contains(stories[i].id),
                        selecting: _selecting,
                        onTap: () =>
                            _selecting ? _toggleSelect(stories[i].id) : _openViewer(stories, i),
                        onLongPress: () => _selecting
                            ? _toggleSelect(stories[i].id)
                            : _startSelecting(stories[i].id),
                        onDelete: () async {
                          final ok =
                              await _confirmDelete('Delete status?', 'This cannot be undone.');
                          if (ok && mounted) {
                            await context.read<StoryProvider>().deleteStory(stories[i].id);
                          }
                        },
                      ),
                      childCount: stories.length,
                    ),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 0.72,
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _StoryListCard(
                          story: stories[i],
                          isSelected: _selected.contains(stories[i].id),
                          selecting: _selecting,
                          onTap: () =>
                              _selecting ? _toggleSelect(stories[i].id) : _openViewer(stories, i),
                          onLongPress: () => _selecting
                              ? _toggleSelect(stories[i].id)
                              : _startSelecting(stories[i].id),
                          onDelete: () async {
                            final ok =
                                await _confirmDelete('Delete status?', 'This cannot be undone.');
                            if (ok && mounted) {
                              await context.read<StoryProvider>().deleteStory(stories[i].id);
                            }
                          },
                        ),
                      ),
                      childCount: stories.length,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: _selecting
          ? null
          : FloatingActionButton.extended(
              onPressed: _openCreator,
              icon: const Icon(Icons.add),
              label: const Text('Add Status'),
              elevation: 4,
            ),
      bottomNavigationBar: _selecting && _selected.isNotEmpty
          ? _SelectionBar(
              count: _selected.length,
              onDelete: _deleteSelected,
              onCancel: () => setState(() {
                _selected.clear();
                _selecting = false;
              }),
            )
          : null,
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      elevation: 0,
      title: _selecting
          ? Text('${_selected.length} selected',
              style: const TextStyle(fontWeight: FontWeight.w700))
          : const Text('My Status', style: TextStyle(fontWeight: FontWeight.w800)),
      actions: [
        if (!_selecting) ...[
          IconButton(
            icon: Icon(_gridView ? Icons.list : Icons.grid_view),
            tooltip: _gridView ? 'List view' : 'Grid view',
            onPressed: () => setState(() => _gridView = !_gridView),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'New Status',
            onPressed: _openCreator,
          ),
        ] else ...[
          TextButton(
            onPressed: () => setState(() {
              _selected.clear();
              _selecting = false;
            }),
            child: const Text('Cancel'),
          ),
        ],
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  final int storyCount;
  final int totalViews;
  final int totalReactions;

  const _StatsRow({
    required this.storyCount,
    required this.totalViews,
    required this.totalReactions,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primary.withValues(alpha: 0.12),
            scheme.secondary.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          _StatItem(
            value: storyCount.toString(),
            label: 'Status',
            icon: Icons.auto_stories,
            color: scheme.primary,
          ),
          _divider(),
          _StatItem(
            value: totalViews.toString(),
            label: 'Views',
            icon: Icons.remove_red_eye_outlined,
            color: Colors.blue,
          ),
          _divider(),
          _StatItem(
            value: totalReactions.toString(),
            label: 'Reactions',
            icon: Icons.emoji_emotions_outlined,
            color: Colors.orange,
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 40,
        color: Colors.grey.withValues(alpha: 0.2),
        margin: const EdgeInsets.symmetric(horizontal: 8),
      );
}

class _StatItem extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;

  const _StatItem({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}

class _StoryListCard extends StatelessWidget {
  final Story story;
  final bool isSelected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onDelete;

  const _StoryListCard({
    required this.story,
    required this.isSelected,
    required this.selecting,
    required this.onTap,
    required this.onLongPress,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final remaining = story.remainingTime;
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes % 60;
    final expiringSoon = hours < 2;
    final scheme = Theme.of(context).colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isSelected ? scheme.primary : Theme.of(context).dividerColor,
          width: isSelected ? 2 : 0.5,
        ),
        color: isSelected ? scheme.primary.withValues(alpha: 0.08) : Theme.of(context).cardColor,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _Thumbnail(story: story),
                  ),
                  if (selecting)
                    Positioned(
                      top: 2,
                      right: 2,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected ? scheme.primary : Colors.white70,
                          border: Border.all(
                            color: isSelected ? scheme.primary : Colors.grey,
                            width: 2,
                          ),
                        ),
                        child: isSelected
                            ? const Icon(Icons.check, color: Colors.white, size: 14)
                            : null,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _TypeBadge(type: story.type),
                        const Spacer(),
                        Icon(Icons.access_time, size: 12, color: Colors.grey.shade500),
                        const SizedBox(width: 3),
                        Text(
                          hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m',
                          style: TextStyle(
                            fontSize: 11,
                            color: expiringSoon ? Colors.orange : Colors.grey.shade500,
                            fontWeight: expiringSoon ? FontWeight.w700 : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      story.type == StoryType.text
                          ? (story.textContent ?? '')
                          : (story.caption?.isNotEmpty == true
                              ? story.caption!
                              : story.type == StoryType.video
                                  ? '🎥 Video'
                                  : '📸 Photo'),
                      style: Theme.of(context).textTheme.bodyMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _MiniStat(
                          icon: Icons.remove_red_eye_outlined,
                          value: story.viewCount,
                          color: Colors.blue,
                        ),
                        const SizedBox(width: 12),
                        _MiniStat(
                          icon: Icons.emoji_emotions_outlined,
                          value: story.reactions.length,
                          color: Colors.orange,
                        ),
                        const Spacer(),
                        Text(
                          DateFormat('HH:mm').format(story.createdAt),
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!selecting)
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                  onPressed: onDelete,
                  tooltip: 'Delete',
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StoryGridCard extends StatelessWidget {
  final Story story;
  final bool isSelected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onDelete;

  const _StoryGridCard({
    required this.story,
    required this.isSelected,
    required this.selecting,
    required this.onTap,
    required this.onLongPress,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final remaining = story.remainingTime;
    final expiringSoon = remaining.inHours < 2;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? scheme.primary : Colors.transparent,
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
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.65),
                    ],
                    stops: const [0.5, 1.0],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 10,
              left: 10,
              child: _TypeBadge(type: story.type),
            ),
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
                    color: isSelected ? scheme.primary : Colors.white60,
                    border: Border.all(color: isSelected ? scheme.primary : Colors.grey, width: 2),
                  ),
                  child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 16) : null,
                ),
              ),
            if (!selecting)
              Positioned(
                top: 6,
                right: 6,
                child: GestureDetector(
                  onTap: onDelete,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 14),
                  ),
                ),
              ),
            Positioned(
              bottom: 10,
              left: 10,
              right: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.remove_red_eye_outlined, color: Colors.white70, size: 12),
                      const SizedBox(width: 3),
                      Text(
                        '${story.viewCount}',
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                      const SizedBox(width: 8),
                      if (story.reactions.isNotEmpty) ...[
                        const Text('😊', style: TextStyle(fontSize: 11)),
                        const SizedBox(width: 2),
                        Text(
                          '${story.reactions.length}',
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                      const Spacer(),
                      Text(
                        expiringSoon ? '${remaining.inMinutes}m' : '${remaining.inHours}h',
                        style: TextStyle(
                          color: expiringSoon ? Colors.orange : Colors.white54,
                          fontSize: 10,
                          fontWeight: expiringSoon ? FontWeight.w700 : FontWeight.normal,
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

class _SelectionBar extends StatelessWidget {
  final int count;
  final VoidCallback onDelete;
  final VoidCallback onCancel;

  const _SelectionBar({
    required this.count,
    required this.onDelete,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
        ),
        child: Row(
          children: [
            TextButton.icon(
              onPressed: onCancel,
              icon: const Icon(Icons.close),
              label: const Text('Cancel'),
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: onDelete,
              icon: const Icon(Icons.delete, size: 18),
              label: Text('Delete $count item${count > 1 ? 's' : ''}'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                    Theme.of(context).colorScheme.secondary.withValues(alpha: 0.15),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.auto_stories_outlined,
                size: 50,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'No Status Yet',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              'Share a photo, text, or video — it disappears after 24 hours.',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500, height: 1.6),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 36),
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Create Status'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                elevation: 4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  final Story story;
  final bool fillParent;

  const _Thumbnail({required this.story, this.fillParent = false});

  @override
  Widget build(BuildContext context) {
    const sz = 72.0;

    if (story.type == StoryType.image && story.mediaUrl != null) {
      return Image.network(
        story.mediaUrl!,
        width: fillParent ? double.infinity : sz,
        height: fillParent ? double.infinity : sz,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallback(sz),
      );
    }

    if (story.type == StoryType.video) {
      return Container(
        width: fillParent ? double.infinity : sz,
        height: fillParent ? double.infinity : sz,
        color: Colors.black,
        child: const Center(
          child: Icon(Icons.play_circle_filled, color: Colors.white70, size: 36),
        ),
      );
    }

    final bg = story.backgroundColor ?? const Color(0xFF1A1A2E);
    return Container(
      width: fillParent ? double.infinity : sz,
      height: fillParent ? double.infinity : sz,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [bg, Color.lerp(bg, Colors.black, 0.38)!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(6),
      child: Text(
        story.textContent ?? '',
        style: TextStyle(
          color: story.textColor ?? Colors.white,
          fontSize: fillParent ? 13 : 10,
          fontFamily: story.fontFamily,
          fontWeight: FontWeight.w700,
        ),
        textAlign: TextAlign.center,
        maxLines: fillParent ? 5 : 3,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _fallback(double sz) => Container(
        width: sz,
        height: sz,
        color: Colors.grey.shade200,
        child: const Icon(Icons.image, color: Colors.grey),
      );
}

class _TypeBadge extends StatelessWidget {
  final StoryType type;
  const _TypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = switch (type) {
      StoryType.image => (Icons.image, 'Photo', const Color(0xFF2196F3)),
      StoryType.text => (Icons.text_fields, 'Text', const Color(0xFF9C27B0)),
      StoryType.video => (Icons.videocam, 'Video', const Color(0xFFE91E63)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final int value;
  final Color color;

  const _MiniStat({
    required this.icon,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: Colors.grey.shade500),
        const SizedBox(width: 3),
        Text(
          value.toString(),
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
        ),
      ],
    );
  }
}
