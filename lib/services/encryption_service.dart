// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

import 'e2ee_service.dart';

enum PayloadType { e2eeGcm, legacyCbc, plain }

class _PayloadInfo {
  final PayloadType type;
  final String raw;
  const _PayloadInfo(this.type, this.raw);
}

class EncryptionService {
  EncryptionService._internal();
  static final EncryptionService _instance = EncryptionService._internal();
  factory EncryptionService() => _instance;

  final E2EEService _e2ee = E2EEService();

  static const String _legacySalt = 'APP_CHAT_PLUS_SECURE_SALT_2026';

  static final _legacyPayloadRegex = RegExp(r'^[A-Za-z0-9+/=]+=*:[A-Za-z0-9+/=]+=*$');

  enc.Key _generateLegacyKey(String conversationId) {
    final bytes = utf8.encode(conversationId + _legacySalt);
    final digest = sha256.convert(bytes);
    return enc.Key(Uint8List.fromList(digest.bytes));
  }

  String encryptMessageLegacy(String plainText, String conversationId) {
    if (plainText.isEmpty || _isSkippable(plainText)) return plainText;
    try {
      final key = _generateLegacyKey(conversationId);
      final iv = enc.IV.fromSecureRandom(16);
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      final encrypted = encrypter.encrypt(plainText, iv: iv);
      return '${iv.base64}:${encrypted.base64}';
    } catch (e) {
      debugPrint('[EncryptionService] ❌ Legacy encrypt error: $e');
      return plainText;
    }
  }

  String decryptMessageLegacy(String encryptedText, String conversationId) {
    if (encryptedText.isEmpty) return encryptedText;
    try {
      final parts = encryptedText.split(':');
      if (parts.length != 2) return encryptedText;
      final iv = enc.IV.fromBase64(parts[0]);
      final key = _generateLegacyKey(conversationId);
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      return encrypter.decrypt64(parts[1], iv: iv);
    } catch (e) {
      debugPrint('[EncryptionService] ❌ Legacy decrypt error: $e');
      return '🔒 [Tin nhắn không thể giải mã]';
    }
  }

  Future<String> encryptPayload(
    String plainText,
    String conversationId,
    List<String> participantIds,
    String currentUserId,
  ) async {
    if (plainText.isEmpty || _isSkippable(plainText)) return plainText;

    if (!_e2ee.isInitialized) await _e2ee.loadLocalKeys();

    if (_e2ee.isInitialized) {
      try {
        return await _e2ee.encryptPayload(
          plainText,
          conversationId,
          participantIds,
          currentUserId,
        );
      } on E2EEException catch (e) {
        debugPrint(
          '[EncryptionService] ⚠️ E2EE encrypt failed (${e.type.name}), '
          'falling back to legacy: $e',
        );
      } catch (e) {
        debugPrint(
          '[EncryptionService] ⚠️ E2EE encrypt unexpected error, falling back: $e',
        );
      }
    }

    debugPrint('[EncryptionService] 🔄 Using Legacy-CBC fallback');
    return encryptMessageLegacy(plainText, conversationId);
  }

  Future<String> decryptPayload(
    String encryptedText,
    String conversationId,
    List<String> participantIds,
    String currentUserId,
  ) async {
    if (encryptedText.isEmpty) return encryptedText;

    final info = _detectPayloadType(encryptedText);

    switch (info.type) {
      case PayloadType.plain:
        return encryptedText;

      case PayloadType.e2eeGcm:
        return _decryptE2EE(
          encryptedText,
          conversationId,
          participantIds,
          currentUserId,
        );

      case PayloadType.legacyCbc:
        return decryptMessageLegacy(encryptedText, conversationId);
    }
  }

