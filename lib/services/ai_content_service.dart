// lib/services/ai_content_service.dart
//
// Quản lý collection 'ai_content' — lưu plain text đã masked PII.
// FIRESTORE RULES: client chỉ WRITE, Cloud Functions (admin SDK) mới READ.
// KHÔNG có getRecentMaskedMessages() — client đọc từ LocalDbService thay thế.
//
// Architecture:
//  - Tích hợp Retry Mechanism (Exponential Backoff) bảo vệ mất mát dữ liệu
//  - TTL tự động: 95 ngày (đủ qua 1 cycle 90 ngày cho Cloud Functions)
//  - Guard: reject ciphertext lọt vào
//  - Cleanup: hỗ trợ xoá expired docs theo batch

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_chat_demo/utils/utils.dart';

class AiContentService {
  AiContentService._();
  static final AiContentService _instance = AiContentService._();
  factory AiContentService() => _instance;

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// TTL đủ cho 90-day analysis của Cloud Functions + buffer 5 ngày
  static const int _ttlDays = 95;

  /// Batch size cho cleanup
  static const int _cleanupBatchSize = 500;

  CollectionReference<Map<String, dynamic>> _ref(String convId) =>
      _db.collection('ai_content').doc(convId).collection('ai_content');

  // ── Push ──────────────────────────────────────────────────────────────────

