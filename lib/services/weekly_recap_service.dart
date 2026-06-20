// lib/services/weekly_recap_service.dart
// Service + Models cho tính năng Weekly AI Recap
// Hỗ trợ: chat cá nhân, nhóm; nhiều phong cách AI; cache thông minh

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../utils/error_logger.dart';

// ══════════════════════════════════════════════════════════════════════════════
// ENUMS
// ══════════════════════════════════════════════════════════════════════════════

/// Phong cách tổng kết tuần do AI tạo ra.
enum RecapStyle {
  humorous('humorous', '😂 Bóc Phốt', 'Hài hước, tiếng lóng Gen Z'),
  professional('professional', '📊 Báo Cáo', 'Chuyên nghiệp, súc tích'),
  romantic('romantic', '💕 Kỷ Niệm', 'Lãng mạn, tình cảm'),
  tvHost('tv_host', '🎬 Bản Tin', 'MC truyền hình năng động'),
  minimal('minimal', '📝 Tóm Tắt', 'Ngắn gọn, đi thẳng vào vấn đề');

  final String key;
  final String label;
  final String description;

  const RecapStyle(this.key, this.label, this.description);

  static RecapStyle fromKey(String? key) => RecapStyle.values.firstWhere(
    (s) => s.key == key,
    orElse: () => RecapStyle.humorous,
  );

  /// Màu gradient [start, end] cho card chia sẻ.
  List<int> get gradientArgb => switch (this) {
    RecapStyle.humorous => [0xFFFF5722, 0xFFFF9800],
    RecapStyle.professional => [0xFF0D47A1, 0xFF1E88E5],
    RecapStyle.romantic => [0xFFAD1457, 0xFF7B1FA2],
    RecapStyle.tvHost => [0xFF4E342E, 0xFFE65100],
    RecapStyle.minimal => [0xFF263238, 0xFF1565C0],
  };

  /// Icon trang trí chính của style này.
  String get decorIcon => switch (this) {
    RecapStyle.humorous => '🎭',
    RecapStyle.professional => '📈',
    RecapStyle.romantic => '✨',
    RecapStyle.tvHost => '📺',
    RecapStyle.minimal => '🗂️',
  };
}

/// Loại hội thoại được tổng kết.
enum RecapConversationType {
  personal, // Chat cá nhân 1-1
  group, // Chat nhóm
}

/// Khoảng thời gian nhìn lại để tổng kết.
enum RecapLookback {
  oneWeek(7, 'Tuần này'),
  twoWeeks(14, '2 tuần qua'),
  oneMonth(30, 'Tháng này');

  final int days;
  final String label;
  const RecapLookback(this.days, this.label);
}

// ══════════════════════════════════════════════════════════════════════════════
// DATA MODEL
// ══════════════════════════════════════════════════════════════════════════════

/// Dữ liệu tổng kết tuần đầy đủ được trả về từ Cloud Function.
class WeeklyRecapData {
  final bool success;
  final RecapStyle style;
  final String styleLabel;
  final String styleEmoji;

  /// Toàn bộ nội dung recap do AI sinh ra (văn bản đầy đủ).
  final String fullText;

  /// 1 câu tóm lược ngắn (dùng cho preview card).
  final String summary;

  /// Danh sách 2–4 điểm nổi bật.
  final List<String> highlights;

  /// Cảm xúc chủ đạo: positive | neutral | negative
  final String sentiment;

  /// Từ khoá nổi bật của tuần.
  final List<String> topKeywords;

  final int messageCount;
  final DateTime generatedAt;
  final RecapConversationType conversationType;
  final int lookbackDays;
  final String? failReason;

  const WeeklyRecapData({
    required this.success,
    required this.style,
    required this.styleLabel,
    required this.styleEmoji,
    required this.fullText,
    required this.summary,
    required this.highlights,
    required this.sentiment,
    required this.topKeywords,
    required this.messageCount,
    required this.generatedAt,
    required this.conversationType,
    this.lookbackDays = 7,
    this.failReason,
  });

