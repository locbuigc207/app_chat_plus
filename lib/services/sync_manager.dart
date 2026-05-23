import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'encryption_service.dart';
import 'local_db_service.dart';

class SyncManager {
  static final SyncManager _instance = SyncManager._internal();
  factory SyncManager() => _instance;
  SyncManager._internal();

  StreamSubscription? _connectivitySubscription;
  bool _isSyncing = false;

  void startListening() {
    // connectivity_plus v5+ trả về List<ConnectivityResult>
    _connectivitySubscription = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      final bool isOnline = results.any((r) =>
          r == ConnectivityResult.mobile || r == ConnectivityResult.wifi);
      if (isOnline) {
        _syncPendingMessages();
      }
    });
    // Gọi thử một lần khi khởi động
    _syncPendingMessages();
  }

  Future<void> _syncPendingMessages() async {
    if (_isSyncing) return;
    _isSyncing = true;

    final syncQueue = LocalDbService().syncQueueBox;
    final keys = syncQueue.keys.toList();

    for (var key in keys) {
      try {
        final task = syncQueue.get(key) as Map<dynamic, dynamic>;

        if (task['type'] == 'send_message') {
          final payload = Map<String, dynamic>.from(task['payload']);
          final plainText = payload['content'];

          // 1. Mã hóa E2EE trước khi đẩy lên Firebase
          final encryptedContent = await EncryptionService().encryptPayload(
            plainText,
            payload['conversationId'],
            [payload['idFrom'], payload['idTo']],
            payload['idFrom'],
          );

          // 2. Đẩy lên Firestore
          await FirebaseFirestore.instance
              .collection('messages')
              .doc(payload['conversationId'])
              .collection(payload['conversationId'])
              .doc(payload['messageId'])
              .set({
            'idFrom': payload['idFrom'],
            'idTo': payload['idTo'],
            'timestamp': payload['timestamp'],
            'content': encryptedContent,
            'type': payload['messageType'],
          });

          // 3. Cập nhật trạng thái trong Local DB thành "đã gửi"
          final localMsgKey =
              '${payload['conversationId']}_${payload['messageId']}';
          final localMsg = LocalDbService().messagesBox.get(localMsgKey);
          if (localMsg != null) {
            localMsg['status'] = 'sent';
            await LocalDbService().messagesBox.put(localMsgKey, localMsg);
          }

          // 4. Xóa khỏi hàng đợi
          await LocalDbService().removeFromSyncQueue(key);
          print(
              '🔄 Đồng bộ thành công tin nhắn Offline: ${payload['messageId']}');
        }
      } catch (e) {
        print('❌ Lỗi đồng bộ task $key: $e');
        // Giữ lại trong queue để thử lại sau
      }
    }
    _isSyncing = false;
  }

  void stopListening() {
    _connectivitySubscription?.cancel();
  }
}
