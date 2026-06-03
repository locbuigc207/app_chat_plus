// lib/services/ai_content_service.dart
//
// Quản lý collection 'ai_content' — lưu plain text đã masked PII.
// FIRESTORE RULES: client chỉ WRITE, Cloud Functions (admin SDK) mới READ.
// KHÔNG có getRecentMaskedMessages() — client đọc từ LocalDbService thay thế.
//
// Architecture:
//  - Fire-and-forget pattern: không block main flow, lỗi chỉ log
//  - TTL tự động: 9 ngày (đủ qua 1 weeklyAiRecap cycle 7 ngày)
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

  /// TTL đủ qua 1 weeklyAiRecap cycle (7 ngày) với buffer 2 ngày
  static const int _ttlDays = 9;

  /// Batch size cho cleanup
  static const int _cleanupBatchSize = 500;

  CollectionReference<Map<String, dynamic>> _ref(String convId) =>
      _db.collection('ai_content').doc(convId).collection(convId);

  // ── Push ──────────────────────────────────────────────────────────────────

  /// Push plain text (đã mask PII) lên Firestore để Cloud Functions đọc.
  ///
  /// Được gọi từ SyncManager sau bước Firestore write thành công.
  /// Non-blocking: dùng fire-and-forget, lỗi chỉ log không throw.
  ///
  /// Guards:
  ///  - messageType != 0 → skip (chỉ text)
  ///  - Empty content → skip
  ///  - Ciphertext detected → skip với warning log
  Future<void> pushAiContent({
    required String conversationId,
    required String messageId,
    required String plainText,
    required String idFrom,
    required int messageType,
    String? groupId,
  }) async {
    // Chỉ xử lý text messages (type 0)
    if (messageType != 0 || plainText.trim().isEmpty) return;

    // Guard: không push ciphertext lên ai_content
    // JSON E2EE payload bắt đầu bằng {"iv": hoặc base64 JWT
    if (_isCiphertext(plainText)) {
      debugPrint(
          '[AiContent] ⚠️ Ciphertext detected — skip push for $messageId');
      return;
    }

    // Guard: quá ngắn để có giá trị phân tích
    if (plainText.trim().length < 3) return;

    try {
      final masked = MaskingSession.maskOnly(plainText);
      final expireAt = DateTime.now().add(const Duration(days: _ttlDays));

      await _ref(conversationId).doc(messageId).set({
        'idFrom': idFrom,
        'content': masked,
        'timestamp': DateTime.now().millisecondsSinceEpoch.toString(),
        if (groupId != null) 'groupId': groupId,
        'expireAt': Timestamp.fromDate(expireAt),
        'pushedAt': FieldValue.serverTimestamp(),
      });

      debugPrint(
          '[AiContent] ✅ Pushed $messageId (masked ${plainText.length} → ${masked.length} chars)');
    } catch (e, st) {
      // Non-critical: không throw, chỉ log
      ErrorLogger.logError(e, st, context: 'AiContentService.pushAiContent');
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

        if (messageType != 0 || plainText.trim().isEmpty || messageId.isEmpty)
          continue;
        if (_isCiphertext(plainText)) continue;

        final masked = MaskingSession.maskOnly(plainText);
        if (masked.trim().length < 3) continue;

        final docRef = _ref(conversationId).doc(messageId);
        batch.set(docRef, {
          'idFrom': idFrom,
          'content': masked,
          'timestamp': DateTime.now().millisecondsSinceEpoch.toString(),
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
            '[AiContent] ✅ Batch pushed $count messages for $conversationId');
      }
    } catch (e, st) {
      ErrorLogger.logError(e, st,
          context: 'AiContentService.pushAiContentBatch');
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
          '[AiContent] 🗑 Cleaned ${expired.docs.length} expired docs from $conversationId');
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
    if (trimmed.startsWith('{"iv":') && trimmed.contains('"data":'))
      return true;
    // Base64 JWT / legacy CBC
    if (trimmed.startsWith('eyJ')) return true;
    // Legacy CBC: base64:base64
    if (RegExp(r'^[A-Za-z0-9+/=]+=*:[A-Za-z0-9+/=]+=*$').hasMatch(trimmed))
      return true;
    return false;
  }
}
