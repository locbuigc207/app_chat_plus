// ignore_for_file: avoid_print
// lib/services/ai_backend_service.dart

import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../models/ai_models.dart';
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
          data['status'] as String? ?? data['level'] as String?),
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
  String toString() => 'AIBackendException(${type.name}): $message'
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
  static const _kAnalysisTimeout = Duration(seconds: 30);
  static const _kBatchTimeout = Duration(seconds: 45);
  static const _kInsightTimeout = Duration(seconds: 90);

  // ── Masking config ────────────────────────────────────────────────────────
  static const _kAiMaskingConfig = MaskingConfig.piiOnly;

  // ══════════════════════════════════════════════════════════════════════════
  // CORE METHODS
  // ══════════════════════════════════════════════════════════════════════════

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

  /// Gợi ý reply dạng chuỗi.
  Future<List<String>> suggestRepliesString({
    required List<String> recentMessages,
    String tone = 'friendly',
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
      _logError('suggestRepliesString', e, st);
      return [];
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
        plainTextContent.startsWith('eyJ')) return null;

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

  /// Gợi ý câu trả lời thông minh dựa trên context đoạn chat.
  Future<List<String>> smartReplyWithContext({
    required List<String> messages,
    Map<String, dynamic> userProfile = const {},
    String replyIntent = 'helpful',
    int maxLength = 150,
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
          'maxLength': maxLength,
          'language': language,
          'count': count,
        },
        timeout: _kAnalysisTimeout,
      );
      final replies = result?['replies'];
      if (replies is List) return replies.cast<String>();
      final single = result?['reply'] as String?;
      if (single != null && single.isNotEmpty) return [single];
      return [];
    } catch (e, st) {
      _logError('smartReplyWithContext', e, st);
      return [];
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
    final texts = await smartReplyWithContext(
      messages: messages,
      userProfile: userProfile,
      replyIntent: replyIntent,
      language: language,
      count: count,
    );
    return texts
        .where((t) => t.trim().isNotEmpty)
        .map((text) => SmartReply(
              text: text,
              confidence: 0.92,
              isAiGenerated: true,
              category: replyIntent,
            ))
        .toList();
  }

  Future<List<String>> generateIcebreakers({
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
      final list = result?['icebreakers'];
      if (list is List) return list.cast<String>();
      return [];
    } catch (e, st) {
      _logError('generateIcebreakers', e, st);
      return [];
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
    try {
      final safeMessages = messages
          .map((m) => {
                'id': m.id,
                'text': DataMaskingUtils.maskText(m.text,
                    config: _kAiMaskingConfig),
              })
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
          id: map['id']?.toString() ?? messages[entry.key].id,
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
  }) async {
    try {
      final cutoff = DateTime.now()
          .subtract(Duration(days: lookbackDays))
          .millisecondsSinceEpoch;

      final recentMessages = LocalDbService()
          .getMessages(conversationId)
          .where((m) {
            final ts = int.tryParse(m['timestamp']?.toString() ?? '0') ?? 0;
            return ts >= cutoff;
          })
          .take(messageLimit)
          .map((m) => m['content']?.toString() ?? '')
          .where((c) =>
              c.isNotEmpty && !c.startsWith('{"iv":') && !c.startsWith('eyJ'))
          .toList();

      if (recentMessages.length < 5) {
        _log('getUserInsights: not enough messages (${recentMessages.length})');
        return null;
      }

      final maskedMessages = DataMaskingUtils.maskList(
        recentMessages,
        config: _kAiMaskingConfig,
      );

      final result = await _call(
        functionName: 'getUserInsights',
        params: {
          'messages': maskedMessages,
          'lookbackDays': lookbackDays,
        },
        timeout: _kInsightTimeout,
      );
      if (result == null) return null;
      return UserInsightsResult.fromMap(Map<String, dynamic>.from(result));
    } catch (e, st) {
      _logError('getUserInsights', e, st);
      return null;
    }
  }

  /// Wrapper tiện lợi: lấy messages từ LocalDB rồi gọi extractRelationshipMemory.
  Future<RelationshipMemory?> extractRelationshipMemoryFromLocal({
    required String conversationId,
    int messageLimit = 100,
  }) async {
    try {
      final messages = LocalDbService()
          .getMessages(conversationId)
          .take(messageLimit)
          .map((m) => m['content']?.toString() ?? '')
          .where((c) =>
              c.isNotEmpty &&
              !c.startsWith('{"iv":') &&
              !c.startsWith('{') &&
              c.length > 3)
          .toList()
          .reversed
          .toList();

      if (messages.length < 10) {
        _log(
            'extractRelationshipMemoryFromLocal: not enough messages (${messages.length})');
        return null;
      }
      return extractRelationshipMemory(
          messages: messages, conversationId: conversationId);
    } catch (e, st) {
      _logError('extractRelationshipMemoryFromLocal', e, st);
      return null;
    }
  }

  /// Tạo câu trả lời auto-pilot thay mặt người dùng.
  Future<String?> generateAutoPilotReply({
    required String incomingMessage,
    String myStyleContext = 'thân thiện, ngắn gọn',
    String? awayMessage,
  }) async {
    if (incomingMessage.trim().isEmpty) return awayMessage;
    try {
      final safe =
          DataMaskingUtils.maskText(incomingMessage, config: _kAiMaskingConfig);
      final result = await _call(
        functionName: 'generateAutoPilotReply',
        params: {
          'incomingMessage': safe,
          'myStyleContext': myStyleContext,
          if (awayMessage != null) 'awayMessage': awayMessage,
        },
        timeout: _kDefaultTimeout,
      );
      return result?['reply'] as String?;
    } catch (e, st) {
      _logError('generateAutoPilotReply', e, st);
      return awayMessage;
    }
  }

  /// Tạo 4 câu trả lời swipe ngắn cho Zero-Type feature.
  Future<List<String>> generateSwipeReplies({
    required String incomingMessage,
    String contextMessages = '',
    String replyStyle = 'genz',
  }) async {
    const fallback = ['Ok nha', 'Thế à?', 'Chịu luôn 😂', 'Đỉnh!'];
    if (incomingMessage.trim().isEmpty) return fallback;
    try {
      final safe =
          DataMaskingUtils.maskText(incomingMessage, config: _kAiMaskingConfig);
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

  /// Phân tích bảo mật cuộc gọi — phát hiện deepfake, social engineering.
  Future<Map<String, dynamic>?> analyzeCallSecurity({
    required String callTranscript,
    String? peerId,
    String? conversationId,
  }) async {
    if (callTranscript.trim().isEmpty) return null;
    try {
      final safe =
          DataMaskingUtils.maskText(callTranscript, config: _kAiMaskingConfig);
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
  Future<ToxicityResult> analyzeSingleToxicity(String message,
      {String? id}) async {
    if (message.trim().isEmpty) return ToxicityResult.safe(id: id);
    final results =
        await analyzeToxicityBatch([ToxicityInput(id: id, text: message)]);
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
            .map((e) => ToxicityInput(
                id: messageIds.length > e.key ? messageIds[e.key] : null,
                text: e.value))
            .toList();
        final toxicityResults = await analyzeToxicityBatch(inputs);
        results['toxicity'] = toxicityResults;
      }
    } catch (e, st) {
      _logError('batchAnalyzeMessages', e, st);
    }
    return results;
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
