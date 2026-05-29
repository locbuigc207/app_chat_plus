import 'dart:io';

import 'package:flutter/material.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_chat_demo/models/story_model.dart';

export 'package:flutter_chat_demo/models/story_model.dart';

class StoryProvider extends ChangeNotifier {
  final FirebaseFirestore firebaseFirestore;
  final FirebaseStorage firebaseStorage;

  static const String _col = 'stories';
  static const String _repliesCol = 'story_replies';
  static const Duration _ttl = Duration(hours: 24);

  StoryProvider({
    required this.firebaseFirestore,
    required this.firebaseStorage,
  });

  
  
  

  Stream<List<UserStories>> getStoriesStream({
    required String currentUserId,
    required List<String> friendIds,
  }) {
    final ids = [currentUserId, ...friendIds].take(10).toList();
    if (ids.isEmpty) return Stream.value([]);

    return firebaseFirestore
        .collection(_col)
        .where('userId', whereIn: ids)
        .where('isDeleted', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(_groupAndFilter(currentUserId));
  }

  List<UserStories> Function(QuerySnapshot) _groupAndFilter(String currentUserId) {
    return (QuerySnapshot snapshot) {
      final Map<String, List<Story>> grouped = {};

      for (final doc in snapshot.docs) {
        try {
          final story = Story.fromDocument(doc);
          if (!story.isExpired && !story.isDeleted) {
            grouped.putIfAbsent(story.userId, () => []).add(story);
          }
        } catch (e) {
          debugPrint('⚠️ Error parsing story ${doc.id}: $e');
        }
      }

      final result = grouped.entries.map((entry) {
        final sorted = entry.value..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        final first = sorted.first;
        return UserStories(
          userId: entry.key,
          userName: first.userName,
          userPhotoUrl: first.userPhotoUrl,
          stories: sorted,
          isCurrentUser: entry.key == currentUserId,
        );
      }).toList();

      result.sort((a, b) {
        if (a.isCurrentUser) return -1;
        if (b.isCurrentUser) return 1;
        
        final aUnseen = a.hasUnseenStoriesBy(currentUserId);
        final bUnseen = b.hasUnseenStoriesBy(currentUserId);
        if (aUnseen && !bUnseen) return -1;
        if (!aUnseen && bUnseen) return 1;
        
        final aLatest = a.latestStory?.createdAt ?? DateTime(2000);
        final bLatest = b.latestStory?.createdAt ?? DateTime(2000);
        return bLatest.compareTo(aLatest);
      });

      return result;
    };
  }

  
  
  

  Stream<List<Story>> getMyStoriesStream(String userId) {
    return firebaseFirestore
        .collection(_col)
        .where('userId', isEqualTo: userId)
        .where('isDeleted', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) {
              try {
                return Story.fromDocument(doc);
              } catch (e) {
                debugPrint('⚠️ Error parsing story ${doc.id}: $e');
                return null;
              }
            })
            .whereType<Story>()
            .where((s) => !s.isExpired)
            .toList());
  }

  
  
  

  Future<String?> createImageStory({
    required String userId,
    required String userName,
    required String userPhotoUrl,
    required File imageFile,
    String? caption,
    StoryPrivacy privacy = StoryPrivacy.friends,
  }) async {
    try {
      final fileName = 'stories/${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = firebaseStorage.ref().child(fileName);
      final task = await ref.putFile(
        imageFile,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final mediaUrl = await task.ref.getDownloadURL();

      return _saveDocument(
        userId: userId,
        userName: userName,
        userPhotoUrl: userPhotoUrl,
        type: StoryType.image,
        mediaUrl: mediaUrl,
        caption: caption,
        privacy: privacy,
      );
    } catch (e) {
      debugPrint('❌ createImageStory: $e');
      return null;
    }
  }

  Future<String?> createVideoStory({
    required String userId,
    required String userName,
    required String userPhotoUrl,
    required File videoFile,
    String? caption,
    Duration? videoDuration,
    StoryPrivacy privacy = StoryPrivacy.friends,
  }) async {
    try {
      final fileName = 'stories/${userId}_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final ref = firebaseStorage.ref().child(fileName);
      final task = await ref.putFile(
        videoFile,
        SettableMetadata(contentType: 'video/mp4'),
      );
      final mediaUrl = await task.ref.getDownloadURL();

      return _saveDocument(
        userId: userId,
        userName: userName,
        userPhotoUrl: userPhotoUrl,
        type: StoryType.video,
        mediaUrl: mediaUrl,
        caption: caption,
        privacy: privacy,
        videoDuration: videoDuration,
      );
    } catch (e) {
      debugPrint('❌ createVideoStory: $e');
      return null;
    }
  }

  Future<String?> createTextStory({
    required String userId,
    required String userName,
    required String userPhotoUrl,
    required String textContent,
    required Color backgroundColor,
    required Color textColor,
    String? fontFamily,
    double fontSize = 28.0,
    StoryPrivacy privacy = StoryPrivacy.friends,
  }) async {
    try {
      return _saveDocument(
        userId: userId,
        userName: userName,
        userPhotoUrl: userPhotoUrl,
        type: StoryType.text,
        textContent: textContent,
        backgroundColor: backgroundColor,
        textColor: textColor,
        fontFamily: fontFamily,
        fontSize: fontSize,
        privacy: privacy,
      );
    } catch (e) {
      debugPrint('❌ createTextStory: $e');
      return null;
    }
  }

  Future<String?> _saveDocument({
    required String userId,
    required String userName,
    required String userPhotoUrl,
    required StoryType type,
    String? mediaUrl,
    String? thumbnailUrl,
    String? textContent,
    String? caption,
    Color? backgroundColor,
    Color? textColor,
    String? fontFamily,
    double fontSize = 28.0,
    StoryPrivacy privacy = StoryPrivacy.friends,
    Duration? videoDuration,
  }) async {
    final now = DateTime.now();
    final data = <String, dynamic>{
      'userId': userId,
      'userName': userName,
      'userPhotoUrl': userPhotoUrl,
      'type': type.index,
      'mediaUrl': mediaUrl,
      'thumbnailUrl': thumbnailUrl,
      'textContent': textContent,
      'caption': caption,
      'backgroundColor': backgroundColor?.toARGB32(),
      'textColor': textColor?.toARGB32(),
      'fontFamily': fontFamily,
      'fontSize': fontSize,
      'createdAt': now.millisecondsSinceEpoch.toString(),
      'expiresAt': now.add(_ttl).millisecondsSinceEpoch.toString(),
      'views': <dynamic>[],
      'reactions': <dynamic>[],
      'privacy': privacy.index,
      'isDeleted': false,
      if (videoDuration != null) 'videoDurationMs': videoDuration.inMilliseconds,
    };

    final doc = await firebaseFirestore.collection(_col).add(data);
    debugPrint('✅ Story created: ${doc.id}');
    return doc.id;
  }

  
  
  

  Future<void> markStoryViewed({
    required String storyId,
    required String viewerId,
    required String viewerName,
    required String viewerPhotoUrl,
  }) async {
    try {
      final ref = firebaseFirestore.collection(_col).doc(storyId);
      final snap = await ref.get();
      if (!snap.exists) return;

      final story = Story.fromDocument(snap);
      if (story.userId == viewerId) return;
      if (story.isViewedBy(viewerId)) return;

      final viewData = StoryView(
        userId: viewerId,
        userName: viewerName,
        photoUrl: viewerPhotoUrl,
        viewedAt: DateTime.now(),
      ).toJson();

      await ref.update({
        'views': FieldValue.arrayUnion([viewData]),
      });
    } catch (e) {
      debugPrint('❌ markStoryViewed: $e');
    }
  }

  
  
  

  Future<void> reactToStory({
    required String storyId,
    required String reactorId,
    required String reactorName,
    required String reactorPhotoUrl,
    required String emoji,
  }) async {
    try {
      final ref = firebaseFirestore.collection(_col).doc(storyId);
      final snap = await ref.get();
      if (!snap.exists) return;

      final story = Story.fromDocument(snap);

      
      final existingReaction =
          story.reactions.where((r) => r.userId == reactorId).map((r) => r.toJson()).toList();

      if (existingReaction.isNotEmpty) {
        await ref.update({
          'reactions': FieldValue.arrayRemove(existingReaction),
        });
      }

      final reactionData = StoryReaction(
        userId: reactorId,
        userName: reactorName,
        photoUrl: reactorPhotoUrl,
        emoji: emoji,
        reactedAt: DateTime.now(),
      ).toJson();

      await ref.update({
        'reactions': FieldValue.arrayUnion([reactionData]),
      });
    } catch (e) {
      debugPrint('❌ reactToStory: $e');
    }
  }

  
  
  

  Future<void> replyToStory({
    required String storyId,
    required String senderId,
    required String senderName,
    required String senderPhotoUrl,
    required String message,
  }) async {
    try {
      await firebaseFirestore.collection(_col).doc(storyId).collection(_repliesCol).add({
        'senderId': senderId,
        'senderName': senderName,
        'senderPhotoUrl': senderPhotoUrl,
        'message': message,
        'sentAt': DateTime.now().millisecondsSinceEpoch.toString(),
      });
    } catch (e) {
      debugPrint('❌ replyToStory: $e');
    }
  }

  
  
  

  Future<bool> deleteStory(String storyId) async {
    try {
      await firebaseFirestore.collection(_col).doc(storyId).update({'isDeleted': true});
      return true;
    } catch (e) {
      debugPrint('❌ deleteStory: $e');
      return false;
    }
  }

  
  
  

  Future<void> cleanupExpired(String userId) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch.toString();
      final snap = await firebaseFirestore
          .collection(_col)
          .where('userId', isEqualTo: userId)
          .where('isDeleted', isEqualTo: false)
          .get();

      final batch = firebaseFirestore.batch();
      int count = 0;
      for (final doc in snap.docs) {
        final data = doc.data();
        final expiresAtStr = data['expiresAt'] as String?;
        if (expiresAtStr != null && expiresAtStr.compareTo(now) < 0) {
          batch.update(doc.reference, {'isDeleted': true});
          count++;
        }
      }
      if (count > 0) {
        await batch.commit();
        debugPrint('🧹 Cleaned up $count expired stories');
      }
    } catch (e) {
      debugPrint('❌ cleanupExpired: $e');
    }
  }

  
  
  

  String formatTimeRemaining(Duration d) {
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m remaining';
    if (d.inMinutes > 0) return '${d.inMinutes}m remaining';
    return 'Expiring soon';
  }

  String formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
