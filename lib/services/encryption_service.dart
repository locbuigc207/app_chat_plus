// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';

import 'e2ee_service.dart';

// =========================================================
// MODELS
// =========================================================

/// Loại payload để phân biệt E2EE-GCM vs Legacy-CBC vs Plain.
enum PayloadType { e2eeGcm, legacyCbc, plain }

/// Kết quả phân tích payload đầu vào.
class _PayloadInfo {
  final PayloadType type;
  final String raw;
  const _PayloadInfo(this.type, this.raw);
}

// =========================================================
// ENCRYPTION SERVICE
// =========================================================

/// Lớp trung gian quản lý toàn bộ mã hóa/giải mã tin nhắn.
///
/// **Kiến trúc 2 lớp:**
/// - **E2EE (Production)**: AES-256-GCM với session key động từ [E2EEService].
/// - **Legacy (Fallback)**: AES-256-CBC với key tĩnh sinh từ conversationId,
///   dùng để tương thích ngược với lịch sử tin nhắn cũ trước khi triển khai E2EE.
///
/// **Logic phát hiện loại payload:**
/// - JSON `{"iv":...,"data":...}` → E2EE-GCM
/// - `"<base64>:<base64>"` → Legacy-CBC
/// - Còn lại (URL, plaintext) → Plain (không mã hóa)
class EncryptionService {
  // ── Singleton ──────────────────────────────────────────
  EncryptionService._internal();
  static final EncryptionService _instance = EncryptionService._internal();
  factory EncryptionService() => _instance;

  // ── Dependencies ───────────────────────────────────────
  final E2EEService _e2ee = E2EEService();

  // ── Legacy salt (obfuscated — đừng hardcode production key ở đây) ─────────
  // Trong production, nên đọc từ environment variable hoặc remote config.
  static const String _legacySalt = 'APP_CHAT_PLUS_SECURE_SALT_2026';

  // ── Regex nhận diện legacy payload: "<base64>:<base64>" ──────────────────
  static final _legacyPayloadRegex =
      RegExp(r'^[A-Za-z0-9+/=]+=*:[A-Za-z0-9+/=]+=*$');

  // =========================================================
  // 1. LEGACY LAYER — AES-256-CBC (Tương thích ngược)
  // =========================================================

  /// Sinh key AES-256 cố định từ `conversationId + salt` (SHA-256).
  enc.Key _generateLegacyKey(String conversationId) {
    final bytes = utf8.encode(conversationId + _legacySalt);
    final digest = sha256.convert(bytes);
    return enc.Key(Uint8List.fromList(digest.bytes));
  }

  /// Mã hóa bằng AES-256-CBC (Legacy).
  /// Trả về `"<iv_base64>:<ciphertext_base64>"` hoặc nguyên bản nếu lỗi.
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

  /// Giải mã AES-256-CBC (Legacy).
  /// Nhận `"<iv_base64>:<ciphertext_base64>"`.
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

  // =========================================================
  // 2. E2EE LAYER — AES-256-GCM (Production)
  // =========================================================

  /// Mã hóa qua E2EE-GCM với session key động.
  ///
  /// - URL/file → trả về nguyên bản (không mã hóa link media).
  /// - Nếu E2EE chưa sẵn sàng → tự động fallback về Legacy-CBC.
  /// - Nếu cả hai thất bại → trả về plaintext (an toàn hơn mất tin nhắn).
  Future<String> encryptPayload(
    String plainText,
    String conversationId,
    List<String> participantIds,
    String currentUserId,
  ) async {
    if (plainText.isEmpty || _isSkippable(plainText)) return plainText;

    // Đảm bảo khóa cục bộ đã được tải
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
            '[EncryptionService] ⚠️ E2EE encrypt failed (${e.type.name}), falling back to legacy: $e');
      } catch (e) {
        debugPrint(
            '[EncryptionService] ⚠️ E2EE encrypt unexpected error, falling back: $e');
      }
    }

    // Fallback Legacy
    debugPrint('[EncryptionService] 🔄 Using Legacy-CBC fallback');
    return encryptMessageLegacy(plainText, conversationId);
  }

  /// Giải mã thông minh — tự phát hiện loại payload:
  /// - JSON `{...}` → E2EE-GCM
  /// - `<base64>:<base64>` → Legacy-CBC
  /// - Còn lại → trả về nguyên bản
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
      debugPrint('[EncryptionService] ⚠️ Không có khóa cục bộ để giải mã E2EE');
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
          '[EncryptionService] ❌ E2EE decrypt error (${e.type.name}): $e');
      // Phân biệt loại lỗi để hiển thị thông báo phù hợp
      switch (e.type) {
        case E2EEErrorType.keyNotInitialized:
          return '🔒 [Thiết bị chưa có khóa — không thể giải mã]';
        case E2EEErrorType.invalidPayload:
          return '⚠️ [Dữ liệu tin nhắn bị hỏng]';
        default:
          return '🔒 [Tin nhắn được mã hóa — không thể giải mã]';
      }
    } catch (e) {
      debugPrint('[EncryptionService] ❌ E2EE decrypt unexpected: $e');
      return '🔒 [Tin nhắn được mã hóa — không thể giải mã]';
    }
  }

  // =========================================================
  // 3. BATCH OPERATIONS
  // =========================================================

  /// Giải mã nhiều tin nhắn song song (dùng cho tải lịch sử chat).
  /// Giới hạn concurrency để tránh quá tải Firebase.
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

  /// Kiểm tra nhanh một chuỗi có phải đã được mã hóa không.
  bool isEncrypted(String text) {
    if (text.isEmpty) return false;
    final type = _detectPayloadType(text).type;
    return type != PayloadType.plain;
  }

  /// Trả về loại mã hóa của một payload.
  PayloadType detectPayloadType(String text) => _detectPayloadType(text).type;

  // =========================================================
  // HELPERS
  // =========================================================

  /// Phân tích loại payload để chọn đúng decoder.
  _PayloadInfo _detectPayloadType(String text) {
    final trimmed = text.trim();

    // URL media → không mã hóa
    if (_isSkippable(trimmed)) {
      return _PayloadInfo(PayloadType.plain, trimmed);
    }

    // E2EE-GCM payload: JSON object với trường iv + data
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map &&
            decoded.containsKey('iv') &&
            decoded.containsKey('data')) {
          return _PayloadInfo(PayloadType.e2eeGcm, trimmed);
        }
      } catch (_) {}
    }

    // Legacy-CBC payload: "<base64>:<base64>"
    if (_legacyPayloadRegex.hasMatch(trimmed)) {
      return _PayloadInfo(PayloadType.legacyCbc, trimmed);
    }

    // Plaintext thông thường
    return _PayloadInfo(PayloadType.plain, trimmed);
  }

  /// URL ảnh/file không cần mã hóa.
  bool _isSkippable(String text) =>
      text.startsWith('http://') || text.startsWith('https://');
}
