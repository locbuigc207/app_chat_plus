import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/foundation.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Status Enum ──────────────────────────────────────────────────────────────

enum PhoneAuthStatus {
  /// Trạng thái ban đầu, chưa thực hiện thao tác nào.
  uninitialized,

  /// Đang xử lý (gửi OTP hoặc xác minh).
  authenticating,

  /// Mã OTP đã được gửi thành công đến thiết bị.
  codeSent,

  /// Mã OTP đã được xác minh thành công.
  codeVerified,

  /// Đã đăng nhập hoàn toàn.
  authenticated,

  /// Lỗi xác thực (sai OTP, hết hạn, v.v.).
  authenticateError,

  /// Ngoại lệ không mong muốn.
  authenticateException,
}

// ─── PhoneAuthProvider ────────────────────────────────────────────────────────

class PhoneAuthProvider extends ChangeNotifier {
  // ── Dependencies ─────────────────────────────────────────────────────────────

  final firebase_auth.FirebaseAuth firebaseAuth;
  final FirebaseFirestore firebaseFirestore;
  final SharedPreferences prefs;

  PhoneAuthProvider({
    required this.firebaseAuth,
    required this.firebaseFirestore,
    required this.prefs,
  });

  // ── State ─────────────────────────────────────────────────────────────────────

  PhoneAuthStatus _status = PhoneAuthStatus.uninitialized;
  String? _verificationId;
  int? _resendToken;
  String? _errorMessage;
  String? _lastPhoneNumber;

  // ── Getters ───────────────────────────────────────────────────────────────────

  PhoneAuthStatus get status => _status;
  String? get verificationId => _verificationId;
  String? get errorMessage => _errorMessage;

  /// Trả về true nếu đang xử lý bất kỳ tác vụ async nào.
  bool get isLoading => _status == PhoneAuthStatus.authenticating;

  /// Trả về true nếu mã OTP đã được gửi (hiển thị UI nhập OTP).
  bool get isCodeSent => _status == PhoneAuthStatus.codeSent;

  /// Trả về true nếu đã xác thực thành công.
  bool get isAuthenticated => _status == PhoneAuthStatus.authenticated;

  /// Trả về true nếu có lỗi.
  bool get hasError =>
      _status == PhoneAuthStatus.authenticateError ||
      _status == PhoneAuthStatus.authenticateException;

  // ── QR Code Helper ────────────────────────────────────────────────────────────

  String _generateQRCode(String userId) {
    return 'CHATAPP_${userId}_${DateTime.now().millisecondsSinceEpoch}';
  }

  // ── Send OTP ──────────────────────────────────────────────────────────────────

  /// Gửi mã OTP qua SMS đến [phoneNumber] (đã bao gồm mã quốc gia).
  ///
  /// Trên Android hỗ trợ tự động xác minh (verificationCompleted).
  /// Trên iOS/Web luôn yêu cầu nhập OTP thủ công.
  Future<void> sendOTP(String phoneNumber) async {
    _status = PhoneAuthStatus.authenticating;
    _errorMessage = null;
    _lastPhoneNumber = phoneNumber;
    notifyListeners();

    try {
      await firebaseAuth.verifyPhoneNumber(
        phoneNumber: phoneNumber,

        // Android: tự động xác minh nếu thiết bị nhận được SMS
        verificationCompleted:
            (firebase_auth.PhoneAuthCredential credential) async {
          debugPrint('📱 Auto-verified OTP on Android');
          await _signInWithCredential(credential, phoneNumber);
        },

        // Xác minh thất bại (số điện thoại không hợp lệ, quota hết, v.v.)
        verificationFailed: (firebase_auth.FirebaseAuthException e) {
          debugPrint('❌ Verification failed: ${e.code} – ${e.message}');
          _errorMessage = _mapFirebaseError(e.code);
          _status = PhoneAuthStatus.authenticateError;
          notifyListeners();
        },

        // SMS đã gửi thành công
        codeSent: (String verificationId, int? resendToken) {
          debugPrint('✅ OTP sent. verificationId: $verificationId');
          _verificationId = verificationId;
          _resendToken = resendToken;
          _status = PhoneAuthStatus.codeSent;
          notifyListeners();
        },

        // Timeout tự động lấy lại mã (chỉ Android)
        codeAutoRetrievalTimeout: (String verificationId) {
          debugPrint('⏱️ Auto-retrieval timeout');
          _verificationId = verificationId;
        },

        timeout: const Duration(seconds: 60),
        forceResendingToken: _resendToken, // dùng khi gửi lại OTP
      );
    } catch (e) {
      debugPrint('❌ sendOTP exception: $e');
      _errorMessage = 'Đã xảy ra lỗi không mong muốn. Vui lòng thử lại.';
      _status = PhoneAuthStatus.authenticateException;
      notifyListeners();
    }
  }

