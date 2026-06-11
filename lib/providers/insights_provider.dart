// lib/providers/insights_provider.dart
// TÍNH NĂNG 2: USER INSIGHTS — State management + local analysis
// Flow: Firestore cache → local analysis fallback → background refresh
// Không gọi AI trực tiếp từ client — gọi qua Cloud Function triggerInsightsRefresh

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../models/insights_models.dart';
import '../services/local_db_service.dart';

// ─── Load State ───────────────────────────────────────────────────────────────

enum InsightsLoadState { idle, loading, loaded, error, refreshing }

// ─────────────────────────────────────────────────────────────────────────────
// InsightsProvider
// ─────────────────────────────────────────────────────────────────────────────

class InsightsProvider extends ChangeNotifier {
  final FirebaseFirestore firebaseFirestore;

  InsightsProvider({required this.firebaseFirestore});

  // State
  InsightsDashboard? _dashboard;
  InsightsLoadState _loadState = InsightsLoadState.idle;
  String? _errorMessage;
  InsightsPeriod _selectedPeriod = InsightsPeriod.week7;
  String? _currentConvId;
  String? _currentUserId;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _watcher;

  // ── Getters ──────────────────────────────────────────────────────────────

  InsightsDashboard? get dashboard => _dashboard;
  InsightsLoadState get loadState => _loadState;
  String? get errorMessage => _errorMessage;
  InsightsPeriod get selectedPeriod => _selectedPeriod;

  InsightsSnapshot? get currentSnapshot =>
      _dashboard?.snapshotForPeriod(_selectedPeriod);

  bool get isLoading =>
      _loadState == InsightsLoadState.loading ||
      _loadState == InsightsLoadState.refreshing;

  bool get hasData => _dashboard != null;

  void selectPeriod(InsightsPeriod p) {
    if (_selectedPeriod == p) return;
    _selectedPeriod = p;
    notifyListeners();
  }

  // ── Load Dashboard ────────────────────────────────────────────────────────

