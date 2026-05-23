import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

class LocalDbService {
  static final LocalDbService _instance = LocalDbService._internal();
  factory LocalDbService() => _instance;
  LocalDbService._internal();

  final _secureStorage = const FlutterSecureStorage();

  late Box _messagesBox;
  late Box _syncQueueBox;
  late Box _conversationsBox; // Box mới: lưu metadata hội thoại (preview)

  Box get messagesBox => _messagesBox;
  Box get syncQueueBox => _syncQueueBox;
  Box get conversationsBox => _conversationsBox;

  Future<void> initialize() async {
    await Hive.initFlutter();

    // 1. Lấy hoặc tạo Encryption Key cho Hive (AES-256)
    String? encryptionKeyString =
        await _secureStorage.read(key: 'hive_secure_key');
    if (encryptionKeyString == null) {
      final key = Hive.generateSecureKey();
      await _secureStorage.write(
        key: 'hive_secure_key',
        value: base64UrlEncode(key),
      );
      encryptionKeyString = base64UrlEncode(key);
    }
    final encryptionKeyUint8List = base64Url.decode(encryptionKeyString);

    // 2. Mở các Box với cấu hình Mã hóa bảo mật
    _messagesBox = await Hive.openBox(
      'chat_messages',
      encryptionCipher: HiveAesCipher(encryptionKeyUint8List),
    );

    _syncQueueBox = await Hive.openBox(
      'sync_queue',
      encryptionCipher: HiveAesCipher(encryptionKeyUint8List),
    );

    _conversationsBox = await Hive.openBox(
      'conversations',
      encryptionCipher: HiveAesCipher(encryptionKeyUint8List),
    );

    print("✅ Local Database (Hive) đã khởi tạo an toàn.");
  }

  // =========================================================
  // MESSAGES
  // =========================================================

  /// Lưu (hoặc ghi đè) một tin nhắn vào Local DB.
  /// Key = `"<conversationId>_<messageId>"`.
  Future<void> saveMessage(
    String conversationId,
    String messageId,
    Map<String, dynamic> messageData,
  ) async {
    final key = '${conversationId}_$messageId';
    await _messagesBox.put(key, messageData);
  }

  /// Lấy toàn bộ tin nhắn của một hội thoại, sắp xếp mới nhất lên đầu.
  List<Map<dynamic, dynamic>> getMessages(String conversationId) {
    final prefix = '${conversationId}_';
    return _messagesBox.keys
        .where((key) => key.toString().startsWith(prefix))
        .map((key) => _messagesBox.get(key) as Map<dynamic, dynamic>)
        .toList()
      ..sort((a, b) => b['timestamp'].compareTo(a['timestamp']));
  }

  // =========================================================
  // CONVERSATIONS (preview)
  // =========================================================

  /// Cập nhật (hoặc tạo mới) metadata preview của một hội thoại.
  ///
  /// Được gọi ngay sau [saveMessage] để danh sách chat hiển thị
  /// tin nhắn cuối mà không cần đợi mạng.
  ///
  /// Nếu document chưa tồn tại trong box, tạo mới với [participants]
  /// được tách từ [conversationId] (format: `"userId1-userId2"`).
  Future<void> updateConversationPreview({
    required String conversationId,
    required String lastMessage,
    required String lastMessageTime,
    required int lastMessageType,
  }) async {
    final existing =
        _conversationsBox.get(conversationId) as Map<dynamic, dynamic>?;

    if (existing != null) {
      // Ghi đè chỉ các field preview, giữ nguyên phần còn lại (e.g. participants)
      await _conversationsBox.put(conversationId, {
        ...existing,
        'lastMessage': lastMessage,
        'lastMessageTime': lastMessageTime,
        'lastMessageType': lastMessageType,
      });
    } else {
      // Tạo mới – tách participants từ conversationId
      final participants = conversationId.split('-');
      await _conversationsBox.put(conversationId, {
        'conversationId': conversationId,
        'participants': participants,
        'isGroup': false,
        'lastMessage': lastMessage,
        'lastMessageTime': lastMessageTime,
        'lastMessageType': lastMessageType,
      });
    }
  }

  /// Lấy metadata một hội thoại (hoặc null nếu chưa có).
  Map<dynamic, dynamic>? getConversation(String conversationId) {
    return _conversationsBox.get(conversationId) as Map<dynamic, dynamic>?;
  }

  /// Lấy toàn bộ danh sách hội thoại, sắp xếp mới nhất lên đầu.
  List<Map<dynamic, dynamic>> getAllConversations() {
    return _conversationsBox.values.cast<Map<dynamic, dynamic>>().toList()
      ..sort((a, b) =>
          (b['lastMessageTime'] ?? '0').compareTo(a['lastMessageTime'] ?? '0'));
  }

  // =========================================================
  // SYNC QUEUE
  // =========================================================

  Future<void> addToSyncQueue(Map<String, dynamic> task) async {
    await _syncQueueBox.add(task);
  }

  Future<void> removeFromSyncQueue(int taskKey) async {
    await _syncQueueBox.delete(taskKey);
  }
}
