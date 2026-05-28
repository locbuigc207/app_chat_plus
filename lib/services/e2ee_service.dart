// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:basic_utils/basic_utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart' as pc;

// =========================================================
// MODELS
// =========================================================

/// Kết quả mã hóa đầy đủ, bao gồm IV + ciphertext.
class EncryptedPayload {
  final String iv;
  final String data;
  final String? hmac; // HMAC-SHA256 integrity check (optional)

  const EncryptedPayload({
    required this.iv,
    required this.data,
    this.hmac,
  });

  factory EncryptedPayload.fromJson(Map<String, dynamic> json) =>
      EncryptedPayload(
        iv: json['iv'] as String,
        data: json['data'] as String,
        hmac: json['hmac'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'iv': iv,
        'data': data,
        if (hmac != null) 'hmac': hmac,
      };

  String toJsonString() => jsonEncode(toJson());
}

/// Lỗi E2EE có phân loại rõ ràng.
enum E2EEErrorType {
  keyNotInitialized,
  encryptionFailed,
  decryptionFailed,
  keyDistributionFailed,
  storageError,
  invalidPayload,
}

class E2EEException implements Exception {
  final E2EEErrorType type;
  final String message;
  final Object? cause;

  const E2EEException(this.type, this.message, {this.cause});

