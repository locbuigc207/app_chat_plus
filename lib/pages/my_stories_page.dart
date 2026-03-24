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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.read<StoryProvider>();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'My Status',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Add Status',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => StoryCreatorPage(
                  userId: userId,
                  userName: userName,
                  userPhotoUrl: userPhotoUrl,
                ),
              ),
            ),
          ),
        ],
      ),
      body: StreamBuilder<List<Story>>(
        stream: provider.getMyStoriesStream(userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final stories = snapshot.data ?? [];

          if (stories.isEmpty) {
            return _EmptyMyStories(
              onAdd: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StoryCreatorPage(
                    userId: userId,
                    userName: userName,
                    userPhotoUrl: userPhotoUrl,
                  ),
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: stories.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final story = stories[i];
              return _StoryCard(
                story: story,
                onView: () => Navigator.push(
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
                ),
                onDelete: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Delete Story'),
                      content: const Text('This story will be deleted.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          style:
                              TextButton.styleFrom(foregroundColor: Colors.red),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    await provider.deleteStory(story.id);
                  }
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StoryCreatorPage(
              userId: userId,
              userName: userName,
              userPhotoUrl: userPhotoUrl,
            ),
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Add Status'),
      ),
    );
  }
}

class _EmptyMyStories extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyMyStories({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.auto_stories_outlined,
              size: 52,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'No status yet',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Share a photo or text — it disappears after 24 hours',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Create Status'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
            ),
          ),
        ],
      ),
    );
  }
}

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
    final theme = Theme.of(context);
    final remaining = story.remainingTime;
    final hoursLeft = remaining.inHours;
    final minutesLeft = remaining.inMinutes % 60;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.dividerColor, width: 0.5),
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
                child: _StoryThumbnail(story: story),
              ),

              const SizedBox(width: 14),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _TypeChip(type: story.type),
                        const Spacer(),
                        Icon(Icons.access_time,
                            size: 13, color: Colors.grey.shade500),
                        const SizedBox(width: 3),
                        Text(
                          hoursLeft > 0
                              ? '${hoursLeft}h ${minutesLeft}m left'
                              : '${minutesLeft}m left',
                          style: TextStyle(
                            fontSize: 12,
                            color: hoursLeft < 2
                                ? Colors.orange
                                : Colors.grey.shade500,
                            fontWeight: hoursLeft < 2
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      story.type == StoryType.text
                          ? story.textContent ?? ''
                          : story.caption ?? 'Photo story',
                      style: theme.textTheme.bodyMedium,
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
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          DateFormat('HH:mm').format(story.createdAt),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Actions
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

class _StoryThumbnail extends StatelessWidget {
  final Story story;
  const _StoryThumbnail({required this.story});

  @override
  Widget build(BuildContext context) {
    const size = 70.0;
    if (story.type == StoryType.image && story.mediaUrl != null) {
      return Image.network(
        story.mediaUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallback(size),
      );
    }
    if (story.type == StoryType.text) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              story.backgroundColor ?? const Color(0xFF1A1A2E),
              (story.backgroundColor ?? const Color(0xFF1A1A2E))
                  .withOpacity(0.7),
            ],
          ),
        ),
        child: Center(
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
        ),
      );
    }
    return _fallback(size);
  }

  Widget _fallback(double size) => Container(
        width: size,
        height: size,
        color: Colors.grey.shade200,
        child: const Icon(Icons.image, color: Colors.grey),
      );
}

class _TypeChip extends StatelessWidget {
  final StoryType type;
  const _TypeChip({required this.type});

  @override
  Widget build(BuildContext context) {
    final label = type == StoryType.image ? 'Photo' : 'Text';
    final icon = type == StoryType.image ? Icons.image : Icons.text_fields;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 4),
          Text(
            label,
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
