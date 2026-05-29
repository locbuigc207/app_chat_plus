// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:basic_utils/basic_utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart' as pc;

class EncryptedPayload {
  final String iv;
  final String data;
  final String? hmac;

  const EncryptedPayload({
    required this.iv,
    required this.data,
    this.hmac,
  });

  factory EncryptedPayload.fromJson(Map<String, dynamic> json) => EncryptedPayload(
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

class E2EEService {
  E2EEService._internal();
  static final E2EEService _instance = E2EEService._internal();
  factory E2EEService() => _instance;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  String? _localPrivateKey;
  String? _localPublicKey;

  final Map<String, _CachedKey> _sessionKeyCache = {};
  static const int _maxCacheSize = 50;

  static const _kPrivateKey = 'e2ee_private_key_v2';
  static const _kPublicKey = 'e2ee_public_key_v2';
  static const int _rsaKeySize = 2048;

  final Map<String, Completer<String>> _pendingKeyCreations = {};

  bool get isInitialized => _localPrivateKey != null && _localPublicKey != null;

  Future<bool> loadLocalKeys() async {
    try {
      _localPrivateKey = await _secureStorage.read(key: _kPrivateKey);
      _localPublicKey = await _secureStorage.read(key: _kPublicKey);

      if (_localPrivateKey != null && _localPrivateKey!.trim().isEmpty) {
        _localPrivateKey = null;
      }
      if (_localPublicKey != null && _localPublicKey!.trim().isEmpty) {
        _localPublicKey = null;
      }

      return isInitialized;
    } catch (e) {
      throw E2EEException(
        E2EEErrorType.storageError,
        'Không thể đọc khóa từ Secure Storage',
        cause: e,
      );
    }
  }

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

    final pub = keys['publicKey'] ?? '';
    final priv = keys['privateKey'] ?? '';

    if (pub.isEmpty || priv.isEmpty) {
      throw const E2EEException(
        E2EEErrorType.encryptionFailed,
        'RSA key generation trả về key rỗng',
      );
    }

    _localPublicKey = pub;
    _localPrivateKey = priv;

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

  String generateRandomSessionKey() {
    final bytes = Uint8List.fromList(
      List.generate(32, (_) => Random.secure().nextInt(256)),
    );
    return base64.encode(bytes);
  }

  Future<String> getOrCreateSessionKey({
    required String conversationId,
    required List<String> participantIds,
    required String currentUserId,
  }) async {
    final cached = _sessionKeyCache[conversationId];
    if (cached != null && !cached.isExpired) {
      return cached.key;
    }

    if (_pendingKeyCreations.containsKey(conversationId)) {
      debugPrint('[E2EE] ⏳ Đang chờ session key cho $conversationId...');
      return _pendingKeyCreations[conversationId]!.future;
    }

    final completer = Completer<String>();
    _pendingKeyCreations[conversationId] = completer;

    try {
      final key = await _resolveSessionKey(
        conversationId: conversationId,
        participantIds: participantIds,
        currentUserId: currentUserId,
      );
      completer.complete(key);
      return key;
    } catch (e) {
      completer.completeError(e);
      rethrow;
    } finally {
      _pendingKeyCreations.remove(conversationId);
    }
  }

  Future<String> _resolveSessionKey({
    required String conversationId,
    required List<String> participantIds,
    required String currentUserId,
  }) async {
    final myKeyRef = _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('e2ee_keys')
        .doc(currentUserId);

    final snapshot = await myKeyRef.get();

    if (snapshot.exists) {
      final encryptedKey = snapshot.data()?['encryptedKey'] as String?;

      if (encryptedKey == null || encryptedKey.trim().isEmpty) {
        debugPrint(
          '[E2EE] ⚠️ encryptedKey rỗng cho $conversationId, tạo mới...',
        );

        return _createAndDistributeSessionKey(
          conversationId: conversationId,
          participantIds: participantIds,
          currentUserId: currentUserId,
        );
      }

      try {
        final sessionKey = decryptSessionKeyWithMyPrivateKey(encryptedKey);

        _validateSessionKeyBytes(sessionKey);

        _cacheSessionKey(conversationId, sessionKey);
        return sessionKey;
      } on E2EEException catch (e) {
        debugPrint(
          '[E2EE] ⚠️ Decrypt session key thất bại ($e), tạo lại key...',
        );

        evictSessionKey(conversationId);
        return _createAndDistributeSessionKey(
          conversationId: conversationId,
          participantIds: participantIds,
          currentUserId: currentUserId,
        );
      }
    }

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

    _validateSessionKeyBytes(newSessionKey);

    final batch = _firestore.batch();
    int distributed = 0;

    final publicKeyFutures = participantIds.map(
      (uid) => _firestore.collection('users').doc(uid).get(),
    );
    final userDocs = await Future.wait(publicKeyFutures);

    for (int i = 0; i < participantIds.length; i++) {
      final uid = participantIds[i];
      final publicKey = userDocs[i].data()?['publicKey'] as String?;

      if (publicKey == null || publicKey.trim().isEmpty) {
        debugPrint('[E2EE] ⚠️ Bỏ qua user $uid — publicKey rỗng hoặc null');
        continue;
      }

      try {
        final encryptedKey = encryptSessionKeyWithPublicKey(
          newSessionKey,
          publicKey,
        );

        if (encryptedKey.isEmpty) {
          debugPrint('[E2EE] ⚠️ encryptedKey rỗng cho user $uid, bỏ qua');
          continue;
        }

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
      '[E2EE] ✅ Phân phối khóa phiên cho $distributed/${participantIds.length} thành viên',
    );
    return newSessionKey;
  }

  void _cacheSessionKey(String conversationId, String key) {
    if (_sessionKeyCache.length >= _maxCacheSize) {
      final oldest = _sessionKeyCache.entries
          .reduce(
            (a, b) => a.value.cachedAt.isBefore(b.value.cachedAt) ? a : b,
          )
          .key;
      _sessionKeyCache.remove(oldest);
    }
    _sessionKeyCache[conversationId] = _CachedKey(key);
  }

  String encryptSessionKeyWithPublicKey(
    String sessionKey,
    String publicKeyPem,
  ) {
    if (sessionKey.isEmpty) {
      throw const E2EEException(
        E2EEErrorType.encryptionFailed,
        'sessionKey rỗng, không thể mã hóa',
      );
    }
    if (publicKeyPem.trim().isEmpty) {
      throw const E2EEException(
        E2EEErrorType.encryptionFailed,
        'publicKeyPem rỗng, không thể mã hóa',
      );
    }

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

  String decryptSessionKeyWithMyPrivateKey(String encryptedBase64) {
    if (_localPrivateKey == null) {
      throw const E2EEException(
        E2EEErrorType.keyNotInitialized,
        'Private key chưa được tải. Gọi loadLocalKeys() hoặc generateAndStoreUserKeys() trước.',
      );
    }

    if (encryptedBase64.trim().isEmpty) {
      throw const E2EEException(
        E2EEErrorType.decryptionFailed,
        'encryptedBase64 rỗng, không thể giải mã RSA',
      );
    }

    try {
      final rsaPrivateKey = CryptoUtils.rsaPrivateKeyFromPem(_localPrivateKey!);
      final encrypter = enc.Encrypter(enc.RSA(privateKey: rsaPrivateKey));
      final decrypted = encrypter.decrypt(enc.Encrypted.fromBase64(encryptedBase64));

      if (decrypted.isEmpty) {
        throw const E2EEException(
          E2EEErrorType.decryptionFailed,
          'RSA decrypt trả về chuỗi rỗng',
        );
      }

      return decrypted;
    } on E2EEException {
      rethrow;
    } catch (e) {
      throw E2EEException(
        E2EEErrorType.decryptionFailed,
        'RSA decrypt session key thất bại',
        cause: e,
      );
    }
  }

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

  String decryptMessage(String encryptedPayload, String sessionKey) {
    if (encryptedPayload.trim().isEmpty) {
      throw const E2EEException(
        E2EEErrorType.invalidPayload,
        'encryptedPayload rỗng',
      );
    }

    try {
      final payload = EncryptedPayload.fromJson(
        jsonDecode(encryptedPayload) as Map<String, dynamic>,
      );

      if (payload.iv.isEmpty || payload.data.isEmpty) {
        throw const E2EEException(
          E2EEErrorType.invalidPayload,
          'payload.iv hoặc payload.data rỗng',
        );
      }

      final keyBytes = _decodeSessionKey(sessionKey);

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
    } on E2EEException {
      rethrow;
    } catch (e) {
      throw E2EEException(
        E2EEErrorType.decryptionFailed,
        'Lỗi không xác định trong decryptPayload',
        cause: e,
      );
    }
  }

  Future<String> rotateSessionKey({
    required String conversationId,
    required List<String> participantIds,
    required String currentUserId,
  }) async {
    _sessionKeyCache.remove(conversationId);

    final keysRef =
        _firestore.collection('conversations').doc(conversationId).collection('e2ee_keys');

    final oldKeys = await keysRef.get();
    final deleteBatch = _firestore.batch();
    for (final doc in oldKeys.docs) {
      deleteBatch.delete(doc.reference);
    }
    await deleteBatch.commit();

    return _createAndDistributeSessionKey(
      conversationId: conversationId,
      participantIds: participantIds,
      currentUserId: currentUserId,
    );
  }

  Future<void> addParticipantToConversation({
    required String conversationId,
    required String newParticipantId,
    required String currentUserId,
    required List<String> allParticipantIds,
  }) async {
    final sessionKey = await getOrCreateSessionKey(
      conversationId: conversationId,
      participantIds: allParticipantIds,
      currentUserId: currentUserId,
    );

    final userDoc = await _firestore.collection('users').doc(newParticipantId).get();
    final publicKey = userDoc.data()?['publicKey'] as String?;

    if (publicKey == null || publicKey.trim().isEmpty) {
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

  void clearSessionCache() => _sessionKeyCache.clear();

  void evictSessionKey(String conversationId) => _sessionKeyCache.remove(conversationId);

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

  Future<void> clearKeysOnLogout() async {
    clearSessionCache();
    _pendingKeyCreations.clear();
    await clearLocalKeys();
    debugPrint('[E2EE] 🧹 Đã dọn sạch tất cả khóa.');
  }

  String? get localPublicKey => _localPublicKey;
  int get cachedKeyCount => _sessionKeyCache.length;

  Uint8List _decodeSessionKey(String sessionKey) {
    if (sessionKey.trim().isEmpty) {
      throw const E2EEException(
        E2EEErrorType.invalidPayload,
        'Session key rỗng — không thể decode',
      );
    }

    final Uint8List bytes;
    try {
      bytes = Uint8List.fromList(base64.decode(sessionKey));
    } catch (e) {
      throw E2EEException(
        E2EEErrorType.invalidPayload,
        'Session key không phải base64 hợp lệ',
        cause: e,
      );
    }

    if (bytes.isEmpty) {
      throw const E2EEException(
        E2EEErrorType.invalidPayload,
        'Session key decode ra 0 byte — key bị hỏng',
      );
    }
    if (bytes.length != 32) {
      throw E2EEException(
        E2EEErrorType.invalidPayload,
        'Session key phải là 32 byte (AES-256), nhận được ${bytes.length} byte',
      );
    }

    return bytes;
  }

  void _validateSessionKeyBytes(String sessionKey) {
    _decodeSessionKey(sessionKey);
  }

  String _computeHmac(Uint8List keyBytes, String data) {
    final hmacSha256 = pc.HMac(pc.SHA256Digest(), 64);
    hmacSha256.init(pc.KeyParameter(keyBytes));
    final dataBytes = Uint8List.fromList(utf8.encode(data));
    final out = Uint8List(hmacSha256.macSize);
    hmacSha256.update(dataBytes, 0, dataBytes.length);
    hmacSha256.doFinal(out, 0);
    return base64.encode(out);
  }

  bool _constantTimeEqual(String a, String b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }
}

class _CachedKey {
  final String key;
  final DateTime cachedAt;
  static const _ttl = Duration(hours: 24);

  _CachedKey(this.key) : cachedAt = DateTime.now();

  bool get isExpired => DateTime.now().difference(cachedAt) > _ttl;
}
