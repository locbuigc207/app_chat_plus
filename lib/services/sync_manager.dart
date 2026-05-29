// ignore_for_file: avoid_print

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_chat_demo/services/services.dart';





abstract class MessageStatus {
  static const String pending = 'pending';
  static const String sent = 'sent';
  static const String delivered = 'delivered';
  static const String failed = 'failed';
}

abstract class SyncJobType {
  static const String sendMessage = 'send_message';
  static const String aiResponse = 'ai_response';
}





class _SyncResult {
  final int success;
  final int failed;
  const _SyncResult({required this.success, required this.failed});
}












class SyncManager {
  
  SyncManager._internal();
  static final SyncManager _instance = SyncManager._internal();
  factory SyncManager() => _instance;

  
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _isSyncing = false;
  bool _isStarted = false;

  
  static const int _maxRetries = 3;
  static const Duration _baseDelay = Duration(seconds: 2);
  static const int _maxQueueBatch = 20; 

  
  final LocalDbService _localDb = LocalDbService();
  final EncryptionService _encryption = EncryptionService();
  final GeminiService _gemini = GeminiService();

  
  
  

  
  
  void startListening() {
    if (!_isStarted) {
      _isStarted = true;
      _connectivitySub = Connectivity().onConnectivityChanged.listen(_onConnectivityChanged);
    }
    
    _trySync();
  }

  
  void stopListening() {
    _connectivitySub?.cancel();
    _connectivitySub = null;
    _isStarted = false;
  }

  
  
  

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final online = results.any((r) =>
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.ethernet);
    if (online) {
      debugPrint('[SyncManager] 🌐 Online — bắt đầu sync');
      _trySync();
    } else {
      debugPrint('[SyncManager] 📵 Offline — tạm dừng sync');
    }
  }

  
  
  

  Future<void> _trySync() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final result = await _processBatch();
      if (result.success > 0 || result.failed > 0) {
        debugPrint('[SyncManager] ✅ Sync: ${result.success} ok, ${result.failed} failed');
      }
    } catch (e) {
      debugPrint('[SyncManager] ❌ Fatal sync error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  Future<_SyncResult> _processBatch() async {
    final box = _localDb.syncQueueBox;
    final keys = box.keys.take(_maxQueueBatch).toList();

    int success = 0;
    int failed = 0;

    for (final key in keys) {
      final raw = box.get(key);
      if (raw == null) continue;

      final task = Map<String, dynamic>.from(raw as Map);
      final jobType = task['type'] as String? ?? '';
      final payload = Map<String, dynamic>.from(task['payload'] as Map? ?? {});

      bool ok = false;

      try {
        switch (jobType) {
          case SyncJobType.sendMessage:
            ok = await _processSendMessageJob(payload);
            break;
          case SyncJobType.aiResponse:
            ok = await _processAiResponseJob(payload);
            break;
          default:
            debugPrint('[SyncManager] ⚠️ Unknown job type: $jobType — removing');
            ok = true; 
        }
      } catch (e) {
        debugPrint('[SyncManager] ❌ Job $key error: $e');
      }

      if (ok) {
        await _localDb.removeFromSyncQueue(key as int);
        success++;
      } else {
        final retries = (task['retries'] as int? ?? 0) + 1;

        if (retries >= _maxRetries) {
          debugPrint('[SyncManager] 🗑 Job $key exceeded max retries — removing');
          await _markMessageFailed(payload);
          await _localDb.removeFromSyncQueue(key as int);
          failed++;
        } else {
          
          await box.put(key, {...task, 'retries': retries});

          
          
          debugPrint('[SyncManager] ⚠️ Tạm dừng batch do phát hiện lỗi mạng/server.');
          break; 
        }
      }
    }

    return _SyncResult(success: success, failed: failed);
  }

  
  
  

  Future<bool> _processSendMessageJob(Map<String, dynamic> payload) async {
    final conversationId = payload['conversationId'] as String? ?? '';
    final messageId = payload['messageId'] as String? ?? '';
    final idFrom = payload['idFrom'] as String? ?? '';
    final idTo = payload['idTo'] as String? ?? '';
    final plainContent = payload['content'] as String? ?? '';
    final messageType = payload['messageType'] as int? ?? 0;
    final timestamp = payload['timestamp'] as String? ?? '';

    if (conversationId.isEmpty || messageId.isEmpty) return false;

    
    String encryptedContent;
    try {
      encryptedContent = await _encryption.encryptPayload(
        plainContent,
        conversationId,
        [idFrom, idTo],
        idFrom,
      );
    } catch (e) {
      debugPrint('[SyncManager] ❌ Encrypt failed: $e');
      return false;
    }

    
    await FirebaseFirestore.instance
        .collection('messages')
        .doc(conversationId)
        .collection(conversationId)
        .doc(messageId)
        .set({
      'idFrom': idFrom,
      'idTo': idTo,
      'timestamp': timestamp,
      'content': encryptedContent,
      'type': messageType,
      'status': MessageStatus.sent,
    });

    
    final localKey = '${conversationId}_$messageId';
    final local = _localDb.messagesBox.get(localKey);
    if (local != null) {
      final updated = Map<String, dynamic>.from(local as Map)..['status'] = MessageStatus.sent;
      await _localDb.saveMessage(conversationId, messageId, updated);
    }

    debugPrint('[SyncManager] 📤 Synced message $messageId');
    return true;
  }

  
  
  

  Future<bool> _processAiResponseJob(Map<String, dynamic> payload) async {
    final conversationId = payload['conversationId'] as String? ?? '';
    final currentUserId = payload['currentUserId'] as String? ?? '';
    final userMessage = payload['userMessage'] as String? ?? '';

    if (conversationId.isEmpty || userMessage.isEmpty) return false;

    
    final history = _localDb
        .getMessages(conversationId)
        .take(30)
        .map((m) => <String, dynamic>{
              'idFrom': m['idFrom'],
              'content': m['content'],
            })
        .toList()
        .reversed
        .toList();

    
    final aiText = await _gemini.sendMessage(userMessage, history);
    if (aiText.isEmpty) return false;

    
    final aiTimestamp = (DateTime.now().millisecondsSinceEpoch + 1).toString();
    final aiMessage = <String, dynamic>{
      'messageId': aiTimestamp,
      'idFrom': AppConstants.aiAssistantId,
      'idTo': currentUserId,
      'timestamp': aiTimestamp,
      'content': aiText,
      'type': TypeMessage.text,
      'status': MessageStatus.sent,
    };

    await _localDb.saveMessage(conversationId, aiTimestamp, aiMessage);

    
    await FirebaseFirestore.instance
        .collection('messages')
        .doc(conversationId)
        .collection(conversationId)
        .doc(aiTimestamp)
        .set({
      'idFrom': AppConstants.aiAssistantId,
      'idTo': currentUserId,
      'timestamp': aiTimestamp,
      'content': aiText,
      'type': TypeMessage.text,
    });

    debugPrint('[SyncManager] 🤖 AI response synced for $conversationId');
    return true;
  }

  
  
  

  Future<void> _markMessageFailed(Map<String, dynamic> payload) async {
    final conversationId = payload['conversationId'] as String? ?? '';
    final messageId = payload['messageId'] as String? ?? '';
    if (conversationId.isEmpty || messageId.isEmpty) return;

    final localKey = '${conversationId}_$messageId';
    final local = _localDb.messagesBox.get(localKey);
    if (local != null) {
      final updated = Map<String, dynamic>.from(local as Map)..['status'] = MessageStatus.failed;
      await _localDb.saveMessage(conversationId, messageId, updated);
    }
  }
}
