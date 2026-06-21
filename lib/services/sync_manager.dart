// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_chat_demo/services/services.dart';
import 'package:flutter_chat_demo/utils/utils.dart'; // Sử dụng DataMaskingUtils

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
  idle, // Không có gì cần đồng bộ
  syncing, // Đang chạy đồng bộ các tác vụ trong hàng đợi
  paused, // Có kết nối mạng nhưng tạm dừng để chờ hồi phục (backoff) sau lỗi
  offline, // Mất kết nối mạng hoàn toàn
  error, // Lỗi nghiêm trọng kéo dài (đã cạn số lần thử lại)
}

// ─────────────────────────────────────────────────────────────────────────────
// JOB PRIORITY
// ─────────────────────────────────────────────────────────────────────────────

enum JobPriority {
  high, // Tin nhắn bị lỗi cần được gửi lại khẩn cấp
  normal, // Tin nhắn gửi đi thông thường của người dùng
  low, // Phản hồi tự động hoặc nội dung từ AI
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

class SyncManager {
  // ── Singleton ──────────────────────────────────────────────────────────────
  SyncManager._internal();
  static final SyncManager _instance = SyncManager._internal();
  factory SyncManager() => _instance;

  // ── Status stream ──────────────────────────────────────────────────────────
  final _statusCtrl = StreamController<SyncStatus>.broadcast();

  /// Đăng ký lắng nghe biến động trạng thái đồng bộ trong thời gian thực.
  Stream<SyncStatus> get statusStream => _statusCtrl.stream;

  SyncStatus _status = SyncStatus.idle;
  SyncStatus get currentStatus => _status;

  // ── Lifecycle ────────────────────────────────────────────────
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _heartbeatTimer;
  bool _isSyncing = false;
  bool _isStarted = false;
  bool _isOnline = true;

  // ── Retry config ───────────────────────────────────────────────────────────
  static const int _maxRetries = 4;
  static const int _maxBatchSize = 20;
  static const Duration _heartbeatInterval = Duration(seconds: 30);

  /// Exponential backoff: 2s, 4s, 8s, 16s … giới hạn trần tại 60s.
  static Duration _backoff(int retries) =>
      Duration(seconds: min(60, pow(2, retries + 1).toInt()));

  // ── Dependencies ───────────────────────────────────────────────────────────
  final _localDb = LocalDbService();
  final _encryption = EncryptionService();
  final _gemini = GeminiService();
  final _aiContent = AiContentService();

  // ═════════════════════════════════════════════════════════════════════════
  // PUBLIC API
  // ═════════════════════════════════════════════════════════════════════════

