// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SERVICE
// ─────────────────────────────────────────────────────────────────────────────

/// Singleton service that analyses chat messages and emits [BubbleContext]
/// state changes in real time.
///
/// Usage:
/// ```dart
/// final svc = ContextualBubbleService();
/// svc.analyzeMessage(content: text, messageType: 0);
/// svc.contextStream.listen((ctx) { /* rebuild UI */ });
/// ```
class ContextualBubbleService extends ChangeNotifier {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static final ContextualBubbleService _instance =
      ContextualBubbleService._internal();
  factory ContextualBubbleService() => _instance;
  ContextualBubbleService._internal();

  // ── State ──────────────────────────────────────────────────────────────────
  BubbleContext _ctx = BubbleContext(
    mode: BubbleMode.normal,
    updatedAt: DateTime.now(),
  );

  BubbleContext get currentContext => _ctx;
  BubbleMode get currentMode => _ctx.mode;

  // ── Stream ─────────────────────────────────────────────────────────────────
  final _streamCtrl = StreamController<BubbleContext>.broadcast();
  Stream<BubbleContext> get contextStream => _streamCtrl.stream;

  // ── Media counter ──────────────────────────────────────────────────────────
  int _recentMediaCount = 0;
  Timer? _mediaResetTimer;
  static const _mediaThreshold = 2;
  static const _mediaResetWindow = Duration(minutes: 5);

  // ── Auto-reset timers ──────────────────────────────────────────────────────
  Timer? _normalResetTimer;
  static const _autoResetDelay = Duration(minutes: 15);
  static const _locationResetDelay = Duration(minutes: 30);

  // ── Message-type constants (mirrors ChatMessage.messageType) ──────────────
  static const _typeText = 0;
  static const _typeImage = 1;
  static const _typeVideo = 2;
  static const _typeAudio = 3;
  static const _typeFile = 4;
  static const _typeLocation = 5;
  static const _typeSticker = 6;
  static const _typeGif = 7;

  // ── Work keywords ─────────────────────────────────────────────────────────
  static const _workKeywords = <String>[
    // English
    'task', 'tasks', 'deadline', 'deadlines', 'meeting', 'meetings',
    'project', 'projects', 'report', 'reports', 'review', 'reviews',
    'sprint', 'ticket', 'tickets', 'jira', 'trello', 'asana', 'figma',
    'notion', 'pr ', 'pull request', 'deploy', 'deployment', 'release',
    'bug', 'fix', 'hotfix', 'issue', 'issues', 'milestone',
    'urgent', 'asap', 'priority', 'schedule', 'calendar', 'action item',
    'follow up', 'follow-up', 'deliverable', 'okr', 'kpi',
    // Vietnamese
    'công việc', 'nhiệm vụ', 'họp', 'dự án', 'báo cáo',
    'kế hoạch', 'tiến độ', 'gửi file', 'nộp báo cáo',
    'hạn chót', 'khẩn', 'quan trọng', 'cần làm ngay',
    'lịch họp', 'tài liệu', 'trình bày',
  ];

  // ── Location keywords ─────────────────────────────────────────────────────
  static const _locationKeywords = <String>[
    'where are you',
    'your location',
    'location',
    'maps',
    'navigate',
    'direction',
    'meet',
    'gps',
    'coordinates',
    'address',
    'bạn đang ở đâu',
    'vị trí',
    'địa chỉ',
    'đang ở đâu',
    'gặp nhau',
    'đến đây',
    'đường đi',
    'chỉ đường',
    'bản đồ',
    'ở chỗ này',
    'ở đây',
    'chỗ này',
    'nơi này',
  ];

  // ── URL patterns ──────────────────────────────────────────────────────────
  static final _googleMapsPattern = RegExp(
      r'https?://(?:www\.)?(?:google\.com/maps|goo\.gl/maps|maps\.app\.goo\.gl)[^\s]*');
  static final _locationEmojiPattern = RegExp(r'📍');

