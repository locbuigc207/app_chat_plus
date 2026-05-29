// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/models.dart';














class ContextualBubbleService extends ChangeNotifier {
  
  static final ContextualBubbleService _instance = ContextualBubbleService._internal();
  factory ContextualBubbleService() => _instance;
  ContextualBubbleService._internal();

  
  BubbleContext _ctx = BubbleContext(
    mode: BubbleMode.normal,
    updatedAt: DateTime.now(),
  );

  BubbleContext get currentContext => _ctx;
  BubbleMode get currentMode => _ctx.mode;

  
  final _streamCtrl = StreamController<BubbleContext>.broadcast();
  Stream<BubbleContext> get contextStream => _streamCtrl.stream;

  
  int _recentMediaCount = 0;
  Timer? _mediaResetTimer;
  static const _mediaThreshold = 2;
  static const _mediaResetWindow = Duration(minutes: 5);

  
  Timer? _normalResetTimer;
  static const _autoResetDelay = Duration(minutes: 15);
  static const _locationResetDelay = Duration(minutes: 30);

  
  static const _typeText = 0;
  static const _typeImage = 1;
  static const _typeVideo = 2;
  static const _typeAudio = 3;
  static const _typeFile = 4;
  static const _typeLocation = 5;
  static const _typeSticker = 6;
  static const _typeGif = 7;

  
  static const _workKeywords = <String>[
    
    'task', 'tasks', 'deadline', 'deadlines', 'meeting', 'meetings',
    'project', 'projects', 'report', 'reports', 'review', 'reviews',
    'sprint', 'ticket', 'tickets', 'jira', 'trello', 'asana', 'figma',
    'notion', 'pr ', 'pull request', 'deploy', 'deployment', 'release',
    'bug', 'fix', 'hotfix', 'issue', 'issues', 'milestone',
    'urgent', 'asap', 'priority', 'schedule', 'calendar', 'action item',
    'follow up', 'follow-up', 'deliverable', 'okr', 'kpi',
    
    'công việc', 'nhiệm vụ', 'họp', 'dự án', 'báo cáo',
    'kế hoạch', 'tiến độ', 'gửi file', 'nộp báo cáo',
    'hạn chót', 'khẩn', 'quan trọng', 'cần làm ngay',
    'lịch họp', 'tài liệu', 'trình bày',
  ];

  
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

  
  static final _googleMapsPattern =
      RegExp(r'https?://(?:www\.)?(?:google\.com/maps|goo\.gl/maps|maps\.app\.goo\.gl)[^\s]*');
  static final _locationEmojiPattern = RegExp(r'📍');

  
  
  

  
  
  
  
  
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

  
  void activateSharedMode({Map<String, dynamic>? extraData}) =>
      _transition(BubbleMode.shared, extraData: extraData);

  
  void activateSecureMode() => _transition(BubbleMode.secure);

  
  void resetToNormal() => _transition(BubbleMode.normal);

  
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

  
  
  

  void _analyzeInternal({
    required String content,
    required int messageType,
    required bool isFromCurrentUser,
    Map<String, dynamic>? extra,
  }) {
    
    if (messageType == _typeLocation) {
      final mapsUrl = extra?['mapsUrl'] as String? ?? _extractMapsUrl(content);
      _transition(BubbleMode.location, extraData: {
        if (mapsUrl != null) 'mapsUrl': mapsUrl,
        ...?extra,
      });
      return;
    }

    
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

    
    if (messageType == _typeFile) {
      _transition(BubbleMode.work,
          detectedTopic: 'file', extraData: {'fileName': extra?['fileName']});
      return;
    }

    
    if (messageType != _typeText) return;

    
    if (_isLocationContent(content)) {
      _transition(BubbleMode.location, extraData: {
        'mapsUrl': _extractMapsUrl(content),
      });
      return;
    }

    
    if (_hasWorkKeyword(content)) {
      _transition(BubbleMode.work, detectedTopic: _extractWorkTopic(content));
      return;
    }

    
    if (_ctx.mode != BubbleMode.secure && _ctx.mode != BubbleMode.shared) {
      _scheduleAutoReset(_autoResetDelay);
    }
  }

  void _transition(
    BubbleMode mode, {
    String? detectedTopic,
    Map<String, dynamic>? extraData,
  }) {
    
    if (mode != BubbleMode.secure && _ctx.mode == BubbleMode.secure) return;
    if (mode != BubbleMode.shared && _ctx.mode == BubbleMode.shared && mode != BubbleMode.normal) {
      return;
    }

    final newCtx = _ctx.copyWith(
      mode: mode,
      detectedTopic: detectedTopic,
      extraData: extraData,
    );
    if (newCtx == _ctx) return; 

    _normalResetTimer?.cancel();
    _ctx = newCtx;
    _streamCtrl.add(newCtx);
    notifyListeners();

    debugPrint('🎯 BubbleMode → ${mode.name}'
        '${detectedTopic != null ? " ($detectedTopic)" : ""}');

    
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
    if (lower.contains('task') || lower.contains('nhiệm vụ') || lower.contains('việc')) {
      return 'task';
    }
    if (lower.contains('meeting') || lower.contains('họp') || lower.contains('lịch họp')) {
      return 'meeting';
    }
    if (lower.contains('deadline') || lower.contains('hạn chót')) {
      return 'deadline';
    }
    if (lower.contains('file') || lower.contains('tài liệu') || lower.contains('gửi file')) {
      return 'file';
    }
    if (lower.contains('deploy') || lower.contains('release') || lower.contains('sprint')) {
      return 'engineering';
    }
    if (lower.contains('bug') || lower.contains('fix') || lower.contains('issue')) {
      return 'bug';
    }
    return 'work';
  }

  

  static double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(_rad(lat1)) * math.cos(_rad(lat2)) * math.pow(math.sin(dLon / 2), 2);
    final c = 2 * math.asin(math.sqrt(a.clamp(0.0, 1.0)));
    return R * c;
  }

  static double _rad(double deg) => deg * math.pi / 180;

  
  
  

  @override
  void dispose() {
    _streamCtrl.close();
    _mediaResetTimer?.cancel();
    _normalResetTimer?.cancel();
    super.dispose();
  }
}
