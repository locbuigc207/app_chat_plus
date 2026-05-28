// ignore_for_file: avoid_print

import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../utils/utils.dart';

// =========================================================
// MODELS
// =========================================================

/// Mức độ nguy hiểm của tin nhắn sau phân tích scam.
enum ScamLevel {
  safe,    // An toàn
  warning, // Đáng ngờ
  scam,    // Lừa đảo rõ ràng
}

extension ScamLevelX on ScamLevel {
  String get label {
    switch (this) {
      case ScamLevel.safe:    return 'SAFE';
      case ScamLevel.warning: return 'WARNING';
      case ScamLevel.scam:    return 'SCAM';
    }
  }

  static ScamLevel fromString(String? raw) {
    switch (raw?.toUpperCase()) {
      case 'WARNING': return ScamLevel.warning;
      case 'SCAM':    return ScamLevel.scam;
      default:        return ScamLevel.safe;
    }
  }
}

/// Kết quả phân tích scam đầy đủ.
class ScamAnalysisResult {
  final ScamLevel level;
  final String? reason;
  final double? confidence; // 0.0 – 1.0
  final List<String> warningKeywords;

  const ScamAnalysisResult({
    required this.level,
    this.reason,
    this.confidence,
    this.warningKeywords = const [],
  });

  factory ScamAnalysisResult.safe() =>
      const ScamAnalysisResult(level: ScamLevel.safe);

  factory ScamAnalysisResult.fromMap(Map<dynamic, dynamic> data) {
    final keywords = data['warningKeywords'];
    return ScamAnalysisResult(
      level: ScamLevelX.fromString(data['status'] as String?),
      reason: data['reason'] as String?,
      confidence: (data['confidence'] as num?)?.toDouble(),
      warningKeywords: keywords is List
          ? keywords.cast<String>()
          : const [],
    );
  }
}

/// Kết quả trích xuất relationship memory.
class RelationshipMemory {
  final String? relationshipType; // friend, family, colleague...
  final List<String> sharedTopics;
  final List<String> importantDates;
  final Map<String, dynamic> rawData;

  const RelationshipMemory({
    this.relationshipType,
    this.sharedTopics = const [],
    this.importantDates = const [],
    required this.rawData,
  });

  factory RelationshipMemory.fromMap(Map<dynamic, dynamic> data) {
    final topics = data['sharedTopics'];
    final dates = data['importantDates'];
    return RelationshipMemory(
      relationshipType: data['relationshipType'] as String?,
      sharedTopics: topics is List ? topics.cast<String>() : [],
      importantDates: dates is List ? dates.cast<String>() : [],
      rawData: Map<String, dynamic>.from(data),
    );
  }
}

// =========================================================
// EXCEPTIONS
// =========================================================

enum AIBackendErrorType {
  networkError,
  authError,
  quotaExceeded,
  invalidResponse,
  functionNotFound,
  unknown,
}

class AIBackendException implements Exception {
  final AIBackendErrorType type;
  final String message;
  final Object? cause;

  const AIBackendException(this.type, this.message, {this.cause});

  @override
  String toString() =>
      'AIBackendException(${type.name}): $message'
          '${cause != null ? ' — $cause' : ''}';
}

// =========================================================
// AI BACKEND SERVICE
// =========================================================

/// Service giao tiếp với Firebase Cloud Functions để xử lý AI phía backend.
///
/// Toàn bộ nội dung tin nhắn được mask qua [DataMaskingUtils] trước khi
/// gửi lên server, đảm bảo không rò rỉ dữ liệu nhạy cảm ra ngoài.
///
/// Tất cả các method đều:
/// - Mask PII trước khi gửi lên server.
/// - Có timeout tích hợp để tránh treo UI.
/// - Trả về giá trị mặc định an toàn khi gặp lỗi (không ném exception ra ngoài).
class AIBackendService {
  // ── Singleton ──────────────────────────────────────────
  AIBackendService._internal();
  static final AIBackendService _instance = AIBackendService._internal();
  factory AIBackendService() => _instance;