  // ─────────────────────────────────────────────────────────────────────────
  // PUBLIC API
  // ─────────────────────────────────────────────────────────────────────────

  /// Analyse a message and update context accordingly.
  ///
  /// [messageType] values:
  ///  0 = text, 1 = image, 2 = video, 3 = audio, 4 = file,
  ///  5 = location, 6 = sticker, 7 = gif
  void analyzeMessage({
    required String content,
    required int messageType,
    bool isFromCurrentUser = true,
    Map<String, dynamic>? extra,
  }) {
    try {
      _analyzeInternal(
        content: content,
        messageType: messageType,
        isFromCurrentUser: isFromCurrentUser,
        extra: extra,
      );
    } catch (e, st) {
      debugPrint('ContextualBubbleService.analyzeMessage error: $e\n$st');
    }
  }

  /// Forcefully activate shared-space mode.
  void activateSharedMode({Map<String, dynamic>? extraData}) =>
      _transition(BubbleMode.shared, extraData: extraData);

  /// Forcefully activate anti-shoulder-surf secure mode.
  void activateSecureMode() => _transition(BubbleMode.secure);

  /// Reset to normal mode immediately.
  void resetToNormal() => _transition(BubbleMode.normal);

  /// Push updated GPS coordinates while in location mode.
  void updateLocationData({
    required double myLat,
    required double myLng,
    required double peerLat,
    required double peerLng,
    String? peerName,
    String? mapsUrl,
  }) {
    if (_ctx.mode != BubbleMode.location) return;
    final distance = _haversineKm(myLat, myLng, peerLat, peerLng);
    _transition(BubbleMode.location, extraData: {
      ...?_ctx.extraData,
      'myLat': myLat,
      'myLng': myLng,
      'peerLat': peerLat,
      'peerLng': peerLng,
      'distance': distance,
      if (peerName != null) 'peerName': peerName,
      if (mapsUrl != null) 'mapsUrl': mapsUrl,
    });
  }

