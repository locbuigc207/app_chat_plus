// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_chat_demo/services/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PUBLIC CONSTANTS
// ─────────────────────────────────────────────────────────────────────────────

abstract class MessageStatus {
  static const String pending = 'pending';
  static const String sent = 'sent';
  static const String delivered = 'delivered';
  static const String read = 'read';
  static const String failed = 'failed';
}

abstract class SyncJobType {
  static const String sendMessage = 'send_message';
  static const String aiResponse = 'ai_response';
}

// ─────────────────────────────────────────────────────────────────────────────
// SYNC STATUS — broadcast to UI via [SyncManager.statusStream]
// ─────────────────────────────────────────────────────────────────────────────

enum SyncStatus {
  idle, // nothing to sync
  syncing, // actively uploading jobs
  paused, // online but backing off after an error
  offline, // no network
  error, // persistent failure (all retries exhausted)
}

// ─────────────────────────────────────────────────────────────────────────────
// JOB PRIORITY
// ─────────────────────────────────────────────────────────────────────────────

enum JobPriority {
  high, // failed messages being re-sent
  normal, // new outgoing messages
  low, // AI responses
}

// ─────────────────────────────────────────────────────────────────────────────
// INTERNAL MODELS
// ─────────────────────────────────────────────────────────────────────────────

class _SyncResult {
  final int success;
  final int failed;
  final bool networkError;
  const _SyncResult({
    required this.success,
    required this.failed,
    this.networkError = false,
  });
  bool get hasWork => success > 0 || failed > 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// SYNC MANAGER
// ─────────────────────────────────────────────────────────────────────────────
//
// Responsibilities:
//   • Drain the local sync queue to Firestore when online.
//   • Exponential backoff: 2 s → 4 s → 8 s … capped at 60 s.
//   • Priority ordering: high > normal > low within each batch.
//   • `statusStream` lets the UI show a "Syncing…" indicator.
//   • Periodic heartbeat (30 s) to catch jobs added while the app was idle.
//   • Safe for concurrent environments: _isSyncing mutex prevents overlap.
// ─────────────────────────────────────────────────────────────────────────────

class SyncManager {
  // ── Singleton ──────────────────────────────────────────────────────────────
  SyncManager._internal();
  static final SyncManager _instance = SyncManager._internal();
  factory SyncManager() => _instance;

  // ── Status stream ──────────────────────────────────────────────────────────
  final _statusCtrl = StreamController<SyncStatus>.broadcast();

  /// Subscribe to get real-time sync state changes.
  Stream<SyncStatus> get statusStream => _statusCtrl.stream;

  SyncStatus _status = SyncStatus.idle;
  SyncStatus get currentStatus => _status;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _heartbeatTimer;
  bool _isSyncing = false;
  bool _isStarted = false;
  bool _isOnline = true;

  // ── Retry config ───────────────────────────────────────────────────────────
  static const int _maxRetries = 4;
  static const int _maxBatchSize = 20;
  static const Duration _heartbeatInterval = Duration(seconds: 30);

  /// Exponential backoff: 2s, 4s, 8s, 16s … capped at 60s.
  static Duration _backoff(int retries) =>
      Duration(seconds: min(60, pow(2, retries + 1).toInt()));

  // ── Dependencies ───────────────────────────────────────────────────────────
  final _localDb = LocalDbService();
  final _encryption = EncryptionService();
  final _gemini = GeminiService();

  // ─────────────────────────────────────────────────────────────────────────
  // PUBLIC API
  // ─────────────────────────────────────────────────────────────────────────

