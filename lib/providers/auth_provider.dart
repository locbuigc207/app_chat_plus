
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

      final result = await firebaseFirestore
          .collection(FirestoreConstants.pathUserCollection)
          .where(FirestoreConstants.id, isEqualTo: firebaseUser.uid)
          .get();

      final documents = result.docs;

      if (documents.isEmpty) {
        
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

  void handleException() {
    _status = Status.authenticateException;
    notifyListeners();
  }

  Future<void> handleSignOut() async {
    _status = Status.uninitialized;

    try {
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