  Future<void> loadDashboard({
    required String conversationId,
    required String userId,
  }) async {
    if (_loadState == InsightsLoadState.loading) return;

    _currentConvId = conversationId;
    _currentUserId = userId;
    _loadState = InsightsLoadState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      // 1. Đọc Firestore cache trước
      final cached = await _readFromFirestore(conversationId, userId);

      if (cached != null) {
        _dashboard = cached;
        _loadState = InsightsLoadState.loaded;
        notifyListeners();

        // 2. Nếu stale → refresh background
        if (cached.week7.isStale) {
          _triggerBackgroundRefresh(conversationId, userId);
        }
      } else {
        // 3. Không có cache → local analysis
        await _runLocalAnalysis(conversationId, userId);
      }

      // 4. Bắt đầu watch Firestore live
      _startWatcher(conversationId, userId);
    } catch (e) {
      debugPrint('[Insights] loadDashboard error: $e');
      // Fallback: local analysis
      try {
        await _runLocalAnalysis(conversationId, userId);
      } catch (e2) {
        _loadState = InsightsLoadState.error;
        _errorMessage = 'Không thể tải dữ liệu. Thử lại sau.';
        notifyListeners();
      }
    }
  }

  // ── Manual Refresh ────────────────────────────────────────────────────────

  Future<void> refresh() async {
    if (_currentConvId == null || _currentUserId == null) return;
    if (_loadState == InsightsLoadState.refreshing) return;

    _loadState = InsightsLoadState.refreshing;
    notifyListeners();

    try {
      // Gọi Cloud Function triggerInsightsRefresh
      final functions =
          FirebaseFunctions.instanceFor(region: 'asia-southeast1');
      final callable = functions.httpsCallable('triggerInsightsRefresh');
      await callable.call({
        'conversationId': _currentConvId,
        'userId': _currentUserId,
      });
      // Watcher sẽ tự cập nhật khi CF xong
    } catch (e) {
      debugPrint('[Insights] refresh CF error: $e — fallback local');
      // Fallback local nếu CF lỗi
      await _runLocalAnalysis(_currentConvId!, _currentUserId!);
    }

    if (_loadState == InsightsLoadState.refreshing) {
      _loadState = InsightsLoadState.loaded;
      notifyListeners();
    }
  }

  // ── Local Analysis (offline, không cần API) ────────────────────────────────

  Future<void> _runLocalAnalysis(String conversationId, String userId) async {
    final now = DateTime.now();

    final w7 = await _analyzeOnePeriod(
        conversationId, userId, InsightsPeriod.week7, now);
    final d30 = await _analyzeOnePeriod(
        conversationId, userId, InsightsPeriod.days30, now);
    final d90 = await _analyzeOnePeriod(
        conversationId, userId, InsightsPeriod.days90, now);

    _dashboard = InsightsDashboard(
      conversationId: conversationId,
      userId: userId,
      week7: w7,
      days30: d30,
      days90: d90,
      lastUpdated: now,
    );
    _loadState = InsightsLoadState.loaded;
    notifyListeners();

    // Persist kết quả local vào Firestore để dùng lần sau
    _saveToFirestore(conversationId, userId, _dashboard!).ignore();
  }

  Future<InsightsSnapshot> _analyzeOnePeriod(
    String conversationId,
    String userId,
    InsightsPeriod period,
    DateTime now,
  ) async {
    try {
      final cutoff =
          now.subtract(Duration(days: period.days)).millisecondsSinceEpoch;

      // Lấy messages từ LocalDb
      final allMsgs = LocalDbService().getMessages(conversationId);
      final msgs = allMsgs.where((m) {
        final ts = m['timestamp'] as int? ?? 0;
        final content = m['content']?.toString() ?? '';
        return ts >= cutoff &&
            m['idFrom'] == userId &&
            m['type'] == 0 &&
            content.isNotEmpty &&
            !content.startsWith('{"iv":') &&
            !content.startsWith('eyJ');
      }).toList();

      if (msgs.isEmpty) {
        return InsightsSnapshot(period: period, generatedAt: now);
      }

      final totalMessages = msgs.length;
      final activeDays = _countActiveDays(msgs, now, period.days);
      final avgMsgPerDay = activeDays > 0 ? totalMessages / activeDays : 0.0;
      final avgMsgLen = msgs.fold<int>(
              0, (s, m) => s + (m['content']?.toString().length ?? 0)) ~/
          msgs.length;

      final contents = msgs.map((m) => m['content']?.toString() ?? '').toList();

      final emojiRe = RegExp(
          r'[\u{1F600}-\u{1F64F}\u{1F300}-\u{1F5FF}\u{1F680}-\u{1F6FF}]',
          unicode: true);
      int emojiTotal = 0;
      for (final c in contents) {
        emojiTotal += emojiRe.allMatches(c).length;
      }
      final emojiLevel = emojiTotal > totalMessages * 0.5
          ? 'heavy'
          : emojiTotal > totalMessages * 0.2
              ? 'moderate'
              : 'minimal';

      final commStyle = avgMsgLen < 25
          ? 'concise'
          : avgMsgLen > 80
              ? 'expressive'
              : 'balanced';

      final heatmap = _buildHeatmap(msgs, now, period.days);
      final moodTrend = _buildMoodTrend(msgs, now, period.days);
      final sentiment = _buildSentiment(moodTrend);
      final topics = _extractTopics(contents);
      final activityPattern = _detectActivityPattern(heatmap);
      final traits = _inferTraits(emojiLevel, commStyle, sentiment);

      final summary = _buildLocalSummary(
        period: period,
        totalMessages: totalMessages,
        activeDays: activeDays,
        avgMsgPerDay: avgMsgPerDay,
        commStyle: commStyle,
        emojiLevel: emojiLevel,
        activityPattern: activityPattern,
      );

      return InsightsSnapshot(
        period: period,
        totalMessages: totalMessages,
        activeDays: activeDays,
        avgMessagesPerDay: double.parse(avgMsgPerDay.toStringAsFixed(1)),
        avgMessageLength: avgMsgLen,
        communicationStyle: commStyle,
        emojiUsageLevel: emojiLevel,
        personalityTraits: traits,
        activityPattern: activityPattern,
        insightSummary: summary,
        moodTrend: moodTrend,
        activityHeatmap: heatmap,
        topTopics: topics,
        sentimentBreakdown: sentiment,
        generatedAt: now,
      );
    } catch (e) {
      debugPrint('[Insights] _analyzeOnePeriod error [$period]: $e');
      return InsightsSnapshot(period: period, generatedAt: DateTime.now());
    }
  }

  // ─── Build Heatmap 7×24 ────────────────────────────────────────────────────

  List<ActivitySlot> _buildHeatmap(
      List<Map<dynamic, dynamic>> msgs, DateTime now, int days) {
    // Khởi tạo grid 7×24
    final grid = List.generate(7, (d) => List.generate(24, (h) => 0));

    final cutoff = now.subtract(Duration(days: days)).millisecondsSinceEpoch;

    for (final m in msgs) {
      final ts = m['timestamp'] as int? ?? 0;
      if (ts < cutoff) continue;
      final dt = DateTime.fromMillisecondsSinceEpoch(ts);
      final dow = (dt.weekday - 1) % 7; // 0=Mon
      grid[dow][dt.hour]++;
    }

    // Tìm max để normalize
    int maxCount = 1;
    for (final row in grid) {
      for (final c in row) {
        if (c > maxCount) maxCount = c;
      }
    }

    final result = <ActivitySlot>[];
    for (int d = 0; d < 7; d++) {
      for (int h = 0; h < 24; h++) {
        result.add(ActivitySlot(
          dayOfWeek: d,
          hour: h,
          count: grid[d][h],
          intensity: grid[d][h] / maxCount,
        ));
      }
    }
    return result;
  }

  // ─── Build Mood Trend theo ngày ────────────────────────────────────────────

  List<MoodPoint> _buildMoodTrend(
      List<Map<dynamic, dynamic>> msgs, DateTime now, int days) {
    // Nhóm msgs theo ngày
    final byDay = <String, List<String>>{};
    final cutoff = now.subtract(Duration(days: days));

    for (final m in msgs) {
      final ts = m['timestamp'] as int? ?? 0;
      final dt = DateTime.fromMillisecondsSinceEpoch(ts);
      if (dt.isBefore(cutoff)) continue;
      final key =
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      byDay.putIfAbsent(key, () => []).add(m['content']?.toString() ?? '');
    }

    // Positive/negative keywords đơn giản
    const posWords = {
      'vui',
      'thích',
      'tuyệt',
      'hay',
      'oke',
      'ok',
      'được',
      'yêu',
      'xinh',
      'đẹp',
      'ngon',
      'thú vị',
      'tốt',
      'giỏi',
      '😊',
      '😂',
      '❤️',
      '🥰',
      '😍',
      '👍',
      '🔥',
      '✨',
    };
    const negWords = {
      'buồn',
      'chán',
      'mệt',
      'khó',
      'tệ',
      'xấu',
      'không',
      'sai',
      'lỗi',
      'lo',
      'sợ',
      'ghét',
      'nhàm',
      '😢',
      '😠',
      '😤',
      '🤦',
      '😞',
    };

    double _score(List<String> dayMsgs) {
      int pos = 0, neg = 0;
      for (final msg in dayMsgs) {
        final lower = msg.toLowerCase();
        for (final w in posWords) if (lower.contains(w)) pos++;
        for (final w in negWords) if (lower.contains(w)) neg++;
      }
      final total = pos + neg;
      if (total == 0) return 0.5;
      return pos / total;
    }

    String _emoji(double score) {
      if (score > 0.75) return '😄';
      if (score > 0.55) return '😊';
      if (score > 0.45) return '😐';
      if (score > 0.25) return '😕';
      return '😢';
    }

    final sorted = byDay.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return sorted.map((e) {
      final parts = e.key.split('-');
      final date = DateTime(
          int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      final score = _score(e.value);
      return MoodPoint(
        date: date,
        score: score,
        emoji: _emoji(score),
        messageCount: e.value.length,
      );
    }).toList();
  }

  // ─── Build Sentiment ───────────────────────────────────────────────────────

  SentimentBreakdown _buildSentiment(List<MoodPoint> moodTrend) {
    if (moodTrend.isEmpty) return const SentimentBreakdown();

    int pos = 0, neg = 0, neu = 0;
    for (final p in moodTrend) {
      if (p.score > 0.6)
        pos++;
      else if (p.score < 0.4)
        neg++;
      else
        neu++;
    }
    final total = moodTrend.length;
    final posR = pos / total;
    final negR = neg / total;
    final neuR = neu / total;

    // Trend: so sánh nửa đầu vs nửa sau
    String trend = 'stable';
    if (moodTrend.length >= 4) {
      final half = moodTrend.length ~/ 2;
      final firstHalf =
          moodTrend.take(half).fold(0.0, (s, p) => s + p.score) / half;
      final secondHalf = moodTrend.skip(half).fold(0.0, (s, p) => s + p.score) /
          (moodTrend.length - half);
      if (secondHalf - firstHalf > 0.12) trend = 'improving';
      if (firstHalf - secondHalf > 0.12) trend = 'declining';
    }

    return SentimentBreakdown(
      positive: double.parse(posR.toStringAsFixed(2)),
      neutral: double.parse(neuR.toStringAsFixed(2)),
      negative: double.parse(negR.toStringAsFixed(2)),
      trend: trend,
    );
  }

  // ─── Extract Topics ────────────────────────────────────────────────────────

  List<TopicTag> _extractTopics(List<String> contents) {
    const stopwords = {
      'là',
      'và',
      'có',
      'không',
      'được',
      'của',
      'với',
      'cho',
      'trong',
      'mình',
      'bạn',
      'thì',
      'đã',
      'sẽ',
      'ở',
      'tôi',
      'mày',
      'tao',
      'nha',
      'nhé',
      'ạ',
      'ra',
      'vào',
      'thôi',
      'rồi',
      'đây',
      'đó',
      'này',
    };
    const topicEmojis = {
      'ăn': '🍜',
      'nhậu': '🍺',
      'cà phê': '☕',
      'học': '📚',
      'làm': '💼',
      'game': '🎮',
      'phim': '🎬',
      'nhạc': '🎵',
      'đi': '🚗',
      'chơi': '🎉',
      'mua': '🛍️',
      'tiền': '💰',
    };

    final freq = <String, int>{};
    for (final c in contents) {
      final words = c.toLowerCase().split(RegExp(r'[\s,.\!\?\n]+'));
      for (final w in words) {
        final clean = w.replaceAll(RegExp(r'[^\w]'), '').trim();
        if (clean.length >= 2 && !stopwords.contains(clean)) {
          freq[clean] = (freq[clean] ?? 0) + 1;
        }
      }
    }

    final sorted = (freq.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(8)
        .toList();

    final total = sorted.fold<int>(0, (s, e) => s + e.value);
    if (total == 0) return [];

    return sorted.map((e) {
      final emoji = topicEmojis.entries
          .firstWhere((te) => e.key.contains(te.key),
              orElse: () => const MapEntry('', '💬'))
          .value;
      return TopicTag(
        topic: e.key,
        count: e.value,
        percentage: e.value / total,
        emoji: emoji,
      );
    }).toList();
  }

  // ─── Detect Activity Pattern ───────────────────────────────────────────────

  String _detectActivityPattern(List<ActivitySlot> heatmap) {
    int morningCount = 0, afternoonCount = 0, eveningCount = 0, nightCount = 0;
    for (final slot in heatmap) {
      if (slot.hour >= 6 && slot.hour < 12)
        morningCount += slot.count;
      else if (slot.hour >= 12 && slot.hour < 18)
        afternoonCount += slot.count;
      else if (slot.hour >= 18 && slot.hour < 23)
        eveningCount += slot.count;
      else
        nightCount += slot.count;
    }
    final total = morningCount + afternoonCount + eveningCount + nightCount;
    if (total == 0) return 'balanced';
    if (nightCount / total > 0.4) return 'night_owl';
    if (morningCount / total > 0.4) return 'morning_person';
    if (eveningCount / total > 0.4) return 'evening_person';
    return 'balanced';
  }

  // ─── Infer Personality Traits ──────────────────────────────────────────────

  List<String> _inferTraits(
      String emojiLevel, String commStyle, SentimentBreakdown sentiment) {
    final traits = <String>[];
    if (emojiLevel == 'heavy') traits.add('expressive');
    if (commStyle == 'expressive') traits.add('communicative');
    if (commStyle == 'concise') traits.add('direct');
    if (sentiment.positive > 0.6) traits.add('optimistic');
    if (sentiment.negative > 0.4) traits.add('reflective');
    if (traits.isEmpty) traits.add('balanced');
    return traits;
  }

  // ─── Count Active Days ─────────────────────────────────────────────────────

  int _countActiveDays(
      List<Map<dynamic, dynamic>> msgs, DateTime now, int days) {
    final cutoff = now.subtract(Duration(days: days));
    final activeDates = <String>{};
    for (final m in msgs) {
      final ts = m['timestamp'] as int? ?? 0;
      final dt = DateTime.fromMillisecondsSinceEpoch(ts);
      if (dt.isAfter(cutoff)) {
        activeDates.add('${dt.year}-${dt.month}-${dt.day}');
      }
    }
    return activeDates.length;
  }

  // ─── Build Local Summary ───────────────────────────────────────────────────

  String _buildLocalSummary({
    required InsightsPeriod period,
    required int totalMessages,
    required int activeDays,
    required double avgMsgPerDay,
    required String commStyle,
    required String emojiLevel,
    required String activityPattern,
  }) {
    final periodLabel = period.label;
    final styleDesc = commStyle == 'concise'
        ? 'ngắn gọn, súc tích'
        : commStyle == 'expressive'
            ? 'chi tiết, cởi mở'
            : 'cân bằng, rõ ràng';
    final emojiDesc = emojiLevel == 'heavy'
        ? 'thường xuyên dùng emoji'
        : emojiLevel == 'moderate'
            ? 'đôi khi dùng emoji'
            : 'ít dùng emoji';
    final patternDesc = activityPattern == 'night_owl'
        ? 'nhắn tin nhiều về đêm'
        : activityPattern == 'morning_person'
            ? 'hay nhắn tin buổi sáng'
            : 'nhắn tin đều trong ngày';

    return 'Trong $periodLabel qua, bạn đã gửi $totalMessages tin nhắn '
        'trên $activeDays ngày (trung bình ${avgMsgPerDay.toStringAsFixed(1)} tin/ngày). '
        'Phong cách giao tiếp của bạn $styleDesc, $emojiDesc và $patternDesc.';
  }

  // ─── Firestore I/O ────────────────────────────────────────────────────────

  Future<InsightsDashboard?> _readFromFirestore(
      String conversationId, String userId) async {
    try {
      final doc = await firebaseFirestore
          .collection('users')
          .doc(userId)
          .collection('insights_cache')
          .doc('dashboard_$conversationId')
          .get();
      if (!doc.exists || doc.data() == null) return null;
      return InsightsDashboard.fromFirestore(doc, conversationId, userId);
    } catch (e) {
      debugPrint('[Insights] _readFromFirestore error: $e');
      return null;
    }
  }

  Future<void> _saveToFirestore(
      String conversationId, String userId, InsightsDashboard dash) async {
    try {
      await firebaseFirestore
          .collection('users')
          .doc(userId)
          .collection('insights_cache')
          .doc('dashboard_$conversationId')
          .set(dash.toMap(), SetOptions(merge: true));
    } catch (e) {
      debugPrint('[Insights] _saveToFirestore error: $e');
    }
  }

  // ─── Watcher ──────────────────────────────────────────────────────────────

  void _startWatcher(String conversationId, String userId) {
    _watcher?.cancel();
    _watcher = firebaseFirestore
        .collection('users')
        .doc(userId)
        .collection('insights_cache')
        .doc('dashboard_$conversationId')
        .snapshots()
        .listen(
      (snap) {
        if (snap.exists && snap.data() != null) {
          final updated =
              InsightsDashboard.fromFirestore(snap, conversationId, userId);
          _dashboard = updated;
          if (_loadState == InsightsLoadState.refreshing) {
            _loadState = InsightsLoadState.loaded;
          }
          notifyListeners();
        }
      },
      onError: (e) => debugPrint('[Insights] watcher error: $e'),
    );
  }

  void _triggerBackgroundRefresh(String conversationId, String userId) {
    Future.microtask(() async {
      try {
        final functions =
            FirebaseFunctions.instanceFor(region: 'asia-southeast1');
        final callable = functions.httpsCallable('triggerInsightsRefresh');
        await callable.call({
          'conversationId': conversationId,
          'userId': userId,
        });
      } catch (e) {
        debugPrint('[Insights] background refresh error: $e');
      }
    });
  }

  void cancelWatcher() {
    _watcher?.cancel();
    _watcher = null;
  }

  // ─── Dispose ──────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _watcher?.cancel();
    super.dispose();
  }
}