  // ── Resend OTP ────────────────────────────────────────────────────────────────

  /// Gửi lại OTP đến số điện thoại đã nhập trước đó.
  /// Sử dụng [_resendToken] để tránh bị giới hạn bởi Firebase.
  Future<void> resendOTP() async {
    if (_lastPhoneNumber == null) return;
    await sendOTP(_lastPhoneNumber!);
  }

  // ── Verify OTP ────────────────────────────────────────────────────────────────

  /// Xác minh mã OTP [smsCode] người dùng nhập.
  ///
  /// Returns `true` nếu đăng nhập thành công.
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

  // ── Sign In with Credential ───────────────────────────────────────────────────

  Future<bool> _signInWithCredential(
    firebase_auth.PhoneAuthCredential credential,
    String phoneNumber,
  ) async {
    try {
      final userCredential =
          await firebaseAuth.signInWithCredential(credential);
      final firebaseUser = userCredential.user;

      if (firebaseUser == null) {
        _errorMessage = 'Không thể xác thực người dùng.';
        _status = PhoneAuthStatus.authenticateError;
        notifyListeners();
        return false;
      }

      debugPrint('✅ Firebase sign-in success: ${firebaseUser.uid}');

      // Cập nhật/tạo hồ sơ trên Firestore
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

  // ── Upsert User Profile ───────────────────────────────────────────────────────

  /// Tạo mới hoặc cập nhật hồ sơ người dùng trên Firestore & SharedPreferences.
  Future<void> _upsertUserProfile(
    firebase_auth.User firebaseUser,
    String phoneNumber,
  ) async {
    final userRef = firebaseFirestore
        .collection(FirestoreConstants.pathUserCollection)
        .doc(firebaseUser.uid);

    final snapshot = await userRef.get();

    if (!snapshot.exists) {
      // ── Người dùng mới ────────────────────────────────────────────────────
      final qrCode = _generateQRCode(firebaseUser.uid);

      await userRef.set({
        FirestoreConstants.nickname: _formatPhoneAsNickname(phoneNumber),
        FirestoreConstants.photoUrl: '',
        FirestoreConstants.id: firebaseUser.uid,
        FirestoreConstants.phoneNumber: phoneNumber,
        FirestoreConstants.qrCode: qrCode,
        FirestoreConstants.createdAt:
            DateTime.now().millisecondsSinceEpoch.toString(),
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
      // ── Người dùng cũ ─────────────────────────────────────────────────────
      final userChat = UserChat.fromDocument(snapshot);

      String qrCode = userChat.qrCode;
      if (qrCode.isEmpty) {
        qrCode = _generateQRCode(firebaseUser.uid);
        await userRef.update({FirestoreConstants.qrCode: qrCode});
        debugPrint('🔄 QR code regenerated for ${firebaseUser.uid}');
      }

      await _savePrefs(
        id: userChat.id,
        nickname: userChat.nickname.isNotEmpty
            ? userChat.nickname
            : _formatPhoneAsNickname(phoneNumber),
        photoUrl: userChat.photoUrl,
        phoneNumber: userChat.phoneNumber.isNotEmpty
            ? userChat.phoneNumber
            : phoneNumber,
        qrCode: qrCode,
        aboutMe: userChat.aboutMe,
      );

      debugPrint('🔄 Existing phone user updated: ${firebaseUser.uid}');
    }
  }

  // ── Save SharedPreferences ────────────────────────────────────────────────────

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

  // ── Reset Status ──────────────────────────────────────────────────────────────

  /// Đặt lại trạng thái về ban đầu (dùng khi người dùng muốn thay đổi số).
  void resetStatus() {
    _status = PhoneAuthStatus.uninitialized;
    _errorMessage = null;
    _verificationId = null;
    notifyListeners();
  }

  // ── Handle Exception ──────────────────────────────────────────────────────────

  void handleException() {
    _status = PhoneAuthStatus.authenticateException;
    notifyListeners();
  }

  // ── Firebase Error Mapping ────────────────────────────────────────────────────

  /// Chuyển đổi mã lỗi Firebase thành thông báo tiếng Việt thân thiện.
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

  // ── Format Phone as Nickname ──────────────────────────────────────────────────

  /// Tạo nickname mặc định từ số điện thoại (ẩn giữa để bảo mật).
  /// Ví dụ: +84912345678 → "Người dùng ***678"
  String _formatPhoneAsNickname(String phone) {
    if (phone.length < 4) return 'Người dùng';
    final last4 = phone.substring(phone.length - 4);
    return 'Người dùng ***$last4';
  }
}
