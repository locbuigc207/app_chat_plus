// lib/providers/auth_provider.dart
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

  Future<bool> isLoggedIn() async {
    try {
      final currentUser = firebaseAuth.currentUser;
      if (currentUser != null &&
          prefs.getString(FirestoreConstants.id)?.isNotEmpty == true) {
        print('✅ User logged in: ${currentUser.uid}');
        return true;
      }

      print('❌ No active login found');
      return false;
    } catch (e) {
      print('❌ Error checking login status: $e');
      return false;
    }
  }

  // Generate unique QR code for user
  String _generateQRCode(String userId) {
    return 'CHATAPP_${userId}_${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<bool> handleSignIn() async {
    _status = Status.authenticating;
    notifyListeners();

    try {
      print('🔄 Starting Google Sign In...');

      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        print('❌ User canceled sign in');
        _status = Status.authenticateCanceled;
        notifyListeners();
        return false;
      }

      print('✅ Google user: ${googleUser.email}');

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
        print('❌ Firebase user is null');
        _status = Status.authenticateError;
        notifyListeners();
        return false;
      }

      print('✅ Firebase user: ${firebaseUser.uid}');

      final result = await firebaseFirestore
          .collection(FirestoreConstants.pathUserCollection)
          .where(FirestoreConstants.id, isEqualTo: firebaseUser.uid)
          .get();

      final documents = result.docs;

      if (documents.isEmpty) {
        print('📝 Creating new user...');

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
        });

        await prefs.setString(FirestoreConstants.id, firebaseUser.uid);
        await prefs.setString(
            FirestoreConstants.nickname, firebaseUser.displayName ?? '');
        await prefs.setString(
            FirestoreConstants.photoUrl, firebaseUser.photoURL ?? '');
        await prefs.setString(
            FirestoreConstants.phoneNumber, firebaseUser.phoneNumber ?? '');
        await prefs.setString(FirestoreConstants.qrCode, qrCode);
        await prefs.setString(FirestoreConstants.aboutMe, '');

        print('✅ New user created');
      } else {
        print('📖 Loading existing user...');

        final documentSnapshot = documents.first;
        final userChat = UserChat.fromDocument(documentSnapshot);

        if (userChat.qrCode.isEmpty) {
          final qrCode = _generateQRCode(firebaseUser.uid);
          await firebaseFirestore
              .collection(FirestoreConstants.pathUserCollection)
              .doc(firebaseUser.uid)
              .update({FirestoreConstants.qrCode: qrCode});

          await prefs.setString(FirestoreConstants.qrCode, qrCode);
        } else {
          await prefs.setString(FirestoreConstants.qrCode, userChat.qrCode);
        }

        await prefs.setString(FirestoreConstants.id, userChat.id);
        await prefs.setString(FirestoreConstants.nickname, userChat.nickname);
        await prefs.setString(FirestoreConstants.photoUrl, userChat.photoUrl);
        await prefs.setString(FirestoreConstants.aboutMe, userChat.aboutMe);
        await prefs.setString(
            FirestoreConstants.phoneNumber, userChat.phoneNumber);

        print('✅ User loaded');
      }

      _status = Status.authenticated;
      notifyListeners();
      return true;
    } catch (e) {
      print('❌ Sign in error: $e');
      _status = Status.authenticateError;
      notifyListeners();
      return false;
    }
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
      print('✅ Sign out successful');
    } catch (e) {
      print('⚠️ Sign out error: $e');
    }

    notifyListeners();
  }
}
