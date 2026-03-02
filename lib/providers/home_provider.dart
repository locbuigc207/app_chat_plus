import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_chat_demo/constants/firestore_constants.dart';

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

  // NEW: Search by phone number
  Stream<QuerySnapshot> searchByPhoneNumber(String phoneNumber, int limit) {
    return firebaseFirestore
        .collection(FirestoreConstants.pathUserCollection)
        .where(FirestoreConstants.phoneNumber, isEqualTo: phoneNumber)
        .limit(limit)
        .snapshots();
  }

  // NEW: Search by QR code
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

  // NEW: Combined search functions
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
