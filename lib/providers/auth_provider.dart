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

// ─── Status Enum ──────────────────────────────────────────────────────────────

enum Status {
  uninitialized,
  authenticated,
  authenticating,
  authenticateError,
  authenticateException,
  authenticateCanceled,
}

// ─── AuthProvider ──────────────────────────────────────────────────────────────

class AuthProvider extends ChangeNotifier {
  // ── Dependencies ────────────────────────────────────────────────────────────

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

  // ── State ────────────────────────────────────────────────────────────────────

  Status _status = Status.uninitialized;
  Status get status => _status;

  /// Firebase UID hiện tại (từ SharedPreferences).
  String? get userFirebaseId => prefs.getString(FirestoreConstants.id);
  String? get currentUserName => prefs.getString(FirestoreConstants.nickname);
  String? get currentUserAvatar => prefs.getString(FirestoreConstants.photoUrl);

  /// Lưu tạm thông tin user khi đang chờ xác thực 2FA.
  UserChat? tempUserChat;

  // ── Is Logged In ─────────────────────────────────────────────────────────────

  /// Kiểm tra phiên đăng nhập còn hợp lệ không.
  Future<bool> isLoggedIn() async {
    try {
      final currentUser = firebaseAuth.currentUser;
      final savedId = prefs.getString(FirestoreConstants.id);
      return currentUser != null && savedId != null && savedId.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ── Generate QR Code ─────────────────────────────────────────────────────────

  String _generateQRCode(String userId) {
    return 'CHATAPP_${userId}_${DateTime.now().millisecondsSinceEpoch}';
  }

  // ── Sign In with Google ───────────────────────────────────────────────────────

  /// Xử lý đăng nhập Google.
  /// Returns: 'success' | 'requires_2fa' | 'canceled' | 'error'
  Future<String> handleSignIn() async {
    _status = Status.authenticating;
    notifyListeners();

    try {
      // 1. Google OAuth flow
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

      // 2. Firebase sign in
      final UserCredential userCredential =
          await firebaseAuth.signInWithCredential(credential);
      final User? firebaseUser = userCredential.user;

      if (firebaseUser == null) {
        _status = Status.authenticateError;
        notifyListeners();
        return 'error';
      }

      // 3. Khởi tạo E2EE keys
      debugPrint('🔑 Khởi tạo cặp khóa E2EE...');
      await E2EEService().generateAndStoreUserKeys(firebaseUser.uid);
      debugPrint('✅ Khóa E2EE đã được khởi tạo thành công!');

      // 4. Kiểm tra Firestore
      final result = await firebaseFirestore
          .collection(FirestoreConstants.pathUserCollection)
          .where(FirestoreConstants.id, isEqualTo: firebaseUser.uid)
          .get();

      if (result.docs.isEmpty) {
        // ── New user: tạo document ──
        return await _createNewUser(firebaseUser);
      } else {
        // ── Existing user: đọc dữ liệu ──
        return await _handleExistingUser(firebaseUser, result.docs.first);
      }
    } catch (e) {
      debugPrint('❌ Sign in error: $e');
      _status = Status.authenticateError;
      notifyListeners();
      return 'error';
    }
  }

  Future<String> _createNewUser(User firebaseUser) async {
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
      id: firebaseUser.uid,
      nickname: firebaseUser.displayName ?? '',
      photoUrl: firebaseUser.photoURL ?? '',
      phoneNumber: firebaseUser.phoneNumber ?? '',
      qrCode: qrCode,
      aboutMe: '',
      is2FAEnabled: false,
      twoFactorSecret: '',
    );

    _status = Status.authenticated;
    notifyListeners();
    return 'success';
  }

  Future<String> _handleExistingUser(
      User firebaseUser, DocumentSnapshot documentSnapshot) async {
    final userChat = UserChat.fromDocument(documentSnapshot);

    // Cập nhật QR code nếu trống
    String qrCode = userChat.qrCode;
    if (qrCode.isEmpty) {
      qrCode = _generateQRCode(firebaseUser.uid);
      await firebaseFirestore
          .collection(FirestoreConstants.pathUserCollection)
          .doc(firebaseUser.uid)
          .update({FirestoreConstants.qrCode: qrCode});
    }

    // Yêu cầu 2FA nếu bật
    if (userChat.is2FAEnabled) {
      tempUserChat = userChat.copyWith(qrCode: qrCode);
      _status = Status.uninitialized;
      notifyListeners();
      return 'requires_2fa';
    }

    await _saveUserToPrefs(
      id: userChat.id,
      nickname: userChat.nickname,
      photoUrl: userChat.photoUrl,
      phoneNumber: userChat.phoneNumber,
      qrCode: qrCode,
      aboutMe: userChat.aboutMe,
      is2FAEnabled: false,
      twoFactorSecret: '',
    );

    _status = Status.authenticated;
    notifyListeners();
    return 'success';
  }

  // ── Complete 2FA Login ────────────────────────────────────────────────────────

  /// Gọi sau khi xác thực 2FA thành công để hoàn tất đăng nhập.
  Future<void> complete2FALogin() async {
    if (tempUserChat == null) return;

    await _saveUserToPrefs(
      id: tempUserChat!.id,
      nickname: tempUserChat!.nickname,
      photoUrl: tempUserChat!.photoUrl,
      phoneNumber: tempUserChat!.phoneNumber,
      qrCode: tempUserChat!.qrCode,
      aboutMe: tempUserChat!.aboutMe,
      is2FAEnabled: true,
      twoFactorSecret: tempUserChat!.twoFactorSecret,
    );

    tempUserChat = null;
    _status = Status.authenticated;
    notifyListeners();
  }

  // ── Save User to Prefs ────────────────────────────────────────────────────────

  Future<void> _saveUserToPrefs({
    required String id,
    required String nickname,
    required String photoUrl,
    required String phoneNumber,
    required String qrCode,
    required String aboutMe,
    required bool is2FAEnabled,
    required String twoFactorSecret,
  }) async {
    await Future.wait([
      prefs.setString(FirestoreConstants.id, id),
      prefs.setString(FirestoreConstants.nickname, nickname),
      prefs.setString(FirestoreConstants.photoUrl, photoUrl),
      prefs.setString(FirestoreConstants.phoneNumber, phoneNumber),
      prefs.setString(FirestoreConstants.qrCode, qrCode),
      prefs.setString(FirestoreConstants.aboutMe, aboutMe),
      prefs.setBool('is2FAEnabled', is2FAEnabled),
      prefs.setString('twoFactorSecret', twoFactorSecret),
    ]);
  }

  // ── Refresh User Profile ──────────────────────────────────────────────────────

  /// Làm mới dữ liệu hồ sơ từ Firestore (dùng sau khi cập nhật profile).
  Future<void> refreshUserProfile() async {
    final userId = userFirebaseId;
    if (userId == null) return;

    try {
      final doc = await firebaseFirestore
          .collection(FirestoreConstants.pathUserCollection)
          .doc(userId)
          .get();

      if (doc.exists) {
        final userChat = UserChat.fromDocument(doc);
        await _saveUserToPrefs(
          id: userChat.id,
          nickname: userChat.nickname,
          photoUrl: userChat.photoUrl,
          phoneNumber: userChat.phoneNumber,
          qrCode: userChat.qrCode,
          aboutMe: userChat.aboutMe,
          is2FAEnabled: userChat.is2FAEnabled,
          twoFactorSecret: userChat.twoFactorSecret,
        );
        notifyListeners();
      }
    } catch (e) {
      debugPrint('⚠️ Refresh profile error: $e');
    }
  }

  // ── Handle Exception ──────────────────────────────────────────────────────────

  void handleException() {
    _status = Status.authenticateException;
    notifyListeners();
  }

  // ── Sign Out ──────────────────────────────────────────────────────────────────

  /// Đăng xuất hoàn toàn:
  /// - Xóa khóa E2EE cục bộ
  /// - Đăng xuất Firebase & Google
  /// - Xóa SharedPreferences
  Future<void> handleSignOut() async {
    _status = Status.uninitialized;

    try {
      // Xóa khóa E2EE trước khi đăng xuất
      debugPrint('🗑️ Đang xóa khóa E2EE cục bộ...');
      await E2EEService().clearKeysOnLogout();
      debugPrint('✅ Đã xóa khóa E2EE!');

      await Future.wait([
        firebaseAuth.signOut(),
        googleSignIn.disconnect().catchError((_) => null),
        googleSignIn.signOut(),
      ]);

      await prefs.clear();
      debugPrint('✅ Đăng xuất thành công!');
    } catch (e) {
      debugPrint('⚠️ Sign out error: $e');
    }

    notifyListeners();
  }

  // ── Delete Account ────────────────────────────────────────────────────────────

  /// Xóa tài khoản vĩnh viễn.
  Future<bool> deleteAccount() async {
    try {
      final userId = userFirebaseId;
      if (userId == null) return false;

      // Xóa document trên Firestore
      await firebaseFirestore
          .collection(FirestoreConstants.pathUserCollection)
          .doc(userId)
          .delete();

      // Xóa Firebase Auth user
      await firebaseAuth.currentUser?.delete();

      // Xóa keys & prefs
      await E2EEService().clearKeysOnLogout();
      await prefs.clear();

      _status = Status.uninitialized;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('❌ Delete account error: $e');
      return false;
    }
  }
}
