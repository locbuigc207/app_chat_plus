// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

class LocalDbService {
  LocalDbService._internal();
  static final LocalDbService _instance = LocalDbService._internal();
  factory LocalDbService() => _instance;

  static const _kHiveKey = 'hive_secure_key_v2';
  static const _kMessagesBox = 'chat_messages_v2';
  static const _kSyncBox = 'sync_queue_v2';
  static const _kConvoBox = 'conversations_v2';

  final _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  late Box _messagesBox;
  late Box _syncQueueBox;
  late Box _conversationsBox;

  bool _initialized = false;

  Box get messagesBox => _messagesBox;
  Box get syncQueueBox => _syncQueueBox;
  Box get conversationsBox => _conversationsBox;

  Future<void> initialize() async {
    if (_initialized) return;

    await Hive.initFlutter();

    final cipher = await _resolveEncryptionCipher();

    _messagesBox = await Hive.openBox(
      _kMessagesBox,
      encryptionCipher: cipher,
    );
    _syncQueueBox = await Hive.openBox(
      _kSyncBox,
      encryptionCipher: cipher,
    );
    _conversationsBox = await Hive.openBox(
      _kConvoBox,
      encryptionCipher: cipher,
    );

    _initialized = true;
    debugPrint('[LocalDbService] ✅ Hive initialized — encrypted AES-256');
  }

  Future<HiveAesCipher> _resolveEncryptionCipher() async {
    String? keyStr = await _secureStorage.read(key: _kHiveKey);

    if (keyStr == null) {
      final newKey = Hive.generateSecureKey();
      keyStr = base64UrlEncode(newKey);
      await _secureStorage.write(key: _kHiveKey, value: keyStr);
    }

    return HiveAesCipher(base64Url.decode(keyStr));
  }

  Future<void> saveMessage(
    String conversationId,
    String messageId,
    Map<String, dynamic> data,
  ) async {
    assert(_initialized, 'LocalDbService chưa được khởi tạo');
    await _messagesBox.put('${conversationId}_$messageId', data);
  }

  List<Map<dynamic, dynamic>> getMessages(String conversationId) {
    assert(_initialized, 'LocalDbService chưa được khởi tạo');
    final prefix = '${conversationId}_';
    final msgs = _messagesBox.keys
        .where((k) => k.toString().startsWith(prefix))
        .map((k) => _messagesBox.get(k) as Map<dynamic, dynamic>)
        .toList();

    msgs.sort((a, b) {
      final ta = int.tryParse(a['timestamp']?.toString() ?? '0') ?? 0;
      final tb = int.tryParse(b['timestamp']?.toString() ?? '0') ?? 0;
      return tb.compareTo(ta);
    });

    return msgs;
  }

  Map<dynamic, dynamic>? getMessage(String conversationId, String messageId) {
    assert(_initialized, 'LocalDbService chưa được khởi tạo');
    return _messagesBox.get('${conversationId}_$messageId') as Map<dynamic, dynamic>?;
  }

  Future<void> deleteMessage(String conversationId, String messageId) async {
    assert(_initialized, 'LocalDbService chưa được khởi tạo');
    await _messagesBox.delete('${conversationId}_$messageId');
  }

  int countMessages(String conversationId) {
    final prefix = '${conversationId}_';
    return _messagesBox.keys.where((k) => k.toString().startsWith(prefix)).length;
  }

  Future<void> clearConversationMessages(String conversationId) async {
    assert(_initialized, 'LocalDbService chưa được khởi tạo');
    final prefix = '${conversationId}_';
    final keys = _messagesBox.keys.where((k) => k.toString().startsWith(prefix)).toList();
    await _messagesBox.deleteAll(keys);
    debugPrint('[LocalDbService] 🗑 Cleared ${keys.length} messages for $conversationId');
  }

  Future<void> updateConversationPreview({
    required String conversationId,
    required String lastMessage,
    required String lastMessageTime,
    required int lastMessageType,
  }) async {
    assert(_initialized, 'LocalDbService chưa được khởi tạo');

    final existing = _conversationsBox.get(conversationId) as Map<dynamic, dynamic>?;

    if (existing != null) {
      await _conversationsBox.put(conversationId, {
        ...Map<String, dynamic>.from(existing),
        'lastMessage': lastMessage,
        'lastMessageTime': lastMessageTime,
        'lastMessageType': lastMessageType,
      });
    } else {
      final parts = conversationId.split('-');
      await _conversationsBox.put(conversationId, <String, dynamic>{
        'conversationId': conversationId,
        'participants': parts,
        'isGroup': false,
        'lastMessage': lastMessage,
        'lastMessageTime': lastMessageTime,
        'lastMessageType': lastMessageType,
      });
    }
  }

  Future<void> saveConversation(
    String conversationId,
    Map<String, dynamic> data,
  ) async {
    assert(_initialized, 'LocalDbService chưa được khởi tạo');
    await _conversationsBox.put(conversationId, data);
  }

  Map<dynamic, dynamic>? getConversation(String conversationId) {
    assert(_initialized, 'LocalDbService chưa được khởi tạo');
    return _conversationsBox.get(conversationId) as Map<dynamic, dynamic>?;
  }

  List<Map<dynamic, dynamic>> getAllConversations() {
    assert(_initialized, 'LocalDbService chưa được khởi tạo');
    final list = _conversationsBox.values.cast<Map<dynamic, dynamic>>().toList();

    list.sort((a, b) {
      final ta = int.tryParse(a['lastMessageTime']?.toString() ?? '0') ?? 0;
      final tb = int.tryParse(b['lastMessageTime']?.toString() ?? '0') ?? 0;
      return tb.compareTo(ta);
    });

    return list;
  }

  Future<void> deleteConversation(String conversationId) async {
    assert(_initialized, 'LocalDbService chưa được khởi tạo');
    await _conversationsBox.delete(conversationId);
    await clearConversationMessages(conversationId);
  }

  Future<void> addToSyncQueue(Map<String, dynamic> task) async {
    assert(_initialized, 'LocalDbService chưa được khởi tạo');
    await _syncQueueBox.add({...task, 'retries': 0, 'addedAt': DateTime.now().toIso8601String()});
  }

  Future<void> removeFromSyncQueue(int key) async {
    assert(_initialized, 'LocalDbService chưa được khởi tạo');
    await _syncQueueBox.delete(key);
  }

  int get syncQueueLength => _syncQueueBox.length;

  Future<void> clearAll() async {
    assert(_initialized, 'LocalDbService chưa được khởi tạo');
    await Future.wait([
      _messagesBox.clear(),
      _syncQueueBox.clear(),
      _conversationsBox.clear(),
    ]);
    debugPrint('[LocalDbService] 🧹 All local data cleared');
  }

  Future<int> pruneOldMessages({int days = 30}) async {
    assert(_initialized, 'LocalDbService chưa được khởi tạo');
    final cutoff = DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;

    final toDelete = _messagesBox.keys.where((k) {
      final msg = _messagesBox.get(k) as Map<dynamic, dynamic>?;
      if (msg == null) return false;
      final ts = int.tryParse(msg['timestamp']?.toString() ?? '0') ?? 0;
      return ts < cutoff;
    }).toList();

    await _messagesBox.deleteAll(toDelete);
    debugPrint('[LocalDbService] 🗑 Pruned ${toDelete.length} old messages');
    return toDelete.length;
  }

  Map<String, int> get stats => {
        'messages': _messagesBox.length,
        'syncQueue': _syncQueueBox.length,
        'conversations': _conversationsBox.length,
      };
}
