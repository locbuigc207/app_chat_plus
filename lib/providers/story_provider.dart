// lib/providers/story_provider.dart
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/models/story_model.dart';

export 'package:flutter_chat_demo/models/story_model.dart';

class StoryProvider extends ChangeNotifier {
  final FirebaseFirestore firebaseFirestore;
  final FirebaseStorage firebaseStorage;

  static const String _storiesCollection = 'stories';
  static const Duration _storyDuration = Duration(hours: 24);

  StoryProvider({
    required this.firebaseFirestore,
    required this.firebaseStorage,
  });

  // ─────────────────────────────────────────────
  // STREAMS
  // ─────────────────────────────────────────────

  /// All active stories from friends + current user, grouped by user
  Stream<List<UserStories>> getStoriesStream({
    required String currentUserId,
    required List<String> friendIds,
  }) {
    final allUserIds = [currentUserId, ...friendIds];

    return firebaseFirestore
        .collection(_storiesCollection)
        .where('userId', whereIn: allUserIds.take(10).toList())
        .where('isDeleted', isEqualTo: false)
        .where('expiresAt',
            isGreaterThan: DateTime.now().millisecondsSinceEpoch.toString())
        .orderBy('expiresAt', descending: false)
        .snapshots()
        .map((snapshot) {
      final Map<String, List<Story>> grouped = {};
      for (final doc in snapshot.docs) {
        final story = Story.fromDocument(doc);
        if (!story.isExpired) {
          grouped.putIfAbsent(story.userId, () => []).add(story);
        }
      }

      final result = grouped.entries.map((entry) {
        final stories = entry.value
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        final first = stories.first;
        return UserStories(
          userId: entry.key,
          userName: first.userName,
          userPhotoUrl: first.userPhotoUrl,
          stories: stories,
          isCurrentUser: entry.key == currentUserId,
        );
      }).toList();

      // Current user first
      result.sort((a, b) {
        if (a.isCurrentUser) return -1;
        if (b.isCurrentUser) return 1;
        return 0;
      });

      return result;
    });
  }