  /// Start listening for connectivity changes and run an initial sync.
  /// Safe to call multiple times — only registers once.
  void startListening() {
    if (!_isStarted) {
      _isStarted = true;

      _connectivitySub =
          Connectivity().onConnectivityChanged.listen(_onConnectivity);

      // Periodic heartbeat to flush jobs even if connectivity event missed
      _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
        if (_isOnline) _trySync();
      });
    }
    _trySync();
  }

  /// Stop all background activity — call when the user logs out.
  void stopListening() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _connectivitySub?.cancel();
    _connectivitySub = null;
    _isStarted = false;
    if (!_statusCtrl.isClosed) _statusCtrl.close();
    debugPrint('[SyncManager] 🛑 Stopped');
  }

  /// Enqueue a message-send job with the correct priority.
  Future<void> enqueueMessage({
    required String conversationId,
    required String messageId,
    required String idFrom,
    required String idTo,
    required String content,
    required int messageType,
    required String timestamp,
    JobPriority priority = JobPriority.normal,
  }) async {
    await _localDb.addToSyncQueue({
      'type': SyncJobType.sendMessage,
      'priority': priority.index,
      'payload': {
        'conversationId': conversationId,
        'messageId': messageId,
        'idFrom': idFrom,
        'idTo': idTo,
        'content': content,
        'messageType': messageType,
        'timestamp': timestamp,
      },
    });
    _trySync(); // kick immediately
  }

  /// Enqueue an AI-response generation job.
  Future<void> enqueueAiResponse({
    required String conversationId,
    required String currentUserId,
    required String userMessage,
  }) async {
    await _localDb.addToSyncQueue({
      'type': SyncJobType.aiResponse,
      'priority': JobPriority.low.index,
      'payload': {
        'conversationId': conversationId,
        'currentUserId': currentUserId,
        'userMessage': userMessage,
      },
    });
    _trySync();
  }

  /// Returns the number of jobs currently waiting in the queue.
  int get pendingJobCount => _localDb.syncQueueLength;

  // ─────────────────────────────────────────────────────────────────────────
  // CONNECTIVITY
  // ─────────────────────────────────────────────────────────────────────────

  void _onConnectivity(List<ConnectivityResult> results) {
    final online = results.any((r) =>
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.ethernet);

    if (online && !_isOnline) {
      _isOnline = true;
      debugPrint('[SyncManager] 🌐 Back online');
      _emit(SyncStatus.idle);
      _trySync();
    } else if (!online && _isOnline) {
      _isOnline = false;
      debugPrint('[SyncManager] 📵 Offline');
      _emit(SyncStatus.offline);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SYNC ENTRY POINT
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _trySync() async {
    if (_isSyncing || !_isOnline) return;
    if (_localDb.syncQueueLength == 0) {
      _emit(SyncStatus.idle);
      return;
    }

    _isSyncing = true;
    _emit(SyncStatus.syncing);

    try {
      final result = await _processBatch();

      if (result.networkError) {
        _emit(SyncStatus.paused);
        debugPrint('[SyncManager] ⏸ Paused — network error, will retry');
      } else if (_localDb.syncQueueLength == 0) {
        _emit(SyncStatus.idle);
        debugPrint('[SyncManager] ✅ Queue empty');
      } else {
        // More jobs remain; keep status syncing and let heartbeat catch them
        _emit(SyncStatus.idle);
      }

      if (result.hasWork) {
        debugPrint(
            '[SyncManager] 📊 Batch: ${result.success} ok, ${result.failed} failed');
      }
    } catch (e, st) {
      debugPrint('[SyncManager] ❌ Fatal: $e\n$st');
      _emit(SyncStatus.error);
    } finally {
      _isSyncing = false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BATCH PROCESSOR — priority-sorted, backoff-aware
  // ─────────────────────────────────────────────────────────────────────────

  Future<_SyncResult> _processBatch() async {
    // Use getReadySyncJobs to respect nextRetryAt backoff timestamps
    final jobs = _localDb.getReadySyncJobs(batchSize: _maxBatchSize);

    if (jobs.isEmpty) return const _SyncResult(success: 0, failed: 0);

    // Sort by priority (ascending index = higher priority), then by addedAt
    jobs.sort((a, b) {
      final pa = a.value['priority'] as int? ?? JobPriority.normal.index;
      final pb = b.value['priority'] as int? ?? JobPriority.normal.index;
      if (pa != pb) return pa.compareTo(pb);
      final aa = a.value['addedAt'] as String? ?? '';
      final ab = b.value['addedAt'] as String? ?? '';
      return aa.compareTo(ab);
    });

    int success = 0;
    int failed = 0;
    bool netError = false;

    for (final entry in jobs) {
      final key = entry.key;
      final task = entry.value;
      final jobType = task['type'] as String? ?? '';
      final payload = Map<String, dynamic>.from(task['payload'] as Map? ?? {});
      final retries = task['retries'] as int? ?? 0;

      bool ok = false;
      bool isNetworkError = false;

      try {
        ok = switch (jobType) {
          SyncJobType.sendMessage => await _processSendMessage(payload),
          SyncJobType.aiResponse => await _processAiResponse(payload),
          _ => true, // unknown type — discard
        };
      } on FirebaseException catch (e) {
        isNetworkError =
            e.code == 'unavailable' || e.code == 'deadline-exceeded';
        debugPrint('[SyncManager] 🔥 Firebase ${e.code}: ${e.message}');
      } catch (e) {
        debugPrint('[SyncManager] ❌ Job error: $e');
      }

      if (ok) {
        await _localDb.removeFromSyncQueue(key as int);
        success++;
      } else {
        final newRetries = retries + 1;

        if (newRetries >= _maxRetries) {
          debugPrint(
              '[SyncManager] 🗑 Job $key exhausted retries — marking failed');
          await _markMessageFailed(payload);
          await _localDb.removeFromSyncQueue(key as int);
          failed++;
        } else {
          final delay = _backoff(newRetries);
          final nextRetryAt = DateTime.now().add(delay).millisecondsSinceEpoch;

          await _localDb.updateSyncJob(key as int, {
            'retries': newRetries,
            'nextRetryAt': nextRetryAt,
          });

          debugPrint(
              '[SyncManager] ⏳ Job $key retry $newRetries in ${delay.inSeconds}s');

          if (isNetworkError) {
            netError = true;
            break; // abort batch on network errors; wait for next connectivity event
          }
        }
      }
    }

    return _SyncResult(
        success: success, failed: failed, networkError: netError);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // JOB HANDLERS
  // ─────────────────────────────────────────────────────────────────────────

  Future<bool> _processSendMessage(Map<String, dynamic> payload) async {
    final conversationId = _str(payload['conversationId']);
    final messageId = _str(payload['messageId']);
    final idFrom = _str(payload['idFrom']);
    final idTo = _str(payload['idTo']);
    final plainContent = _str(payload['content']);
    final messageType = payload['messageType'] as int? ?? 0;
    final timestamp = _str(payload['timestamp']);

    if (conversationId.isEmpty || messageId.isEmpty) return false;

    // 1. Encrypt
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

    // 2. Write to Firestore
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

    // 3. Update conversation metadata
    await FirebaseFirestore.instance
        .collection('conversations')
        .doc(conversationId)
        .update({
      'lastMessage': plainContent,
      'lastMessageTime': timestamp,
      'lastMessageType': messageType,
    }).catchError((_) {}); // non-fatal

    // 4. Update local status: pending → sent
    await _localDb.updateMessageStatus(
        conversationId, messageId, MessageStatus.sent);

    debugPrint('[SyncManager] 📤 Sent message $messageId');
    return true;
  }

  Future<bool> _processAiResponse(Map<String, dynamic> payload) async {
    final conversationId = _str(payload['conversationId']);
    final currentUserId = _str(payload['currentUserId']);
    final userMessage = _str(payload['userMessage']);

    if (conversationId.isEmpty || userMessage.isEmpty) return false;

    // Build history from local cache (up to 30 messages, chronological order)
    final history = _localDb
        .getMessages(conversationId)
        .take(30)
        .toList()
        .reversed
        .map((m) => <String, dynamic>{
              'idFrom': m['idFrom'],
              'content': m['content'],
            })
        .toList();

    // Call Gemini
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

    // Save locally first (optimistic)
    await _localDb.saveMessage(conversationId, aiTimestamp, aiMessage);

    // Push to Firestore (AI messages are plaintext — no E2EE)
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
      'status': MessageStatus.sent,
    });

    // Update conversation preview
    await FirebaseFirestore.instance
        .collection('conversations')
        .doc(conversationId)
        .update({
      'lastMessage':
          aiText.length > 80 ? '${aiText.substring(0, 80)}…' : aiText,
      'lastMessageTime': aiTimestamp,
      'lastMessageType': TypeMessage.text,
    }).catchError((_) {});

    debugPrint('[SyncManager] 🤖 AI response synced for $conversationId');
    return true;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _markMessageFailed(Map<String, dynamic> payload) async {
    final conversationId = _str(payload['conversationId']);
    final messageId = _str(payload['messageId']);
    if (conversationId.isEmpty || messageId.isEmpty) return;
    await _localDb.updateMessageStatus(
        conversationId, messageId, MessageStatus.failed);
    debugPrint('[SyncManager] ❌ Marked $messageId as failed');
  }

  void _emit(SyncStatus status) {
    if (_status == status) return;
    _status = status;
    if (!_statusCtrl.isClosed) _statusCtrl.add(status);
  }

  static String _str(dynamic v) => v?.toString() ?? '';
}
