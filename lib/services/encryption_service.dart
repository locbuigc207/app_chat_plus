import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

import 'e2ee_service.dart';

/// Lớp trung gian quản lý toàn bộ mã hóa/giải mã tin nhắn.
///
/// Kiến trúc 2 lớp:
/// - **E2EE (Production)**: AES-256-GCM với session key động từ [E2EEService].
/// - **Legacy (Fallback)**: AES-256-CBC với key tĩnh sinh từ conversationId,
///   dùng để tương thích ngược với lịch sử tin nhắn cũ trước khi triển khai E2EE.
class EncryptionService {
  static final EncryptionService _instance = EncryptionService._internal();

  factory EncryptionService() => _instance;

  EncryptionService._internal();

  static const String _secretSalt = 'APP_CHAT_PLUS_SECURE_SALT_2026';

  // =========================================================
  // LEGACY LAYER — AES-256-CBC (Tương thích ngược tin nhắn cũ)
  // =========================================================

  /// Sinh key AES cố định từ conversationId + salt (dùng cho tin nhắn cũ).
  encrypt.Key _generateLegacyKey(String conversationId) {
    final bytes = utf8.encode(conversationId + _secretSalt);
    final digest = sha256.convert(bytes);
    return encrypt.Key(Uint8List.fromList(digest.bytes));
  }

  /// Mã hóa tin nhắn bằng AES-256-CBC (Legacy).
  /// Trả về định dạng `"<iv_base64>:<ciphertext_base64>"`.
  String encryptMessage(String plainText, String conversationId) {
    if (plainText.isEmpty) return plainText;
    if (_isUrl(plainText)) return plainText;

    try {
      final key = _generateLegacyKey(conversationId);
      final iv = encrypt.IV.fromSecureRandom(16);
      final encrypter =
          encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));

      final encrypted = encrypter.encrypt(plainText, iv: iv);
      return '${iv.base64}:${encrypted.base64}';
    } catch (e) {
      print('❌ Lỗi mã hóa Legacy: $e');
      return plainText;
    }
  }

  /// Giải mã tin nhắn bằng AES-256-CBC (Legacy).
  /// Nhận định dạng `"<iv_base64>:<ciphertext_base64>"`.
  String decryptMessage(String encryptedText, String conversationId) {
    if (encryptedText.isEmpty || !encryptedText.contains(':')) {
      return encryptedText;
    }

    try {
      final parts = encryptedText.split(':');
      if (parts.length != 2) return encryptedText;

      final iv = encrypt.IV.fromBase64(parts[0]);
      final cipherText = parts[1];

      final key = _generateLegacyKey(conversationId);
      final encrypter =
          encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));

      return encrypter.decrypt64(cipherText, iv: iv);
    } catch (e) {
      print('❌ Lỗi giải mã Legacy: $e');
      return '🔒 [Tin nhắn không thể giải mã]';
    }
  }

  // =========================================================
  // E2EE LAYER — AES-256-GCM (Production)
  // =========================================================

  /// Mã hóa tin nhắn qua E2EE với session key động từ [E2EEService].
  ///
  /// - URL ảnh/file được bỏ qua, trả về nguyên bản.
  /// - Nếu E2EE thất bại (lỗi khởi tạo khóa...), tự động fallback về Legacy.
  ///
  /// Được gọi bởi [ChatProvider.sendMessage] và [ChatProvider._handleAiResponse].
  Future<String> encryptPayload(
    String plainText,
    String conversationId,
    List<String> participantIds,
    String currentUserId,
  ) async {
    if (plainText.isEmpty) return plainText;
    if (_isUrl(plainText)) return plainText;

    try {
      final sessionKey = await E2EEService().getConversationSessionKey(
        conversationId: conversationId,
        participantIds: participantIds,
        currentUserId: currentUserId,
      );
      return E2EEService().encryptMessage(plainText, sessionKey);
    } catch (e) {
      print('⚠️ Lỗi mã hóa E2EE, fallback về Legacy: $e');
      return encryptMessage(plainText, conversationId);
    }
  }

  /// Giải mã tin nhắn qua E2EE với session key động từ [E2EEService].
  ///
  /// - Thử E2EE trước; nếu thất bại tự động fallback về Legacy
  ///   để tương thích với lịch sử chat cũ.
  ///
  /// Được gọi bởi [AdaptiveChatBubble] qua `FutureBuilder`.
  Future<String> decryptPayload(
    String encryptedText,
    String conversationId,
    List<String> participantIds,
    String currentUserId,
  ) async {
    if (encryptedText.isEmpty) return encryptedText;

    // Payload JSON (E2EE-GCM) có dạng {"iv":"...","data":"..."}
    // Payload Legacy (CBC) có dạng "<iv_base64>:<ciphertext_base64>"
    final isE2EEPayload = encryptedText.trimLeft().startsWith('{');

    if (isE2EEPayload) {
      // ── Thử giải mã E2EE ──────────────────────────────────
      try {
        final sessionKey = await E2EEService().getConversationSessionKey(
          conversationId: conversationId,
          participantIds: participantIds,
          currentUserId: currentUserId,
        );
        final result = E2EEService().decryptMessage(encryptedText, sessionKey);

        // E2EEService trả về chuỗi lỗi cố định khi không giải mã được
        if (result == '[Không thể giải mã tin nhắn]') {
          throw Exception('Không khớp khóa E2EE');
        }

        return result;
      } catch (e) {
        print('⚠️ Lỗi giải mã E2EE: $e');
        return '🔒 [Tin nhắn được mã hóa — không thể giải mã]';
      }
    } else {
      // ── Fallback: giải mã Legacy (tin nhắn cũ trước E2EE) ─
      return decryptMessage(encryptedText, conversationId);
    }
  }

  // =========================================================
  // HELPERS
  // =========================================================

  /// Kiểm tra chuỗi có phải URL ảnh/file hay không.
  bool _isUrl(String text) =>
      text.startsWith('http://') || text.startsWith('https://');
}
