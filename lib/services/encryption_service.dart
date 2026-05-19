
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

class EncryptionService {
  static final EncryptionService _instance = EncryptionService._internal();
  factory EncryptionService() => _instance;
  EncryptionService._internal();

  
  static const String _secretSalt = "APP_CHAT_PLUS_SECURE_SALT_2026";

  
  encrypt.Key _generateKey(String conversationId) {
    final bytes = utf8.encode(conversationId + _secretSalt);
    final digest = sha256.convert(bytes);
    return encrypt.Key(Uint8List.fromList(digest.bytes));
  }

  
  String encryptMessage(String plainText, String conversationId) {
    if (plainText.isEmpty) return plainText;

    
    
    if (plainText.startsWith('http://') || plainText.startsWith('https://')) {
      return plainText;
    }

    try {
      final key = _generateKey(conversationId);
      final iv = encrypt.IV.fromSecureRandom(16); 
      final encrypter =
          encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));

      final encrypted = encrypter.encrypt(plainText, iv: iv);
      
      return "${iv.base64}:${encrypted.base64}";
    } catch (e) {
      print("Lỗi mã hóa: $e");
      return plainText;
    }
  }

  
  String decryptMessage(String encryptedText, String conversationId) {
    if (encryptedText.isEmpty || !encryptedText.contains(':')) {
      return encryptedText; 
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
