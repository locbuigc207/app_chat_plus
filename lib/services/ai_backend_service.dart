import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../utils/utils.dart';
import 'local_db_service.dart';

export '../models/ai_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RESULT & ERROR TYPES
// ─────────────────────────────────────────────────────────────────────────────

class ScamAnalysisResult {
  final ScamLevel level;
  final String? reason;
  final double? confidence;
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
      level: ScamLevelX.fromString(
        data['status'] as String? ?? data['level'] as String?,
      ),
      reason: data['reason'] as String?,
      confidence: (data['confidence'] as num?)?.toDouble(),
      warningKeywords: keywords is List ? keywords.cast<String>() : const [],
    );
  }

  bool get isSafe => level == ScamLevel.safe;
  bool get isWarning => level == ScamLevel.warning;
  bool get isScam => level == ScamLevel.scam;

  @override
  String toString() =>
      'ScamAnalysisResult(level: ${level.name}, confidence: $confidence)';
}

/// Model kết quả học Persona thay thế cho class trong autopilot_ai_service
class LearnPersonaResult {
  final bool success;
  final String? personaText;
  final int messageCount;
  final String? errorMessage;

  const LearnPersonaResult._({
    required this.success,
    this.personaText,
    this.messageCount = 0,
    this.errorMessage,
  });

  factory LearnPersonaResult.success({
    required String personaText,
    int messageCount = 0,
  }) => LearnPersonaResult._(
    success: true,
    personaText: personaText,
    messageCount: messageCount,
  );

  factory LearnPersonaResult.fail(String reason) =>
      LearnPersonaResult._(success: false, errorMessage: reason);
}

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

// ─────────────────────────────────────────────────────────────────────────────
// MAIN SERVICE
// ─────────────────────────────────────────────────────────────────────────────