  /// Current user's own stories
  Stream<List<Story>> getMyStoriesStream(String userId) {
    return firebaseFirestore
        .collection(_storiesCollection)
        .where('userId', isEqualTo: userId)
        .where('isDeleted', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Story.fromDocument(doc))
            .where((s) => !s.isExpired)
            .toList());
  }

  // ─────────────────────────────────────────────
  // CREATE STORIES
  // ─────────────────────────────────────────────

  /// Upload image and create image story
  Future<String?> createImageStory({
    required String userId,
    required String userName,
    required String userPhotoUrl,
    required File imageFile,
    String? caption,
    StoryPrivacy privacy = StoryPrivacy.friends,
  }) async {
    try {
      // Upload image to Firebase Storage
      final fileName =
          'stories/${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = firebaseStorage.ref().child(fileName);
      final task = await ref.putFile(imageFile);
      final mediaUrl = await task.ref.getDownloadURL();

      return await _createStoryDocument(
        userId: userId,
        userName: userName,
        userPhotoUrl: userPhotoUrl,
        type: StoryType.image,
        mediaUrl: mediaUrl,
        caption: caption,
        privacy: privacy,
      );
    } catch (e) {
      debugPrint('❌ Error creating image story: $e');
      return null;
    }
  }

  /// Create text-only story
  Future<String?> createTextStory({
    required String userId,
    required String userName,
    required String userPhotoUrl,
    required String textContent,
    required Color backgroundColor,
    required Color textColor,
    String? fontFamily,
    double fontSize = 28.0,
    String? caption,
    StoryPrivacy privacy = StoryPrivacy.friends,
  }) async {
    try {
      return await _createStoryDocument(
        userId: userId,
        userName: userName,
        userPhotoUrl: userPhotoUrl,
        type: StoryType.text,
        textContent: textContent,
        backgroundColor: backgroundColor,
        textColor: textColor,
        fontFamily: fontFamily,
        fontSize: fontSize,
        caption: caption,
        privacy: privacy,
      );
    } catch (e) {
      debugPrint('❌ Error creating text story: $e');
      return null;
    }
  }

  Future<String?> _createStoryDocument({
    required String userId,
    required String userName,
    required String userPhotoUrl,
    required StoryType type,
    String? mediaUrl,
    String? textContent,
    String? caption,
    Color? backgroundColor,
    Color? textColor,
    String? fontFamily,
    double fontSize = 24.0,
    StoryPrivacy privacy = StoryPrivacy.friends,
  }) async {
    final now = DateTime.now();
    final expiresAt = now.add(_storyDuration);

    final data = {
      'userId': userId,
      'userName': userName,
      'userPhotoUrl': userPhotoUrl,
      'type': type.index,
      'mediaUrl': mediaUrl,
      'textContent': textContent,
      'caption': caption,
      'backgroundColor': backgroundColor?.value,
      'textColor': textColor?.value,
      'fontFamily': fontFamily,
      'fontSize': fontSize,
      'createdAt': now.millisecondsSinceEpoch.toString(),
      'expiresAt': expiresAt.millisecondsSinceEpoch.toString(),
      'views': [],
      'privacy': privacy.index,
      'isDeleted': false,
    };

    final doc =
        await firebaseFirestore.collection(_storiesCollection).add(data);
    debugPrint('✅ Story created: ${doc.id}');
    return doc.id;
  }

  // ─────────────────────────────────────────────
  // VIEW TRACKING
  // ─────────────────────────────────────────────

  /// Mark a story as viewed by user
  Future<void> markStoryViewed({
    required String storyId,
    required String viewerId,
    required String viewerName,
    required String viewerPhotoUrl,
  }) async {
    try {
      final storyRef =
          firebaseFirestore.collection(_storiesCollection).doc(storyId);
      final snap = await storyRef.get();
      if (!snap.exists) return;

      final story = Story.fromDocument(snap);

      // Don't track owner's own views
      if (story.userId == viewerId) return;

      // Don't re-add if already viewed
      if (story.isViewedBy(viewerId)) return;

      final viewData = StoryView(
        userId: viewerId,
        userName: viewerName,
        photoUrl: viewerPhotoUrl,
        viewedAt: DateTime.now(),
      ).toJson();

      await storyRef.update({
        'views': FieldValue.arrayUnion([viewData]),
      });
    } catch (e) {
      debugPrint('❌ Error marking story viewed: $e');
    }
  }

  // ─────────────────────────────────────────────
  // DELETE
  // ─────────────────────────────────────────────

  Future<bool> deleteStory(String storyId) async {
    try {
      await firebaseFirestore
          .collection(_storiesCollection)
          .doc(storyId)
          .update({'isDeleted': true});
      return true;
    } catch (e) {
      debugPrint('❌ Error deleting story: $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────
  // CLEANUP (called by Cloud Functions / manually)
  // ─────────────────────────────────────────────

  Future<void> cleanupExpiredStories() async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch.toString();
      final expired = await firebaseFirestore
          .collection(_storiesCollection)
          .where('expiresAt', isLessThanOrEqualTo: now)
          .where('isDeleted', isEqualTo: false)
          .get();

      final batch = firebaseFirestore.batch();
      for (final doc in expired.docs) {
        batch.update(doc.reference, {'isDeleted': true});
      }
      await batch.commit();
      debugPrint('🗑️ Cleaned ${expired.docs.length} expired stories');
    } catch (e) {
      debugPrint('❌ Error cleaning up stories: $e');
    }
  }

  // ─────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────

  String formatTimeRemaining(Duration remaining) {
    if (remaining.inHours > 0) {
      return '${remaining.inHours}h remaining';
    } else if (remaining.inMinutes > 0) {
      return '${remaining.inMinutes}m remaining';
    } else {
      return 'Expiring soon';
    }
  }
}
