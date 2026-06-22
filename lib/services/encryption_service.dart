// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';

import 'e2ee_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ENUMS & HELPERS
// ─────────────────────────────────────────────────────────────────────────────

enum PayloadType { e2eeGcm, legacyCbc, plain }

class _PayloadInfo {
  final PayloadType type;
  final String raw;
  const _PayloadInfo(this.type, this.raw);
}

// ─────────────────────────────────────────────────────────────────────────────
// ENCRYPTION SERVICE  (facade over E2EEService + legacy CBC fallback)
// ─────────────────────────────────────────────────────────────────────────────

/// Single entry-point for all message encryption / decryption.
///
/// Strategy:
///  1. Try E2EE (AES-256-GCM + RSA session-key distribution).
///  2. Fall back to legacy AES-CBC keyed from the conversation ID.
///  3. Return plain text when neither applies.
///
/// GeoLocked messages, media URLs and other non-text types are **never**
/// encrypted — they are identified by [_isSkippable] and passed through.
class EncryptionService {
  EncryptionService._internal();
  static final EncryptionService _instance = EncryptionService._internal();
  factory EncryptionService() => _instance;

  final E2EEService _e2ee = E2EEService();

  // ── Legacy key derivation ─────────────────────────────────────────────────

  static const String _legacySalt = 'APP_CHAT_PLUS_SECURE_SALT_2026';

  static final _legacyPayloadRegex = RegExp(
    r'^[A-Za-z0-9+/=]+=*:[A-Za-z0-9+/=]+=*$',
  );

  enc.Key _generateLegacyKey(String conversationId) {
    final bytes = utf8.encode(conversationId + _legacySalt);
    final digest = sha256.convert(bytes);
    return enc.Key(Uint8List.fromList(digest.bytes));
  }

  // ── Legacy CBC ────────────────────────────────────────────────────────────

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

  // ── High-level E2EE encrypt/decrypt ───────────────────────────────────────

  /// Encrypts [plainText] for a conversation.
  ///
  /// Skips encryption for:
  ///  * HTTP(S) URLs (media, thumbnails, voice)
  ///  * JSON objects (geoLocked, polls, game payloads)
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
          '[EncryptionService] ⚠️ E2EE encrypt failed (${e.type.name}), falling back: $e',
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

  /// Decrypts [encryptedText] for a conversation.
  ///
  /// Auto-detects payload type (E2EE-GCM, Legacy-CBC, plain) and routes
  /// accordingly. Never throws — returns a human-readable error string on
  /// failure so the UI always has something to display.
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

  // ── E2EE decrypt (with graceful fallbacks) ────────────────────────────────

  Future<String> _decryptE2EE(
    String encryptedText,
    String conversationId,
    List<String> participantIds,
    String currentUserId,
  ) async {
    if (!_e2ee.isInitialized) await _e2ee.loadLocalKeys();

    if (!_e2ee.isInitialized) {
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
          // Might be a legacy payload mis-detected as GCM; try legacy
          final legacyResult = decryptMessageLegacy(
            encryptedText,
            conversationId,
          );
          if (legacyResult.startsWith('🔒')) {
            return '⚠️ [Dữ liệu tin nhắn bị hỏng]';
          }
          return legacyResult;

        case E2EEErrorType.decryptionFailed:
          // Session key might be stale; evict and retry once
          _e2ee.evictSessionKey(conversationId);
          try {
            return await _e2ee.decryptPayload(
              encryptedText,
              conversationId,
              participantIds,
              currentUserId,
            );
          } catch (_) {
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

  // ── Batch decrypt ─────────────────────────────────────────────────────────

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

  // ── Inspection helpers ────────────────────────────────────────────────────

  bool isEncrypted(String text) =>
      text.isNotEmpty && _detectPayloadType(text).type != PayloadType.plain;

  PayloadType detectPayloadType(String text) => _detectPayloadType(text).type;

  // ── Internal type detection ───────────────────────────────────────────────

  _PayloadInfo _detectPayloadType(String text) {
    final trimmed = text.trim();

    // Đồng bộ (A2): Bất kỳ nội dung nào bị skip (URL, Poll, Game, GeoLocked)
    // đều sẽ được trả về trực tiếp ở đây dưới dạng plain.
    if (_isSkippable(trimmed)) {
      return _PayloadInfo(PayloadType.plain, trimmed);
    }

    // E2EE-GCM: JSON with "iv" and "data" keys
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          final hasIv = decoded.containsKey('iv');
          final hasData = decoded.containsKey('data');
          if (hasIv && hasData) {
            final iv = decoded['iv']?.toString() ?? '';
            final data = decoded['data']?.toString() ?? '';
            if (iv.isNotEmpty && data.isNotEmpty) {
              return _PayloadInfo(PayloadType.e2eeGcm, trimmed);
            }
          }
        }
      } catch (_) {}
      // Any other fallback JSON
      return _PayloadInfo(PayloadType.plain, trimmed);
    }

    // Legacy CBC: "base64:base64"
    if (_legacyPayloadRegex.hasMatch(trimmed)) {
      return _PayloadInfo(PayloadType.legacyCbc, trimmed);
    }

    return _PayloadInfo(PayloadType.plain, trimmed);
  }

  /// Returns true for content that must never be encrypted:
  ///  * HTTP/HTTPS URLs (media, voice, file storage)
  ///  * JSON objects (geoLocked, polls, game states)
  bool _isSkippable(String text) {
    final t = text.trim();
    if (t.startsWith('http://') || t.startsWith('https://')) return true;

    // Bỏ qua mã hóa đối với các JSON payload của hệ thống (Poll, Game, Location)
    if (t.startsWith('{') && t.endsWith('}')) {
      try {
        final decoded = jsonDecode(t);
        if (decoded is Map) {
          // KHÔNG skip nếu đây là gói tin mã hóa E2EE thực sự (chứa 'iv' và 'data')
          if (decoded.containsKey('iv') && decoded.containsKey('data')) {
            return false;
          }

          // Siết điều kiện match (A3): Yêu cầu có đủ cả cụm 2 key đặc thù
          // để tránh false-positive với các đoạn text thông thường có chứa chuỗi JSON.
          if ((decoded.containsKey('question') &&
                  decoded.containsKey('options')) || // Dấu hiệu của Poll
              (decoded.containsKey('matchId') &&
                  decoded.containsKey(
                    'gameType',
                  )) || // Dấu hiệu của Game Center
              (decoded.containsKey('lat') && decoded.containsKey('lng'))) {
            // Dấu hiệu của GeoLocked
            return true;
          }
        }
      } catch (_) {}
    }
    return false;
  }
}