  factory WeeklyRecapData.failure(
    String reason, {
    RecapStyle style = RecapStyle.humorous,
  }) => WeeklyRecapData(
    success: false,
    style: style,
    styleLabel: style.label,
    styleEmoji: '',
    fullText: '',
    summary: '',
    highlights: const [],
    sentiment: 'neutral',
    topKeywords: const [],
    messageCount: 0,
    generatedAt: DateTime.now(),
    conversationType: RecapConversationType.group,
    failReason: reason,
  );

  factory WeeklyRecapData.fromMap(Map<dynamic, dynamic> map, RecapStyle style) {
    final ts = map['generatedAt'];
    DateTime dt;
    if (ts is int) {
      dt = DateTime.fromMillisecondsSinceEpoch(ts);
    } else if (ts is Timestamp) {
      dt = ts.toDate();
    } else if (ts is String) {
      dt = DateTime.tryParse(ts) ?? DateTime.now();
    } else {
      dt = DateTime.now();
    }

    // Lấy structuredData nếu Cloud Function trả về theo cấu trúc lồng
    final structuredData = map['structuredData'] as Map<dynamic, dynamic>?;

    return WeeklyRecapData(
      success: map['success'] as bool? ?? false,
      style: style,
      styleLabel: map['styleLabel'] as String? ?? style.label,
      styleEmoji: map['styleEmoji'] as String? ?? '',

      // Fallback linh hoạt giữa "recap" (từ Callable CF) và "fullText" (từ Cache DB phẳng)
      fullText: (map['recap'] as String?) ?? (map['fullText'] as String?) ?? '',

      // Đọc từ structuredData nếu có, nếu không thì fallback về key phẳng
      summary:
          (structuredData?['summary'] as String?) ??
          (map['summary'] as String?) ??
          '',
      highlights: List<String>.from(
        (structuredData?['highlights'] as List?) ??
            (map['highlights'] as List?) ??
            [],
      ),
      sentiment:
          (structuredData?['sentiment'] as String?) ??
          (map['sentiment'] as String?) ??
          'neutral',
      topKeywords: List<String>.from(
        (structuredData?['topKeywords'] as List?) ??
            (map['topKeywords'] as List?) ??
            [],
      ),

      messageCount: map['messageCount'] as int? ?? 0,
      generatedAt: dt,
      conversationType: map['conversationType'] == 'personal'
          ? RecapConversationType.personal
          : RecapConversationType.group,
      lookbackDays: map['lookbackDays'] as int? ?? 7,
      failReason: map['reason'] as String?,
    );
  }

  // ── Computed properties ────────────────────────────────────────────────────

  String get sentimentEmoji => switch (sentiment) {
    'positive' => '😊',
    'negative' => '😔',
    _ => '😐',
  };

  String get sentimentLabel => switch (sentiment) {
    'positive' => 'Tích cực',
    'negative' => 'Tiêu cực',
    _ => 'Trung tính',
  };

  bool get hasHighlights => highlights.isNotEmpty;
  bool get hasKeywords => topKeywords.isNotEmpty;
  bool get isPersonal => conversationType == RecapConversationType.personal;

  /// Tiêu đề ngắn phù hợp theo loại hội thoại & style.
  String get recapTitle => switch (style) {
    RecapStyle.humorous =>
      isPersonal ? '🎭 Bóc Phốt Đôi Bạn' : '🎭 Bóc Phốt Nhóm',
    RecapStyle.professional =>
      isPersonal ? '📊 Báo Cáo Cá Nhân' : '📊 Báo Cáo Nhóm',
    RecapStyle.romantic =>
      isPersonal ? '💕 Kỷ Niệm Tuần' : '💕 Hành Trình Nhóm',
    RecapStyle.tvHost => isPersonal ? '📺 Bản Tin Đôi' : '📺 Bản Tin Nhóm',
    RecapStyle.minimal => '📝 Tóm Tắt Tuần',
  };

