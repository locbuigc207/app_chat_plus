// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_chat_demo/services/services.dart';
import 'package:flutter_chat_demo/utils/utils.dart';

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

enum SyncStatus { idle, syncing, paused, offline, error }

// ─────────────────────────────────────────────────────────────────────────────
// JOB PRIORITY
// ─────────────────────────────────────────────────────────────────────────────

enum JobPriority { high, normal, low }

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

class SyncManager {
  // ── Singleton ──────────────────────────────────────────────────────────────
  SyncManager._internal();
  static final SyncManager _instance = SyncManager._internal();
  factory SyncManager() => _instance;

  // ── Status stream ──────────────────────────────────────────────────────────
  final _statusCtrl = StreamController<SyncStatus>.broadcast();

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

  static Duration _backoff(int retries) =>
      Duration(seconds: min(60, pow(2, retries + 1).toInt()));

  // ── Dependencies ───────────────────────────────────────────────────────────
  final _localDb = LocalDbService();
  final _encryption = EncryptionService();
  final _aiBackend =
  AIBackendService(); // Dùng Cloud Functions thay vì Gemini trực tiếp
  final _aiContent = AiContentService();

  // ═════════════════════════════════════════════════════════════════════════
  // PUBLIC API
  // ═════════════════════════════════════════════════════════════════════════

