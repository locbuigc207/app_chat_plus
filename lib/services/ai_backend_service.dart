import 'package:cloud_functions/cloud_functions.dart';

import '../utils/utils.dart';

/// Service giao tiếp với Firebase Cloud Functions để xử lý AI phía backend.
///
/// Toàn bộ nội dung tin nhắn được mask qua [DataMaskingUtils] trước khi
/// gửi lên server, đảm bảo không rò rỉ dữ liệu nhạy cảm ra ngoài.
class AIBackendService {
  static final AIBackendService _instance = AIBackendService._internal();

  factory AIBackendService() => _instance;

  AIBackendService._internal();

  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  // =========================================================
  // ANALYZE DECRYPTED MESSAGE (SCAM DETECTION)
  // =========================================================

  /// Gửi tin nhắn đã giải mã lên Cloud Function để phân tích scam/lừa đảo.
  ///
  /// Được gọi từ [AdaptiveChatBubble._triggerClientSideAI] sau khi
  /// giải mã E2EE thành công, chỉ với tin nhắn người khác gửi đến.
  ///
  /// Tham số:
  /// - [plainText]: Nội dung tin nhắn đã giải mã.
  /// - [conversationId]: ID cuộc hội thoại.
  /// - [messageId]: Timestamp của tin nhắn (dùng làm document ID).
  /// - [idFrom]: UID người gửi (peerId).
  /// - [idTo]: UID người nhận (currentUserId).
  Future<void> analyzeDecryptedMessage({
    required String plainText,
    required String conversationId,
    required String messageId,
    required String idFrom,
    required String idTo,
  }) async {
    if (plainText.trim().isEmpty) return;

    try {
      final safeMessage = DataMaskingUtils.maskSensitiveData(plainText);

      final HttpsCallable callable =
          _functions.httpsCallable('analyzeDecryptedMessage');

      await callable.call(<String, dynamic>{
        'plainText': safeMessage,
        'conversationId': conversationId,
        'messageId': messageId,
        'idFrom': idFrom,
        'idTo': idTo,
      });
    } catch (e, stackTrace) {
      ErrorLogger.logError(
        e,
        stackTrace,
        context: 'AIBackendService.analyzeDecryptedMessage',
      );
    }
  }

  // =========================================================
  // TRANSLATE COMMUNICATION
  // =========================================================

  /// Dịch/diễn giải lại tin nhắn phù hợp với đối tượng nhận (elder, work, student...).
  Future<String?> translateCommunication(
    String message,
    String targetAudience,
  ) async {
    try {
      final safeMessage = DataMaskingUtils.maskSensitiveData(message);

      final HttpsCallable callable =
          _functions.httpsCallable('translateCommunication');

      final result = await callable.call(<String, dynamic>{
        'message': safeMessage,
        'targetAudience': targetAudience,
      });

      return result.data['translatedText'] as String?;
    } catch (e, stackTrace) {
      ErrorLogger.logError(
        e,
        stackTrace,
        context: 'AIBackendService.translateCommunication',
      );
      return null;
    }
  }

  // =========================================================
  // ANALYZE CHAT CONTEXT
  // =========================================================

  /// Phân tích ngữ cảnh cuộc hội thoại để gợi ý hành động hoặc tóm tắt.
  ///
  /// - [contextType]: Loại ngữ cảnh, vd: `'study'`, `'work'`, `'elder'`.
  /// - [action]: Hành động cần thực hiện, vd: `'summarize'`, `'suggest'`.
  Future<String?> analyzeChatContext(
    List<String> messages,
    String contextType,
    String action,
  ) async {
    try {
      final safeMessages = DataMaskingUtils.maskMessageList(messages);
      final chatHistory = safeMessages.join('\n');

      final HttpsCallable callable =
          _functions.httpsCallable('analyzeChatContext');

      final result = await callable.call(<String, dynamic>{
        'messages': chatHistory,
        'contextType': contextType,
        'action': action,
      });

      return result.data['analysisResult'] as String?;
    } catch (e, stackTrace) {
      ErrorLogger.logError(
        e,
        stackTrace,
        context: 'AIBackendService.analyzeChatContext',
      );
      return null;
    }
  }

  // =========================================================
  // CHECK SCAM
  // =========================================================

  /// Kiểm tra nhanh một tin nhắn có dấu hiệu scam/lừa đảo không.
  ///
  /// Trả về:
  /// - `'SAFE'`: An toàn.
  /// - `'WARNING'`: Có dấu hiệu đáng ngờ.
  /// - `'SCAM'`: Phát hiện lừa đảo.
  ///
  /// Mặc định trả về `'SAFE'` nếu gặp lỗi để không làm gián đoạn trải nghiệm.
  Future<String> checkScam(String message) async {
    try {
      final safeMessage = DataMaskingUtils.maskSensitiveData(message);

      final HttpsCallable callable = _functions.httpsCallable('analyzeScam');

      final result = await callable.call(<String, dynamic>{
        'message': safeMessage,
      });

      return result.data['status'] as String? ?? 'SAFE';
    } catch (e, stackTrace) {
      ErrorLogger.logError(
        e,
        stackTrace,
        context: 'AIBackendService.checkScam',
      );
      return 'SAFE';
    }
  }

  // =========================================================
  // EXTRACT RELATIONSHIP MEMORY
  // =========================================================

  /// Trích xuất thông tin quan hệ/ngữ cảnh từ lịch sử hội thoại.
  /// Kết quả dùng để cá nhân hóa gợi ý AI trong các cuộc trò chuyện sau.
  Future<Map<String, dynamic>?> extractRelationshipMemory(
    List<String> messages,
  ) async {
    try {
      final safeMessages = DataMaskingUtils.maskMessageList(messages);
      final chatHistory = safeMessages.join('\n');

      final HttpsCallable callable =
          _functions.httpsCallable('extractRelationshipMemory');

      final result = await callable.call(<String, dynamic>{
        'messages': chatHistory,
      });

      return Map<String, dynamic>.from(result.data as Map);
    } catch (e, stackTrace) {
      ErrorLogger.logError(
        e,
        stackTrace,
        context: 'AIBackendService.extractRelationshipMemory',
      );
      return null;
    }
  }
}