  // ── Dependencies ───────────────────────────────────────
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'asia-southeast1', // Đặt gần Vietnam để giảm latency
  );

  // ── Timeouts ───────────────────────────────────────────
  static const _kDefaultTimeout = Duration(seconds: 15);
  static const _kAnalysisTimeout = Duration(seconds: 20);
  static const _kBatchTimeout = Duration(seconds: 30);

  // ── Masking config cho AI (chỉ mask PII, giữ ngữ cảnh) ─
  static const _kAiMaskingConfig = MaskingConfig.piiOnly;

  // =========================================================
  // 1. PHÂN TÍCH SCAM (NHANH)
  // =========================================================

  /// Kiểm tra nhanh một tin nhắn có dấu hiệu scam/lừa đảo không.
  /// Trả về [ScamLevel.safe] nếu gặp lỗi để không làm gián đoạn UX.
  Future<ScamLevel> checkScam(String message) async {
    final result = await analyzeScamDetailed(message);
    return result.level;
  }

  /// Phân tích scam chi tiết — trả về [ScamAnalysisResult] đầy đủ.
  Future<ScamAnalysisResult> analyzeScamDetailed(String message) async {
    if (message.trim().isEmpty) return ScamAnalysisResult.safe();

    try {
      final safeMessage = DataMaskingUtils.maskText(
        message,
        config: _kAiMaskingConfig,
      );

      final result = await _call(
        functionName: 'analyzeScam',
        params: {'message': safeMessage},
        timeout: _kDefaultTimeout,
      );

      if (result == null) return ScamAnalysisResult.safe();
      return ScamAnalysisResult.fromMap(result as Map);
    } catch (e) {
      _log('checkScam error: $e');
      return ScamAnalysisResult.safe();
    }
  }

  // =========================================================
  // 2. PHÂN TÍCH TIN NHẮN ĐÃ GIẢI MÃ (SCAM DETECTION PIPELINE)
  // =========================================================

  /// Gửi tin nhắn đã giải mã E2EE lên Cloud Function để phân tích.
  ///
  /// Được gọi từ [AdaptiveChatBubble._triggerClientSideAI] sau khi
  /// giải mã thành công, chỉ với tin nhắn từ người khác.
  Future<void> analyzeDecryptedMessage({
    required String plainText,
    required String conversationId,
    required String messageId,
    required String idFrom,
    required String idTo,
  }) async {
    if (plainText.trim().isEmpty) return;

    try {
      final safeMessage = DataMaskingUtils.maskText(
        plainText,
        config: _kAiMaskingConfig,
      );

      await _call(
        functionName: 'analyzeDecryptedMessage',
        params: {
          'plainText': safeMessage,
          'conversationId': conversationId,
          'messageId': messageId,
          'idFrom': idFrom,
          'idTo': idTo,
          'timestamp': DateTime.now().toIso8601String(),
        },
        timeout: _kAnalysisTimeout,
      );
    } catch (e, st) {
      _logError('analyzeDecryptedMessage', e, st);
    }
  }

  // =========================================================
  // 3. DỊCH / DIỄN GIẢI TIN NHẮN
  // =========================================================

  /// Dịch/diễn giải lại tin nhắn phù hợp với đối tượng nhận.
  ///
  /// [targetAudience]: `'elder'` | `'student'` | `'work'` | `'child'`
  Future<String?> translateCommunication(
      String message,
      String targetAudience,
      ) async {
    if (message.trim().isEmpty) return null;

    try {
      final safeMessage = DataMaskingUtils.maskText(
        message,
        config: _kAiMaskingConfig,
      );

      final result = await _call(
        functionName: 'translateCommunication',
        params: {
          'message': safeMessage,
          'targetAudience': targetAudience,
        },
        timeout: _kAnalysisTimeout,
      );

      return result?['translatedText'] as String?;
    } catch (e, st) {
      _logError('translateCommunication', e, st);
      return null;
    }
  }

  // =========================================================
  // 4. PHÂN TÍCH NGỮ CẢNH CHAT
  // =========================================================

  /// Phân tích ngữ cảnh cuộc hội thoại để gợi ý hành động hoặc tóm tắt.
  ///
  /// [contextType]: `'study'` | `'work'` | `'elder'` | `'general'`
  /// [action]: `'summarize'` | `'suggest'` | `'analyze_mood'`
  Future<String?> analyzeChatContext(
      List<String> messages,
      String contextType,
      String action,
      ) async {
    if (messages.isEmpty) return null;

    try {
      final safeMessages = DataMaskingUtils.prepareForAI(messages);

      final result = await _call(
        functionName: 'analyzeChatContext',
        params: {
          'messages': safeMessages, // Gửi dạng List thay vì join — backend dễ xử lý hơn
          'contextType': contextType,
          'action': action,
          'messageCount': messages.length,
        },
        timeout: _kBatchTimeout,
      );

      return result?['analysisResult'] as String?;
    } catch (e, st) {
      _logError('analyzeChatContext', e, st);
      return null;
    }
  }

  // =========================================================
  // 5. TRÍCH XUẤT RELATIONSHIP MEMORY
  // =========================================================

  /// Trích xuất thông tin quan hệ/ngữ cảnh từ lịch sử hội thoại.
  Future<RelationshipMemory?> extractRelationshipMemory(
      List<String> messages, {
        String? conversationId,
      }) async {
    if (messages.isEmpty) return null;

    try {
      final safeMessages = DataMaskingUtils.prepareForAI(messages);

      final result = await _call(
        functionName: 'extractRelationshipMemory',
        params: {
          'messages': safeMessages,
          if (conversationId != null) 'conversationId': conversationId,
        },
        timeout: _kBatchTimeout,
      );

      if (result == null) return null;
      return RelationshipMemory.fromMap(result as Map);
    } catch (e, st) {
      _logError('extractRelationshipMemory', e, st);
      return null;
    }
  }

  // =========================================================
  // 6. GỢI Ý TRẢ LỜI THÔNG MINH
  // =========================================================

  /// Gợi ý 3 cách trả lời ngắn gọn phù hợp với ngữ cảnh.
  Future<List<String>> suggestReplies(
      List<String> recentMessages, {
        String tone = 'friendly', // 'friendly' | 'formal' | 'casual'
      }) async {
    if (recentMessages.isEmpty) return [];

    try {
      final safeMessages = DataMaskingUtils.prepareForAI(recentMessages);

      final result = await _call(
        functionName: 'suggestReplies',
        params: {
          'messages': safeMessages,
          'tone': tone,
          'count': 3,
        },
        timeout: _kDefaultTimeout,
      );

      final suggestions = result?['suggestions'];
      if (suggestions is List) return suggestions.cast<String>();
      return [];
    } catch (e, st) {
      _logError('suggestReplies', e, st);
      return [];
    }
  }

  // =========================================================
  // 7. TÓM TẮT CUỘC TRÒ CHUYỆN
  // =========================================================

  /// Tóm tắt nội dung cuộc hội thoại trong một đoạn ngắn.
  Future<String?> summarizeConversation(
      List<String> messages, {
        int maxSentences = 3,
        String language = 'vi',
      }) async {
    if (messages.isEmpty) return null;

    try {
      final safeMessages = DataMaskingUtils.prepareForAI(messages);

      final result = await _call(
        functionName: 'summarizeConversation',
        params: {
          'messages': safeMessages,
          'maxSentences': maxSentences,
          'language': language,
        },
        timeout: _kAnalysisTimeout,
      );

      return result?['summary'] as String?;
    } catch (e, st) {
      _logError('summarizeConversation', e, st);
      return null;
    }
  }

  // =========================================================
  // 8. PHÂN TÍCH CẢM XÚC (SENTIMENT)
  // =========================================================

  /// Phân tích cảm xúc tổng thể của cuộc hội thoại.
  /// Trả về map: `{'sentiment': 'positive'|'neutral'|'negative', 'score': 0.0-1.0}`
  Future<Map<String, dynamic>?> analyzeSentiment(
      List<String> messages,
      ) async {
    if (messages.isEmpty) return null;

    try {
      final safeMessages = DataMaskingUtils.prepareForAI(messages);

      final result = await _call(
        functionName: 'analyzeSentiment',
        params: {'messages': safeMessages},
        timeout: _kDefaultTimeout,
      );

      if (result == null) return null;
      return Map<String, dynamic>.from(result as Map);
    } catch (e, st) {
      _logError('analyzeSentiment', e, st);
      return null;
    }
  }

  // =========================================================
  // 9. PHÁT HIỆN NGÔN NGỮ THÙ GHÉT / NỘI DUNG ĐỘC HẠI
  // =========================================================

  /// Kiểm tra tin nhắn có chứa ngôn ngữ thù ghét, quấy rối, nội dung độc hại.
  /// Trả về `false` nếu an toàn hoặc gặp lỗi.
  Future<bool> detectHateSpeech(String message) async {
    if (message.trim().isEmpty) return false;

    try {
      final safeMessage = DataMaskingUtils.maskText(
        message,
        config: _kAiMaskingConfig,
      );

      final result = await _call(
        functionName: 'detectHateSpeech',
        params: {'message': safeMessage},
        timeout: _kDefaultTimeout,
      );

      return result?['isHateful'] as bool? ?? false;
    } catch (e, st) {
      _logError('detectHateSpeech', e, st);
      return false;
    }
  }

  // =========================================================
  // PRIVATE: HTTP CALL WRAPPER
  // =========================================================

  /// Wrapper chung cho tất cả Cloud Function calls.
  /// Tích hợp: timeout, error mapping, retry cho rate-limit.
  Future<Map<dynamic, dynamic>?> _call({
    required String functionName,
    required Map<String, dynamic> params,
    Duration timeout = _kDefaultTimeout,
    int maxRetries = 1,
  }) async {
    int attempt = 0;

    while (attempt <= maxRetries) {
      try {
        final callable = _functions.httpsCallable(
          functionName,
          options: HttpsCallableOptions(timeout: timeout),
        );

        final result = await callable.call(params);
        return result.data as Map<dynamic, dynamic>?;
      } on FirebaseFunctionsException catch (e) {
        final mapped = _mapFunctionsException(e);

        // Retry chỉ khi bị rate-limit
        if (mapped.type == AIBackendErrorType.quotaExceeded &&
            attempt < maxRetries) {
          attempt++;
          await Future.delayed(Duration(seconds: 2 * attempt));
          continue;
        }
        throw mapped;
      } on TimeoutException catch (e) {
        throw AIBackendException(
          AIBackendErrorType.networkError,
          'Cloud Function "$functionName" timeout sau ${timeout.inSeconds}s',
          cause: e,
        );
      } catch (e) {
        throw AIBackendException(
          AIBackendErrorType.unknown,
          'Lỗi không xác định khi gọi "$functionName"',
          cause: e,
        );
      }
    }

    return null;
  }

  AIBackendException _mapFunctionsException(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'unauthenticated':
      case 'permission-denied':
        return AIBackendException(
          AIBackendErrorType.authError,
          'Không có quyền gọi Cloud Function: ${e.message}',
          cause: e,
        );
      case 'resource-exhausted':
        return AIBackendException(
          AIBackendErrorType.quotaExceeded,
          'Cloud Function vượt quota: ${e.message}',
          cause: e,
        );
      case 'not-found':
        return AIBackendException(
          AIBackendErrorType.functionNotFound,
          'Cloud Function không tồn tại: ${e.message}',
          cause: e,
        );
      case 'unavailable':
      case 'deadline-exceeded':
        return AIBackendException(
          AIBackendErrorType.networkError,
          'Cloud Function không khả dụng: ${e.message}',
          cause: e,
        );
      default:
        return AIBackendException(
          AIBackendErrorType.unknown,
          'FirebaseFunctionsException [${e.code}]: ${e.message}',
          cause: e,
        );
    }
  }

  // =========================================================
  // LOGGING
  // =========================================================

  void _log(String msg) {
    if (kDebugMode) debugPrint('[AIBackendService] $msg');
  }

  void _logError(String method, Object e, StackTrace st) {
    if (kDebugMode) {
      debugPrint('[AIBackendService] ❌ $method error: $e');
    }
    ErrorLogger.logError(e, st, context: 'AIBackendService.$method');
  }
}