  Future<String> _decryptE2EE(
    String encryptedText,
    String conversationId,
    List<String> participantIds,
    String currentUserId,
  ) async {
    if (!_e2ee.isInitialized) await _e2ee.loadLocalKeys();

    if (!_e2ee.isInitialized) {
      debugPrint(
        '[EncryptionService] ⚠️ Không có khóa cục bộ để giải mã E2EE',
      );
      return '🔒 [Thiết bị chưa có khóa — không thể giải mã]';
    }

    try {
      return await _e2ee.decryptPayload(
        encryptedText,
        conversationId,
        participantIds,
        currentUserId,
      );
    } on E2EEException catch (e) {
      debugPrint(
        '[EncryptionService] ❌ E2EE decrypt error (${e.type.name}): $e',
      );

      switch (e.type) {
        case E2EEErrorType.keyNotInitialized:
          return '🔒 [Thiết bị chưa có khóa — không thể giải mã]';

        case E2EEErrorType.invalidPayload:
          debugPrint(
            '[EncryptionService] 🔄 Invalid payload, thử Legacy-CBC fallback...',
          );
          final legacyResult = decryptMessageLegacy(encryptedText, conversationId);

          if (legacyResult.startsWith('🔒')) {
            return '⚠️ [Dữ liệu tin nhắn bị hỏng]';
          }
          return legacyResult;

        case E2EEErrorType.decryptionFailed:
          debugPrint(
            '[EncryptionService] 🔄 decryptionFailed — evict cache và thử lại...',
          );
          _e2ee.evictSessionKey(conversationId);

          try {
            return await _e2ee.decryptPayload(
              encryptedText,
              conversationId,
              participantIds,
              currentUserId,
            );
          } catch (retryErr) {
            debugPrint(
              '[EncryptionService] ❌ Retry thất bại: $retryErr',
            );
            return '🔒 [Tin nhắn được mã hóa — không thể giải mã]';
          }

        default:
          return '🔒 [Tin nhắn được mã hóa — không thể giải mã]';
      }
    } catch (e) {
      debugPrint('[EncryptionService] ❌ E2EE decrypt unexpected: $e');
      return '🔒 [Tin nhắn được mã hóa — không thể giải mã]';
    }
  }

  Future<List<String>> decryptBatch(
    List<String> encryptedMessages,
    String conversationId,
    List<String> participantIds,
    String currentUserId, {
    int maxConcurrent = 5,
  }) async {
    final results = List<String>.filled(encryptedMessages.length, '');

    for (int i = 0; i < encryptedMessages.length; i += maxConcurrent) {
      final end = (i + maxConcurrent).clamp(0, encryptedMessages.length);
      final batch = encryptedMessages.sublist(i, end);

      final batchResults = await Future.wait(
        batch.map(
          (msg) => decryptPayload(
            msg,
            conversationId,
            participantIds,
            currentUserId,
          ),
        ),
      );

      for (int j = 0; j < batchResults.length; j++) {
        results[i + j] = batchResults[j];
      }
    }

    return results;
  }

  bool isEncrypted(String text) {
    if (text.isEmpty) return false;
    return _detectPayloadType(text).type != PayloadType.plain;
  }

  PayloadType detectPayloadType(String text) => _detectPayloadType(text).type;

  _PayloadInfo _detectPayloadType(String text) {
    final trimmed = text.trim();

    if (_isSkippable(trimmed)) {
      return _PayloadInfo(PayloadType.plain, trimmed);
    }

    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map && decoded.containsKey('iv') && decoded.containsKey('data')) {
          final iv = decoded['iv']?.toString() ?? '';
          final data = decoded['data']?.toString() ?? '';
          if (iv.isNotEmpty && data.isNotEmpty) {
            return _PayloadInfo(PayloadType.e2eeGcm, trimmed);
          }
        }
      } catch (_) {}
    }

    if (_legacyPayloadRegex.hasMatch(trimmed)) {
      return _PayloadInfo(PayloadType.legacyCbc, trimmed);
    }

    return _PayloadInfo(PayloadType.plain, trimmed);
  }

  bool _isSkippable(String text) => text.startsWith('http://') || text.startsWith('https://');
}
