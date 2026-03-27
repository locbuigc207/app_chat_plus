// lib/pages/my_stories_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/pages/story_creator_page.dart';
import 'package:flutter_chat_demo/pages/story_viewer_page.dart';
import 'package:flutter_chat_demo/providers/story_provider.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class MyStoriesPage extends StatelessWidget {
  final String userId;
  final String userName;
  final String userPhotoUrl;

  const MyStoriesPage({
    super.key,
    required this.userId,
    required this.userName,
    required this.userPhotoUrl,
  });

  void _openCreator(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoryCreatorPage(
          userId: userId,
          userName: userName,
          userPhotoUrl: userPhotoUrl,
        ),
      ),
    );
  }

  void _openViewer(BuildContext context, List<Story> stories, int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoryViewerPage(
          allUserStories: [
            UserStories(
              userId: userId,
              userName: userName,
              userPhotoUrl: userPhotoUrl,
              stories: stories,
              isCurrentUser: true,
            ),
          ],
          initialUserIndex: 0,
          currentUserId: userId,
          currentUserName: userName,
          currentUserPhotoUrl: userPhotoUrl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Status',
            style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'New Status',
            onPressed: () => _openCreator(context),
          ),
        ],
      ),
      body: StreamBuilder<List<Story>>(
        stream: context.read<StoryProvider>().getMyStoriesStream(userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final stories = snapshot.data ?? [];

          if (stories.isEmpty) {
            return _EmptyState(onAdd: () => _openCreator(context));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: stories.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) => _StoryCard(
              story: stories[i],
              onView: () => _openViewer(context, stories, i),
              onDelete: () async {
                final ok = await _confirmDelete(context);
                if (ok) {
                  // ignore: use_build_context_synchronously
                  await context
                      .read<StoryProvider>()
                      .deleteStory(stories[i].id);
                }
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCreator(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Status'),
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Story'),
        content: const Text('This story will be permanently deleted.'),
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
    return ok == true;
  }
}

// ── Empty state ───────────────────────────────────────────────

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
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.auto_stories_outlined,
                  size: 48, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(height: 24),
            const Text('No Status Yet',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              'Share a photo or text — it disappears after 24 hours',
              style: TextStyle(
                  fontSize: 14, color: Colors.grey.shade500, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Create Status'),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Story card ────────────────────────────────────────────────

class _StoryCard extends StatelessWidget {
  final Story story;
  final VoidCallback onView;
  final VoidCallback onDelete;

  const _StoryCard({
    required this.story,
    required this.onView,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final remaining = story.remainingTime;
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes % 60;
    final expiringSoon = hours < 2;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).dividerColor, width: 0.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onView,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: _Thumbnail(story: story),
              ),

              const SizedBox(width: 14),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _TypeBadge(type: story.type),
                        const Spacer(),
                        Icon(Icons.access_time,
                            size: 13, color: Colors.grey.shade500),
                        const SizedBox(width: 3),
                        Text(
                          hours > 0
                              ? '${hours}h ${minutes}m left'
                              : '${minutes}m left',
                          style: TextStyle(
                            fontSize: 12,
                            color: expiringSoon
                                ? Colors.orange
                                : Colors.grey.shade500,
                            fontWeight: expiringSoon
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      story.type == StoryType.text
                          ? (story.textContent ?? '')
                          : (story.caption ?? 'Photo'),
                      style: Theme.of(context).textTheme.bodyMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.remove_red_eye_outlined,
                            size: 14, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Text(
                          '${story.viewCount} view${story.viewCount != 1 ? 's' : ''}',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade500),
                        ),
                        const Spacer(),
                        Text(
                          DateFormat('HH:mm').format(story.createdAt),
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade400),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Delete
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: Colors.redAccent, size: 20),
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

class _Thumbnail extends StatelessWidget {
  final Story story;
  const _Thumbnail({required this.story});

  @override
  Widget build(BuildContext context) {
    const sz = 68.0;

    if (story.type == StoryType.image && story.mediaUrl != null) {
      return Image.network(
        story.mediaUrl!,
        width: sz,
        height: sz,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallback(sz),
      );
    }

    final bg = story.backgroundColor ?? const Color(0xFF1A1A2E);
    return Container(
      width: sz,
      height: sz,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [bg, Color.lerp(bg, Colors.black, 0.35)!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(4),
      child: Text(
        story.textContent ?? '',
        style: TextStyle(
          color: story.textColor ?? Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
        textAlign: TextAlign.center,
        maxLines: 3,
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
    final isImage = type == StoryType.image;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isImage ? Icons.image : Icons.text_fields,
            size: 12,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 4),
          Text(
            isImage ? 'Photo' : 'Text',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
