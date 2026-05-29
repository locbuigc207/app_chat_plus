import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  String? get currentUserName => prefs.getString(FirestoreConstants.nickname);
  String? get currentUserAvatar => prefs.getString(FirestoreConstants.photoUrl);

  
  UserChat? tempUserChat;

  

  
  Future<bool> isLoggedIn() async {
    try {
      final currentUser = firebaseAuth.currentUser;
      final savedId = prefs.getString(FirestoreConstants.id);
      return currentUser != null && savedId != null && savedId.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  

  String _generateQRCode(String userId) {
    return 'CHATAPP_${userId}_${DateTime.now().millisecondsSinceEpoch}';
  }

  

  
  
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

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      
      final UserCredential userCredential = await firebaseAuth.signInWithCredential(credential);
      final User? firebaseUser = userCredential.user;

      if (firebaseUser == null) {
        _status = Status.authenticateError;
        notifyListeners();
        return 'error';
      }

      
      debugPrint('🔑 Khởi tạo cặp khóa E2EE...');
      await E2EEService().generateAndStoreUserKeys(firebaseUser.uid);
      debugPrint('✅ Khóa E2EE đã được khởi tạo thành công!');

      
      final result = await firebaseFirestore
          .collection(FirestoreConstants.pathUserCollection)
          .where(FirestoreConstants.id, isEqualTo: firebaseUser.uid)
          .get();

      if (result.docs.isEmpty) {
        
        return await _createNewUser(firebaseUser);
      } else {
        
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
      FirestoreConstants.createdAt: DateTime.now().millisecondsSinceEpoch.toString(),
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

  Future<String> _handleExistingUser(User firebaseUser, DocumentSnapshot documentSnapshot) async {
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

  

  void handleException() {
    _status = Status.authenticateException;
    notifyListeners();
  }

  

  
  
  
  
  Future<void> handleSignOut() async {
    _status = Status.uninitialized;

    try {
      
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

  

  
  Future<bool> deleteAccount() async {
    try {
      final userId = userFirebaseId;
      if (userId == null) return false;

      
      await firebaseFirestore
          .collection(FirestoreConstants.pathUserCollection)
          .doc(userId)
          .delete();

      
      await firebaseAuth.currentUser?.delete();

      
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
