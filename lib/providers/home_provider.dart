import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/constants/firestore_constants.dart';
import 'package:flutter_chat_demo/services/database_optimizer.dart';

enum SearchType {
  nickname,
  phoneNumber,
  qrCode,
}

class HomeProvider {
  final FirebaseFirestore firebaseFirestore;

  HomeProvider({required this.firebaseFirestore});

  Future<void> updateDataFirestore(
    String collectionPath,
    String path,
    Map<String, String> dataNeedUpdate,
  ) {
    return firebaseFirestore
        .collection(collectionPath)
        .doc(path)
        .update(dataNeedUpdate);
  }

  Stream<QuerySnapshot> getStreamFireStore(
    String pathCollection,
    int limit,
    String? textSearch,
  ) {
    if (textSearch?.isNotEmpty == true) {
      return firebaseFirestore
          .collection(pathCollection)
          .limit(limit)
          .where(FirestoreConstants.nickname, isEqualTo: textSearch)
          .snapshots();
    } else {
      return firebaseFirestore
          .collection(pathCollection)
          .limit(limit)
          .snapshots();
    }
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

    if (result.docs.isNotEmpty) {
      return result.docs.first;
    }
    return null;
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
}

class HomeProviderOptimized {
  final FirebaseFirestore firebaseFirestore;
  final DatabaseOptimizer _optimizer = DatabaseOptimizer();

  HomeProviderOptimized({required this.firebaseFirestore});

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
        .map((snapshot) => snapshot.docs);
  }

  Future<Map<String, DocumentSnapshot>> batchLoadUserProfiles(
    List<String> userIds,
  ) async {
    final results = await _optimizer.batchGet(
      collection: FirestoreConstants.pathUserCollection,
      docIds: userIds,
    );
    return {
      for (final doc in results) doc.id: doc,
    };
  }

  Stream<QuerySnapshot> searchUsersOptimized(
    String searchTerm,
    int limit,
  ) {
    final query = searchTerm.trim();
    if (query.isEmpty) {
      return Stream.value(
        MockQuerySnapshot(docs: []),
      );
    }
    final isPhoneNumber = RegExp(r'^[+\d][\d\s-]*$').hasMatch(query);
    if (isPhoneNumber) {
      return firebaseFirestore
          .collection(FirestoreConstants.pathUserCollection)
          .where(FirestoreConstants.phoneNumber, isEqualTo: query)
          .limit(limit)
          .snapshots();
    } else {
      return firebaseFirestore
          .collection(FirestoreConstants.pathUserCollection)
          .where(FirestoreConstants.nickname, isGreaterThanOrEqualTo: query)
          .where(FirestoreConstants.nickname,
              isLessThanOrEqualTo: '$query\uf8ff')
          .limit(limit)
          .snapshots();
    }
  }

  Future<void> updateDataFirestoreOptimistic(
    String collectionPath,
    String docId,
    Map<String, dynamic> data,
  ) async {
    _optimizer.clearCacheEntry(collectionPath, docId);
    try {
      await firebaseFirestore
          .collection(collectionPath)
          .doc(docId)
          .update(data);
    } catch (e) {
      print('❌ Update failed: $e');
      rethrow;
    }
  }

  Map<String, dynamic> getCacheStats() {
    return _optimizer.getCacheStats();
  }

  void clearCache() {
    _optimizer.clearCache();
  }
}

class MockQuerySnapshot implements QuerySnapshot {
  @override
  final List<QueryDocumentSnapshot> docs;

  MockQuerySnapshot({required this.docs});

  @override
  List<DocumentChange> get docChanges => [];

  @override
  SnapshotMetadata get metadata => MockSnapshotMetadata();

  @override
  int get size => docs.length;
}

class MockSnapshotMetadata implements SnapshotMetadata {
  @override
  bool get hasPendingWrites => false;

  @override
  bool get isFromCache => false;
}
