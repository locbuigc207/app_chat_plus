// lib/models/ai_models.dart
// Tất cả data models cho AI features — tự chứa, không import service nào
// Covers: ToneRewriterResult, IcebreakerResult, SentimentResult,
//         KeyMomentsResult, KeyMoment, UserInsightsResult,
//         WeeklyRecapResult, RelationshipMemory, ToxicityInput,
//         ToxicityResult, HateSpeechResult, ClientMessageAnalysis,
//         MessageReminder, SmartReply, ScamLevel, TypingInfo

import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Tone Rewriter
// ─────────────────────────────────────────────────────────────────────────────

/// Kết quả viết lại tin nhắn theo tông giọng khác.
class ToneRewriterResult {
  final String original;
  final String rewritten;
  final String toTone;
  final String fromTone;

  const ToneRewriterResult({
    required this.original,
    required this.rewritten,
    required this.toTone,
    this.fromTone = 'auto',
  });

  factory ToneRewriterResult.fromMap(Map<String, dynamic> map) =>
      ToneRewriterResult(
        original: map['original'] as String? ?? '',
        rewritten: map['rewritten'] as String? ?? '',
        toTone: map['toTone'] as String? ?? '',
        fromTone: map['fromTone'] as String? ?? 'auto',
      );

  Map<String, dynamic> toMap() => {
    'original': original,
    'rewritten': rewritten,
    'toTone': toTone,
    'fromTone': fromTone,
  };

  @override
  String toString() =>
      'ToneRewriterResult(toTone: $toTone, original: ${original.length} chars, rewritten: ${rewritten.length} chars)';
}

// ─────────────────────────────────────────────────────────────────────────────
// Sentiment Analysis
// ─────────────────────────────────────────────────────────────────────────────

class SentimentResult {
  final String sentiment; // positive | neutral | negative
  final double score; // 0.0 – 1.0
  final String emoji;
  final String mood;
  final String trend; // improving | stable | declining

  const SentimentResult({
    required this.sentiment,
    required this.score,
    required this.emoji,
    required this.mood,
    required this.trend,
  });

  factory SentimentResult.fromMap(Map<String, dynamic> map) => SentimentResult(
    sentiment: map['sentiment'] as String? ?? 'neutral',
    score: (map['score'] as num?)?.toDouble() ?? 0.5,
    emoji: map['emoji'] as String? ?? '😐',
    mood: map['mood'] as String? ?? 'Trung tính',
    trend: map['trend'] as String? ?? 'stable',
  );

