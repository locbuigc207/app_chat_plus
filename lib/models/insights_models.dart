// lib/models/insights_models.dart
// TÍNH NĂNG 2: USER INSIGHTS — Data models hoàn chỉnh
// Models: InsightsPeriod, SentimentLabel, MoodPoint, ActivitySlot,
//         TopicTag, SentimentBreakdown, InsightsSnapshot, InsightsDashboard

import 'package:cloud_firestore/cloud_firestore.dart';

// ─── Enums ────────────────────────────────────────────────────────────────────

enum InsightsPeriod { week7, days30, days90 }

extension InsightsPeriodX on InsightsPeriod {
  String get label => const {
        InsightsPeriod.week7: '7 ngày',
        InsightsPeriod.days30: '30 ngày',
        InsightsPeriod.days90: '90 ngày',
      }[this]!;

  int get days => const {
        InsightsPeriod.week7: 7,
        InsightsPeriod.days30: 30,
        InsightsPeriod.days90: 90,
      }[this]!;

  String get key => toString().split('.').last;

  static InsightsPeriod fromString(String s) => InsightsPeriod.values
      .firstWhere((e) => e.key == s, orElse: () => InsightsPeriod.week7);
}

enum SentimentLabel { positive, neutral, negative }

extension SentimentLabelX on SentimentLabel {
  String get label => const {
        SentimentLabel.positive: 'Tích cực',
        SentimentLabel.neutral: 'Trung lập',
        SentimentLabel.negative: 'Tiêu cực',
      }[this]!;

  String get key => toString().split('.').last;

  static SentimentLabel fromString(String s) => SentimentLabel.values
      .firstWhere((e) => e.key == s, orElse: () => SentimentLabel.neutral);
}

// ─── MoodPoint — 1 điểm trên biểu đồ tâm trạng theo ngày ─────────────────────

class MoodPoint {
  final DateTime date;
  final double score; // 0.0 – 1.0 (0=rất tiêu cực, 1=rất tích cực)
  final String emoji; // emoji đại diện tâm trạng ngày đó
  final int messageCount;

  const MoodPoint({
    required this.date,
    required this.score,
    this.emoji = '😐',
    this.messageCount = 0,
  });

  Map<String, dynamic> toMap() => {
        'date': date.millisecondsSinceEpoch,
        'score': score,
        'emoji': emoji,
        'messageCount': messageCount,
      };

  factory MoodPoint.fromMap(Map<String, dynamic> m) => MoodPoint(
        date: DateTime.fromMillisecondsSinceEpoch(m['date'] as int? ?? 0),
        score: (m['score'] as num?)?.toDouble() ?? 0.5,
        emoji: m['emoji'] as String? ?? '😐',
        messageCount: m['messageCount'] as int? ?? 0,
      );
}

// ─── ActivitySlot — 1 ô trong heatmap 7×24 ───────────────────────────────────

class ActivitySlot {
  final int dayOfWeek; // 0=Mon … 6=Sun
  final int hour; // 0–23
  final int count; // số tin nhắn
  final double intensity; // 0.0–1.0 (đã normalize)

  const ActivitySlot({
    required this.dayOfWeek,
    required this.hour,
    required this.count,
    this.intensity = 0.0,
  });

  Map<String, dynamic> toMap() => {
        'dow': dayOfWeek,
        'hour': hour,
        'count': count,
        'intensity': intensity,
      };

  factory ActivitySlot.fromMap(Map<String, dynamic> m) => ActivitySlot(
        dayOfWeek: m['dow'] as int? ?? 0,
        hour: m['hour'] as int? ?? 0,
        count: m['count'] as int? ?? 0,
        intensity: (m['intensity'] as num?)?.toDouble() ?? 0.0,
      );
}

// ─── TopicTag — chủ đề nổi bật ───────────────────────────────────────────────

class TopicTag {
  final String topic;
  final int count;
  final double percentage; // 0.0–1.0
  final String emoji;

  const TopicTag({
    required this.topic,
    required this.count,
    this.percentage = 0.0,
    this.emoji = '💬',
  });

  Map<String, dynamic> toMap() => {
        'topic': topic,
        'count': count,
        'percentage': percentage,
        'emoji': emoji,
      };