  /// Returns a human-readable label for [mode].
  static String labelFor(BubbleMode mode) {
    switch (mode) {
      case BubbleMode.work:
        return 'Work';
      case BubbleMode.media:
        return 'Media';
      case BubbleMode.location:
        return 'Location';
      case BubbleMode.shared:
        return 'Shared';
      case BubbleMode.secure:
        return 'Secure';
      default:
        return 'Normal';
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // INTERNAL
  // ─────────────────────────────────────────────────────────────────────────

  void _analyzeInternal({
    required String content,
    required int messageType,
    required bool isFromCurrentUser,
    Map<String, dynamic>? extra,
  }) {
    // 1. Native location message type
    if (messageType == _typeLocation) {
      final mapsUrl = extra?['mapsUrl'] as String? ?? _extractMapsUrl(content);
      _transition(BubbleMode.location, extraData: {
        if (mapsUrl != null) 'mapsUrl': mapsUrl,
        ...?extra,
      });
      return;
    }

    // 2. Media messages (image / video / audio / gif)
    if (messageType == _typeImage ||
        messageType == _typeVideo ||
        messageType == _typeAudio ||
        messageType == _typeGif) {
      _recentMediaCount++;
      _mediaResetTimer?.cancel();
      _mediaResetTimer = Timer(_mediaResetWindow, () {
        _recentMediaCount = 0;
        if (_ctx.mode == BubbleMode.media) _scheduleAutoReset(_autoResetDelay);
      });
      if (_recentMediaCount >= _mediaThreshold) {
        _transition(BubbleMode.media, extraData: {
          'mediaCount': _recentMediaCount,
          'lastType': messageType,
        });
        return;
      }
    }

    // 3. File share → work mode
    if (messageType == _typeFile) {
      _transition(BubbleMode.work,
          detectedTopic: 'file', extraData: {'fileName': extra?['fileName']});
      return;
    }

    // 4. Text analysis (only run on text messages)
    if (messageType != _typeText) return;

    // 4a. Location mention in text
    if (_isLocationContent(content)) {
      _transition(BubbleMode.location, extraData: {
        'mapsUrl': _extractMapsUrl(content),
      });
      return;
    }

    // 4b. Work keywords
    if (_hasWorkKeyword(content)) {
      _transition(BubbleMode.work, detectedTopic: _extractWorkTopic(content));
      return;
    }

    // 4c. If currently in non-sticky mode, schedule revert to normal
    if (_ctx.mode != BubbleMode.secure && _ctx.mode != BubbleMode.shared) {
      _scheduleAutoReset(_autoResetDelay);
    }
  }

  void _transition(
    BubbleMode mode, {
    String? detectedTopic,
    Map<String, dynamic>? extraData,
  }) {
    // Don't interrupt secure or shared unless explicitly resetting
    if (mode != BubbleMode.secure && _ctx.mode == BubbleMode.secure) return;
    if (mode != BubbleMode.shared &&
        _ctx.mode == BubbleMode.shared &&
        mode != BubbleMode.normal) return;

    final newCtx = _ctx.copyWith(
      mode: mode,
      detectedTopic: detectedTopic,
      extraData: extraData,
    );
    if (newCtx == _ctx) return; // no actual change

    _normalResetTimer?.cancel();
    _ctx = newCtx;
    _streamCtrl.add(newCtx);
    notifyListeners();

    debugPrint('🎯 BubbleMode → ${mode.name}'
        '${detectedTopic != null ? " ($detectedTopic)" : ""}');

    // Auto-reset location after extended idle
    if (mode == BubbleMode.location) {
      _scheduleAutoReset(_locationResetDelay);
    }
  }

  void _scheduleAutoReset(Duration delay) {
    _normalResetTimer?.cancel();
    _normalResetTimer = Timer(delay, () {
      if (_ctx.mode != BubbleMode.secure && _ctx.mode != BubbleMode.shared) {
        _transition(BubbleMode.normal);
      }
    });
  }

  // ── Text analysis helpers ─────────────────────────────────────────────────

  bool _isLocationContent(String content) {
    if (_locationEmojiPattern.hasMatch(content)) return true;
    if (_googleMapsPattern.hasMatch(content)) return true;
    final lower = content.toLowerCase();
    return _locationKeywords.any((kw) => lower.contains(kw));
  }

  String? _extractMapsUrl(String content) {
    final match = _googleMapsPattern.firstMatch(content);
    return match?.group(0);
  }

  bool _hasWorkKeyword(String content) {
    final lower = content.toLowerCase();
    return _workKeywords.any((kw) => lower.contains(kw));
  }

  String _extractWorkTopic(String content) {
    final lower = content.toLowerCase();
    if (lower.contains('task') ||
        lower.contains('nhiệm vụ') ||
        lower.contains('việc')) return 'task';
    if (lower.contains('meeting') ||
        lower.contains('họp') ||
        lower.contains('lịch họp')) return 'meeting';
    if (lower.contains('deadline') || lower.contains('hạn chót')) {
      return 'deadline';
    }
    if (lower.contains('file') ||
        lower.contains('tài liệu') ||
        lower.contains('gửi file')) return 'file';
    if (lower.contains('deploy') ||
        lower.contains('release') ||
        lower.contains('sprint')) return 'engineering';
    if (lower.contains('bug') ||
        lower.contains('fix') ||
        lower.contains('issue')) return 'bug';
    return 'work';
  }

  // ── Haversine distance ────────────────────────────────────────────────────

  static double _haversineKm(
      double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.pow(math.sin(dLon / 2), 2);
    final c = 2 * math.asin(math.sqrt(a.clamp(0.0, 1.0)));
    return R * c;
  }

  static double _rad(double deg) => deg * math.pi / 180;

  // ─────────────────────────────────────────────────────────────────────────
  // DISPOSE
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _streamCtrl.close();
    _mediaResetTimer?.cancel();
    _normalResetTimer?.cancel();
    super.dispose();
  }
}