  /// Bắt đầu lắng nghe thay đổi trạng thái kết nối và kích hoạt đồng bộ đợt đầu.
  void startListening() {
    if (!_isStarted) {
      _isStarted = true;

      _connectivitySub = Connectivity().onConnectivityChanged.listen(
        _onConnectivity,
      );

      // Heartbeat định kỳ phòng trường hợp bỏ sót sự kiện thay đổi kết nối của hệ thống
      _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
        if (_isOnline) _trySync();
      });
    }
    _trySync();
  }

  /// Dừng toàn bộ hoạt động chạy nền — thường gọi khi người dùng đăng xuất.
  void stopListening() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _connectivitySub?.cancel();
    _connectivitySub = null;
    _isStarted = false;

    // [ĐÃ SỬA LỖI P0]: KHÔNG close _statusCtrl tại đây — đây là singleton,
    // cần giữ stream mở để có thể restart mượt mà sau khi user login lại.
    _emit(SyncStatus.idle);
    debugPrint('[SyncManager] 🛑 Stopped');
  }

  /// Đưa tác vụ gửi tin nhắn vào hàng đợi đồng bộ với độ ưu tiên chỉ định.
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
    _trySync(); // Kích hoạt đồng bộ ngay lập tức
  }

  /// Đưa tác vụ sinh câu trả lời của AI trợ lý vào hàng đợi.
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

  /// Trả về số lượng tác vụ hiện đang xếp hàng chờ xử lý.
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
            '[SyncManager] 🗑 Job $key exhausted retries — marking failed',
          );
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
        .collection(FirestoreConstants.pathMessageCollection) // 'messages'
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

    // 3. Cập nhật dữ liệu hội thoại trực tiếp (Xóa bỏ khối query tốn quota)
    // [ĐÃ ĐỒNG BỘ LOGIC BUG 7]: Kiểm tra tránh add nhầm groupChatId vào participants mảng đối với Group Chat.
    try {
      final isGroupChat = idTo == conversationId;

      await FirebaseFirestore.instance
          .collection(FirestoreConstants.pathConversationCollection)
          .doc(conversationId)
          .set({
            'lastMessage': plainContent.length > 100
                ? plainContent.substring(0, 100)
                : plainContent,
            'lastMessageTime': timestamp,
            'lastMessageType': messageType,
            if (!isGroupChat)
              'participants': FieldValue.arrayUnion([idFrom, idTo]),
          }, SetOptions(merge: true));
    } catch (err) {
      debugPrint('[SyncManager] convo update error: $err');
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

    final maskedUserMessage = DataMaskingUtils.maskText(
      userMessage,
      config: MaskingConfig.piiOnly,
    );

    final history = _localDb
        .getMessages(conversationId)
        .take(30)
        .toList()
        .reversed
        .map(
          (m) => <String, dynamic>{
            'idFrom': m['idFrom'],
            'content': DataMaskingUtils.maskText(
              m['content']?.toString() ?? '',
              config: MaskingConfig.piiOnly,
            ),
          },
        )
        .toList();

    final response = await _gemini.sendMessageDetailed(
      maskedUserMessage,
      history,
    );

    if (response.isError) {
      if (response.isRetryable == true) {
        return false;
      }
    }

    final aiText = (response.isError || response.text.isEmpty)
        ? 'Trợ lý AI hiện không phản hồi được, vui lòng thử lại sau.'
        : response.text;

    // SỬA LỖI P0: Tạo aiMessageId ghép liền không dấu gạch dưới để không phá vỡ LocalDb Key Convention
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final aiMessageId = '$nowMs${(1000 + Random().nextInt(9000))}';
    final aiTimestampStr = nowMs.toString();

    final aiMessage = <String, dynamic>{
      'messageId': aiMessageId,
      'idFrom': AppConstants.aiAssistantId,
      'idTo': currentUserId,
      'timestamp': aiTimestampStr,
      'content': aiText,
      'type': TypeMessage.text,
      'status': MessageStatus.sent,
    };

    // Lưu trữ xuống local cache
    await _localDb.saveMessage(conversationId, aiMessageId, aiMessage);

    // Ghi tài liệu lên Firestore Collection (Dùng subcollection động conversationId)
    await FirebaseFirestore.instance
        .collection(FirestoreConstants.pathMessageCollection) // 'messages'
        .doc(conversationId)
        .collection(conversationId)
        .doc(aiMessageId)
        .set({
          'idFrom': AppConstants.aiAssistantId,
          'idTo': currentUserId,
          'timestamp': aiTimestampStr,
          'content': aiText,
          'type': TypeMessage.text,
          'status': MessageStatus.sent,
        });

    // Cập nhật lại khung tin nhắn cuối cùng hiển thị ngoài danh sách chat
    await FirebaseFirestore.instance
        .collection(FirestoreConstants.pathConversationCollection)
        .doc(conversationId)
        .set({
          'lastMessage': aiText.length > 80
              ? '${aiText.substring(0, 80)}…'
              : aiText,
          'lastMessageTime': aiTimestampStr,
          'lastMessageType': TypeMessage.text,
          'participants': FieldValue.arrayUnion([
            currentUserId,
            AppConstants.aiAssistantId,
          ]),
        }, SetOptions(merge: true));

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