  void startListening() {
    if (!_isStarted) {
      _isStarted = true;

      _connectivitySub = Connectivity().onConnectivityChanged.listen(
        _onConnectivity,
      );

      _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
        if (_isOnline) _trySync();
      });
    }
    _trySync();
  }

  void stopListening() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _connectivitySub?.cancel();
    _connectivitySub = null;
    _isStarted = false;

    _emit(SyncStatus.idle);
    debugPrint('[SyncManager] 🛑 Stopped');
  }

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
    _trySync();
  }

  Future<void> enqueueAiResponse({
    required String conversationId,
    required String currentUserId,
    required String userMessage,
  }) async {
    await _localDb.addToSyncQueue({
      'type': SyncJobType.aiResponse,
      'priority': JobPriority.normal.index,
      'payload': {
        'conversationId': conversationId,
        'currentUserId': currentUserId,
        'userMessage': userMessage,
      },
    });
    _trySync();
  }

  int get pendingJobCount => _localDb.syncQueueLength;

  // ═════════════════════════════════════════════════════════════════════════
  // CONNECTIVITY MANAGEMENT
  // ═════════════════════════════════════════════════════════════════════════

  void _onConnectivity(List<ConnectivityResult> results) {
    final online = results.any(
          (r) =>
      r == ConnectivityResult.mobile ||
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.ethernet,
    );

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

  // ═════════════════════════════════════════════════════════════════════════
  // SYNC PROCESSING ENGINE
  // ═════════════════════════════════════════════════════════════════════════

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
        _emit(SyncStatus.idle);
      }

      if (result.hasWork) {
        debugPrint(
          '[SyncManager] 📊 Batch: ${result.success} ok, ${result.failed} failed',
        );
      }
    } catch (e, st) {
      debugPrint('[SyncManager] ❌ Fatal: $e\n$st');
      _emit(SyncStatus.error);
    } finally {
      _isSyncing = false;
    }
  }

  Future<_SyncResult> _processBatch() async {
    final jobs = _localDb.getReadySyncJobs(batchSize: _maxBatchSize);

    if (jobs.isEmpty) return const _SyncResult(success: 0, failed: 0);

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
          _ => true,
        };
      } on AIBackendException catch (e) {
        // Bắt riêng lỗi từ hệ thống AI (AIBackendService)
        // Lỗi này xảy ra khi có cấu hình sai hoặc model không khả dụng, không cần retry
        if (e.type == AIBackendErrorType.unknown) {
          debugPrint('[SyncManager] ❌ Permanent AI Error: $e');
          await _sendAiErrorMessage(payload);
          await _localDb.removeFromSyncQueue(key as int);
          failed++;
          continue; // Chuyển sang Job tiếp theo luôn, bỏ qua luồng retry phía dưới
        } else {
          // Những lỗi transient (networkError, quotaExceeded...) để pass qua dưới và tiếp tục tính retries
          debugPrint('[SyncManager] Transient AI error: $e');
        }
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
            '[SyncManager] 🗑 Job $key exhausted retries — handling failure',
          );

          // Gửi thông báo lỗi AI trực quan cho người dùng thay vì xóa ngầm
          if (jobType == SyncJobType.aiResponse) {
            await _sendAiErrorMessage(payload);
          } else {
            await _markMessageFailed(payload);
          }

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
            '[SyncManager] ⏳ Job $key retry $newRetries in ${delay.inSeconds}s',
          );

          if (isNetworkError) {
            netError = true;
            break;
          }
        }
      }
    }

    return _SyncResult(
      success: success,
      failed: failed,
      networkError: netError,
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═════════════════════════════════════════════════════════════════════════

  static String _buildPreview(String plainContent, int messageType) {
    if (messageType == TypeMessage.image) return '📷 Hình ảnh';
    if (messageType == TypeMessage.video) return '🎬 Video';
    if (messageType == 3) return '🎤 Tin nhắn thoại';
    if (messageType == TypeMessage.sticker) return '😊 Sticker';
    if (messageType == TypeMessage.document) return '📄 Tài liệu';
    if (messageType == TypeMessage.poll) return '📊 Bình chọn';
    if (messageType == TypeMessage.geoLocked) return '📍 Tin nhắn địa điểm';
    if (messageType == TypeMessage.gameInvite) return '🎮 Lời mời chơi game';
    if (messageType == TypeMessage.gameResult) return '🏆 Kết quả game';
    if (messageType == TypeMessage.gameLive) return '🎮 Đang chơi game';

    final masked = DataMaskingUtils.maskText(
      plainContent,
      config: MaskingConfig.piiOnly,
    );
    return masked.length > 80 ? '${masked.substring(0, 80)}…' : masked;
  }

  Future<void> _sendAiErrorMessage(Map<String, dynamic> payload) async {
    final conversationId = _str(payload['conversationId']);
    final currentUserId = _str(payload['currentUserId']);
    if (conversationId.isEmpty) return;

    const errorText =
        '❌ Trợ lý AI tạm thời không khả dụng. Vui lòng thử lại sau.';
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // Đổi từ '_' sang '-' để không vi phạm quy tắc của LocalDbService
    final msgId = '${nowMs}-err';
    final tsStr = nowMs.toString();

    try {
      final errorMessage = <String, dynamic>{
        'messageId': msgId,
        'idFrom': AppConstants.aiAssistantId,
        'idTo': currentUserId,
        'timestamp': tsStr,
        'content': errorText,
        'contentPlain': errorText,
        'type': TypeMessage.text,
        'status': MessageStatus.sent,
        'isError': true,
      };

      await _localDb.saveMessage(conversationId, msgId, errorMessage);

      await FirebaseFirestore.instance
          .collection(FirestoreConstants.pathMessageCollection)
          .doc(conversationId)
          .collection(conversationId)
          .doc(msgId)
          .set({
        'idFrom': AppConstants.aiAssistantId,
        'idTo': currentUserId,
        'timestamp': tsStr,
        'content': errorText,
        'type': TypeMessage.text,
        'status': MessageStatus.sent,
        'isError': true,
      });
    } catch (e) {
      debugPrint('[SyncManager] ❌ Cannot send AI error message: $e');
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // JOB HANDLERS IMPLEMENTATION
  // ═════════════════════════════════════════════════════════════════════════

  Future<bool> _processSendMessage(Map<String, dynamic> payload) async {
    final conversationId = _str(payload['conversationId']);
    final messageId = _str(payload['messageId']);
    final idFrom = _str(payload['idFrom']);
    final idTo = _str(payload['idTo']);
    final plainContent = _str(payload['content']);
    final messageType = payload['messageType'] as int? ?? 0;
    final timestamp = _str(payload['timestamp']);

    if (conversationId.isEmpty || messageId.isEmpty) return false;

    // 1. Mã hóa đầu cuối (End-to-End Encryption)
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

    // 2. Ghi tài liệu lên Firestore Collection (Dùng subcollection động conversationId)
    await FirebaseFirestore.instance
        .collection(FirestoreConstants.pathMessageCollection)
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

    // 3. Cập nhật dữ liệu hội thoại bằng Transaction để đảm bảo tính toàn vẹn
    try {
      final isGroupChat = idTo == conversationId;
      final convRef = FirebaseFirestore.instance
          .collection(FirestoreConstants.pathConversationCollection)
          .doc(conversationId);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(convRef);
        final data = snapshot.data() ?? {};

        final currentLastTime =
            int.tryParse(data['lastMessageTime']?.toString() ?? '0') ?? 0;
        final newTime = int.tryParse(timestamp) ?? 0;

        final updates = <String, dynamic>{};

        if (newTime >= currentLastTime || !snapshot.exists) {
          // Lưu đoạn trích thay vì chuỗi mã hóa
          updates['lastMessage'] = _buildPreview(plainContent, messageType);
          updates['lastMessageTime'] = timestamp;
          updates['lastMessageType'] = messageType;
        }

        List<dynamic> participants = List.from(data['participants'] ?? []);
        if (!participants.contains(idFrom)) participants.add(idFrom);
        if (!isGroupChat && !participants.contains(idTo)) {
          participants.add(idTo);
        }
        updates['participants'] = participants;

        for (final p in participants) {
          if (p != idFrom) {
            updates['unreadCount.$p'] = FieldValue.increment(1);
          }
        }

        transaction.set(convRef, updates, SetOptions(merge: true));
      });
    } catch (err) {
      // [FIX] Cảnh báo lỗi non-fatal, bỏ lệnh return false để Job không bị Retry vô tận
      debugPrint('[SyncManager] ⚠️ Conversation update non-fatal: $err');
    }

    // 4. Cập nhật trạng thái database cục bộ: pending → sent
    await _localDb.updateMessageStatus(
      conversationId,
      messageId,
      MessageStatus.sent,
    );

    // ── AI Content Bridge ──────────────────────────────────────────────────
    if (messageType == TypeMessage.text &&
        plainContent.isNotEmpty &&
        idTo != AppConstants.aiAssistantId) {
      _pushAiContent(
        conversationId: conversationId,
        messageId: messageId,
        plainContent: plainContent,
        idFrom: idFrom,
      );
    }

    debugPrint('[SyncManager] 📤 Sent message $messageId');
    return true;
  }

  Future<bool> _processAiResponse(Map<String, dynamic> payload) async {
    final conversationId = _str(payload['conversationId']);
    final currentUserId = _str(payload['currentUserId']);
    final userMessage = _str(payload['userMessage']);

    if (conversationId.isEmpty || userMessage.isEmpty) return false;

    // Lịch sử hội thoại từ LocalDB
    final rawHistoryMessages = _localDb
        .getMessages(conversationId)
        .take(20)
        .toList()
        .reversed
        .map((m) {
      final text =
          m['contentPlain']?.toString() ?? m['content']?.toString() ?? '';
      if (text.isEmpty ||
          text.startsWith('{"iv":') ||
          text.startsWith('eyJ')) {
        return null;
      }
      final isMe = m['idFrom'] == currentUserId;
      return '${isMe ? "User" : "Assistant"}: $text';
    })
        .whereType<String>()
        .toList();

    String? aiText;
    try {
      // Gọi lên cổng Cloud Function thay vì GeminiService nội bộ
      aiText = await _aiBackend.generateAiChatReply(
        userMessage: userMessage,
        conversationHistory: rawHistoryMessages,
      );
    } on AIBackendException catch (e) {
      // Nếu là Permanent error, rethrow để `_processBatch` xử lý catch block riêng của nó
      if (e.type == AIBackendErrorType.unknown) {
        rethrow;
      }
      debugPrint('[SyncManager] Transient AI error details: $e');
    }

    // Nếu trả về null, trả về false để Queue tự động Retry
    if (aiText == null || aiText.trim().isEmpty) {
      debugPrint('[SyncManager] ⚠️ AI CF returned null — will retry');
      return false;
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // Đổi từ '_' sang '-' để không vi phạm quy tắc của LocalDbService
    final aiMessageId = '${nowMs}-${1000 + Random().nextInt(9000)}';
    final aiTimestampStr = nowMs.toString();

    // Mã hóa tin nhắn với ID của người dùng thực
    String encryptedAiText;
    try {
      encryptedAiText = await _encryption.encryptPayload(
        aiText,
        conversationId,
        [currentUserId, AppConstants.aiAssistantId],
        currentUserId, // Trực tiếp dùng Human ID để lấy session_key
      );
    } catch (e) {
      debugPrint('[SyncManager] ❌ AI Encrypt failed: $e');
      encryptedAiText = aiText;
    }

    final aiMessage = <String, dynamic>{
      'messageId': aiMessageId,
      'idFrom': AppConstants.aiAssistantId,
      'idTo': currentUserId,
      'timestamp': aiTimestampStr,
      'content': encryptedAiText,
      'contentPlain': aiText, // Lưu dự phòng plaintext vào bộ nhớ tạm
      'type': TypeMessage.text,
      'status': MessageStatus.sent,
    };

    // Lưu trữ xuống local cache
    await _localDb.saveMessage(conversationId, aiMessageId, aiMessage);

    // Ghi tài liệu lên Firestore Collection (Lưu chuỗi đã mã hóa an toàn lên Cloud)
    await FirebaseFirestore.instance
        .collection(FirestoreConstants.pathMessageCollection)
        .doc(conversationId)
        .collection(conversationId)
        .doc(aiMessageId)
        .set({
      'idFrom': AppConstants.aiAssistantId,
      'idTo': currentUserId,
      'timestamp': aiTimestampStr,
      'content': encryptedAiText,
      'type': TypeMessage.text,
      'status': MessageStatus.sent,
    });

    // Cập nhật lại khung tin nhắn hiển thị ngoài danh sách chat
    try {
      final convRef = FirebaseFirestore.instance
          .collection(FirestoreConstants.pathConversationCollection)
          .doc(conversationId);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(convRef);
        final data = snapshot.data() ?? {};

        final currentLastTime =
            int.tryParse(data['lastMessageTime']?.toString() ?? '0') ?? 0;
        final newTime = int.tryParse(aiTimestampStr) ?? 0;

        final updates = <String, dynamic>{};

        if (newTime >= currentLastTime || !snapshot.exists) {
          final preview =
          aiText!.length > 80 // Safe do đã check null trước
              ? '${aiText.substring(0, 80)}…'
              : aiText;
          updates['lastMessage'] = '[Trợ lý AI] $preview';
          updates['lastMessageTime'] = aiTimestampStr;
          updates['lastMessageType'] = TypeMessage.text;
        }

        List<dynamic> participants = List.from(data['participants'] ?? []);
        if (!participants.contains(currentUserId)) {
          participants.add(currentUserId);
        }
        if (!participants.contains(AppConstants.aiAssistantId)) {
          participants.add(AppConstants.aiAssistantId);
        }
        updates['participants'] = participants;
        updates['unreadCount.$currentUserId'] = FieldValue.increment(1);

        transaction.set(convRef, updates, SetOptions(merge: true));
      });
    } catch (e) {
      debugPrint('[SyncManager] ❌ AI conv update error: $e');
      return false;
    }

    debugPrint('[SyncManager] 🤖 AI response synced for $conversationId');
    return true;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // AI CONTENT BRIDGE MECHANICS
  // ═════════════════════════════════════════════════════════════════════════

  void _pushAiContent({
    required String conversationId,
    required String messageId,
    required String plainContent,
    required String idFrom,
  }) {
    FirebaseFirestore.instance
        .collection(FirestoreConstants.pathConversationCollection)
        .doc(conversationId)
        .get()
        .then((doc) {
      final isGroup = doc.data()?['isGroup'] as bool? ?? false;
      _aiContent
          .pushAiContentWithRetry(
        conversationId: conversationId,
        messageId: messageId,
        plainText: plainContent,
        idFrom: idFrom,
        messageType: TypeMessage.text,
        groupId: isGroup ? conversationId : null,
      )
          .catchError((e) {
        debugPrint('[SyncManager] AiContent retry push failed: $e');
      });
    })
        .catchError((e) {
      _aiContent
          .pushAiContentWithRetry(
        conversationId: conversationId,
        messageId: messageId,
        plainText: plainContent,
        idFrom: idFrom,
        messageType: TypeMessage.text,
        groupId: null,
      )
          .catchError((err) {
        debugPrint(
          '[SyncManager] AiContent fallback retry push failed: $err',
        );
      });
      debugPrint(
        ('[SyncManager] AiContent conv fetch error (non-critical): $e'),
      );
    });
  }

  // ═════════════════════════════════════════════════════════════════════════
  // INTERNAL HELPERS
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> _markMessageFailed(Map<String, dynamic> payload) async {
    final conversationId = _str(payload['conversationId']);
    final messageId = _str(payload['messageId']);
    if (conversationId.isEmpty || messageId.isEmpty) return;
    await _localDb.updateMessageStatus(
      conversationId,
      messageId,
      MessageStatus.failed,
    );
    debugPrint('[SyncManager] ❌ Marked $messageId as failed');
  }

  void _emit(SyncStatus status) {
    if (_status == status) return;
    _status = status;
    if (!_statusCtrl.isClosed) _statusCtrl.add(status);
  }

  static String _str(dynamic v) => v?.toString() ?? '';
}