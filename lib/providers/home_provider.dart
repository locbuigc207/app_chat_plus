import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/constants/firestore_constants.dart';
import 'package:flutter_chat_demo/models/models.dart';

enum SearchType { nickname, phoneNumber, qrCode, email }

// ─────────────────────────────────────────────────────────────────────────────
// HOME PROVIDER
// ─────────────────────────────────────────────────────────────────────────────

/// Central data-access layer for the Home screen.
class HomeProvider {
  final FirebaseFirestore firebaseFirestore;

  HomeProvider({required this.firebaseFirestore});

  // ─── Generic Firestore ────────────────────────────────────────────────────

  Future<void> updateDataFirestore(
    String collectionPath,
    String path,
    Map<String, dynamic> dataNeedUpdate,
  ) {
    return firebaseFirestore
        .collection(collectionPath)
        .doc(path)
        .update(dataNeedUpdate);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BATCH FETCH
  // ─────────────────────────────────────────────────────────────────────────

  /// Fetches multiple user profiles in as few Firestore round-trips as
  /// possible (chunks of 10 to stay under the `whereIn` limit on older SDKs).
  /// Returns a Map keyed by userId so callers can do O(1) cache lookups.
  Future<Map<String, UserChat>> batchFetchUserChats(
    List<String> userIds,
  ) async {
    if (userIds.isEmpty) return {};

    final result = <String, UserChat>{};
    const chunkSize = 10;

    try {
      for (int i = 0; i < userIds.length; i += chunkSize) {
        final chunk = userIds.sublist(
          i,
          (i + chunkSize).clamp(0, userIds.length),
        );
        final snap = await firebaseFirestore
            .collection(FirestoreConstants.pathUserCollection)
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final doc in snap.docs) {
          result[doc.id] = UserChat.fromDocument(doc);
        }
      }
    } catch (e) {
      debugPrint('❌ [HomeProvider] batchFetchUserChats: $e');
    }

    return result;
  }

  /// Fetches multiple group profiles in batches.
  /// Returns a Map keyed by groupId.
  Future<Map<String, Group>> batchFetchGroups(List<String> groupIds) async {
    if (groupIds.isEmpty) return {};

    final result = <String, Group>{};
    const chunkSize = 10;

    try {
      for (int i = 0; i < groupIds.length; i += chunkSize) {
        final chunk = groupIds.sublist(
          i,
          (i + chunkSize).clamp(0, groupIds.length),
        );
        final snap = await firebaseFirestore
            .collection(FirestoreConstants.pathGroupCollection)
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final doc in snap.docs) {
          result[doc.id] = Group.fromDocument(doc);
        }
      }
    } catch (e) {
      debugPrint('❌ [HomeProvider] batchFetchGroups: $e');
    }

