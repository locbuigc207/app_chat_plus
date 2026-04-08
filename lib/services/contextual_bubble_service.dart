// lib/services/contextual_bubble_service.dart
// Contextual Bubble Universe - Core Service
// Phân tích nội dung tin nhắn và quản lý trạng thái ngữ cảnh của bubble

import 'dart:async';

import 'package:flutter/foundation.dart';

/// Các chế độ ngữ cảnh mà bubble có thể hiển thị
enum BubbleMode {
  normal,    // Chế độ chat thông thường
  work,      // Chế độ công việc (từ khóa: task, deadline, meeting, ...)
  media,     // Chế độ media (gửi ảnh, video, nhạc nhiều)
  location,  // Chế độ vị trí (chia sẻ location)
  shared,    // Chế độ không gian chung (co-browsing, whiteboard)
  secure,    // Chế độ bảo mật (view-once + face detection)
}

/// Dữ liệu context hiện tại của bubble
class BubbleContext {
  final BubbleMode mode;
  final String? detectedTopic;
  final Map<String, dynamic>? extraData;
  final DateTime updatedAt;

  const BubbleContext({
    required this.mode,
    this.detectedTopic,
    this.extraData,
    required this.updatedAt,
  });

  BubbleContext copyWith({
    BubbleMode? mode,
    String? detectedTopic,
    Map<String, dynamic>? extraData,
  }) =>
      BubbleContext(
        mode: mode ?? this.mode,
        detectedTopic: detectedTopic ?? this.detectedTopic,
        extraData: extraData ?? this.extraData,
        updatedAt: DateTime.now(),
      );
}

/// Service chính phân tích ngữ cảnh và điều phối BubbleMode
class ContextualBubbleService extends ChangeNotifier {
  static final ContextualBubbleService _instance =
  ContextualBubbleService._internal();
  factory ContextualBubbleService() => _instance;
  ContextualBubbleService._internal();

  // Trạng thái hiện tại
  BubbleContext _currentContext = BubbleContext(
    mode: BubbleMode.normal,
    updatedAt: DateTime.now(),
  );

  // Đếm số media được gửi gần đây (để detect Media Mode)
  int _recentMediaCount = 0;
  Timer? _mediaCountResetTimer;

  // Stream controller để broadcast thay đổi context
  final _contextController =
  StreamController<BubbleContext>.broadcast();

  Stream<BubbleContext> get contextStream => _contextController.stream;
  BubbleContext get currentContext => _currentContext;
  BubbleMode get currentMode => _currentContext.mode;

  // ─── WORK MODE KEYWORDS ──────────────────────────────────────────────────
  static const _workKeywords = [
    'task', 'deadline', 'meeting', 'project', 'report', 'review',
    'sprint', 'ticket', 'jira', 'trello', 'asana', 'figma',
    'pr', 'pull request', 'deploy', 'release', 'bug', 'fix',
    'công việc', 'nhiệm vụ', 'họp', 'dự án', 'deadline', 'báo cáo',
    'kế hoạch', 'tiến độ', 'file', 'tài liệu', 'gửi file', 'send file',
    'urgent', 'asap', 'schedule', 'calendar', 'email', 'call',
  ];

  // ─── LOCATION KEYWORDS ──────────────────────────────────────────────────
  static const _locationKeywords = [
    'where are you', 'location', 'maps', 'địa chỉ', 'vị trí',
    'bạn đang ở đâu', 'meet', 'gặp nhau', 'đến đây', 'đường đi',
    'navigate', 'direction', 'ở đây', 'chỗ này', 'nơi này',
  ];

  // ─── CORE ANALYSIS ──────────────────────────────────────────────────────

