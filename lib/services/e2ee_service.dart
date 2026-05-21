import 'dart:convert';
import 'dart:math';

import 'package:basic_utils/basic_utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart' as pc;

// =========================================================
// TOP-LEVEL FUNCTION — CHẠY SINH KHÓA RSA TRÊN ISOLATE
// Phải là top-level (không nằm trong class) để `compute()` serialize được.
// Tránh đơ/giật UI vì RSA 2048-bit tốn ~1-2 giây trên mobile.
// =========================================================

Map<String, String> _generateRSAKeyPairInIsolate(Null _) {
  final secureRandom = pc.SecureRandom('Fortuna')
    ..seed(
      pc.KeyParameter(
        Uint8List.fromList(
          List.generate(32, (_) => Random.secure().nextInt(256)),
        ),
      ),
    );

  final keyGen = pc.RSAKeyGenerator()
    ..init(
      pc.ParametersWithRandom(
        pc.RSAKeyGeneratorParameters(BigInt.parse('65537'), 2048, 64),
        secureRandom,
      ),
    );

  final pair = keyGen.generateKeyPair();

  final publicKey = pair.publicKey as pc.RSAPublicKey;
  final privateKey = pair.privateKey as pc.RSAPrivateKey;

  return {
    'publicKey': CryptoUtils.encodeRSAPublicKeyToPemPkcs1(publicKey),
    'privateKey': CryptoUtils.encodeRSAPrivateKeyToPemPkcs1(privateKey),
  };
}

class E2EEService {
  static final E2EEService _instance = E2EEService._internal();

  factory E2EEService() => _instance;

  E2EEService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 🔒 Lưu khóa vào Keychain (iOS) / Keystore (Android) thay vì SharedPreferences
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  String? _localPrivateKey;
  String? _localPublicKey;

  final Map<String, String> _cachedSessionKeys = {};

  // =========================================================
  // 1. GENERATE RSA KEYPAIR
  // =========================================================

  /// Sinh cặp khóa RSA 2048-bit cho người dùng mới và lưu vào thiết bị.
  /// - Dùng `compute()` để chạy trên Isolate riêng, tránh lag UI.
  /// - Dùng `FlutterSecureStorage` để lưu vào Keychain/Keystore (bảo mật phần cứng).
  /// - Public Key được đẩy lên Firestore để các thành viên khác mã hóa khóa phiên.
  Future<void> generateAndStoreUserKeys(String userId) async {
    // Đọc từ Secure Storage — nếu đã có thì dùng lại, không sinh lại
    _localPrivateKey = await _secureStorage.read(key: 'e2ee_private_key');
    _localPublicKey = await _secureStorage.read(key: 'e2ee_public_key');

    if (_localPrivateKey != null && _localPublicKey != null) {
      return;
    }

    // 🚀 Sinh khóa trên Isolate riêng để không block UI thread
    print('🔑 Đang tạo khóa RSA trên luồng độc lập...');
    final keys = await compute(_generateRSAKeyPairInIsolate, null);

    _localPublicKey = keys['publicKey'];
    _localPrivateKey = keys['privateKey'];

    // Lưu Private Key vào Keychain (iOS) / Keystore (Android)
    await _secureStorage.write(
        key: 'e2ee_private_key', value: _localPrivateKey);
    await _secureStorage.write(key: 'e2ee_public_key', value: _localPublicKey);

    // Đẩy Public Key lên Firestore để người khác lấy về mã hóa khóa phiên
    await _firestore.collection('users').doc(userId).set(
      {'publicKey': _localPublicKey},
      SetOptions(merge: true),
    );

    print('✅ Tạo khóa và lưu trữ thành công!');
  }

  // =========================================================
  // 2. GENERATE SESSION KEY
  // =========================================================

  /// Sinh khóa phiên đối xứng ngẫu nhiên 256-bit cho cuộc hội thoại mới.
  String generateRandomSessionKey() {
    final values = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    return base64.encode(values);
  }

  // =========================================================
  // 3. RSA ENCRYPT SESSION KEY
  // =========================================================

  /// Mã hóa khóa phiên đối xứng bằng Public Key của đối phương (RSA-OAEP).
  String encryptSessionKeyWithReceiverPublicKey(
    String sessionKey,
    String receiverPublicKeyPem,
  ) {
    final rsaPublicKey = CryptoUtils.rsaPublicKeyFromPem(receiverPublicKeyPem);
    final encrypter = enc.Encrypter(enc.RSA(publicKey: rsaPublicKey));
    return encrypter.encrypt(sessionKey).base64;
  }

  // =========================================================
  // 4. RSA DECRYPT SESSION KEY
  // =========================================================

  /// Giải mã khóa phiên bằng Private Key cục bộ của mình.
  String decryptSessionKeyWithMyPrivateKey(String encryptedSessionKeyBase64) {
    if (_localPrivateKey == null) {
      throw Exception('Private key chưa được khởi tạo');
    }

    final rsaPrivateKey = CryptoUtils.rsaPrivateKeyFromPem(_localPrivateKey!);
    final encrypter = enc.Encrypter(enc.RSA(privateKey: rsaPrivateKey));

    return encrypter.decrypt(
      enc.Encrypted.fromBase64(encryptedSessionKeyBase64),
    );
  }

