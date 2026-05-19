// lib/services/encryption_service.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

class EncryptionService {
  static final EncryptionService _instance = EncryptionService._internal();
  factory EncryptionService() => _instance;
  EncryptionService._internal();

  // Chuỗi bí mật dùng để trộn (Salt). Trong thực tế nên đưa vào file .env
  static const String _secretSalt = "APP_CHAT_PLUS_SECURE_SALT_2026";

  /// Tạo khóa AES-256 tĩnh dựa trên Conversation ID
  encrypt.Key _generateKey(String conversationId) {
    final bytes = utf8.encode(conversationId + _secretSalt);
    final digest = sha256.convert(bytes);
    return encrypt.Key(Uint8List.fromList(digest.bytes));
  }

  /// Mã hóa tin nhắn trước khi gửi lên Firestore
  String encryptMessage(String plainText, String conversationId) {
    if (plainText.isEmpty) return plainText;

    // Nếu tin nhắn là URL ảnh/voice (bắt đầu bằng http) thì tạm thời không mã hóa URL
    // (Bảo mật Media cần cơ chế mã hóa File riêng)
    if (plainText.startsWith('http://') || plainText.startsWith('https://')) {
      return plainText;
    }

    try {
      final key = _generateKey(conversationId);
      final iv = encrypt.IV.fromSecureRandom(16); // Tạo Vector ngẫu nhiên
      final encrypter =
          encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));

      final encrypted = encrypter.encrypt(plainText, iv: iv);
      // Lưu trữ theo định dạng:  IV_Base64:CipherText_Base64
      return "${iv.base64}:${encrypted.base64}";
    } catch (e) {
      print("Lỗi mã hóa: $e");
      return plainText;
    }
  }

  /// Giải mã tin nhắn khi lấy từ Firestore về Client
  String decryptMessage(String encryptedText, String conversationId) {
    if (encryptedText.isEmpty || !encryptedText.contains(':')) {
      return encryptedText; // Trả về nguyên gốc nếu là tin nhắn cũ (chưa bị mã hóa)
    }

    try {
      final parts = encryptedText.split(':');
      if (parts.length != 2) return encryptedText;

      final iv = encrypt.IV.fromBase64(parts[0]);
      final cipherText = parts[1];

      final key = _generateKey(conversationId);
      final encrypter =
          encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));

      return encrypter.decrypt64(cipherText, iv: iv);
    } catch (e) {
      print("Lỗi giải mã: $e");
      return "🔒 [Tin nhắn không thể giải mã]";
    }
  }
}