  /// Phân tích nội dung tin nhắn để xác định mode
  void analyzeMessage({
    required String content,
    required int messageType, // 0=text, 1=image, 3=voice, location=4
    bool isFromCurrentUser = true,
  }) {
    // Media mode: nhiều ảnh/voice
    if (messageType == 1 || messageType == 3) {
      _recentMediaCount++;
      _mediaCountResetTimer?.cancel();
      _mediaCountResetTimer = Timer(const Duration(minutes: 5), () {
        _recentMediaCount = 0;
      });

      if (_recentMediaCount >= 2) {
        _updateMode(BubbleMode.media);
        return;
      }
    }

    // Location mode
    if (messageType == 0 && _isLocationMessage(content)) {
      _updateMode(BubbleMode.location, extraData: {
        'mapsUrl': _extractMapsUrl(content),
      });
      return;
    }

    // Work mode: phân tích từ khóa text
    if (messageType == 0 && _containsWorkKeywords(content)) {
      final topic = _extractWorkTopic(content);
      _updateMode(BubbleMode.work, detectedTopic: topic);
      return;
    }

    // Nếu không match gì đặc biệt → về normal sau 10 phút idle
    _scheduleNormalReset();
  }

  /// Kích hoạt Shared Space mode thủ công
  void activateSharedMode({Map<String, dynamic>? extraData}) {
    _updateMode(BubbleMode.shared, extraData: extraData);
  }

  /// Kích hoạt Secure mode (anti-shoulder-surf)
  void activateSecureMode() {
    _updateMode(BubbleMode.secure);
  }

  /// Reset về Normal mode
  void resetToNormal() {
    _updateMode(BubbleMode.normal);
  }

  /// Cập nhật location data khi nhận được vị trí mới
  void updateLocationData({
    required double myLat,
    required double myLng,
    required double peerLat,
    required double peerLng,
    String? peerName,
  }) {
    if (_currentContext.mode == BubbleMode.location) {
      final distance = _calculateDistance(myLat, myLng, peerLat, peerLng);
      _updateMode(BubbleMode.location, extraData: {
        ...?_currentContext.extraData,
        'myLat': myLat,
        'myLng': myLng,
        'peerLat': peerLat,
        'peerLng': peerLng,
        'distance': distance,
        'peerName': peerName,
      });
    }
  }

  // ─── PRIVATE HELPERS ─────────────────────────────────────────────────────

  void _updateMode(
      BubbleMode mode, {
        String? detectedTopic,
        Map<String, dynamic>? extraData,
      }) {
    final newContext = _currentContext.copyWith(
      mode: mode,
      detectedTopic: detectedTopic,
      extraData: extraData,
    );
    _currentContext = newContext;
    _contextController.add(newContext);
    notifyListeners();
    debugPrint('🎯 BubbleMode changed to: ${mode.name}');
  }

  Timer? _normalResetTimer;

  void _scheduleNormalReset() {
    _normalResetTimer?.cancel();
    _normalResetTimer = Timer(const Duration(minutes: 10), () {
      if (_currentContext.mode != BubbleMode.secure &&
          _currentContext.mode != BubbleMode.shared) {
        _updateMode(BubbleMode.normal);
      }
    });
  }

  bool _isLocationMessage(String content) {
    return content.contains('maps.google.com') ||
        content.contains('📍 Location') ||
        _locationKeywords.any((kw) => content.toLowerCase().contains(kw));
  }

  String? _extractMapsUrl(String content) {
    final urlPattern = RegExp(r'https://www\.google\.com/maps[^\s]+');
    final match = urlPattern.firstMatch(content);
    return match?.group(0);
  }

  bool _containsWorkKeywords(String content) {
    final lower = content.toLowerCase();
    return _workKeywords.any((kw) => lower.contains(kw));
  }

  String _extractWorkTopic(String content) {
    final lower = content.toLowerCase();
    if (lower.contains('task') || lower.contains('nhiệm vụ')) return 'task';
    if (lower.contains('meeting') || lower.contains('họp')) return 'meeting';
    if (lower.contains('deadline')) return 'deadline';
    if (lower.contains('file') || lower.contains('tài liệu')) return 'file';
    return 'work';
  }

  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371.0; // km
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = (dLat / 2 * dLat / 2) +
        (dLon / 2 * dLon / 2) *
            (_toRad(lat1).abs()) *
            (_toRad(lat2).abs());
    final c = 2 * (a < 1 ? a : 1);
    return earthRadius * c;
  }

  double _toRad(double deg) => deg * 3.14159265 / 180;

  // ─── DISPOSE ──────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _contextController.close();
    _mediaCountResetTimer?.cancel();
    _normalResetTimer?.cancel();
    super.dispose();
  }
}