  /// [FIX 18] Push plain text (đã mask PII) lên Firestore với cơ chế Retry
  /// (Exponential Backoff) để giảm thiểu tối đa rủi ro mất dữ liệu AI do lỗi mạng.
  Future<void> pushAiContentWithRetry({
    required String conversationId,
    required String messageId,
    required String plainText,
    required String idFrom,
    required int messageType,
    String? groupId,
    int maxRetries = 3,
  }) async {
    // Chỉ xử lý text messages (type 0)
    if (messageType != 0 || plainText.trim().isEmpty) return;

    // Guard: không push ciphertext lên ai_content
    if (_isCiphertext(plainText)) {
      debugPrint(
        '[AiContent] ⚠️ Ciphertext detected — skip push for $messageId',
      );
      return;
    }

    // Guard: quá ngắn để có giá trị phân tích
    if (plainText.trim().length < 3) return;

    final masked = MaskingSession.maskOnly(plainText);
    final expireAt = DateTime.now().add(const Duration(days: _ttlDays));

    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        await _ref(conversationId).doc(messageId).set({
          'idFrom': idFrom,
          'userId': idFrom,
          'conversationId': conversationId,
          'content': masked,
          // Lưu timestamp kiểu Number chuẩn xác cho logic của Cloud Functions Node.js
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          if (groupId != null) 'groupId': groupId,
          'expireAt': Timestamp.fromDate(expireAt),
          'pushedAt': FieldValue.serverTimestamp(),
        });

        debugPrint(
          '[AiContent] ✅ Pushed $messageId (masked ${plainText.length} → ${masked.length} chars)',
        );
        return; // Thành công thì thoát vòng lặp retry
      } catch (e, st) {
        if (attempt < maxRetries - 1) {
          // Exponential backoff delay: 2s, 4s, 6s...
          final delaySeconds = (attempt + 1) * 2;
          debugPrint(
            '[AiContent] 🔄 Retry push $messageId after ${delaySeconds}s (Error: $e)',
          );
          await Future.delayed(Duration(seconds: delaySeconds));
        } else {
          // Báo lỗi critical khi đã kiệt sức retry
          ErrorLogger.logError(
            e,
            st,
            context: 'AiContentService.pushAiContentWithRetry.exhausted',
          );
        }
      }
    }
  }

  /// Hàm push cũ (fire-and-forget không có retry) giữ lại để tương thích ngược
  /// với những phần code chưa migrate sang `pushAiContentWithRetry`
  Future<void> pushAiContent({
    required String conversationId,
    required String messageId,
    required String plainText,
    required String idFrom,
    required int messageType,
    String? groupId,
  }) async {
    if (messageType != 0 || plainText.trim().isEmpty) return;
    if (_isCiphertext(plainText)) return;
    if (plainText.trim().length < 3) return;

    try {
      final masked = MaskingSession.maskOnly(plainText);
      final expireAt = DateTime.now().add(const Duration(days: _ttlDays));

      await _ref(conversationId).doc(messageId).set({
        'idFrom': idFrom,
        'userId': idFrom,
        'conversationId': conversationId,
        'content': masked,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        if (groupId != null) 'groupId': groupId,
        'expireAt': Timestamp.fromDate(expireAt),
        'pushedAt': FieldValue.serverTimestamp(),
      });
    } catch (e, st) {
      ErrorLogger.logError(e, st, context: 'AiContentService.pushAiContent');
    }
  }

  /// Push content trực tiếp (gọi thủ công trước khi gửi tin nhắn từ AI Infrastructure).
  /// Nhận plain text đã mask PII, tự động tạo ID tài liệu dựa trên timestamp.
  Future<void> pushContent({
    required String conversationId,
    required String content,
    required String idFrom,
    required int timestamp,
    String? groupId,
  }) async {
    if (content.trim().isEmpty) return;

    if (_isCiphertext(content)) {
      debugPrint(
        '[AiContent] ⚠️ Ciphertext detected in pushContent — skip push',
      );
      return;
    }

    if (content.trim().length < 3) return;

    try {
      final masked = MaskingSession.maskOnly(content);
      final expireAt = DateTime.now().add(const Duration(days: _ttlDays));
      final docId = timestamp.toString();

      await _ref(conversationId).doc(docId).set({
        'idFrom': idFrom,
        'userId': idFrom,
        'conversationId': conversationId,
        'content': masked,
        'timestamp': timestamp,
        if (groupId != null) 'groupId': groupId,
        'expireAt': Timestamp.fromDate(expireAt),
        'pushedAt': FieldValue.serverTimestamp(),
      });

      debugPrint(
        '[AiContent] ✅ Pushed content explicitly via pushContent: $docId',
      );
    } catch (e, st) {
      ErrorLogger.logError(e, st, context: 'AiContentService.pushContent');
    }
  }

  /// Push batch nhiều messages cùng lúc (dùng Firestore batch write).
  /// Fire-and-forget, lỗi chỉ log.
  Future<void> pushAiContentBatch({
    required String conversationId,
    required List<Map<String, dynamic>> messages,
  }) async {
    if (messages.isEmpty) return;

    try {
      final expireAt = Timestamp.fromDate(
        DateTime.now().add(const Duration(days: _ttlDays)),
      );
      final batch = _db.batch();
      int count = 0;

      for (final msg in messages) {
        final messageType = msg['type'] as int? ?? -1;
        final plainText = msg['content'] as String? ?? '';
        final messageId = msg['messageId'] as String? ?? '';
        final idFrom = msg['idFrom'] as String? ?? '';

        if (messageType != 0 || plainText.trim().isEmpty || messageId.isEmpty) {
          continue;
        }
        if (_isCiphertext(plainText)) continue;

        final masked = MaskingSession.maskOnly(plainText);
        if (masked.trim().length < 3) continue;

        final docRef = _ref(conversationId).doc(messageId);
        batch.set(docRef, {
          'idFrom': idFrom,
          'userId': idFrom,
          'conversationId': conversationId,
          'content': masked,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'expireAt': expireAt,
          'pushedAt': FieldValue.serverTimestamp(),
        });
        count++;

        // Firestore batch limit = 500
        if (count >= 499) break;
      }

      if (count > 0) {
        await batch.commit();
        debugPrint(
          '[AiContent] ✅ Batch pushed $count messages for $conversationId',
        );
      }
    } catch (e, st) {
      ErrorLogger.logError(
        e,
        st,
        context: 'AiContentService.pushAiContentBatch',
      );
    }
  }

  // ── Cleanup ───────────────────────────────────────────────────────────────

  /// Dọn documents hết hạn trong 1 conversation.
  /// Gọi từ maintenance task, không phải main flow.
  Future<int> cleanupExpired(String conversationId) async {
    try {
      final now = Timestamp.now();
      final expired = await _ref(conversationId)
          .where('expireAt', isLessThanOrEqualTo: now)
          .limit(_cleanupBatchSize)
          .get();

      if (expired.docs.isEmpty) return 0;

      final batch = _db.batch();
      for (final doc in expired.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      debugPrint(
        '[AiContent] 🗑 Cleaned ${expired.docs.length} expired docs from $conversationId',
      );
      return expired.docs.length;
    } catch (e) {
      debugPrint('[AiContent] cleanupExpired error: $e');
      return 0;
    }
  }

  /// Xoá toàn bộ ai_content của 1 conversation (vd: khi xoá conversation).
  Future<void> deleteAll(String conversationId) async {
    try {
      final snap = await _ref(conversationId).limit(_cleanupBatchSize).get();
      if (snap.docs.isEmpty) return;

      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      debugPrint('[AiContent] 🗑 Deleted all docs for $conversationId');
    } catch (e) {
      debugPrint('[AiContent] deleteAll error: $e');
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Phát hiện ciphertext để không push lên ai_content
  static bool _isCiphertext(String text) {
    final trimmed = text.trim();
    // E2EE GCM: {"iv":"...","data":"..."}
    if (trimmed.startsWith('{"iv":') && trimmed.contains('"data":')) {
      return true;
    }
    // Base64 JWT / legacy CBC
    if (trimmed.startsWith('eyJ')) return true;
    // Legacy CBC: base64:base64
    if (RegExp(r'^[A-Za-z0-9+/=]+=*:[A-Za-z0-9+/=]+=*$').hasMatch(trimmed)) {
      return true;
    }
    return false;
  }
}
