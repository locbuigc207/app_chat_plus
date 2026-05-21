import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/e2ee_service.dart';

enum Status {
  uninitialized,
  authenticated,
  authenticating,
  authenticateError,
  authenticateException,
  authenticateCanceled,
}

class AuthProvider extends ChangeNotifier {
  final GoogleSignIn googleSignIn = GoogleSignIn(
    clientId: kIsWeb ? dotenv.env['WEB_CLIENT_ID'] : null,
    scopes: [
      'email',
      'https://www.googleapis.com/auth/contacts.readonly',
    ],
  );
  final FirebaseAuth firebaseAuth;
  final FirebaseFirestore firebaseFirestore;
  final SharedPreferences prefs;

  AuthProvider({
    required this.firebaseAuth,
    required this.prefs,
    required this.firebaseFirestore,
  });

  Status _status = Status.uninitialized;

  Status get status => _status;

  String? get userFirebaseId => prefs.getString(FirestoreConstants.id);

  UserChat? tempUserChat;

  // =========================================================
  // IS LOGGED IN
  // =========================================================

  Future<bool> isLoggedIn() async {
    try {
      final currentUser = firebaseAuth.currentUser;
      if (currentUser != null &&
          prefs.getString(FirestoreConstants.id)?.isNotEmpty == true) {
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  // =========================================================
  // GENERATE QR CODE
  // =========================================================

  String _generateQRCode(String userId) {
    return 'CHATAPP_${userId}_${DateTime.now().millisecondsSinceEpoch}';
  }

  // =========================================================
  // SIGN IN
  // =========================================================

  Future<String> handleSignIn() async {
    _status = Status.authenticating;
    notifyListeners();

    try {
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        _status = Status.authenticateCanceled;
        notifyListeners();
        return 'canceled';
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential =
          await firebaseAuth.signInWithCredential(credential);

      final User? firebaseUser = userCredential.user;

      if (firebaseUser == null) {
        _status = Status.authenticateError;
        notifyListeners();
        return 'error';
      }

      // 🔐 Khởi tạo cặp khóa E2EE ngay sau khi xác thực Firebase thành công
      print('🔑 Đang khởi tạo cặp khóa E2EE cho User...');
      await E2EEService().generateAndStoreUserKeys(firebaseUser.uid);
      print('✅ Khởi tạo khóa E2EE thành công!');

      final result = await firebaseFirestore
          .collection(FirestoreConstants.pathUserCollection)
          .where(FirestoreConstants.id, isEqualTo: firebaseUser.uid)
          .get();

      final documents = result.docs;

      if (documents.isEmpty) {
        // Người dùng mới: tạo document trên Firestore
        final qrCode = _generateQRCode(firebaseUser.uid);

        await firebaseFirestore
            .collection(FirestoreConstants.pathUserCollection)
            .doc(firebaseUser.uid)
            .set({
          FirestoreConstants.nickname: firebaseUser.displayName ?? '',
          FirestoreConstants.photoUrl: firebaseUser.photoURL ?? '',
          FirestoreConstants.id: firebaseUser.uid,
          FirestoreConstants.phoneNumber: firebaseUser.phoneNumber ?? '',
          FirestoreConstants.qrCode: qrCode,
          FirestoreConstants.createdAt:
              DateTime.now().millisecondsSinceEpoch.toString(),
          FirestoreConstants.chattingWith: null,
          FirestoreConstants.aboutMe: '',
          'is2FAEnabled': false,
          'twoFactorSecret': '',
        });

        await _saveUserToPrefs(
          firebaseUser.uid,
          firebaseUser.displayName ?? '',
          firebaseUser.photoURL ?? '',
          firebaseUser.phoneNumber ?? '',
          qrCode,
          '',
          false,
          '',
        );

        _status = Status.authenticated;
        notifyListeners();
        return 'success';
      } else {
        // Người dùng cũ: đọc dữ liệu từ Firestore
        final documentSnapshot = documents.first;
        final userChat = UserChat.fromDocument(documentSnapshot);

        String qrCode = userChat.qrCode;
        if (qrCode.isEmpty) {
          qrCode = _generateQRCode(firebaseUser.uid);
          await firebaseFirestore
              .collection(FirestoreConstants.pathUserCollection)
              .doc(firebaseUser.uid)
              .update({FirestoreConstants.qrCode: qrCode});
        }

        if (userChat.is2FAEnabled) {
          // Yêu cầu xác thực 2FA trước khi hoàn tất đăng nhập
          tempUserChat = userChat;
          _status = Status.uninitialized;
          notifyListeners();
          return 'requires_2fa';
        } else {
          await _saveUserToPrefs(
            userChat.id,
            userChat.nickname,
            userChat.photoUrl,
            userChat.phoneNumber,
            qrCode,
            userChat.aboutMe,
            false,
            '',
          );
          _status = Status.authenticated;
          notifyListeners();
          return 'success';
        }
      }
    } catch (e) {
      print('❌ Sign in error: $e');
      _status = Status.authenticateError;
      notifyListeners();
      return 'error';
    }
  }

  // =========================================================
  // COMPLETE 2FA LOGIN
  // =========================================================

  /// Hoàn tất đăng nhập sau khi người dùng xác thực 2FA thành công.
  Future<void> complete2FALogin() async {
    if (tempUserChat != null) {
      await _saveUserToPrefs(
        tempUserChat!.id,
        tempUserChat!.nickname,
        tempUserChat!.photoUrl,
        tempUserChat!.phoneNumber,
        tempUserChat!.qrCode,
        tempUserChat!.aboutMe,
        true,
        tempUserChat!.twoFactorSecret,
      );
      tempUserChat = null;
      _status = Status.authenticated;
      notifyListeners();
    }
  }

  // =========================================================
  // SAVE USER TO PREFS
  // =========================================================

  Future<void> _saveUserToPrefs(
    String id,
    String nickname,
    String photoUrl,
    String phoneNumber,
    String qrCode,
    String aboutMe,
    bool is2FAEnabled,
    String secret,
  ) async {
    await prefs.setString(FirestoreConstants.id, id);
    await prefs.setString(FirestoreConstants.nickname, nickname);
    await prefs.setString(FirestoreConstants.photoUrl, photoUrl);
    await prefs.setString(FirestoreConstants.phoneNumber, phoneNumber);
    await prefs.setString(FirestoreConstants.qrCode, qrCode);
    await prefs.setString(FirestoreConstants.aboutMe, aboutMe);
    await prefs.setBool('is2FAEnabled', is2FAEnabled);
    await prefs.setString('twoFactorSecret', secret);
  }

  // =========================================================
  // HANDLE EXCEPTION
  // =========================================================

  void handleException() {
    _status = Status.authenticateException;
    notifyListeners();
  }

  // =========================================================
  // SIGN OUT
  // =========================================================

  /// Đăng xuất và dọn dẹp toàn bộ dữ liệu nhạy cảm:
  /// - Xóa khóa RSA cục bộ và cache khóa phiên E2EE
  /// - Ngắt kết nối Google Sign-In
  /// - Xóa SharedPreferences
  Future<void> handleSignOut() async {
    _status = Status.uninitialized;

    try {
      // 🔐 Xóa khóa E2EE để tránh user khác dùng nhầm Private Key cũ
      print('🗑️ Đang xóa khóa E2EE cục bộ...');
      await E2EEService().clearKeysOnLogout();
      print('✅ Đã xóa khóa E2EE thành công!');

      await firebaseAuth.signOut();
      await googleSignIn.disconnect();
      await googleSignIn.signOut();
      await prefs.clear();

      print('✅ Sign out successful');
    } catch (e) {
      print('⚠️ Sign out error: $e');
    }

    notifyListeners();
  }
}