  // =========================================================
  // 5. GET / CREATE CONVERSATION SESSION KEY
  // =========================================================

  /// Thiết lập hoặc lấy khóa phiên đồng bộ giữa các thành viên chat.
  /// - Nếu đã tồn tại trong cache hoặc Firestore: giải mã và trả về.
  /// - Nếu chưa có: tạo mới, phân phối cho tất cả thành viên qua batch write.
  Future<String> getConversationSessionKey({
    required String conversationId,
    required List<String> participantIds,
    required String currentUserId,
  }) async {
    if (_cachedSessionKeys.containsKey(conversationId)) {
      return _cachedSessionKeys[conversationId]!;
    }

    final myKeyDoc = _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('e2ee_keys')
        .doc(currentUserId);

    final snapshot = await myKeyDoc.get();

    // =========================================
    // SESSION KEY EXISTS → DECRYPT AND RETURN
    // =========================================

    if (snapshot.exists) {
      final encryptedKey = snapshot.data()?['encryptedKey'] as String?;

      if (encryptedKey == null) {
        throw Exception('encryptedKey không tồn tại trong Firestore');
      }

      final decrypted = decryptSessionKeyWithMyPrivateKey(encryptedKey);
      _cachedSessionKeys[conversationId] = decrypted;
      return decrypted;
    }

    // =========================================
    // CREATE NEW SESSION KEY → DISTRIBUTE
    // =========================================

    final newSessionKey = generateRandomSessionKey();
    final batch = _firestore.batch();

    for (final uid in participantIds) {
      final userDoc = await _firestore.collection('users').doc(uid).get();
      final publicKey = userDoc.data()?['publicKey'] as String?;

      if (publicKey == null) continue;

      final encryptedKey = encryptSessionKeyWithReceiverPublicKey(
        newSessionKey,
        publicKey,
      );

      final keyRef = _firestore
          .collection('conversations')
          .doc(conversationId)
          .collection('e2ee_keys')
          .doc(uid);

      batch.set(keyRef, {
        'encryptedKey': encryptedKey,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();

    _cachedSessionKeys[conversationId] = newSessionKey;
    return newSessionKey;
  }

  // =========================================================
  // 6. AES-GCM ENCRYPT MESSAGE
  // =========================================================

  /// Mã hóa tin nhắn thô bằng khóa phiên đối xứng (AES-256-GCM).
  /// IV ngẫu nhiên 12 byte được sinh mới cho mỗi tin nhắn và đóng gói cùng ciphertext.
  String encryptMessage(String plainText, String sessionKey) {
    try {
      final key = enc.Key(Uint8List.fromList(base64.decode(sessionKey)));
      final iv = enc.IV.fromSecureRandom(12);

      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
      final encrypted = encrypter.encrypt(plainText, iv: iv);

      return jsonEncode({
        'iv': iv.base64,
        'data': encrypted.base64,
      });
    } catch (e) {
      throw Exception('Encrypt message failed: $e');
    }
  }

  // =========================================================
  // 7. AES-GCM DECRYPT MESSAGE
  // =========================================================

  /// Giải mã tin nhắn bằng khóa phiên đối xứng (AES-256-GCM).
  String decryptMessage(String encryptedPayload, String sessionKey) {
    try {
      final payload = jsonDecode(encryptedPayload) as Map<String, dynamic>;

      final iv = enc.IV.fromBase64(payload['iv'] as String);
      final encryptedData = enc.Encrypted.fromBase64(payload['data'] as String);
      final key = enc.Key(Uint8List.fromList(base64.decode(sessionKey)));

      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));

      return encrypter.decrypt(encryptedData, iv: iv);
    } catch (e) {
      return '[Không thể giải mã tin nhắn]';
    }
  }

  // =========================================================
  // 8. CLEAR SESSION CACHE
  // =========================================================

  /// Xóa toàn bộ khóa phiên đang được cache trong bộ nhớ.
  void clearSessionCache() {
    _cachedSessionKeys.clear();
  }

  // =========================================================
  // 9. REMOVE LOCAL KEYS
  // =========================================================

  /// Xóa cặp khóa RSA cục bộ khỏi Secure Storage và bộ nhớ trong.
  Future<void> clearLocalKeys() async {
    await _secureStorage.delete(key: 'e2ee_private_key');
    await _secureStorage.delete(key: 'e2ee_public_key');

    _localPrivateKey = null;
    _localPublicKey = null;
  }

  // =========================================================
  // 10. CLEAR KEYS ON LOGOUT
  // =========================================================

  /// Xóa toàn bộ khóa RSA cục bộ và cache khóa phiên khi đăng xuất.
  /// ⚠️ BẮT BUỘC gọi hàm này khi đăng xuất để tránh user khác
  /// dùng nhầm Private Key cũ trên cùng thiết bị.
  Future<void> clearKeysOnLogout() async {
    clearSessionCache();
    await clearLocalKeys();
  }

  // =========================================================
  // 11. GETTERS
  // =========================================================

  /// Trả về Public Key PEM của thiết bị hiện tại (null nếu chưa khởi tạo).
  String? get localPublicKey => _localPublicKey;
}