  WeeklyRecapData copyWith({RecapStyle? style, String? fullText}) =>
      WeeklyRecapData(
        success: success,
        style: style ?? this.style,
        styleLabel: style?.label ?? styleLabel,
        styleEmoji: style?.key ?? styleEmoji,
        fullText: fullText ?? this.fullText,
        summary: summary,
        highlights: highlights,
        sentiment: sentiment,
        topKeywords: topKeywords,
        messageCount: messageCount,
        generatedAt: generatedAt,
        conversationType: conversationType,
        lookbackDays: lookbackDays,
        failReason: failReason,
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// SERVICE
// ══════════════════════════════════════════════════════════════════════════════

class WeeklyRecapService {
  // ── Singleton ──────────────────────────────────────────────────────────────
  WeeklyRecapService._();
  static final WeeklyRecapService _instance = WeeklyRecapService._();
  factory WeeklyRecapService() => _instance;

  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'asia-southeast1',
  );

  // Cache: "${conversationId}_${style.key}_${lookbackDays}"
  final Map<String, WeeklyRecapData> _cache = {};

  static const Duration _cacheMaxAge = Duration(hours: 1);
  static const Duration _timeout = Duration(seconds: 90);

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Đọc dữ liệu Weekly Recap do hệ thống CronJob tự động tạo ra và lưu
  /// sẵn trên Firestore để giảm thiểu số lượt gọi Cloud Function sinh phí.
  Future<WeeklyRecapData?> getStoredRecap(String conversationId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('conversations')
          .doc(conversationId)
          .get();

      final recapData = doc.data()?['weeklyRecap'] as Map<String, dynamic>?;
      if (recapData == null) return null;

      final generatedAt = recapData['generatedAt'];
      DateTime? genTime;
      if (generatedAt is Timestamp) {
        genTime = generatedAt.toDate();
      } else if (generatedAt is int) {
        genTime = DateTime.fromMillisecondsSinceEpoch(generatedAt);
      } else if (generatedAt is String) {
        genTime = DateTime.tryParse(generatedAt);
      }

      // Vứt bỏ Recap lưu trong DB nếu đã vượt quá 7 ngày do dữ liệu đã cũ
      if (genTime != null && DateTime.now().difference(genTime).inDays > 7) {
        return null;
      }

      return WeeklyRecapData(
        success: true,
        style: RecapStyle
            .humorous, // Scheduled Cloud Function dùng humorous mặc định
        styleLabel: RecapStyle.humorous.label,
        styleEmoji: RecapStyle.humorous.decorIcon,
        fullText: recapData['fullText'] as String? ?? '',
        summary: recapData['summary'] as String? ?? '',
        highlights: List<String>.from(recapData['highlights'] as List? ?? []),
        sentiment: recapData['sentiment'] as String? ?? 'neutral',
        topKeywords: List<String>.from(recapData['topKeywords'] as List? ?? []),
        messageCount: recapData['messageCount'] as int? ?? 0,
        generatedAt: genTime ?? DateTime.now(),
        conversationType: RecapConversationType.group,
        lookbackDays: 7,
      );
    } catch (e) {
      debugPrint('[WeeklyRecap] Lỗi đọc Cached Firestore: $e');
      return null;
    }
  }