    return result;
  }

  // ─── User Search ──────────────────────────────────────────────────────────

  /// Legacy exact-match stream (kept for backwards compat).
  Stream<QuerySnapshot> getStreamFireStore(
    String pathCollection,
    int limit,
    String? textSearch,
  ) {
    if (textSearch?.isNotEmpty == true) {
      return firebaseFirestore
          .collection(pathCollection)
          .where(FirestoreConstants.nickname, isEqualTo: textSearch)
          .limit(limit)
          .snapshots();
    }
    return firebaseFirestore
        .collection(pathCollection)
        .limit(limit)
        .snapshots();
  }

  /// Phone-number exact search.
  Stream<QuerySnapshot> searchByPhoneNumber(String phoneNumber, int limit) {
    return firebaseFirestore
        .collection(FirestoreConstants.pathUserCollection)
        .where(FirestoreConstants.phoneNumber, isEqualTo: phoneNumber)
        .limit(limit)
        .snapshots();
  }

  /// QR code lookup — returns the first matching document or null.
  Future<DocumentSnapshot?> searchByQRCode(String qrCode) async {
    final result = await firebaseFirestore
        .collection(FirestoreConstants.pathUserCollection)
        .where(FirestoreConstants.qrCode, isEqualTo: qrCode)
        .limit(1)
        .get();
    return result.docs.isNotEmpty ? result.docs.first : null;
  }

  /// Typed search with explicit field selection.
  Stream<QuerySnapshot> searchUsers(
    String searchText,
    SearchType searchType,
    int limit,
  ) {
    if (searchText.isEmpty) {
      return firebaseFirestore
          .collection(FirestoreConstants.pathUserCollection)
          .limit(limit)
          .snapshots();
    }

    final fieldName = switch (searchType) {
      SearchType.phoneNumber => FirestoreConstants.phoneNumber,
      SearchType.qrCode => FirestoreConstants.qrCode,
      SearchType.email => 'email',
      SearchType.nickname => FirestoreConstants.nickname,
    };

    return firebaseFirestore
        .collection(FirestoreConstants.pathUserCollection)
        .where(fieldName, isEqualTo: searchText)
        .limit(limit)
        .snapshots();
  }

  /// Prefix (starts-with) search for nickname; auto-detects phone numbers.
  /// Used by the home search bar for real-time filtering.
  Stream<QuerySnapshot> searchUsersByPrefix(String prefix, int limit) {
    final trimmed = prefix.trim();
    if (trimmed.isEmpty) {
      return firebaseFirestore
          .collection(FirestoreConstants.pathUserCollection)
          .limit(limit)
          .snapshots();
    }

    if (RegExp(r'^[+\d][\d\s-]*$').hasMatch(trimmed)) {
      return firebaseFirestore
          .collection(FirestoreConstants.pathUserCollection)
          .where(FirestoreConstants.phoneNumber, isEqualTo: trimmed)
          .limit(limit)
          .snapshots();
    }

    return firebaseFirestore
        .collection(FirestoreConstants.pathUserCollection)
        .where(FirestoreConstants.nickname, isGreaterThanOrEqualTo: trimmed)
        .where(
          FirestoreConstants.nickname,
          isLessThanOrEqualTo: '$trimmed\uf8ff',
        )
        .orderBy(FirestoreConstants.nickname)
        .limit(limit)
        .snapshots();
  }

  /// Advanced search that queries both nickname (prefix) and phone (exact)
  /// simultaneously and merges the results — deduped by document ID.
  Future<List<DocumentSnapshot>> searchUsersAdvanced(
    String query, {
    int limit = 20,
    String? excludeUserId,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final isPhone = RegExp(r'^[+\d][\d\s-]*$').hasMatch(trimmed);

    try {
      if (isPhone) {
        final snap = await firebaseFirestore
            .collection(FirestoreConstants.pathUserCollection)
            .where(FirestoreConstants.phoneNumber, isEqualTo: trimmed)
            .limit(limit)
            .get();
        return snap.docs
            .where((d) => d.id != excludeUserId)
            .take(limit)
            .toList();
      }

      // Nickname prefix query
      final nickSnap = await firebaseFirestore
          .collection(FirestoreConstants.pathUserCollection)
          .where(FirestoreConstants.nickname, isGreaterThanOrEqualTo: trimmed)
          .where(
            FirestoreConstants.nickname,
            isLessThanOrEqualTo: '$trimmed\uf8ff',
          )
          .limit(limit)
          .get();

      final seen = <String>{};
      final merged = <DocumentSnapshot>[];

      for (final doc in nickSnap.docs) {
        if (doc.id != excludeUserId && seen.add(doc.id)) {
          merged.add(doc);
        }
      }

      return merged.take(limit).toList();
    } catch (e) {
      debugPrint('❌ [HomeProvider] searchUsersAdvanced: $e');
      return [];
    }
  }

  // ─── User Profile ─────────────────────────────────────────────────────────

  Future<DocumentSnapshot?> getUserProfile(String userId) async {
    try {
      final doc = await firebaseFirestore
          .collection(FirestoreConstants.pathUserCollection)
          .doc(userId)
          .get();
      return doc.exists ? doc : null;
    } catch (e) {
      debugPrint('❌ [HomeProvider] getUserProfile: $e');
      return null;
    }
  }

  Stream<DocumentSnapshot> watchUserProfile(String userId) {
    return firebaseFirestore
        .collection(FirestoreConstants.pathUserCollection)
        .doc(userId)
        .snapshots();
  }

  Future<void> updateUserProfile(
    String userId,
    Map<String, dynamic> data,
  ) async {
    try {
      await firebaseFirestore
          .collection(FirestoreConstants.pathUserCollection)
          .doc(userId)
          .update({
            ...data,
            'updatedAt': DateTime.now().millisecondsSinceEpoch.toString(),
          });
    } catch (e) {
      debugPrint('❌ [HomeProvider] updateUserProfile: $e');
      rethrow;
    }
  }

  /// Batch-fetch raw DocumentSnapshots — kept for legacy callers.
  Future<Map<String, DocumentSnapshot>> batchGetUserProfiles(
    List<String> userIds,
  ) async {
    if (userIds.isEmpty) return {};

    try {
      final chunks = <List<String>>[];
      for (int i = 0; i < userIds.length; i += 10) {
        chunks.add(userIds.sublist(i, (i + 10).clamp(0, userIds.length)));
      }

      final results = <DocumentSnapshot>[];
      for (final chunk in chunks) {
        final snap = await firebaseFirestore
            .collection(FirestoreConstants.pathUserCollection)
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        results.addAll(snap.docs);
      }

      return {for (final doc in results) doc.id: doc};
    } catch (e) {
      debugPrint('❌ [HomeProvider] batchGetUserProfiles: $e');
      return {};
    }
  }

  // ─── Suggested Users ("People you may know") ─────────────────────────────

  /// Returns up to [limit] users who are NOT yet friends with [userId].
  /// Strategy: fetch recently-joined users and exclude known friend IDs.
  Future<List<UserChat>> getSuggestedUsers({
    required String userId,
    required List<String> friendIds,
    int limit = 8,
  }) async {
    try {
      final excluded = {...friendIds, userId};
      final snap = await firebaseFirestore
          .collection(FirestoreConstants.pathUserCollection)
          .orderBy('createdAt', descending: true)
          .limit(limit + excluded.length) // over-fetch then filter
          .get();

      return snap.docs
          .where((d) => !excluded.contains(d.id))
          .take(limit)
          .map(UserChat.fromDocument)
          .toList();
    } catch (e) {
      debugPrint('❌ [HomeProvider] getSuggestedUsers: $e');
      return [];
    }
  }

  // ─── Online Presence ──────────────────────────────────────────────────────

  /// Sets online/offline status AND updates lastSeen in a single Firestore
  /// write to minimise billing.
  Future<void> setPresence(String userId, {required bool isOnline}) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch.toString();
      final data = isOnline
          ? {'isOnline': true, 'lastSeen': now}
          : {'isOnline': false, 'lastSeen': now};
      await firebaseFirestore
          .collection(FirestoreConstants.pathUserCollection)
          .doc(userId)
          .update(data);
    } catch (e) {
      debugPrint('❌ [HomeProvider] setPresence: $e');
    }
  }

  /// Convenience wrappers kept for backwards compat.
  Future<void> setOnlineStatus(String userId, bool isOnline) =>
      setPresence(userId, isOnline: isOnline);

  Stream<bool> watchOnlineStatus(String userId) {
    return firebaseFirestore
        .collection(FirestoreConstants.pathUserCollection)
        .doc(userId)
        .snapshots()
        .map((s) => s.data()?['isOnline'] as bool? ?? false);
  }

  // ─── Conversations ────────────────────────────────────────────────────────

  /// Real-time paginated conversation stream ordered by pinned then recency.
  ///
  /// [SỬA LỖI BUG #12]:
  /// LƯU Ý BẮT BUỘC: Query này ĐÒI HỎI phải tạo Composite Index trong Firestore.
  /// Mở Firebase Console -> Firestore -> Indexes -> Composite, rồi thêm:
  /// Collection: `conversations`
  /// Fields:
  ///   - `participants` (Arrays)
  ///   - `isPinned` (Descending)
  ///   - `lastMessageTime` (Descending)
  ///
  /// Hoặc click vào link đính kèm trong Firebase log console báo lỗi `FAILED_PRECONDITION`.
  Stream<List<QueryDocumentSnapshot>> getConversationsOptimized(
    String userId, {
    int limit = 20,
  }) {
    return firebaseFirestore
        .collection(FirestoreConstants.pathConversationCollection)
        .where('participants', arrayContains: userId)
        .orderBy('isPinned', descending: true)
        .orderBy('lastMessageTime', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs);
  }

  /// Returns the total number of unread conversations for a user.
  Stream<int> watchUnreadConversationCount(String userId) {
    return firebaseFirestore
        .collection(FirestoreConstants.pathConversationCollection)
        .where('participants', arrayContains: userId)
        // [FIX P0]: Xóa .where('unreadCount', isGreaterThan: 0) và lọc client-side an toàn
        .snapshots()
        .map((snapshot) {
          int unreadConversations = 0;
          for (final doc in snapshot.docs) {
            final data = doc.data() as Map<String, dynamic>? ?? {};
            final rawUnread = data['unreadCount'];

            if (rawUnread is int) {
              if (rawUnread > 0) unreadConversations++;
            } else if (rawUnread is Map) {
              final userUnread = rawUnread[userId];
              if (userUnread is int && userUnread > 0) {
                unreadConversations++;
              }
            }
          }
          return unreadConversations;
        });
  }

  // ─── Groups ───────────────────────────────────────────────────────────────

  /// Fetches a single group document.
  Future<Group?> getGroup(String groupId) async {
    try {
      final doc = await firebaseFirestore
          .collection(FirestoreConstants.pathGroupCollection)
          .doc(groupId)
          .get();
      return doc.exists ? Group.fromDocument(doc) : null;
    } catch (e) {
      debugPrint('❌ [HomeProvider] getGroup: $e');
      return null;
    }
  }

  Stream<Group?> watchGroup(String groupId) {
    return firebaseFirestore
        .collection(FirestoreConstants.pathGroupCollection)
        .doc(groupId)
        .snapshots()
        .map((d) => d.exists ? Group.fromDocument(d) : null);
  }

  // ─── Stories helpers ──────────────────────────────────────────────────────

  /// Removes expired stories (older than 24 h) for a given user.
  Future<void> pruneExpiredStories(String userId) async {
    final cutoff = DateTime.now()
        .subtract(const Duration(hours: 24))
        .millisecondsSinceEpoch;
    try {
      final snap = await firebaseFirestore
          .collection(FirestoreConstants.pathStoryCollection)
          .where(FirestoreConstants.userId1, isEqualTo: userId)
          .where('createdAt', isLessThan: cutoff)
          .get();

      final batch = firebaseFirestore.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      if (snap.docs.isNotEmpty) await batch.commit();
    } catch (e) {
      debugPrint('❌ [HomeProvider] pruneExpiredStories: $e');
    }
  }
}