class AIBackendService {
  AIBackendService._internal();
  static final AIBackendService _instance = AIBackendService._internal();
  factory AIBackendService() => _instance;

  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'asia-southeast1',
  );

  // ── Timeouts & Config ──────────────────────────────────────────────────────
  static const _kDefaultTimeout = Duration(seconds: 15);
  static const _kPreviewTimeout = Duration(seconds: 10);
  static const _kAnalysisTimeout = Duration(seconds: 30);
  static const _kBatchTimeout = Duration(seconds: 45);
  static const _kLearnTimeout = Duration(seconds: 60);
  static const _kInsightTimeout = Duration(seconds: 90);

  // ── Masking config ────────────────────────────────────────────────────────
  static const _kAiMaskingConfig = MaskingConfig.piiOnly;

  // ══════════════════════════════════════════════════════════════════════════
  // CORE METHODS
  // ══════════════════════════════════════════════════════════════════════════

  /// Gọi Cloud Function để lấy AI chat reply (Thay thế GeminiService trực tiếp)
  Future<String?> generateAiChatReply({
    required String userMessage,
    List<String> conversationHistory = const [],
  }) async {
    if (userMessage.trim().isEmpty) return null;
    try {
      final safeMsg = DataMaskingUtils.maskText(
        userMessage,
        config: _kAiMaskingConfig,
      );
      final safeHistory = DataMaskingUtils.prepareForAI(conversationHistory);

      final result = await _call(
        functionName: 'generateAiChatReply',
        params: {'userMessage': safeMsg, 'conversationHistory': safeHistory},
        timeout: const Duration(seconds: 30),
      );
      if (result?['success'] != true) return null;
      return result?['reply'] as String?;
    } catch (e, st) {
      _logError('generateAiChatReply', e, st);
      return null;
    }
  }

  /// Kiểm tra scam nhanh — trả về ScamLevel enum.
  Future<ScamLevel> checkScam(String message) async {
    final result = await analyzeScamDetailed(message);
    return result.level;
  }

  /// Phân tích scam chi tiết — trả về ScamAnalysisResult đầy đủ.
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
      return ScamAnalysisResult.fromMap(result);
    } catch (e, st) {
      _logError('analyzeScamDetailed', e, st);
      return ScamAnalysisResult.safe();
    }
  }

  /// Phân tích tin nhắn đã decrypt từ backend trigger.
  Future<Map<String, dynamic>?> analyzeDecryptedMessage({
    required String plainText,
    required String conversationId,
    required String messageId,
    required String idFrom,
    required String idTo,
  }) async {
    if (plainText.trim().isEmpty) return null;

    try {
      final safeMessage = DataMaskingUtils.maskText(
        plainText,
        config: _kAiMaskingConfig,
      );

      final result = await _call(
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

      return result != null ? Map<String, dynamic>.from(result) : null;
    } catch (e, st) {
      _logError('analyzeDecryptedMessage', e, st);
      return null;
    }
  }

  /// Dịch tin nhắn sang phong cách phù hợp với đối tượng mục tiêu.
  Future<String?> translateCommunication({
    required String message,
    required String targetAudience,
    bool preserveEmoji = true,
  }) async {
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
          'preserveEmoji': preserveEmoji,
        },
        timeout: _kAnalysisTimeout,
      );

      return result?['translatedText'] as String?;
    } catch (e, st) {
      _logError('translateCommunication', e, st);
      return null;
    }
  }

  /// Phân tích ngữ cảnh chat — extract_tasks, summarize, analyze_mood, v.v.
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
          'messages': safeMessages,
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

  /// Trích xuất relationship memory từ lịch sử tin nhắn.
  Future<RelationshipMemory?> extractRelationshipMemory({
    required List<String> messages,
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
      return RelationshipMemory.fromMap(Map<String, dynamic>.from(result));
    } catch (e, st) {
      _logError('extractRelationshipMemory', e, st);
      return null;
    }
  }

  /// Gợi ý câu trả lời thông minh trả về model `SmartReply`.
  Future<List<SmartReply>> suggestReplies({
    required List<String> messages,
    String tone = 'friendly',
    int count = 3,
    String userContext = '',
  }) async {
    if (messages.isEmpty) return [];

    try {
      final safeMessages = DataMaskingUtils.prepareForAI(messages);

      final result = await _call(
        functionName: 'suggestReplies',
        params: {
          'messages': safeMessages,
          'tone': tone,
          'count': count,
          'userContext': userContext,
        },
        timeout: _kDefaultTimeout,
      );

      final map = _asMap(result);
      return (_asList(map['suggestions']))
          .map((s) => SmartReply(text: s.toString(), isAiGenerated: true))
          .toList();
    } catch (e, st) {
      _logError('suggestReplies', e, st);
      return [];
    }
  }

  /// Tóm tắt cuộc hội thoại.
  Future<String?> summarizeConversation({
    required List<String> messages,
    int maxSentences = 4,
    String language = 'vi',
    bool includeKeyPoints = false,
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
          'includeKeyPoints': includeKeyPoints,
        },
        timeout: _kAnalysisTimeout,
      );

      return result?['summary'] as String?;
    } catch (e, st) {
      _logError('summarizeConversation', e, st);
      return null;
    }
  }

  /// Phân tích cảm xúc tổng thể cuộc trò chuyện.
  Future<Map<String, dynamic>?> analyzeSentiment(List<String> messages) async {
    if (messages.isEmpty) return null;

    try {
      final safeMessages = DataMaskingUtils.prepareForAI(messages);

      final result = await _call(
        functionName: 'analyzeSentiment',
        params: {'messages': safeMessages},
        timeout: _kDefaultTimeout,
      );

      if (result == null) return null;
      return Map<String, dynamic>.from(result);
    } catch (e, st) {
      _logError('analyzeSentiment', e, st);
      return null;
    }
  }

  /// Phát hiện ngôn ngữ thù ghét — trả về bool đơn giản.
  Future<bool> detectHateSpeech(String message) async {
    final result = await detectHateSpeechDetailed(message);
    return result.isHateful;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ADVANCED ANALYSIS & FEATURES
  // ══════════════════════════════════════════════════════════════════════════

  /// Phân tích tin nhắn đến: scam + reminder + sentiment + intent.
  Future<Map<String, dynamic>?> analyzeDecryptedClientMessage({
    required String plainTextContent,
    required String conversationId,
    required String messageId,
    String? idTo,
  }) async {
    if (plainTextContent.trim().isEmpty) return null;
    // Bỏ qua nếu content là encrypted blob
    if (plainTextContent.startsWith('{"iv":') ||
        plainTextContent.startsWith('eyJ'))
      return null;

    try {
      final safeText = DataMaskingUtils.maskText(
        plainTextContent,
        config: _kAiMaskingConfig,
      );
      final result = await _call(
        functionName: 'analyzeDecryptedClientMessage',
        params: {
          'plainTextContent': safeText,
          'conversationId': conversationId,
          'messageId': messageId,
          if (idTo != null) 'idTo': idTo,
        },
        timeout: _kAnalysisTimeout,
      );
      if (result == null) return null;
      return Map<String, dynamic>.from(result);
    } catch (e, st) {
      _logError('analyzeDecryptedClientMessage', e, st);
      return null;
    }
  }

  /// Phân tích và trả về ClientMessageAnalysis model đầy đủ.
  Future<ClientMessageAnalysis?> analyzeClientMessageTyped({
    required String plainTextContent,
    required String conversationId,
    required String messageId,
    String? idTo,
  }) async {
    final raw = await analyzeDecryptedClientMessage(
      plainTextContent: plainTextContent,
      conversationId: conversationId,
      messageId: messageId,
      idTo: idTo,
    );
    if (raw == null) return null;
    return ClientMessageAnalysis.fromMap(raw);
  }

  /// Trả về HateSpeechResult chi tiết.
  Future<HateSpeechResult> detectHateSpeechDetailed(String message) async {
    if (message.trim().isEmpty) return HateSpeechResult.safe();
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
      if (result == null) return HateSpeechResult.safe();
      return HateSpeechResult.fromMap(result);
    } catch (e, st) {
      _logError('detectHateSpeechDetailed', e, st);
      return HateSpeechResult.safe();
    }
  }

  /// Phiên bản nâng cao — trả về list SmartReply với metadata.
  Future<List<SmartReply>> smartReplyWithContextTyped({
    required List<String> messages,
    Map<String, dynamic> userProfile = const {},
    String replyIntent = 'helpful',
    String language = 'vi',
    int count = 3,
  }) async {
    if (messages.isEmpty) return [];
    try {
      final safeMessages = DataMaskingUtils.maskList(
        messages,
        config: _kAiMaskingConfig,
      );
      final result = await _call(
        functionName: 'smartReplyWithContext',
        params: {
          'messages': safeMessages,
          'userProfile': userProfile,
          'replyIntent': replyIntent,
          'maxLength': 150,
          'language': language,
          'count': count,
        },
        timeout: _kAnalysisTimeout,
      );
      final replies = result?['replies'];
      List<String> texts = [];
      if (replies is List) {
        texts = replies.cast<String>();
      } else {
        final single = result?['reply'] as String?;
        if (single != null && single.isNotEmpty) texts = [single];
      }

      return texts
          .where((t) => t.trim().isNotEmpty)
          .map(
            (text) => SmartReply(
              text: text,
              confidence: 0.92,
              isAiGenerated: true,
              category: replyIntent,
            ),
          )
          .toList();
    } catch (e, st) {
      _logError('smartReplyWithContextTyped', e, st);
      return [];
    }
  }

  /// Smart reply nâng cao: trả về text suggestions + sticker gợi ý,
  /// cá nhân hóa theo closeness level và relationship type.
  Future<EnhancedSmartReplyResult?> smartReplyEnhanced({
    required List<String> messages,
    int closenessLevel = 3,
    String relationshipType = 'friend',
    String language = 'vi',
    int count = 3,
  }) async {
    if (messages.isEmpty) return null;
    try {
      final safeMessages = DataMaskingUtils.prepareForAI(messages);

      final result = await _call(
        functionName: 'smartReplyEnhanced',
        params: {
          'messages': safeMessages,
          'userProfile': {
            'closenessLevel': closenessLevel,
            'relationshipType': relationshipType,
          },
          'language': language,
          'count': count,
        },
        timeout: _kAnalysisTimeout,
      );

      if (result == null) return null;

      // ✅ FIX P0: CF alias trả về {reply} không phải {replies}, normalize thành list
      List<dynamic> repliesList = [];
      if (result['replies'] is List) {
        repliesList = result['replies'] as List;
      } else if (result['suggestions'] is List) {
        repliesList = result['suggestions'] as List;
      } else if (result['reply'] is String &&
          (result['reply'] as String).isNotEmpty) {
        repliesList = [result['reply']];
      }

      final mappedResult = {
        'replies': repliesList,
        'stickers': result['stickers'] ?? result['stickerCards'] ?? [],
      };

      return EnhancedSmartReplyResult.fromMap(mappedResult);
    } catch (e, st) {
      _logError('smartReplyEnhanced', e, st);
      return null;
    }
  }

  /// Phiên bản nâng cao — trả về IcebreakerResult đầy đủ.
  Future<IcebreakerResult> generateIcebreakersTyped({
    List<String> sharedInterests = const [],
    String relationshipType = 'friend',
    int count = 5,
    String style = 'casual',
  }) async {
    try {
      final result = await _call(
        functionName: 'generateIcebreakers',
        params: {
          'sharedInterests': sharedInterests.take(5).toList(),
          'relationshipType': relationshipType,
          'count': count,
          'style': style,
        },
        timeout: _kDefaultTimeout,
      );
      if (result == null) return IcebreakerResult.empty();
      return IcebreakerResult.fromMap(result);
    } catch (e, st) {
      _logError('generateIcebreakersTyped', e, st);
      return IcebreakerResult.empty();
    }
  }

  /// Viết lại tin nhắn sang tông giọng khác.
  Future<ToneRewriterResult?> generateMessageTone({
    required String message,
    required String toTone,
    String fromTone = 'auto',
    bool keepEmoji = true,
  }) async {
    if (message.trim().isEmpty) return null;
    try {
      // Dùng MaskingSession để restore PII sau khi AI rewrite
      final session = MaskingSession.create(message);
      final result = await _call(
        functionName: 'generateMessageTone',
        params: {
          'message': session.masked,
          'fromTone': fromTone,
          'toTone': toTone,
          'keepEmoji': keepEmoji,
        },
        timeout: _kAnalysisTimeout,
      );

      if (result == null) return null;

      final rawRewritten = result['rewritten'] as String? ?? '';

      // Restore PII vào kết quả AI
      final restored = session.restore(rawRewritten);

      // [FIX 10] Cải thiện PII Fallback: Kiểm tra những placeholder không thể restore
      final hasUnrestoredPlaceholders = RegExp(
        r'\[[A-Z]+_\d+\]',
      ).hasMatch(restored);
      if (hasUnrestoredPlaceholders && session.hasSensitiveData) {
        final restoredCount = session.tokens
            .where((t) => restored.contains(t.placeholder))
            .length;

        // Nếu AI làm mất trên 50% lượng placeholder bí mật -> Chủ động huỷ bỏ mask gọi lại raw bằng nguyên bản tin nhắn
        if (restoredCount > session.tokens.length / 2) {
          _log(
            'generateMessageTone: Quá nhiều placeholder bị AI thay đổi, gọi lại API với raw string.',
          );
          final rawResult = await _call(
            functionName: 'generateMessageTone',
            params: {
              'message': message, // Sử dụng nguyên tin nhắn gốc chưa che giấu
              'fromTone': fromTone,
              'toTone': toTone,
              'keepEmoji': keepEmoji,
            },
            timeout: _kAnalysisTimeout,
          );
          return ToneRewriterResult(
            original: message,
            rewritten: rawResult?['rewritten'] as String? ?? rawRewritten,
            toTone: toTone,
            fromTone: fromTone,
          );
        }
      }

      return ToneRewriterResult(
        original: message,
        rewritten: restored,
        toTone: toTone,
        fromTone: fromTone,
      );
    } catch (e, st) {
      _logError('generateMessageTone', e, st);
      return null;
    }
  }

  Future<List<ToxicityResult>> analyzeToxicityBatch(
    List<ToxicityInput> messages,
  ) async {
    if (messages.isEmpty) return [];

    // [FIX 17] Cài đặt giới hạn 20 message client-side trước khi truyền tải
    const clientLimit = 20;
    if (messages.length > clientLimit) {
      _log(
        'analyzeToxicityBatch: Hệ thống đang điều chỉnh số lượng truyền tải từ ${messages.length} xuống $clientLimit.',
      );
    }

    final limitedMessages = messages.take(clientLimit).toList();

    try {
      final safeMessages = limitedMessages
          .map(
            (m) => {
              'id': m.id,
              'text': DataMaskingUtils.maskText(
                m.text,
                config: _kAiMaskingConfig,
              ),
            },
          )
          .toList();

      final result = await _call(
        functionName: 'analyzeToxicityBatch',
        params: {'messages': safeMessages},
        timeout: _kBatchTimeout,
      );

      final results = result?['results'];
      if (results is! List) return [];

      return results.asMap().entries.map((entry) {
        final map = entry.value as Map<dynamic, dynamic>;
        return ToxicityResult(
          // GUARD CLAUSE (Bug 8): Tránh RangeError khi server trả về nhiều phần tử hơn limitedMessages
          id:
              map['id']?.toString() ??
              (entry.key < limitedMessages.length
                  ? limitedMessages[entry.key].id
                  : null),
          index: (map['index'] as num?)?.toInt() ?? entry.key,
          isToxic: map['isToxic'] as bool? ?? false,
          category: map['category'] as String? ?? 'safe',
          confidence: (map['confidence'] as num?)?.toDouble() ?? 0,
        );
      }).toList();
    } catch (e, st) {
      _logError('analyzeToxicityBatch', e, st);
      return [];
    }
  }

  Future<KeyMomentsResult?> extractKeyMoments({
    required List<String> messages,
    String? conversationId,
  }) async {
    if (messages.length < 5) return null;
    try {
      final safeMessages = DataMaskingUtils.maskList(
        messages,
        config: _kAiMaskingConfig,
      );
      final result = await _call(
        functionName: 'extractKeyMoments',
        params: {
          'messages': safeMessages,
          if (conversationId != null) 'conversationId': conversationId,
        },
        timeout: _kBatchTimeout,
      );
      if (result == null) return null;
      return KeyMomentsResult.fromMap(Map<String, dynamic>.from(result));
    } catch (e, st) {
      _logError('extractKeyMoments', e, st);
      return null;
    }
  }

  /// Lấy messages từ LocalDB (đã decrypt), mask PII, gửi lên Cloud Function.
  Future<UserInsightsResult?> getUserInsights({
    required String conversationId,
    int lookbackDays = 7,
    int messageLimit = 50,
    String period = 'week7',
    bool useAI = false,
  }) async {
    try {
      final cutoff = DateTime.now()
          .subtract(Duration(days: lookbackDays))
          .millisecondsSinceEpoch;

      final rawMessages = LocalDbService()
          .getMessages(conversationId)
          .where((m) {
            final ts = int.tryParse(m['timestamp']?.toString() ?? '0') ?? 0;
            final c = m['content']?.toString() ?? '';
            return ts >= cutoff &&
                c.isNotEmpty &&
                !c.startsWith('{"iv":') &&
                !c.startsWith('eyJ');
          })
          .take(messageLimit)
          .toList();

      if (rawMessages.length < 5) {
        _log('getUserInsights: not enough messages (${rawMessages.length})');
        return null;
      }

      // ✅ FIX P0: Đưa về mảng các chuỗi thô (List<String>) vì CF cần typeof m === "string"
      final maskedMessages = rawMessages
          .map(
            (m) => DataMaskingUtils.maskText(
              m['content']?.toString() ?? '',
              config: _kAiMaskingConfig,
            ),
          )
          .where((s) => s.trim().length > 2)
          .toList();

      final result = await _call(
        functionName: 'getUserInsightsV2',
        params: {
          'messages': maskedMessages,
          'lookbackDays': lookbackDays,
          'conversationId': conversationId,
          'period': period,
          'useAI': useAI,
        },
        timeout: _kInsightTimeout,
      );

      if (result == null) return null;

      // ✅ FIX P0: Truy xuất vào trường insights khi có nested response ({success: bool, insights: {...}})
      if (result['success'] != true) return null;
      final insights = result['insights'];
      if (insights == null) return null;

      return UserInsightsResult.fromMap(
        Map<String, dynamic>.from(insights as Map),
      );
    } catch (e, st) {
      _logError('getUserInsights', e, st);
      return null;
    }
  }

  /// Feature 2: Trigger CF tính lại insights cache (rate-limit 1h/user)
  Future<Map<String, dynamic>?> triggerInsightsRefresh({
    required String conversationId,
    required String userId,
  }) async {
    try {
      final result = await _call(
        functionName: 'triggerInsightsRefresh',
        params: {'conversationId': conversationId, 'userId': userId},
        timeout: _kAnalysisTimeout,
      );
      if (result == null) return null;
      return Map<String, dynamic>.from(result);
    } catch (e, st) {
      _logError('triggerInsightsRefresh', e, st);
      return null;
    }
  }

  /// Wrapper tiện lợi: lấy messages từ LocalDB rồi gọi extractRelationshipMemory.
  Future<RelationshipMemory?> extractRelationshipMemoryFromLocal({
    required String conversationId,
    int messageLimit = 100,
  }) async {
    try {
      // [FIX 5 & 16] Cải thiện filter giữ lại các chuỗi dạng JSON hợp lệ
      final recentMessages = LocalDbService()
          .getMessages(conversationId)
          .take(messageLimit)
          .toList();

      final messages = recentMessages
          .reversed // Chronological order
          .map((m) => m['content']?.toString() ?? '')
          .where((c) {
            if (c.isEmpty || c.length <= 3) return false;
            // E2EE payloads bypass
            if (c.startsWith('{"iv":') && c.contains('"data":')) return false;
            if (c.startsWith('eyJ')) return false;
            if (RegExp(r'^[A-Za-z0-9+/=]+=*:[A-Za-z0-9+/=]+=*$').hasMatch(c))
              return false;

            // Bỏ các chuỗi hệ thống (Poll, Game, Location) để tránh làm nhiễu Relationship AI
            try {
              final decoded = jsonDecode(c);
              if (decoded is Map) {
                if (decoded.containsKey('question') &&
                    decoded.containsKey('options'))
                  return false;
                if (decoded.containsKey('matchId') &&
                    decoded.containsKey('gameType'))
                  return false;
                if (decoded.containsKey('lat') && decoded.containsKey('lng'))
                  return false;
                if (decoded.containsKey('iv') && decoded.containsKey('data'))
                  return false;
              }
            } catch (_) {
              // Bỏ qua lỗi bắt JSON vì nó là Plain Text chat bình thường của User
            }
            return true;
          })
          .toList();

      if (messages.length < 10) {
        _log(
          'extractRelationshipMemoryFromLocal: not enough valid messages (${messages.length})',
        );
        return null;
      }
      return extractRelationshipMemory(
        messages: messages,
        conversationId: conversationId,
      );
    } catch (e, st) {
      _logError('extractRelationshipMemoryFromLocal', e, st);
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // AUTOPILOT
  // ══════════════════════════════════════════════════════════════════════════

  /// Feature 1: Đọc config Autopilot từ Cloud Functions
  Future<Map<String, dynamic>?> getAutoPilotConfig({
    required String conversationId,
    required String userId,
  }) async {
    try {
      final result = await _call(
        functionName: 'getAutoPilotConfig',
        params: {'conversationId': conversationId},
        timeout: _kDefaultTimeout,
      );
      // ✅ FIX P0: Check trường exists vì response của CF là {exists: true, config: {...}}
      if (result?['exists'] == true && result?['config'] != null) {
        return Map<String, dynamic>.from(result!['config'] as Map);
      }
      return null;
    } catch (e, st) {
      _logError('getAutoPilotConfig', e, st);
      return null;
    }
  }

  /// Feature 1: Ghi config Autopilot lên Firestore qua Cloud Functions
  Future<bool> saveAutoPilotConfig({
    required String conversationId,
    required String userId,
    required Map<String, dynamic> config,
  }) async {
    try {
      final result = await _call(
        functionName: 'saveAutoPilotConfig',
        params: {
          'conversationId': conversationId,
          'userId': userId,
          'config': config,
        },
        timeout: _kDefaultTimeout,
      );
      return result?['success'] == true;
    } catch (e, st) {
      _logError('saveAutoPilotConfig', e, st);
      return false;
    }
  }

  /// Feature 1: Server-side persona learning qua Gemini Flash
  Future<LearnPersonaResult> learnUserPersona({
    required String conversationId,
    required String userId,
    required List<String> messages,
  }) async {
    if (messages.length < 10) {
      return LearnPersonaResult.fail(
        'Cần ít nhất 10 tin nhắn để AI học phong cách.',
      );
    }

    // Lọc E2EE, giới hạn 100
    final cleanMsgs = messages
        .where(
          (m) =>
              !m.startsWith('{"iv":') &&
              !m.startsWith('eyJ') &&
              m.trim().length > 3,
        )
        .take(100)
        .toList();

    if (cleanMsgs.length < 10) {
      return LearnPersonaResult.fail('Không đủ tin nhắn hợp lệ sau khi lọc.');
    }

    try {
      final result = await _call(
        functionName: 'learnUserPersona',
        params: {
          'conversationId': conversationId,
          'userId': userId,
          'messages': cleanMsgs, // plain text — không mask để AI học chính xác
        },
        timeout: _kLearnTimeout,
      );

      if (result == null)
        return LearnPersonaResult.fail('Không nhận được phản hồi từ AI.');

      final success = result['success'] as bool? ?? false;
      if (!success) {
        return LearnPersonaResult.fail(
          result['reason'] as String? ?? 'Lỗi không xác định từ AI.',
        );
      }

      final persona = result['persona'];
      String personaStr = '';
      if (persona is Map) {
        final summary = persona['summary'] as String? ?? '';
        final style = persona['tone'] as String? ?? '';
        final emoji = persona['emojiUsage'] as String? ?? '';
        final len = persona['sentenceLength'] as String? ?? '';
        final chars =
            (persona['characteristicWords'] as List?)?.cast<String>().join(
              ', ',
            ) ??
            '';
        personaStr =
            'Tông: $style. Emoji: $emoji. Câu: $len. Từ đặc trưng: $chars. $summary';
      } else if (persona is String) {
        personaStr = persona;
      }

      return LearnPersonaResult.success(
        personaText: personaStr,
        messageCount: result['messageCount'] as int? ?? cleanMsgs.length,
      );
    } catch (e, st) {
      _logError('learnUserPersona', e, st);
      return LearnPersonaResult.fail('Lỗi kết nối AI: $e');
    }
  }

  /// Tạo câu trả lời auto-pilot thay mặt người dùng.
  Future<String?> generateAutoPilotReply({
    required String incomingMessage,
    String myStyleContext = 'thân thiện, ngắn gọn',
    String? awayMessage,
    String tone = 'friendly',
    String? learnedPersona,
    List<String> contextMessages = const [],
    String? conversationId,
    bool isPreview = false,
  }) async {
    if (incomingMessage.trim().isEmpty) return awayMessage;
    // Guard E2EE
    if (incomingMessage.startsWith('{"iv":') ||
        incomingMessage.startsWith('eyJ'))
      return awayMessage;

    // [FIX 18] Chủ động load Config khi Autopilot tone likeMe nhưng thiết bị Client mất learnedPersona State
    String? effectivePersona = learnedPersona;
    if (tone == 'likeMe' &&
        effectivePersona == null &&
        conversationId != null) {
      try {
        final config = await getAutoPilotConfig(
          conversationId: conversationId,
          userId: '',
        );
        effectivePersona = config?['learnedPersona'] as String?;
      } catch (_) {
        // Fallback bỏ qua lỗi
      }
    }

    try {
      final safe = DataMaskingUtils.maskText(
        incomingMessage,
        config: _kAiMaskingConfig,
      );

      final result = await _call(
        functionName: 'generateAutoPilotReply',
        params: {
          'incomingMessage': safe,
          'myStyleContext': myStyleContext,
          if (awayMessage != null) 'awayMessage': awayMessage,
          'tone': tone,
          if (effectivePersona != null) 'learnedPersona': effectivePersona,
          'contextMessages': DataMaskingUtils.maskList(
            contextMessages.take(6).toList(),
            config: _kAiMaskingConfig,
          ),
          if (conversationId != null) 'conversationId': conversationId,
          'isPreview': isPreview,
        },
        timeout: isPreview ? _kPreviewTimeout : _kDefaultTimeout,
      );
      return result?['reply'] as String?;
    } catch (e, st) {
      _logError('generateAutoPilotReply', e, st);
      return awayMessage;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MISC
  // ══════════════════════════════════════════════════════════════════════════

  /// Tạo 4 câu trả lời swipe ngắn cho Zero-Type feature.
  Future<List<String>> generateSwipeReplies({
    required String incomingMessage,
    String contextMessages = '',
    String replyStyle = 'genz',
  }) async {
    const fallback = ['Ok nha', 'Thế à?', 'Chịu luôn 😂', 'Đỉnh!'];
    if (incomingMessage.trim().isEmpty) return fallback;
    try {
      final safe = DataMaskingUtils.maskText(
        incomingMessage,
        config: _kAiMaskingConfig,
      );
      final result = await _call(
        functionName: 'generateSwipeReplies',
        params: {
          'incomingMessage': safe,
          'contextMessages': contextMessages,
          'replyStyle': replyStyle,
        },
        timeout: _kDefaultTimeout,
      );
      final replies = result?['replies'];
      if (replies is List && replies.isNotEmpty) {
        return replies.cast<String>().take(4).toList();
      }
      return fallback;
    } catch (e, st) {
      _logError('generateSwipeReplies', e, st);
      return fallback;
    }
  }

  /// Swipe replies nâng cao: text cards + sticker cards.
  Future<({List<String> replies, List<String> stickerCards})>
  generateSwipeRepliesEnhanced({
    required String incomingMessage,
    String contextMessages = '',
    String replyStyle = 'genz',
    bool includeStickerCards = true,
  }) async {
    const fallback = (
      replies: ['Ok nha', 'Thế à?', 'Chịu luôn 😂', 'Đỉnh!'],
      stickerCards: <String>[],
    );
    if (incomingMessage.trim().isEmpty) return fallback;
    try {
      final safe = DataMaskingUtils.maskText(
        incomingMessage,
        config: _kAiMaskingConfig,
      );
      final result = await _call(
        functionName: 'generateSwipeReplies',
        params: {
          'incomingMessage': safe,
          'contextMessages': contextMessages,
          'replyStyle': replyStyle,
          'includeStickerCards': includeStickerCards,
        },
        timeout: _kDefaultTimeout,
      );
      final replies = result?['replies'];
      final stickers = result?['stickerCards'];
      return (
        replies: replies is List
            ? replies.cast<String>().take(4).toList()
            : fallback.replies,
        stickerCards: stickers is List
            ? stickers.cast<String>().take(2).toList()
            : <String>[],
      );
    } catch (e, st) {
      _logError('generateSwipeRepliesEnhanced', e, st);
      return fallback;
    }
  }

  /// Phân tích bảo mật cuộc gọi — phát hiện deepfake, social engineering.
  Future<Map<String, dynamic>?> analyzeCallSecurity({
    required String callTranscript,
    String? peerId,
    String? conversationId,
  }) async {
    if (callTranscript.trim().isEmpty) return null;
    try {
      final safe = DataMaskingUtils.maskText(
        callTranscript,
        config: _kAiMaskingConfig,
      );
      final result = await _call(
        functionName: 'analyzeCallSecurity',
        params: {
          'callTranscript': safe,
          if (peerId != null) 'peerId': peerId,
          if (conversationId != null) 'conversationId': conversationId,
        },
        timeout: _kAnalysisTimeout,
      );
      if (result == null) return null;
      return Map<String, dynamic>.from(result);
    } catch (e, st) {
      _logError('analyzeCallSecurity', e, st);
      return null;
    }
  }

  /// Phân tích toxicity cho một tin nhắn đơn.
  Future<ToxicityResult> analyzeSingleToxicity(
    String message, {
    String? id,
  }) async {
    if (message.trim().isEmpty) return ToxicityResult.safe(id: id);
    final results = await analyzeToxicityBatch([
      ToxicityInput(id: id, text: message),
    ]);
    return results.isNotEmpty ? results.first : ToxicityResult.safe(id: id);
  }

  /// Batch analyze: toxicity + hate speech cho nhiều tin nhắn cùng lúc.
  Future<Map<String, dynamic>> batchAnalyzeMessages({
    required List<String> messages,
    required List<String> messageIds,
    bool checkToxicity = true,
    bool checkHateSpeech = false,
  }) async {
    final results = <String, dynamic>{};
    if (messages.isEmpty) return results;

    try {
      if (checkToxicity) {
        final inputs = messages
            .asMap()
            .entries
            .map(
              (e) => ToxicityInput(
                id: (e.key < messageIds.length) ? messageIds[e.key] : null,
                text: e.value,
              ),
            )
            .toList();
        final toxicityResults = await analyzeToxicityBatch(inputs);
        results['toxicity'] = toxicityResults;
      }

      if (checkHateSpeech) {
        final hateSpeechResults = await Future.wait(
          messages.map((m) => detectHateSpeechDetailed(m)),
        );
        results['hateSpeech'] = hateSpeechResults;
      }
    } catch (e, st) {
      _logError('batchAnalyzeMessages', e, st);
    }
    return results;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // REMINDER – extractReminderWithPriority
  // ──────────────────────────────────────────────────────────────────────────

  /// Phân tích một tin nhắn, bóc tách TẤT CẢ tác vụ/lịch hẹn cùng với
  /// mức ưu tiên (high/medium/low) và deadline cụ thể.
  Future<ReminderExtractionResult> extractReminderWithPriority({
    required String message,
    String conversationContext = '',
  }) async {
    if (message.trim().isEmpty) return ReminderExtractionResult.empty();
    try {
      final safeMsg = DataMaskingUtils.maskText(
        message,
        config: _kAiMaskingConfig,
      );
      final safeCtx = DataMaskingUtils.maskText(
        conversationContext,
        config: _kAiMaskingConfig,
      );

      final result = await _call(
        functionName: 'extractReminderWithPriority',
        params: {'message': safeMsg, 'conversationContext': safeCtx},
        timeout: _kAnalysisTimeout,
      );

      if (result == null) return ReminderExtractionResult.empty();
      return ReminderExtractionResult.fromMap(
        Map<String, dynamic>.from(result),
      );
    } catch (e, st) {
      _logError('extractReminderWithPriority', e, st);
      return ReminderExtractionResult.empty();
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // REMINDER – batchExtractReminders
  // ──────────────────────────────────────────────────────────────────────────

  /// Bóc tách nhắc nhở từ nhiều tin nhắn cùng lúc (batch, hiệu quả hơn).
  Future<List<ExtractedReminder>> batchExtractReminders({
    required List<Map<String, dynamic>> messages,
    int lookbackHours = 24,
  }) async {
    if (messages.isEmpty) return [];
    try {
      final safeMsgs = messages
          .map(
            (m) => {
              ...m,
              'content': DataMaskingUtils.maskText(
                m['content']?.toString() ?? '',
                config: _kAiMaskingConfig,
              ),
              'timestamp':
                  m['timestamp']?.toString() ??
                  DateTime.now().millisecondsSinceEpoch.toString(),
            },
          )
          .toList();

      final result = await _call(
        functionName: 'batchExtractReminders',
        params: {'messages': safeMsgs, 'lookbackHours': lookbackHours},
        timeout: _kBatchTimeout,
      );

      if (result == null) return [];
      final list = result['reminders'] as List? ?? [];
      return list
          .map(
            (r) =>
                ExtractedReminder.fromMap(Map<String, dynamic>.from(r as Map)),
          )
          .where((r) => r.task.isNotEmpty)
          .toList();
    } catch (e, st) {
      _logError('batchExtractReminders', e, st);
      return [];
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // REMINDER – generateReminderSuggestions
  // ──────────────────────────────────────────────────────────────────────────

  /// Gợi ý các nhắc nhở thông minh dựa trên lịch sử tin nhắn và
  /// các nhắc nhở đã có để tránh trùng lặp.
  Future<List<ReminderSuggestion>> generateReminderSuggestions({
    required List<String> recentMessages,
    List<String> existingReminders = const [],
    String userContext = '',
  }) async {
    if (recentMessages.isEmpty) return [];
    try {
      final safeMessages = DataMaskingUtils.prepareForAI(recentMessages);

      final result = await _call(
        functionName: 'generateReminderSuggestions',
        params: {
          'recentMessages': safeMessages,
          'existingReminders': existingReminders,
          'userContext': DataMaskingUtils.maskText(
            userContext,
            config: _kAiMaskingConfig,
          ),
        },
        timeout: _kDefaultTimeout,
      );

      if (result == null) return [];
      final list = result['suggestions'] as List? ?? [];
      return list
          .map(
            (s) =>
                ReminderSuggestion.fromMap(Map<String, dynamic>.from(s as Map)),
          )
          .where((s) => s.task.isNotEmpty)
          .toList();
    } catch (e, st) {
      _logError('generateReminderSuggestions', e, st);
      return [];
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CORE PRIVATE HELPER METHODS
  // ══════════════════════════════════════════════════════════════════════════

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

        // Retry khi quota exceeded
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

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  List<dynamic> _asList(dynamic data) {
    if (data is List) return data;
    return [];
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