  /// Tạo tổng kết tuần với style và khoảng thời gian chỉ định.
  ///
  /// Dữ liệu được đọc từ `ai_content` collection (plain text đã mask PII),
  /// hoàn toàn an toàn với E2EE — không đọc Firestore messages trực tiếp.
  Future<WeeklyRecapData> generateRecap({
    required String conversationId,
    RecapStyle style = RecapStyle.humorous,
    RecapConversationType conversationType = RecapConversationType.group,
    int lookbackDays = 7,
    bool forceRefresh = false,
  }) async {
    final cacheKey = '${conversationId}_${style.key}_$lookbackDays';

    if (!forceRefresh) {
      // 1. Kiểm tra RAM Cache (In-Memory) trước tiên
      if (_cache.containsKey(cacheKey)) {
        final cached = _cache[cacheKey]!;
        if (DateTime.now().difference(cached.generatedAt) < _cacheMaxAge) {
          debugPrint('[WeeklyRecap] ✅ Trả về từ In-Memory Cache: $cacheKey');
          return cached;
        }
      }

      // 2. Đọc từ Persistent Cache Firestore (Áp dụng cho cấu hình mặc định)
      // Scheduled jobs tự động chạy cấu hình humorous với 7 ngày
      if (style == RecapStyle.humorous && lookbackDays == 7) {
        final stored = await getStoredRecap(conversationId);
        if (stored != null) {
          _cache[cacheKey] =
              stored; // Đưa vào RAM cache để lần sau lấy nhanh hơn
          debugPrint(
            '[WeeklyRecap] ✅ Trả về từ Persistent Firestore Cache cho $conversationId',
          );
          return stored;
        }
      }
    }

    try {
      final callable = _functions.httpsCallable(
        'generateWeeklyRecap',
        options: HttpsCallableOptions(timeout: _timeout),
      );

      debugPrint(
        '[WeeklyRecap] 🚀 Calling generateWeeklyRecap: $conversationId, style=${style.key}',
      );

      // Data request sẽ được bắt lấy thông qua req.data ở Cloud Function "generateWeeklyRecap" đã khai báo
      final result = await callable.call({
        'conversationId': conversationId,
        'recapStyle': style.key,
        'conversationType': conversationType.name,
        'lookbackDays': lookbackDays,
      });

      final data = result.data as Map<dynamic, dynamic>?;
      if (data == null) {
        return WeeklyRecapData.failure(
          'Server không trả về dữ liệu.',
          style: style,
        );
      }

      final recap = WeeklyRecapData.fromMap(data, style);

      if (recap.success) {
        _cache[cacheKey] = recap;
        debugPrint(
          '[WeeklyRecap] ✅ Generated ${recap.messageCount} messages, sentiment=${recap.sentiment}',
        );
      }

      return recap;
    } on FirebaseFunctionsException catch (e) {
      ErrorLogger.logError(
        e,
        null,
        context: 'WeeklyRecapService.generateRecap',
      );
      return WeeklyRecapData.failure(_mapFunctionsError(e), style: style);
    } catch (e, st) {
      ErrorLogger.logError(e, st, context: 'WeeklyRecapService.generateRecap');
      return WeeklyRecapData.failure(
        'Đã xảy ra lỗi. Vui lòng thử lại sau.',
        style: style,
      );
    }
  }

  /// Kiểm tra xem có cache hợp lệ không.
  bool isCached(String conversationId, RecapStyle style, int lookbackDays) {
    final key = '${conversationId}_${style.key}_$lookbackDays';
    final cached = _cache[key];
    if (cached == null) return false;
    return DateTime.now().difference(cached.generatedAt) < _cacheMaxAge;
  }

  /// Lấy cache nếu có, null nếu không.
  WeeklyRecapData? getCached(
    String conversationId,
    RecapStyle style,
    int lookbackDays,
  ) {
    final key = '${conversationId}_${style.key}_$lookbackDays';
    final cached = _cache[key];
    if (cached == null) return null;
    if (DateTime.now().difference(cached.generatedAt) >= _cacheMaxAge) {
      _cache.remove(key);
      return null;
    }
    return cached;
  }

  /// Xoá cache theo conversationId hoặc toàn bộ cache.
  void clearCache([String? conversationId]) {
    if (conversationId != null) {
      _cache.removeWhere((k, _) => k.startsWith(conversationId));
    } else {
      _cache.clear();
    }
    debugPrint(
      '[WeeklyRecap] 🗑 Cache cleared${conversationId != null ? " for $conversationId" : ""}',
    );
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  String _mapFunctionsError(FirebaseFunctionsException e) => switch (e.code) {
    'resource-exhausted' => 'Đã vượt giới hạn yêu cầu. Vui lòng chờ 1 phút.',
    'unauthenticated' => 'Cần đăng nhập để sử dụng tính năng này.',
    'not-found' => 'Không tìm thấy dữ liệu hội thoại.',
    'invalid-argument' => 'Dữ liệu không hợp lệ.',
    'deadline-exceeded' => 'Quá thời gian chờ. AI đang bận, thử lại sau.',
    _ => 'Không thể tạo tóm tắt lúc này. Vui lòng thử lại.',
  };
}
