import 'package:flutter/foundation.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PhoneAuthStatus {
  uninitialized,

  authenticating,

  codeSent,

  codeVerified,

  authenticated,

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
  String? _errorMessage;
  String? _lastPhoneNumber;

  PhoneAuthStatus get status => _status;
  String? get verificationId => _verificationId;
  String? get errorMessage => _errorMessage;

  bool get isLoading => _status == PhoneAuthStatus.authenticating;

  bool get isCodeSent => _status == PhoneAuthStatus.codeSent;

  bool get isAuthenticated => _status == PhoneAuthStatus.authenticated;

  bool get hasError =>
      _status == PhoneAuthStatus.authenticateError ||
      _status == PhoneAuthStatus.authenticateException;

  String _generateQRCode(String userId) {
    return 'CHATAPP_${userId}_${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<void> sendOTP(String phoneNumber) async {
    _status = PhoneAuthStatus.authenticating;
    _errorMessage = null;
    _lastPhoneNumber = phoneNumber;
    notifyListeners();

    try {
      await firebaseAuth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (firebase_auth.PhoneAuthCredential credential) async {
          debugPrint('📱 Auto-verified OTP on Android');
          await _signInWithCredential(credential, phoneNumber);
        },
        verificationFailed: (firebase_auth.FirebaseAuthException e) {
          debugPrint('❌ Verification failed: ${e.code} – ${e.message}');
          _errorMessage = _mapFirebaseError(e.code);
          _status = PhoneAuthStatus.authenticateError;
          notifyListeners();
        },
        codeSent: (String verificationId, int? resendToken) {
          debugPrint('✅ OTP sent. verificationId: $verificationId');
          _verificationId = verificationId;
          _resendToken = resendToken;
          _status = PhoneAuthStatus.codeSent;
          notifyListeners();
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          debugPrint('⏱️ Auto-retrieval timeout');
          _verificationId = verificationId;
        },
        timeout: const Duration(seconds: 60),
        forceResendingToken: _resendToken,
      );
    } catch (e) {
      debugPrint('❌ sendOTP exception: $e');
      _errorMessage = 'Đã xảy ra lỗi không mong muốn. Vui lòng thử lại.';
      _status = PhoneAuthStatus.authenticateException;
      notifyListeners();
    }
  }

  Future<void> resendOTP() async {
    if (_lastPhoneNumber == null) return;
    await sendOTP(_lastPhoneNumber!);
  }

  Future<bool> verifyOTP(String smsCode, String phoneNumber) async {
    if (_verificationId == null) {
      _errorMessage = 'Phiên xác minh hết hạn. Vui lòng gửi lại mã OTP.';
      _status = PhoneAuthStatus.authenticateError;
      notifyListeners();
      return false;
    }

    if (smsCode.length != 6) {
      _errorMessage = 'Mã OTP phải đủ 6 chữ số.';
      _status = PhoneAuthStatus.authenticateError;
      notifyListeners();
      return false;
    }

    try {
      _status = PhoneAuthStatus.authenticating;
      _errorMessage = null;
      notifyListeners();

      final credential = firebase_auth.PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: smsCode,
      );

      return await _signInWithCredential(credential, phoneNumber);
    } on firebase_auth.FirebaseAuthException catch (e) {
      debugPrint('❌ verifyOTP FirebaseAuthException: ${e.code}');
      _errorMessage = _mapFirebaseError(e.code);
      _status = PhoneAuthStatus.authenticateError;
      notifyListeners();
      return false;
    } catch (e) {
      debugPrint('❌ verifyOTP exception: $e');
      _errorMessage = 'Đã xảy ra lỗi không mong muốn.';
      _status = PhoneAuthStatus.authenticateException;
      notifyListeners();
      return false;
    }
  }

  Future<bool> _signInWithCredential(
    firebase_auth.PhoneAuthCredential credential,
    String phoneNumber,
  ) async {
    try {
      final userCredential = await firebaseAuth.signInWithCredential(credential);
      final firebaseUser = userCredential.user;

      if (firebaseUser == null) {
        _errorMessage = 'Không thể xác thực người dùng.';
        _status = PhoneAuthStatus.authenticateError;
        notifyListeners();
        return false;
      }

      debugPrint('✅ Firebase sign-in success: ${firebaseUser.uid}');

      await _upsertUserProfile(firebaseUser, phoneNumber);

      _status = PhoneAuthStatus.authenticated;
      notifyListeners();
      return true;
    } on firebase_auth.FirebaseAuthException catch (e) {
      debugPrint('❌ _signInWithCredential Firebase error: ${e.code}');
      _errorMessage = _mapFirebaseError(e.code);
      _status = PhoneAuthStatus.authenticateError;
      notifyListeners();
      return false;
    } catch (e) {
      debugPrint('❌ _signInWithCredential exception: $e');
      _errorMessage = 'Đăng nhập thất bại. Vui lòng thử lại.';
      _status = PhoneAuthStatus.authenticateError;
      notifyListeners();
      return false;
    }
  }

  Future<void> _upsertUserProfile(
    firebase_auth.User firebaseUser,
    String phoneNumber,
  ) async {
    final userRef =
        firebaseFirestore.collection(FirestoreConstants.pathUserCollection).doc(firebaseUser.uid);

    final snapshot = await userRef.get();

    if (!snapshot.exists) {
      final qrCode = _generateQRCode(firebaseUser.uid);

      await userRef.set({
        FirestoreConstants.nickname: _formatPhoneAsNickname(phoneNumber),
        FirestoreConstants.photoUrl: '',
        FirestoreConstants.id: firebaseUser.uid,
        FirestoreConstants.phoneNumber: phoneNumber,
        FirestoreConstants.qrCode: qrCode,
        FirestoreConstants.createdAt: DateTime.now().millisecondsSinceEpoch.toString(),
        FirestoreConstants.chattingWith: null,
        FirestoreConstants.aboutMe: '',
        'is2FAEnabled': false,
        'twoFactorSecret': '',
      });

      await _savePrefs(
        id: firebaseUser.uid,
        nickname: _formatPhoneAsNickname(phoneNumber),
        photoUrl: '',
        phoneNumber: phoneNumber,
        qrCode: qrCode,
        aboutMe: '',
      );

      debugPrint('🆕 New phone user created: ${firebaseUser.uid}');
    } else {
      final userChat = UserChat.fromDocument(snapshot);

      String qrCode = userChat.qrCode;
      if (qrCode.isEmpty) {
        qrCode = _generateQRCode(firebaseUser.uid);
        await userRef.update({FirestoreConstants.qrCode: qrCode});
        debugPrint('🔄 QR code regenerated for ${firebaseUser.uid}');
      }

      await _savePrefs(
        id: userChat.id,
        nickname:
            userChat.nickname.isNotEmpty ? userChat.nickname : _formatPhoneAsNickname(phoneNumber),
        photoUrl: userChat.photoUrl,
        phoneNumber: userChat.phoneNumber.isNotEmpty ? userChat.phoneNumber : phoneNumber,
        qrCode: qrCode,
        aboutMe: userChat.aboutMe,
      );

      debugPrint('🔄 Existing phone user updated: ${firebaseUser.uid}');
    }
  }

  Future<void> _savePrefs({
    required String id,
    required String nickname,
    required String photoUrl,
    required String phoneNumber,
    required String qrCode,
    required String aboutMe,
  }) async {
    await Future.wait([
      prefs.setString(FirestoreConstants.id, id),
      prefs.setString(FirestoreConstants.nickname, nickname),
      prefs.setString(FirestoreConstants.photoUrl, photoUrl),
      prefs.setString(FirestoreConstants.phoneNumber, phoneNumber),
      prefs.setString(FirestoreConstants.qrCode, qrCode),
      prefs.setString(FirestoreConstants.aboutMe, aboutMe),
    ]);
  }

  void resetStatus() {
    _status = PhoneAuthStatus.uninitialized;
    _errorMessage = null;
    _verificationId = null;
    notifyListeners();
  }

  void handleException() {
    _status = PhoneAuthStatus.authenticateException;
    notifyListeners();
  }

  String _mapFirebaseError(String code) {
    switch (code) {
      case 'invalid-phone-number':
        return 'Số điện thoại không hợp lệ.';
      case 'too-many-requests':
        return 'Quá nhiều yêu cầu. Vui lòng thử lại sau ít phút.';
      case 'invalid-verification-code':
        return 'Mã OTP không đúng. Vui lòng kiểm tra lại.';
      case 'session-expired':
        return 'Phiên xác minh đã hết hạn. Vui lòng gửi lại OTP.';
      case 'quota-exceeded':
        return 'Đã vượt quá giới hạn gửi SMS. Thử lại sau.';
      case 'missing-phone-number':
        return 'Vui lòng nhập số điện thoại.';
      case 'user-disabled':
        return 'Tài khoản này đã bị vô hiệu hóa.';
      case 'network-request-failed':
        return 'Lỗi kết nối mạng. Kiểm tra lại internet của bạn.';
      case 'captcha-check-failed':
        return 'Xác minh captcha thất bại. Vui lòng thử lại.';
      case 'app-not-authorized':
        return 'Ứng dụng chưa được cấp phép sử dụng Firebase.';
      default:
        return 'Đã xảy ra lỗi ($code). Vui lòng thử lại.';
    }
  }

  String _formatPhoneAsNickname(String phone) {
    if (phone.length < 4) return 'Người dùng';
    final last4 = phone.substring(phone.length - 4);
    return 'Người dùng ***$last4';
  }
}
