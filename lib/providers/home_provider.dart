import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/constants/firestore_constants.dart';

enum SearchType { nickname, phoneNumber, qrCode, email }

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

  // ─── User Search ──────────────────────────────────────────────────────────

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

  Stream<QuerySnapshot> searchByPhoneNumber(String phoneNumber, int limit) {
    return firebaseFirestore
        .collection(FirestoreConstants.pathUserCollection)
        .where(FirestoreConstants.phoneNumber, isEqualTo: phoneNumber)
        .limit(limit)
        .snapshots();
  }

  Future<DocumentSnapshot?> searchByQRCode(String qrCode) async {
    final result = await firebaseFirestore
        .collection(FirestoreConstants.pathUserCollection)
        .where(FirestoreConstants.qrCode, isEqualTo: qrCode)
        .limit(1)
        .get();

    return result.docs.isNotEmpty ? result.docs.first : null;
  }

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

    String fieldName;
    switch (searchType) {
      case SearchType.phoneNumber:
        fieldName = FirestoreConstants.phoneNumber;
        break;
      case SearchType.qrCode:
        fieldName = FirestoreConstants.qrCode;
        break;
      case SearchType.email:
        fieldName = 'email';
        break;
      case SearchType.nickname:
      default:
        fieldName = FirestoreConstants.nickname;
        break;
    }

    return firebaseFirestore
        .collection(FirestoreConstants.pathUserCollection)
        .where(fieldName, isEqualTo: searchText)
        .limit(limit)
        .snapshots();
  }

  /// Prefix search for nickname (e.g. "joh" matches "John").
  Stream<QuerySnapshot> searchUsersByPrefix(
    String prefix,
    int limit,
  ) {
    final trimmed = prefix.trim();
    if (trimmed.isEmpty) {
      return firebaseFirestore
          .collection(FirestoreConstants.pathUserCollection)
          .limit(limit)
          .snapshots();
    }

    // Phone number detection
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
        .where(FirestoreConstants.nickname,
            isLessThanOrEqualTo: '$trimmed\uf8ff')
        .limit(limit)
        .snapshots();
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
      print('❌ Error getting user profile: $e');
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
      print('❌ Error updating user profile: $e');
      rethrow;
    }
  }

  Future<Map<String, DocumentSnapshot>> batchGetUserProfiles(
    List<String> userIds,
  ) async {
    if (userIds.isEmpty) return {};

    try {
      // Firestore limits `whereIn` to 30 items
      final chunks = <List<String>>[];
      for (int i = 0; i < userIds.length; i += 30) {
        chunks.add(userIds.sublist(
            i, i + 30 > userIds.length ? userIds.length : i + 30));
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
      print('❌ Error batch loading profiles: $e');
      return {};
    }
  }

  // ─── Online Presence ──────────────────────────────────────────────────────

  Future<void> setOnlineStatus(String userId, bool isOnline) async {
    try {
      await firebaseFirestore
          .collection(FirestoreConstants.pathUserCollection)
          .doc(userId)
          .update({
        'isOnline': isOnline,
        'lastSeen': DateTime.now().millisecondsSinceEpoch.toString(),
      });
    } catch (e) {
      print('❌ Error setting online status: $e');
    }
  }

  Stream<bool> watchOnlineStatus(String userId) {
    return firebaseFirestore
        .collection(FirestoreConstants.pathUserCollection)
        .doc(userId)
        .snapshots()
        .map((snap) => snap.data()?['isOnline'] as bool? ?? false);
  }

  // ─── Conversations (paginated) ────────────────────────────────────────────

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
}
