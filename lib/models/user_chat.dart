import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_chat_demo/constants/constants.dart';

class UserChat {
  final String id;
  final String photoUrl;
  final String nickname;
  final String aboutMe;
  final String phoneNumber;
  final String qrCode;
  final bool is2FAEnabled;
  final String twoFactorSecret;

  const UserChat({
    required this.id,
    required this.photoUrl,
    required this.nickname,
    required this.aboutMe,
    this.phoneNumber = '',
    this.qrCode = '',
    this.is2FAEnabled = false,
    this.twoFactorSecret = '',
  });

  Map<String, dynamic> toJson() {
    return {
      FirestoreConstants.nickname: nickname,
      FirestoreConstants.aboutMe: aboutMe,
      FirestoreConstants.photoUrl: photoUrl,
      FirestoreConstants.phoneNumber: phoneNumber,
      FirestoreConstants.qrCode: qrCode,
      'is2FAEnabled': is2FAEnabled,
      'twoFactorSecret': twoFactorSecret,
    };
  }

  factory UserChat.fromDocument(DocumentSnapshot doc) {
    String aboutMe = "";
    String photoUrl = "";
    String nickname = "";
    String phoneNumber = "";
    String qrCode = "";
    bool is2FAEnabled = false;
    String twoFactorSecret = "";

    try {
      aboutMe = doc.get(FirestoreConstants.aboutMe);
    } catch (_) {}
    try {
      photoUrl = doc.get(FirestoreConstants.photoUrl);
    } catch (_) {}
    try {
      nickname = doc.get(FirestoreConstants.nickname);
    } catch (_) {}
    try {
      phoneNumber = doc.get(FirestoreConstants.phoneNumber);
    } catch (_) {}
    try {
      qrCode = doc.get(FirestoreConstants.qrCode);
    } catch (_) {}
    try {
      is2FAEnabled = doc.get('is2FAEnabled') ?? false;
    } catch (_) {}
    try {
      twoFactorSecret = doc.get('twoFactorSecret') ?? "";
    } catch (_) {}

    return UserChat(
      id: doc.id,
      photoUrl: photoUrl,
      nickname: nickname,
      aboutMe: aboutMe,
      phoneNumber: phoneNumber,
      qrCode: qrCode,
      is2FAEnabled: is2FAEnabled,
      twoFactorSecret: twoFactorSecret,
    );
  }
}