  @override
  String toString() => 'E2EEException(${type.name}): $message'
      '${cause != null ? ' — caused by: $cause' : ''}';
}

// =========================================================
// TOP-LEVEL ISOLATE FUNCTION — RSA KEY GENERATION
// Phải là top-level để `compute()` serialize được.
// =========================================================

Map<String, String> _generateRSAKeyPairInIsolate(int keySize) {
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
        pc.RSAKeyGeneratorParameters(BigInt.parse('65537'), keySize, 64),
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

// =========================================================
// E2EE SERVICE
// =========================================================

class E2EEService {
  // ── Singleton ──────────────────────────────────────────
  E2EEService._internal();
  static final E2EEService _instance = E2EEService._internal();
  factory E2EEService() => _instance;

  // ── Dependencies ───────────────────────────────────────
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  // ── In-memory state ────────────────────────────────────
  String? _localPrivateKey;
  String? _localPublicKey;

  /// LRU-style cache với giới hạn tối đa để tránh memory leak
  final Map<String, _CachedKey> _sessionKeyCache = {};
  static const int _maxCacheSize = 50;

  // ── Storage keys ───────────────────────────────────────
  static const _kPrivateKey = 'e2ee_private_key_v2';
  static const _kPublicKey = 'e2ee_public_key_v2';

  // ── RSA key size ───────────────────────────────────────
  /// 4096-bit cho bảo mật tối đa; dùng 2048 nếu performance là ưu tiên
  static const int _rsaKeySize = 2048;

  // =========================================================
  // 1. KHỞI TẠO & QUẢN LÝ KEYPAIR
  // =========================================================

  /// Kiểm tra xem user hiện tại đã có keypair chưa.
  bool get isInitialized => _localPrivateKey != null && _localPublicKey != null;

  /// Tải khóa từ Secure Storage vào bộ nhớ (không tạo mới).
  /// Gọi khi app khởi động hoặc sau khi đăng nhập.
  Future<bool> loadLocalKeys() async {
    try {
      _localPrivateKey = await _secureStorage.read(key: _kPrivateKey);
      _localPublicKey = await _secureStorage.read(key: _kPublicKey);
      return isInitialized;
    } catch (e) {
      throw E2EEException(
        E2EEErrorType.storageError,
        'Không thể đọc khóa từ Secure Storage',
        cause: e,
      );
    }
  }

  /// Sinh cặp khóa RSA mới hoặc tái sử dụng nếu đã tồn tại.
  /// - Chạy trên Isolate riêng (tránh lag UI).
  /// - Lưu vào Keychain/Keystore (bảo mật phần cứng).
  /// - Đẩy Public Key lên Firestore.
  Future<void> generateAndStoreUserKeys(
    String userId, {
    bool forceRegenerate = false,
  }) async {
    if (!forceRegenerate) {
      await loadLocalKeys();
      if (isInitialized) return;
    }

    debugPrint('[E2EE] 🔑 Đang tạo khóa RSA-$_rsaKeySize trên Isolate...');

    final keys = await compute(_generateRSAKeyPairInIsolate, _rsaKeySize);

    _localPublicKey = keys['publicKey']!;
    _localPrivateKey = keys['privateKey']!;

    try {
      await Future.wait([
        _secureStorage.write(key: _kPrivateKey, value: _localPrivateKey),
        _secureStorage.write(key: _kPublicKey, value: _localPublicKey),
      ]);
    } catch (e) {
      throw E2EEException(
        E2EEErrorType.storageError,
        'Không thể lưu khóa vào Secure Storage',
        cause: e,
      );
    }

    await _uploadPublicKey(userId, _localPublicKey!);
    debugPrint('[E2EE] ✅ Tạo và lưu khóa thành công.');
  }

  /// Đẩy Public Key lên Firestore cho user này.
  Future<void> _uploadPublicKey(String userId, String publicKeyPem) async {
    try {
      await _firestore.collection('users').doc(userId).set(
        {
          'publicKey': publicKeyPem,
          'keyUpdatedAt': FieldValue.serverTimestamp(),
          'keyVersion': _rsaKeySize,
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      throw E2EEException(
        E2EEErrorType.keyDistributionFailed,
        'Không thể đẩy Public Key lên Firestore',
        cause: e,
      );
    }
  }

  // =========================================================
  // 2. KHÓA PHIÊN (SESSION KEY)
  // =========================================================

  /// Sinh khóa phiên AES-256 ngẫu nhiên (32 byte, base64).
  String generateRandomSessionKey() {
    final bytes = Uint8List.fromList(
      List.generate(32, (_) => Random.secure().nextInt(256)),
    );
    return base64.encode(bytes);
  }

  /// Thiết lập hoặc lấy khóa phiên cho một cuộc hội thoại.
  ///
  /// Logic:
  ///   1. Cache in-memory → trả về ngay.
  ///   2. Firestore → giải mã và trả về.
  ///   3. Tạo mới → phân phối cho tất cả members → lưu cache.
  Future<String> getOrCreateSessionKey({
    required String conversationId,
    required List<String> participantIds,
    required String currentUserId,
  }) async {
    // 1. Cache hit
    final cached = _sessionKeyCache[conversationId];
    if (cached != null && !cached.isExpired) {
      return cached.key;
    }

    // 2. Kiểm tra Firestore
    final myKeyRef = _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('e2ee_keys')
        .doc(currentUserId);

    final snapshot = await myKeyRef.get();

    if (snapshot.exists) {
      final encryptedKey = snapshot.data()?['encryptedKey'] as String?;
      if (encryptedKey == null) {
        throw const E2EEException(
          E2EEErrorType.invalidPayload,
          'encryptedKey không tồn tại trong Firestore',
        );
      }
      final sessionKey = decryptSessionKeyWithMyPrivateKey(encryptedKey);
      _cacheSessionKey(conversationId, sessionKey);
      return sessionKey;
    }

    // 3. Tạo mới và phân phối
    return _createAndDistributeSessionKey(
      conversationId: conversationId,
      participantIds: participantIds,
      currentUserId: currentUserId,
    );
  }

  Future<String> _createAndDistributeSessionKey({
    required String conversationId,
    required List<String> participantIds,
    required String currentUserId,
  }) async {
    final newSessionKey = generateRandomSessionKey();
    final batch = _firestore.batch();
    int distributed = 0;

    // Fetch tất cả public keys song song để tăng tốc
    final publicKeyFutures = participantIds.map(
      (uid) => _firestore.collection('users').doc(uid).get(),
    );
    final userDocs = await Future.wait(publicKeyFutures);

    for (int i = 0; i < participantIds.length; i++) {
      final uid = participantIds[i];
      final publicKey = userDocs[i].data()?['publicKey'] as String?;

      if (publicKey == null) {
        debugPrint('[E2EE] ⚠️ Bỏ qua user $uid — không có publicKey');
        continue;
      }

      try {
        final encryptedKey = encryptSessionKeyWithPublicKey(
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
          'createdBy': currentUserId,
          'keyVersion': 1,
        });
        distributed++;
      } catch (e) {
        debugPrint('[E2EE] ❌ Không thể mã hóa key cho user $uid: $e');
      }
    }

    if (distributed == 0) {
      throw const E2EEException(
        E2EEErrorType.keyDistributionFailed,
        'Không phân phối được khóa cho bất kỳ thành viên nào',
      );
    }

    try {
      await batch.commit();
    } catch (e) {
      throw E2EEException(
        E2EEErrorType.keyDistributionFailed,
        'Batch write thất bại khi phân phối khóa phiên',
        cause: e,
      );
    }

    _cacheSessionKey(conversationId, newSessionKey);
    debugPrint(
        '[E2EE] ✅ Phân phối khóa phiên cho $distributed/${participantIds.length} thành viên');
    return newSessionKey;
  }

  void _cacheSessionKey(String conversationId, String key) {
    // Giới hạn cache size — xoá entry cũ nhất
    if (_sessionKeyCache.length >= _maxCacheSize) {
      final oldest = _sessionKeyCache.entries
          .reduce((a, b) => a.value.cachedAt.isBefore(b.value.cachedAt) ? a : b)
          .key;
      _sessionKeyCache.remove(oldest);
    }
    _sessionKeyCache[conversationId] = _CachedKey(key);
  }

  // =========================================================
  // 3. RSA ENCRYPT / DECRYPT SESSION KEY
  // =========================================================

  /// Mã hóa sessionKey bằng Public Key của đối phương (RSA-OAEP).
  String encryptSessionKeyWithPublicKey(
    String sessionKey,
    String publicKeyPem,
  ) {
    try {
      final rsaPublicKey = CryptoUtils.rsaPublicKeyFromPem(publicKeyPem);
      final encrypter = enc.Encrypter(enc.RSA(publicKey: rsaPublicKey));
      return encrypter.encrypt(sessionKey).base64;
    } catch (e) {
      throw E2EEException(
        E2EEErrorType.encryptionFailed,
        'RSA encrypt session key thất bại',
        cause: e,
      );
    }
  }

  /// Giải mã sessionKey bằng Private Key của bản thân (RSA-OAEP).
  String decryptSessionKeyWithMyPrivateKey(String encryptedBase64) {
    if (_localPrivateKey == null) {
      throw const E2EEException(
        E2EEErrorType.keyNotInitialized,
        'Private key chưa được tải. Gọi loadLocalKeys() hoặc generateAndStoreUserKeys() trước.',
      );
    }
    try {
      final rsaPrivateKey = CryptoUtils.rsaPrivateKeyFromPem(_localPrivateKey!);
      final encrypter = enc.Encrypter(enc.RSA(privateKey: rsaPrivateKey));
      return encrypter.decrypt(enc.Encrypted.fromBase64(encryptedBase64));
    } catch (e) {
      throw E2EEException(
        E2EEErrorType.decryptionFailed,
        'RSA decrypt session key thất bại',
        cause: e,
      );
    }
  }

  // =========================================================
  // 4. AES-GCM ENCRYPT MESSAGE
  // =========================================================

  /// Mã hóa tin nhắn bằng AES-256-GCM.
  /// IV ngẫu nhiên 12 byte được sinh mới cho mỗi tin nhắn.
  /// Trả về JSON string chứa iv + data (+ hmac nếu withHmac = true).
  String encryptMessage(
    String plainText,
    String sessionKey, {
    bool withHmac = false,
  }) {
    try {
      final keyBytes = _decodeSessionKey(sessionKey);
      final key = enc.Key(keyBytes);
      final iv = enc.IV.fromSecureRandom(12);

      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
      final encrypted = encrypter.encrypt(plainText, iv: iv);

      String? hmac;
      if (withHmac) {
        hmac = _computeHmac(keyBytes, iv.base64 + encrypted.base64);
      }

      return EncryptedPayload(
        iv: iv.base64,
        data: encrypted.base64,
        hmac: hmac,
      ).toJsonString();
    } catch (e) {
      throw E2EEException(
        E2EEErrorType.encryptionFailed,
        'AES-GCM encrypt thất bại',
        cause: e,
      );
    }
  }

  // =========================================================
  // 5. AES-GCM DECRYPT MESSAGE
  // =========================================================

  /// Giải mã tin nhắn bằng AES-256-GCM.
  /// Trả về plaintext hoặc ném [E2EEException] nếu thất bại.
  String decryptMessage(String encryptedPayload, String sessionKey) {
    try {
      final payload = EncryptedPayload.fromJson(
          jsonDecode(encryptedPayload) as Map<String, dynamic>);
      final keyBytes = _decodeSessionKey(sessionKey);

      // Kiểm tra HMAC nếu có
      if (payload.hmac != null) {
        final expectedHmac = _computeHmac(keyBytes, payload.iv + payload.data);
        if (!_constantTimeEqual(expectedHmac, payload.hmac!)) {
          throw const E2EEException(
            E2EEErrorType.invalidPayload,
            'HMAC verification thất bại — tin nhắn có thể bị giả mạo',
          );
        }
      }

      final key = enc.Key(keyBytes);
      final iv = enc.IV.fromBase64(payload.iv);
      final encryptedData = enc.Encrypted.fromBase64(payload.data);
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));

      return encrypter.decrypt(encryptedData, iv: iv);
    } on E2EEException {
      rethrow;
    } catch (e) {
      throw E2EEException(
        E2EEErrorType.decryptionFailed,
        'AES-GCM decrypt thất bại',
        cause: e,
      );
    }
  }

  // =========================================================
  // 6. CONVENIENCE: FULL ENCRYPT / DECRYPT PIPELINE
  // =========================================================

  /// Pipeline đầy đủ: lấy session key → mã hóa tin nhắn.
  Future<String> encryptPayload(
    String plainText,
    String conversationId,
    List<String> participantIds,
    String currentUserId,
  ) async {
    final sessionKey = await getOrCreateSessionKey(
      conversationId: conversationId,
      participantIds: participantIds,
      currentUserId: currentUserId,
    );
    return encryptMessage(plainText, sessionKey);
  }

  /// Pipeline đầy đủ: lấy session key → giải mã tin nhắn.
  Future<String> decryptPayload(
    String encryptedPayload,
    String conversationId,
    List<String> participantIds,
    String currentUserId,
  ) async {
    try {
      final sessionKey = await getOrCreateSessionKey(
        conversationId: conversationId,
        participantIds: participantIds,
        currentUserId: currentUserId,
      );
      return decryptMessage(encryptedPayload, sessionKey);
    } on E2EEException catch (e) {
      debugPrint('[E2EE] decryptPayload error: $e');
      return '[🔒 Không thể giải mã]';
    }
  }

  // =========================================================
  // 7. KEY ROTATION
  // =========================================================

  /// Xoay vòng khóa phiên cho một cuộc hội thoại.
  /// Hữu ích khi thêm/bớt thành viên hoặc theo lịch định kỳ.
  Future<String> rotateSessionKey({
    required String conversationId,
    required List<String> participantIds,
    required String currentUserId,
  }) async {
    // Xoá cache + Firestore keys cũ
    _sessionKeyCache.remove(conversationId);

    // Xoá e2ee_keys subcollection (batch delete)
    final keysRef = _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('e2ee_keys');

    final oldKeys = await keysRef.get();
    final deleteBatch = _firestore.batch();
    for (final doc in oldKeys.docs) {
      deleteBatch.delete(doc.reference);
    }
    await deleteBatch.commit();

    // Phân phối key mới
    return _createAndDistributeSessionKey(
      conversationId: conversationId,
      participantIds: participantIds,
      currentUserId: currentUserId,
    );
  }

  // =========================================================
  // 8. THÊM THÀNH VIÊN VÀO CONVERSATION ĐÃ TỒN TẠI
  // =========================================================

  /// Phân phối khóa phiên hiện tại cho một thành viên mới được thêm vào.
  Future<void> addParticipantToConversation({
    required String conversationId,
    required String newParticipantId,
    required String currentUserId,
    required List<String> allParticipantIds,
  }) async {
    // Lấy session key hiện tại
    final sessionKey = await getOrCreateSessionKey(
      conversationId: conversationId,
      participantIds: allParticipantIds,
      currentUserId: currentUserId,
    );

    // Lấy public key của thành viên mới
    final userDoc =
        await _firestore.collection('users').doc(newParticipantId).get();
    final publicKey = userDoc.data()?['publicKey'] as String?;

    if (publicKey == null) {
      throw E2EEException(
        E2EEErrorType.keyDistributionFailed,
        'Không tìm thấy publicKey của user $newParticipantId',
      );
    }

    final encryptedKey = encryptSessionKeyWithPublicKey(sessionKey, publicKey);

    await _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('e2ee_keys')
        .doc(newParticipantId)
        .set({
      'encryptedKey': encryptedKey,
      'createdAt': FieldValue.serverTimestamp(),
      'addedBy': currentUserId,
    });
  }

  // =========================================================
  // 9. CACHE & CLEANUP
  // =========================================================

  void clearSessionCache() => _sessionKeyCache.clear();

  void evictSessionKey(String conversationId) =>
      _sessionKeyCache.remove(conversationId);

  Future<void> clearLocalKeys() async {
    try {
      await Future.wait([
        _secureStorage.delete(key: _kPrivateKey),
        _secureStorage.delete(key: _kPublicKey),
      ]);
    } catch (e) {
      debugPrint('[E2EE] ⚠️ clearLocalKeys error: $e');
    }
    _localPrivateKey = null;
    _localPublicKey = null;
  }

  /// Gọi khi đăng xuất: xoá tất cả khóa trong bộ nhớ và Secure Storage.
  Future<void> clearKeysOnLogout() async {
    clearSessionCache();
    await clearLocalKeys();
    debugPrint('[E2EE] 🧹 Đã dọn sạch tất cả khóa.');
  }

  // =========================================================
  // 10. GETTERS
  // =========================================================

  String? get localPublicKey => _localPublicKey;

  int get cachedKeyCount => _sessionKeyCache.length;

  // =========================================================
  // PRIVATE HELPERS
  // =========================================================

  /// Decode và validate session key (phải là 32 byte = 256 bit).
  Uint8List _decodeSessionKey(String sessionKey) {
    try {
      final bytes = Uint8List.fromList(base64.decode(sessionKey));
      if (bytes.length != 32) {
        throw E2EEException(
          E2EEErrorType.invalidPayload,
          'Session key phải là 32 byte, nhận được ${bytes.length}',
        );
      }
      return bytes;
    } on E2EEException {
      rethrow;
    } catch (e) {
      throw E2EEException(
        E2EEErrorType.invalidPayload,
        'Session key không hợp lệ',
        cause: e,
      );
    }
  }

  /// Tính HMAC-SHA256 cho integrity check.
  String _computeHmac(Uint8List keyBytes, String data) {
    final hmacSha256 = pc.HMac(pc.SHA256Digest(), 64);
    hmacSha256.init(pc.KeyParameter(keyBytes));
    final dataBytes = Uint8List.fromList(utf8.encode(data));
    final out = Uint8List(hmacSha256.macSize);
    hmacSha256.update(dataBytes, 0, dataBytes.length);
    hmacSha256.doFinal(out, 0);
    return base64.encode(out);
  }

  /// So sánh constant-time để tránh timing attacks.
  bool _constantTimeEqual(String a, String b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }
}

// =========================================================
// INTERNAL MODELS
// =========================================================

class _CachedKey {
  final String key;
  final DateTime cachedAt;

  // Cache có hiệu lực 24h
  static const _ttl = Duration(hours: 24);

  _CachedKey(this.key) : cachedAt = DateTime.now();

  bool get isExpired => DateTime.now().difference(cachedAt) > _ttl;
}