  factory TopicTag.fromMap(Map<String, dynamic> m) => TopicTag(
        topic: m['topic'] as String? ?? '',
        count: m['count'] as int? ?? 0,
        percentage: (m['percentage'] as num?)?.toDouble() ?? 0.0,
        emoji: m['emoji'] as String? ?? '💬',
      );
}

// ─── SentimentBreakdown — phân bổ % tích cực/trung lập/tiêu cực ──────────────

class SentimentBreakdown {
  final double positive; // 0.0–1.0
  final double neutral;
  final double negative;
  final String trend; // 'improving' | 'stable' | 'declining'

  const SentimentBreakdown({
    this.positive = 0.5,
    this.neutral = 0.3,
    this.negative = 0.2,
    this.trend = 'stable',
  });

  Map<String, dynamic> toMap() => {
        'positive': positive,
        'neutral': neutral,
        'negative': negative,
        'trend': trend,
      };

  factory SentimentBreakdown.fromMap(Map<String, dynamic> m) =>
      SentimentBreakdown(
        positive: (m['positive'] as num?)?.toDouble() ?? 0.5,
        neutral: (m['neutral'] as num?)?.toDouble() ?? 0.3,
        negative: (m['negative'] as num?)?.toDouble() ?? 0.2,
        trend: m['trend'] as String? ?? 'stable',
      );
}

// ─── InsightsSnapshot — dữ liệu 1 period (7/30/90 ngày) ─────────────────────

class InsightsSnapshot {
  final InsightsPeriod period;

  // Thống kê cơ bản
  final int totalMessages;
  final int activeDays;
  final double avgMessagesPerDay;
  final int avgMessageLength;

  // Phân tích phong cách
  final String communicationStyle; // 'expressive' | 'concise' | 'balanced'
  final String emojiUsageLevel; // 'heavy' | 'moderate' | 'minimal'
  final List<String> personalityTraits; // ['empathetic', 'humorous', ...]
  final String activityPattern; // 'morning_person' | 'night_owl' | 'balanced'

  // AI Summary
  final String insightSummary; // đoạn văn mô tả
  final String? aiGeneratedSummary; // nếu gọi AI

  // Charts data
  final List<MoodPoint> moodTrend; // theo ngày
  final List<ActivitySlot> activityHeatmap; // 7×24
  final List<TopicTag> topTopics; // top 8 chủ đề
  final SentimentBreakdown sentimentBreakdown;

  final DateTime generatedAt;

  const InsightsSnapshot({
    required this.period,
    this.totalMessages = 0,
    this.activeDays = 0,
    this.avgMessagesPerDay = 0.0,
    this.avgMessageLength = 0,
    this.communicationStyle = 'balanced',
    this.emojiUsageLevel = 'moderate',
    this.personalityTraits = const [],
    this.activityPattern = 'balanced',
    this.insightSummary = '',
    this.aiGeneratedSummary,
    this.moodTrend = const [],
    this.activityHeatmap = const [],
    this.topTopics = const [],
    this.sentimentBreakdown = const SentimentBreakdown(),
    required this.generatedAt,
  });

  Map<String, dynamic> toMap() => {
        'period': period.key,
        'totalMessages': totalMessages,
        'activeDays': activeDays,
        'avgMessagesPerDay': avgMessagesPerDay,
        'avgMessageLength': avgMessageLength,
        'communicationStyle': communicationStyle,
        'emojiUsageLevel': emojiUsageLevel,
        'personalityTraits': personalityTraits,
        'activityPattern': activityPattern,
        'insightSummary': insightSummary,
        if (aiGeneratedSummary != null)
          'aiGeneratedSummary': aiGeneratedSummary,
        'moodTrend': moodTrend.map((e) => e.toMap()).toList(),
        'activityHeatmap': activityHeatmap.map((e) => e.toMap()).toList(),
        'topTopics': topTopics.map((e) => e.toMap()).toList(),
        'sentimentBreakdown': sentimentBreakdown.toMap(),
        'generatedAt': generatedAt.millisecondsSinceEpoch,
      };

