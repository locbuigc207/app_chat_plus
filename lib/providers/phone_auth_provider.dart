import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PhoneAuthStatus {
  uninitialized,
  codeSent,
  codeVerified,
  authenticated,
  authenticating,
  authenticateError,
  authenticateException,
}

class PhoneAuthProvider extends ChangeNotifier {
  final firebase_auth.FirebaseAuth firebaseAuth;
  final FirebaseFirestore firebaseFirestore;
  final SharedPreferences prefs;

  PhoneAuthProvider({
    required this.firebaseAuth,
    required this.firebaseFirestore,
    required this.prefs,
  });

  PhoneAuthStatus _status = PhoneAuthStatus.uninitialized;
  String? _verificationId;
  int? _resendToken;

  PhoneAuthStatus get status => _status;
  String? get verificationId => _verificationId;

  // Generate unique QR code for user
  String _generateQRCode(String userId) {
    return 'CHATAPP_${userId}_${DateTime.now().millisecondsSinceEpoch}';
  }

  // Send OTP to phone number
  Future<void> sendOTP(String phoneNumber) async {
    _status = PhoneAuthStatus.authenticating;
    notifyListeners();

    await firebaseAuth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (firebase_auth.PhoneAuthCredential credential) async {
        // Auto-verification on Android
        await _signInWithCredential(credential, phoneNumber);
      },
      verificationFailed: (firebase_auth.FirebaseAuthException e) {
        print('Verification failed: ${e.message}');
        _status = PhoneAuthStatus.authenticateError;
        notifyListeners();
      },
      codeSent: (String verificationId, int? resendToken) {
        _verificationId = verificationId;
        _resendToken = resendToken;
        _status = PhoneAuthStatus.codeSent;
        notifyListeners();
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        _verificationId = verificationId;
      },
      timeout: const Duration(seconds: 60),
      forceResendingToken: _resendToken,
    );
  }

  // Verify OTP code
  Future<bool> verifyOTP(String smsCode, String phoneNumber) async {
    try {
      _status = PhoneAuthStatus.authenticating;
      notifyListeners();

      final credential = firebase_auth.PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: smsCode,
      );

      return await _signInWithCredential(credential, phoneNumber);
    } catch (e) {
      print('Error verifying OTP: $e');
      _status = PhoneAuthStatus.authenticateError;
      notifyListeners();
      return false;
    }
  }

  // Sign in with credential
  Future<bool> _signInWithCredential(
      firebase_auth.PhoneAuthCredential credential,
      String phoneNumber,
      ) async {
    try {
      final userCredential = await firebaseAuth.signInWithCredential(credential);
      final firebaseUser = userCredential.user;

      if (firebaseUser == null) {
        _status = PhoneAuthStatus.authenticateError;
        notifyListeners();
        return false;
      }

      // Check if user exists in Firestore
      final result = await firebaseFirestore
          .collection(FirestoreConstants.pathUserCollection)
          .where(FirestoreConstants.id, isEqualTo: firebaseUser.uid)
          .get();

      final documents = result.docs;

      if (documents.isEmpty) {
        // Generate QR code for new user
        final qrCode = _generateQRCode(firebaseUser.uid);

        // Create new user document
        await firebaseFirestore
            .collection(FirestoreConstants.pathUserCollection)
            .doc(firebaseUser.uid)
            .set({
          FirestoreConstants.nickname: phoneNumber,
          FirestoreConstants.photoUrl: '',
          FirestoreConstants.id: firebaseUser.uid,
          FirestoreConstants.phoneNumber: phoneNumber,
          FirestoreConstants.qrCode: qrCode,
          FirestoreConstants.createdAt:
          DateTime.now().millisecondsSinceEpoch.toString(),
          FirestoreConstants.chattingWith: null,
          FirestoreConstants.aboutMe: '',
        });

        // Save to local storage
        await prefs.setString(FirestoreConstants.id, firebaseUser.uid);
        await prefs.setString(FirestoreConstants.nickname, phoneNumber);
        await prefs.setString(FirestoreConstants.phoneNumber, phoneNumber);
        await prefs.setString(FirestoreConstants.qrCode, qrCode);
        await prefs.setString(FirestoreConstants.photoUrl, '');
        await prefs.setString(FirestoreConstants.aboutMe, '');
      } else {
        // User exists, get data
        final documentSnapshot = documents.first;
        final userChat = UserChat.fromDocument(documentSnapshot);

        // Check if user has QR code, if not generate one
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

        // Save to local storage
        await prefs.setString(FirestoreConstants.id, userChat.id);
        await prefs.setString(FirestoreConstants.nickname, userChat.nickname);
        await prefs.setString(FirestoreConstants.photoUrl, userChat.photoUrl);
        await prefs.setString(FirestoreConstants.aboutMe, userChat.aboutMe);
        await prefs.setString(
            FirestoreConstants.phoneNumber, userChat.phoneNumber);
      }

      _status = PhoneAuthStatus.authenticated;
      notifyListeners();
      return true;
    } catch (e) {
      print('Error signing in: $e');
      _status = PhoneAuthStatus.authenticateError;
      notifyListeners();
      return false;
    }
  }

  void handleException() {
    _status = PhoneAuthStatus.authenticateException;
    notifyListeners();
  }
}