  Map<String, dynamic> toMap() => {
    'sentiment': sentiment,
    'score': score,
    'emoji': emoji,
    'mood': mood,
    'trend': trend,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Key Moments
// ─────────────────────────────────────────────────────────────────────────────

/// Một khoảnh khắc đáng nhớ trong cuộc trò chuyện.
class KeyMoment {
  /// 'funny' | 'touching' | 'important' | 'decision'
  final String type;
  final String content;
  final String? timestamp;

  const KeyMoment({required this.type, required this.content, this.timestamp});

  factory KeyMoment.fromMap(Map<dynamic, dynamic> map) => KeyMoment(
    type: map['type'] as String? ?? 'important',
    content: map['content'] as String? ?? '',
    timestamp: map['timestamp'] as String?,
  );

  Map<String, dynamic> toMap() => {
    'type': type,
    'content': content,
    if (timestamp != null) 'timestamp': timestamp,
  };

  String get emoji {
    switch (type) {
      case 'funny':
        return '😂';
      case 'touching':
        return '❤️';
      case 'important':
        return '⭐';
      case 'decision':
        return '🎯';
      default:
        return '✨';
    }
  }

  @override
  String toString() =>
      'KeyMoment(type: $type, content: ${content.length} chars)';
}

/// Tổng hợp các khoảnh khắc nổi bật trong cuộc trò chuyện.
class KeyMomentsResult {
  final List<KeyMoment> moments;
  final List<String> highlights;
  final String? overallVibes;

  const KeyMomentsResult({
    required this.moments,
    required this.highlights,
    this.overallVibes,
  });

  factory KeyMomentsResult.empty() =>
      const KeyMomentsResult(moments: [], highlights: [], overallVibes: '');

  factory KeyMomentsResult.fromMap(Map<dynamic, dynamic> map) {
    final rawMoments = map['moments'] as List? ?? [];
    final rawHighlights = map['highlights'] as List? ?? [];
    return KeyMomentsResult(
      moments: rawMoments
          .map((m) => KeyMoment.fromMap(m as Map<dynamic, dynamic>))
          .toList(),
      highlights: rawHighlights.map((h) => h.toString()).toList(),
      overallVibes: map['overallVibes'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'moments': moments.map((m) => m.toMap()).toList(),
    'highlights': highlights,
    if (overallVibes != null) 'overallVibes': overallVibes,
  };

  bool get isEmpty => moments.isEmpty && highlights.isEmpty;

  @override
  String toString() =>
      'KeyMomentsResult(moments: ${moments.length}, highlights: ${highlights.length})';
}

// ─────────────────────────────────────────────────────────────────────────────
// User Insights
// ─────────────────────────────────────────────────────────────────────────────

/// Thống kê hành vi giao tiếp của người dùng.
class UserInsightsResult {
  /// 'formal' | 'casual' | 'mixed' | 'unknown'
  final String communicationStyle;
  final List<String> topTopics;
  final String activityPattern;
  final List<String> personalityTraits;
  final String insightSummary;

  /// 'high' | 'medium' | 'low'
  final String emojiUsageLevel;

  /// 'short' | 'medium' | 'long'
  final String avgMessageLength;

  const UserInsightsResult({
    required this.communicationStyle,
    required this.topTopics,
    required this.activityPattern,
    required this.personalityTraits,
    required this.insightSummary,
    required this.emojiUsageLevel,
    required this.avgMessageLength,
  });

  factory UserInsightsResult.empty() => const UserInsightsResult(
    communicationStyle: 'unknown',
    topTopics: [],
    activityPattern: '',
    personalityTraits: [],
    insightSummary: 'Chưa đủ dữ liệu để phân tích.',
    emojiUsageLevel: 'medium',
    avgMessageLength: 'medium',
  );

  factory UserInsightsResult.fromMap(Map<dynamic, dynamic> map) =>
      UserInsightsResult(
        communicationStyle: map['communicationStyle'] as String? ?? 'mixed',
        topTopics: (map['topTopics'] as List? ?? [])
            .map((e) => e.toString())
            .toList(),
        activityPattern: map['activityPattern'] as String? ?? '',
        personalityTraits: (map['personalityTraits'] as List? ?? [])
            .map((e) => e.toString())
            .toList(),
        insightSummary: map['insightSummary'] as String? ?? '',
        emojiUsageLevel: map['emojiUsageLevel'] as String? ?? 'medium',
        avgMessageLength: map['avgMessageLength'] as String? ?? 'medium',
      );

  Map<String, dynamic> toMap() => {
    'communicationStyle': communicationStyle,
    'topTopics': topTopics,
    'activityPattern': activityPattern,
    'personalityTraits': personalityTraits,
    'insightSummary': insightSummary,
    'emojiUsageLevel': emojiUsageLevel,
    'avgMessageLength': avgMessageLength,
  };

  bool get hasData => insightSummary.isNotEmpty && topTopics.isNotEmpty;

  /// Emoji hiển thị cho communication style.
  String get styleEmoji {
    switch (communicationStyle) {
      case 'formal':
        return '🎩';
      case 'casual':
        return '😎';
      case 'mixed':
        return '🔀';
      default:
        return '💬';
    }
  }

  @override
  String toString() =>
      'UserInsightsResult(style: $communicationStyle, topics: ${topTopics.length})';
}

// ─────────────────────────────────────────────────────────────────────────────
// Weekly Recap
// ─────────────────────────────────────────────────────────────────────────────

/// Kết quả tóm tắt tuần của nhóm chat.
class WeeklyRecapResult {
  final String summary;
  final List<String> highlights;

  /// 'positive' | 'neutral' | 'negative'
  final String sentiment;
  final DateTime generatedAt;
  final String weekStart;
  final Map<String, dynamic>? extras;

  const WeeklyRecapResult({
    required this.summary,
    required this.highlights,
    required this.sentiment,
    required this.generatedAt,
    this.weekStart = '',
    this.extras,
  });

  factory WeeklyRecapResult.fromMap(Map<String, dynamic> map) {
    DateTime parsedAt;
    final raw = map['generatedAt'];
    if (raw is Timestamp) {
      parsedAt = raw.toDate();
    } else if (raw is int) {
      parsedAt = DateTime.fromMillisecondsSinceEpoch(raw);
    } else if (raw is String) {
      parsedAt =
          DateTime.tryParse(raw) ??
          DateTime.fromMillisecondsSinceEpoch(
            int.tryParse(raw) ?? DateTime.now().millisecondsSinceEpoch,
          );
    } else {
      parsedAt = DateTime.now();
    }

    return WeeklyRecapResult(
      summary: map['summary'] as String? ?? '',
      highlights: (map['highlights'] as List? ?? [])
          .map((e) => e.toString())
          .toList(),
      sentiment: map['sentiment'] as String? ?? 'neutral',
      generatedAt: parsedAt,
      weekStart: map['weekStart'] as String? ?? '',
      extras: map['extras'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toMap() => {
    'summary': summary,
    'highlights': highlights,
    'sentiment': sentiment,
    'generatedAt': generatedAt.millisecondsSinceEpoch,
    'weekStart': weekStart,
    if (extras != null) 'extras': extras,
  };

  String get sentimentEmoji {
    switch (sentiment) {
      case 'positive':
        return '😊';
      case 'negative':
        return '😔';
      default:
        return '😐';
    }
  }

  @override
  String toString() =>
      'WeeklyRecapResult(sentiment: $sentiment, highlights: ${highlights.length})';
}

// ─────────────────────────────────────────────────────────────────────────────
// Relationship Memory
// ─────────────────────────────────────────────────────────────────────────────

class RelationshipMemory {
  final String?
  relationshipType; // friend | family | colleague | romantic | unknown
  final List<String> sharedTopics;
  final List<String> importantDates;
  final List<Map<String, dynamic>> memories;
  final String? communicationStyle; // formal | casual | mixed
  final int? closenessLevel; // 1-5
  final int? healthScore; // 0-100
  final String? summary;
  final List<String> redFlags;
  final List<String> positiveSignals;

  const RelationshipMemory({
    this.relationshipType,
    required this.sharedTopics,
    required this.importantDates,
    required this.memories,
    this.communicationStyle,
    this.closenessLevel,
    this.healthScore,
    this.summary,
    required this.redFlags,
    required this.positiveSignals,
  });

  factory RelationshipMemory.fromMap(Map<String, dynamic> map) =>
      RelationshipMemory(
        relationshipType: map['relationshipType'] as String?,
        sharedTopics: (map['sharedTopics'] as List? ?? [])
            .map((e) => e.toString())
            .toList(),
        importantDates: (map['importantDates'] as List? ?? [])
            .map((e) => e.toString())
            .toList(),
        memories: (map['memories'] as List? ?? [])
            .map((m) => Map<String, dynamic>.from(m as Map))
            .toList(),
        communicationStyle: map['communicationStyle'] as String?,
        closenessLevel: map['closenessLevel'] as int?,
        healthScore: map['healthScore'] as int?,
        summary: map['summary'] as String?,
        redFlags: (map['redFlags'] as List? ?? [])
            .map((e) => e.toString())
            .toList(),
        positiveSignals: (map['positiveSignals'] as List? ?? [])
            .map((e) => e.toString())
            .toList(),
      );

  Map<String, dynamic> toMap() => {
    if (relationshipType != null) 'relationshipType': relationshipType,
    'sharedTopics': sharedTopics,
    'importantDates': importantDates,
    'memories': memories,
    if (communicationStyle != null) 'communicationStyle': communicationStyle,
    if (closenessLevel != null) 'closenessLevel': closenessLevel,
    if (healthScore != null) 'healthScore': healthScore,
    if (summary != null) 'summary': summary,
    'redFlags': redFlags,
    'positiveSignals': positiveSignals,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Toxicity & Hate Speech
// ─────────────────────────────────────────────────────────────────────────────

/// Input cho batch toxicity analysis.
class ToxicityInput {
  final String? id;
  final String text;

  const ToxicityInput({this.id, required this.text});

  Map<String, dynamic> toMap() => {if (id != null) 'id': id, 'text': text};

  @override
  String toString() => 'ToxicityInput(id: $id, text: ${text.length} chars)';
}

/// Kết quả phân tích toxicity cho một tin nhắn.
class ToxicityResult {
  final String? id;
  final bool isToxic;

  /// 'safe' | 'toxic' | 'hate' | 'harassment' | 'offensive'
  final String category;
  final double confidence;
  final int index;

  const ToxicityResult({
    this.id,
    required this.isToxic,
    required this.category,
    required this.confidence,
    required this.index,
  });

  bool get isSafe => !isToxic && category == 'safe';

  factory ToxicityResult.safe({String? id, int index = 0}) => ToxicityResult(
    id: id,
    index: index,
    isToxic: false,
    category: 'safe',
    confidence: 1.0,
  );

  factory ToxicityResult.fromMap(Map<String, dynamic> map) => ToxicityResult(
    id: map['id'] as String?,
    isToxic: map['isToxic'] as bool? ?? false,
    category: map['category'] as String? ?? 'safe',
    confidence: (map['confidence'] as num?)?.toDouble() ?? 0.0,
    index: map['index'] as int? ?? 0,
  );

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'isToxic': isToxic,
    'category': category,
    'confidence': confidence,
    'index': index,
  };

  @override
  String toString() =>
      'ToxicityResult(index: $index, isToxic: $isToxic, category: $category, confidence: ${confidence.toStringAsFixed(2)})';
}

/// Kết quả phát hiện ngôn ngữ thù ghét chi tiết.
class HateSpeechResult {
  final bool isHateful;

  /// 'safe' | 'hate' | 'harassment' | 'discrimination' | 'offensive' | 'none'
  final String category;
  final double confidence;
  final String? reason;

  const HateSpeechResult({
    required this.isHateful,
    required this.category,
    required this.confidence,
    this.reason,
  });

  factory HateSpeechResult.safe() => const HateSpeechResult(
    isHateful: false,
    category: 'safe',
    confidence: 1.0,
  );

  factory HateSpeechResult.fromMap(Map<dynamic, dynamic> m) => HateSpeechResult(
    isHateful: m['isHateful'] as bool? ?? false,
    category: m['category'] as String? ?? 'safe',
    confidence: (m['confidence'] as num?)?.toDouble() ?? 0,
    reason: m['reason'] as String?,
  );

  @override
  String toString() =>
      'HateSpeechResult(isHateful: $isHateful, category: $category, confidence: ${confidence.toStringAsFixed(2)})';
}

// ─────────────────────────────────────────────────────────────────────────────
// Message Analysis & Reminders
// ─────────────────────────────────────────────────────────────────────────────

/// Kết quả phân tích tin nhắn từ client (scam + reminder + sentiment + intent).
class ClientMessageAnalysis {
  final bool isScam;
  final String? scamReason;
  final bool hasReminder;
  final String? reminderTask;
  final String? reminderTime;

  /// 'LOW' | 'MEDIUM' | 'HIGH'
  final String riskLevel;

  /// 'positive' | 'neutral' | 'negative'
  final String sentiment;

  /// 'question' | 'request' | 'statement' | 'greeting' | 'farewell' | 'unknown'
  final String intentCategory;

  const ClientMessageAnalysis({
    required this.isScam,
    this.scamReason,
    required this.hasReminder,
    this.reminderTask,
    this.reminderTime,
    required this.riskLevel,
    required this.sentiment,
    required this.intentCategory,
  });

  factory ClientMessageAnalysis.safe() => const ClientMessageAnalysis(
    isScam: false,
    hasReminder: false,
    riskLevel: 'LOW',
    sentiment: 'neutral',
    intentCategory: 'unknown',
  );

  factory ClientMessageAnalysis.fromMap(Map<dynamic, dynamic> m) =>
      ClientMessageAnalysis(
        isScam: m['isScam'] as bool? ?? false,
        scamReason: m['scamReason'] as String?,
        hasReminder: m['hasReminder'] as bool? ?? false,
        reminderTask: m['reminderTask'] as String?,
        reminderTime: m['reminderTime'] as String?,
        riskLevel: m['riskLevel'] as String? ?? 'LOW',
        sentiment: m['sentiment'] as String? ?? 'neutral',
        intentCategory: m['intentCategory'] as String? ?? 'unknown',
      );

  bool get isHighRisk => riskLevel == 'HIGH';
  bool get isMediumRisk => riskLevel == 'MEDIUM';

  @override
  String toString() =>
      'ClientMessageAnalysis(isScam: $isScam, hasReminder: $hasReminder, risk: $riskLevel)';
}

class MessageReminder {
  final String id;
  final String userId;
  final String? conversationId;
  final String? messageId;
  final String message;
  final DateTime reminderTime;
  final bool isCompleted;
  final bool isAutoGenerated;

  const MessageReminder({
    required this.id,
    required this.userId,
    this.conversationId,
    this.messageId,
    required this.message,
    required this.reminderTime,
    this.isCompleted = false,
    this.isAutoGenerated = false,
  });

  factory MessageReminder.fromMap(String id, Map<String, dynamic> map) {
    DateTime parsedTime;
    final raw = map['reminderTime'] ?? map['timeHint'];
    if (raw is Timestamp) {
      parsedTime = raw.toDate();
    } else if (raw is int) {
      parsedTime = DateTime.fromMillisecondsSinceEpoch(raw);
    } else if (raw is String) {
      parsedTime =
          DateTime.tryParse(raw) ??
          DateTime.fromMillisecondsSinceEpoch(
            int.tryParse(raw) ?? DateTime.now().millisecondsSinceEpoch,
          );
    } else {
      parsedTime = DateTime.now().add(const Duration(hours: 1));
    }

    return MessageReminder(
      id: id,
      userId: map['userId'] as String? ?? '',
      conversationId: map['conversationId'] as String?,
      messageId: map['messageId'] as String?,
      message: map['task'] as String? ?? map['message'] as String? ?? '',
      reminderTime: parsedTime,
      isCompleted: map['isCompleted'] as bool? ?? false,
      isAutoGenerated: map['isAutoGenerated'] as bool? ?? false,
    );
  }

  // ĐÃ SỬA LỖI 2.1: Ép kiểu reminderTime về định dạng String (MillisecondsSinceEpoch)
  // để khớp hoàn toàn với Backend Node.js và Firestore string queries.
  Map<String, dynamic> toMap() => {
    'userId': userId,
    if (conversationId != null) 'conversationId': conversationId,
    if (messageId != null) 'messageId': messageId,
    'task': message,
    'reminderTime': reminderTime.millisecondsSinceEpoch
        .toString(), // <-- Sửa tại đây
    'isCompleted': isCompleted,
    'isAutoGenerated': isAutoGenerated,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Smart Reply & Icebreaker
// ─────────────────────────────────────────────────────────────────────────────

/// Smart reply được tạo từ AI hoặc rule-based.
class SmartReply {
  final String text;
  final double? confidence;
  final bool isAiGenerated;

  /// 'greeting' | 'farewell' | 'acknowledgement' | 'question' | 'general' | ...
  final String? category;

  const SmartReply({
    required this.text,
    this.confidence,
    this.isAiGenerated = false,
    this.category = 'general',
  });

  @override
  String toString() =>
      'SmartReply(text: ${text.length} chars, ai: $isAiGenerated)';
}

/// Icebreaker được tạo bởi AI.
class IcebreakerResult {
  final List<String> icebreakers;
  final String style;
  final String relationshipType;

  const IcebreakerResult({
    required this.icebreakers,
    required this.style,
    required this.relationshipType,
  });

  factory IcebreakerResult.empty() => const IcebreakerResult(
    icebreakers: [],
    style: 'casual',
    relationshipType: 'friend',
  );

  factory IcebreakerResult.fromMap(Map<dynamic, dynamic> m) => IcebreakerResult(
    icebreakers: (m['icebreakers'] as List? ?? []).cast<String>(),
    style: m['style'] as String? ?? 'casual',
    relationshipType: m['relationshipType'] as String? ?? 'friend',
  );

  bool get isEmpty => icebreakers.isEmpty;

  @override
  String toString() =>
      'IcebreakerResult(count: ${icebreakers.length}, style: $style)';
}

// ─────────────────────────────────────────────────────────────────────────────
// Scam Level Enum
// ─────────────────────────────────────────────────────────────────────────────

enum ScamLevel { safe, warning, scam }

extension ScamLevelX on ScamLevel {
  String get name => switch (this) {
    ScamLevel.safe => 'SAFE',
    ScamLevel.warning => 'WARNING',
    ScamLevel.scam => 'SCAM',
  };

  static ScamLevel fromString(String? value) => switch (value?.toUpperCase()) {
    'WARNING' => ScamLevel.warning,
    'SCAM' => ScamLevel.scam,
    _ => ScamLevel.safe,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Typing Info
// ─────────────────────────────────────────────────────────────────────────────

class TypingInfo {
  final bool isTyping;
  final DateTime? lastUpdated;

  const TypingInfo({required this.isTyping, this.lastUpdated});

  factory TypingInfo.fromMap(Map<String, dynamic> map) => TypingInfo(
    isTyping: map['isTyping'] as bool? ?? false,
    lastUpdated: map['timestamp'] != null
        ? (map['timestamp'] as Timestamp).toDate()
        : null,
  );
}