  factory InsightsSnapshot.fromMap(Map<String, dynamic> m) {
    final moodRaw = m['moodTrend'] as List<dynamic>? ?? [];
    final heatRaw = m['activityHeatmap'] as List<dynamic>? ?? [];
    final topicsRaw = m['topTopics'] as List<dynamic>? ?? [];
    final sentRaw = m['sentimentBreakdown'] as Map<String, dynamic>?;
    final traitsRaw = m['personalityTraits'] as List<dynamic>? ?? [];

    return InsightsSnapshot(
      period: InsightsPeriodX.fromString(m['period'] as String? ?? 'week7'),
      totalMessages: m['totalMessages'] as int? ?? 0,
      activeDays: m['activeDays'] as int? ?? 0,
      avgMessagesPerDay: (m['avgMessagesPerDay'] as num?)?.toDouble() ?? 0.0,
      avgMessageLength: m['avgMessageLength'] as int? ?? 0,
      communicationStyle: m['communicationStyle'] as String? ?? 'balanced',
      emojiUsageLevel: m['emojiUsageLevel'] as String? ?? 'moderate',
      personalityTraits: traitsRaw.map((e) => e.toString()).toList(),
      activityPattern: m['activityPattern'] as String? ?? 'balanced',
      insightSummary: m['insightSummary'] as String? ?? '',
      aiGeneratedSummary: m['aiGeneratedSummary'] as String?,
      moodTrend: moodRaw
          .map((e) => MoodPoint.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      activityHeatmap: heatRaw
          .map((e) => ActivitySlot.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      topTopics: topicsRaw
          .map((e) => TopicTag.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      sentimentBreakdown: sentRaw != null
          ? SentimentBreakdown.fromMap(sentRaw)
          : const SentimentBreakdown(),
      generatedAt: m['generatedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(m['generatedAt'] as int)
          : DateTime.now(),
    );
  }

  bool get isStale {
    final age = DateTime.now().difference(generatedAt);
    return switch (period) {
      InsightsPeriod.week7 => age.inHours > 6,
      InsightsPeriod.days30 => age.inHours > 12,
      InsightsPeriod.days90 => age.inHours > 24,
    };
  }
}

// ─── InsightsDashboard — container cho cả 3 periods ──────────────────────────

class InsightsDashboard {
  final String conversationId;
  final String userId;
  final InsightsSnapshot week7;
  final InsightsSnapshot days30;
  final InsightsSnapshot days90;
  final DateTime lastUpdated;

  const InsightsDashboard({
    required this.conversationId,
    required this.userId,
    required this.week7,
    required this.days30,
    required this.days90,
    required this.lastUpdated,
  });

  InsightsSnapshot snapshotForPeriod(InsightsPeriod p) => switch (p) {
        InsightsPeriod.week7 => week7,
        InsightsPeriod.days30 => days30,
        InsightsPeriod.days90 => days90,
      };

  Map<String, dynamic> toMap() => {
        'conversationId': conversationId,
        'userId': userId,
        'week7': week7.toMap(),
        'days30': days30.toMap(),
        'days90': days90.toMap(),
        'lastUpdated': lastUpdated.millisecondsSinceEpoch,
      };

  factory InsightsDashboard.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String conversationId,
    String userId,
  ) {
    final data = doc.data() ?? {};
    return InsightsDashboard(
      conversationId: conversationId,
      userId: userId,
      week7: data['week7'] != null
          ? InsightsSnapshot.fromMap(
              Map<String, dynamic>.from(data['week7'] as Map))
          : InsightsSnapshot(
              period: InsightsPeriod.week7, generatedAt: DateTime.now()),
      days30: data['days30'] != null
          ? InsightsSnapshot.fromMap(
              Map<String, dynamic>.from(data['days30'] as Map))
          : InsightsSnapshot(
              period: InsightsPeriod.days30, generatedAt: DateTime.now()),
      days90: data['days90'] != null
          ? InsightsSnapshot.fromMap(
              Map<String, dynamic>.from(data['days90'] as Map))
          : InsightsSnapshot(
              period: InsightsPeriod.days90, generatedAt: DateTime.now()),
      lastUpdated: data['lastUpdated'] != null
          ? DateTime.fromMillisecondsSinceEpoch(data['lastUpdated'] as int)
          : DateTime.now(),
    );
  }

  factory InsightsDashboard.empty(String conversationId, String userId) =>
      InsightsDashboard(
        conversationId: conversationId,
        userId: userId,
        week7: InsightsSnapshot(
            period: InsightsPeriod.week7, generatedAt: DateTime.now()),
        days30: InsightsSnapshot(
            period: InsightsPeriod.days30, generatedAt: DateTime.now()),
        days90: InsightsSnapshot(
            period: InsightsPeriod.days90, generatedAt: DateTime.now()),
        lastUpdated: DateTime.now(),
      );
}
