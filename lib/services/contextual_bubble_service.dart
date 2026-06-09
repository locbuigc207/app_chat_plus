// lib/services/contextual_bubble_service.dart
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/bubble_models.dart';
import '../models/models.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CONTEXTUAL BUBBLE SERVICE (Singleton, Business Logic)
// ═══════════════════════════════════════════════════════════════════════════

class ContextualBubbleService {
  ContextualBubbleService._();
  static final ContextualBubbleService instance = ContextualBubbleService._();

  static const int typeText = 0;
  static const int typeImage = 1;
  static const int typeVideo = 2;
  static const int typeAudio = 3;
  static const int typeFile = 4;
  static const int typeLocation = 5;
  static const int typeSticker = 6;
  static const int typeGif = 7;

  static const _mediaThreshold = 2;
  static const _mediaResetWindow = Duration(minutes: 5);
  static const _autoResetDelay = Duration(minutes: 15);
  static const _locationResetDelay = Duration(minutes: 30);

  final _contexts = <String, BubbleContext>{};
  final _controllers = <String, StreamController<BubbleContext>>{};

  final _mediaCounts = <String, int>{};
  final _mediaTimers = <String, Timer>{};
  final _resetTimers = <String, Timer>{};

  static BubbleContext analyzeMessage({
    required String message,
    Map<String, dynamic>? extraData,
  }) {
    final lower = message.toLowerCase();

    if (_matchesAny(lower, _locationPatterns)) {
      return BubbleContext(
        mode: BubbleMode.location,
        extraData: {
          if (_extractMapsUrl(message) != null)
            'mapsUrl': _extractMapsUrl(message),
          ...?extraData,
        },
        updatedAt: DateTime.now(),
      );
    }

    if (_matchesAny(lower, _securePatterns)) {
      return BubbleContext(mode: BubbleMode.secure, updatedAt: DateTime.now());
    }

    if (_matchesAny(lower, _mediaPatterns)) {
      return BubbleContext(mode: BubbleMode.media, updatedAt: DateTime.now());
    }

    for (final entry in _workTopics.entries) {
      if (_matchesAny(lower, entry.value)) {
        return BubbleContext(
          mode: BubbleMode.work,
          detectedTopic: entry.key,
          updatedAt: DateTime.now(),
        );
      }
    }

    if (_matchesAny(lower, _sharedPatterns)) {
      return BubbleContext(mode: BubbleMode.shared, updatedAt: DateTime.now());
    }

    return BubbleContext(mode: BubbleMode.normal, updatedAt: DateTime.now());
  }

  BubbleContext getContext(String conversationId) =>
      _contexts[conversationId] ?? BubbleContext(updatedAt: DateTime.now());

  BubbleContext updateContext({
    required String conversationId,
    required String message,
    int messageType = typeText,
    Map<String, dynamic>? extraData,
  }) {
    final prev = getContext(conversationId);
    BubbleContext next;

    if (messageType == typeLocation) {
      next = BubbleContext(
        mode: BubbleMode.location,
        extraData: {
          if (_extractMapsUrl(message) != null)
            'mapsUrl': _extractMapsUrl(message),
          ...?extraData,
        },
        updatedAt: DateTime.now(),
      );
    } else if (messageType == typeFile) {
      next = BubbleContext(
        mode: BubbleMode.work,
        detectedTopic: 'file',
        extraData: {'fileName': extraData?['fileName']},
        updatedAt: DateTime.now(),
      );
    } else if (messageType == typeImage ||
        messageType == typeVideo ||
        messageType == typeAudio ||
        messageType == typeGif) {
      int count = (_mediaCounts[conversationId] ?? 0) + 1;
      _mediaCounts[conversationId] = count;

      _mediaTimers[conversationId]?.cancel();
      _mediaTimers[conversationId] = Timer(_mediaResetWindow, () {
        _mediaCounts[conversationId] = 0;
        if (getContext(conversationId).mode == BubbleMode.media) {
          _scheduleAutoReset(conversationId, _autoResetDelay);
        }
      });

      if (count >= _mediaThreshold) {
        next = BubbleContext(
          mode: BubbleMode.media,
          extraData: {'mediaCount': count, 'lastType': messageType},
          updatedAt: DateTime.now(),
        );
      } else {
        next = prev;
      }
    } else {
      next = analyzeMessage(message: message, extraData: extraData);
    }

    if (next.mode != BubbleMode.secure && prev.mode == BubbleMode.secure) {
      next = prev;
    }
    if (next.mode != BubbleMode.shared &&
        prev.mode == BubbleMode.shared &&
        next.mode != BubbleMode.normal) {
      next = prev;
    }

    if (prev.mode != next.mode || prev.detectedTopic != next.detectedTopic) {
      _contexts[conversationId] = next;
      _controllers[conversationId]?.add(next);

      if (next.mode == BubbleMode.location) {
        _scheduleAutoReset(conversationId, _locationResetDelay);
      } else if (next.mode != BubbleMode.secure &&
          next.mode != BubbleMode.shared &&
          next.mode != BubbleMode.normal) {
        _scheduleAutoReset(conversationId, _autoResetDelay);
      }
    }

    return next;
  }

  void updateLocationData({
    required String conversationId,
    required double myLat,
    required double myLng,
    required double peerLat,
    required double peerLng,
    String? peerName,
    String? mapsUrl,
  }) {
    final ctx = getContext(conversationId);
    if (ctx.mode != BubbleMode.location) return;

    final distance = _haversineKm(myLat, myLng, peerLat, peerLng);
    final updatedCtx = ctx.copyWith(
      extraData: {
        ...?ctx.extraData,
        'myLat': myLat,
        'myLng': myLng,
        'peerLat': peerLat,
        'peerLng': peerLng,
        'distance': distance,
        if (peerName != null) 'peerName': peerName,
        if (mapsUrl != null) 'mapsUrl': mapsUrl,
      },
      updatedAt: DateTime.now(),
    );

    overrideContext(conversationId, updatedCtx);
  }

  void _scheduleAutoReset(String conversationId, Duration delay) {
    _resetTimers[conversationId]?.cancel();
    _resetTimers[conversationId] = Timer(delay, () {
      final ctx = getContext(conversationId);
      if (ctx.mode != BubbleMode.secure && ctx.mode != BubbleMode.shared) {
        overrideContext(conversationId,
            BubbleContext(mode: BubbleMode.normal, updatedAt: DateTime.now()));
      }
    });
  }

  Stream<BubbleContext> contextStream(String conversationId) {
    _controllers.putIfAbsent(
      conversationId,
      () => StreamController<BubbleContext>.broadcast(),
    );
    return _controllers[conversationId]!.stream;
  }

  void overrideContext(String conversationId, BubbleContext ctx) {
    _contexts[conversationId] = ctx;
    _controllers[conversationId]?.add(ctx);
  }

  void clearContext(String conversationId) {
    _contexts.remove(conversationId);
    _controllers[conversationId]?.close();
    _controllers.remove(conversationId);
    _resetTimers[conversationId]?.cancel();
    _resetTimers.remove(conversationId);
    _mediaTimers[conversationId]?.cancel();
    _mediaTimers.remove(conversationId);
    _mediaCounts.remove(conversationId);
  }

  void dispose() {
    for (final c in _controllers.values) {
      c.close();
    }
    _controllers.clear();
    _contexts.clear();

    for (final t in _resetTimers.values) {
      t.cancel();
    }
    _resetTimers.clear();

    for (final t in _mediaTimers.values) {
      t.cancel();
    }
    _mediaTimers.clear();
    _mediaCounts.clear();
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

  static final _googleMapsPattern = RegExp(
      r'https?://(?:www\.)?(?:google\.com/maps|goo\.gl/maps|maps\.app\.goo\.gl)[^\s]*');

  static String? _extractMapsUrl(String content) {
    final match = _googleMapsPattern.firstMatch(content);
    return match?.group(0);
  }

  static const _locationPatterns = [
    'maps.google',
    'maps.apple',
    'waze.com',
    'location:',
    '📍',
    'latitude',
    'longitude',
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
    'tọa độ'
  ];

  static const _securePatterns = [
    '🔒',
    'secret',
    'bí mật',
    'mã hóa',
    'encrypted',
    'confidential',
    'bảo mật',
    'private',
  ];

  static const _mediaPatterns = [
    '🎵',
    '🎶',
    '🎸',
    '🎤',
    '🎬',
    '🎥',
    'youtube.com',
    'youtu.be',
    'spotify.com',
    'tiktok.com',
    'soundcloud.com',
    'đang phát',
    'now playing',
  ];

  static const _sharedPatterns = [
    'figma.com',
    'miro.com',
    'notion.so',
    'docs.google',
    'shared ',
    'chia sẻ',
    'cùng xem',
    'collaborate',
    'whiteboard',
  ];

  static const _workTopics = <String, List<String>>{
    'task': [
      'task',
      'tasks',
      'todo',
      'công việc',
      'nhiệm vụ',
      'ticket',
      'tickets',
      'jira',
      'asana',
      'trello',
      'okr',
      'kpi',
      'action item',
      'deliverable'
    ],
    'meeting': [
      'meeting',
      'meetings',
      'họp',
      'cuộc họp',
      'zoom',
      'teams',
      'google meet',
      'schedule',
      'lịch họp',
      'calendar'
    ],
    'deadline': [
      'deadline',
      'deadlines',
      'hạn chót',
      'due date',
      'due by',
      'submit by',
      'nộp trước',
      'urgent',
      'khẩn cấp',
      'khẩn',
      'quan trọng',
      'cần làm ngay',
      'asap',
      'priority'
    ],
    'bug': [
      'bug',
      'lỗi',
      'error',
      'crash',
      'issue',
      'issues',
      'fix',
      'patch',
      'hotfix',
      'regression'
    ],
    'engineering': [
      'deploy',
      'deployment',
      'release',
      'build',
      'ci/cd',
      'pull request',
      'pr ',
      'merge',
      'code review',
      'staging',
      'production',
      'rollback',
      'sprint',
      'milestone'
    ],
    'file': [
      '.pdf',
      '.docx',
      '.xlsx',
      '.pptx',
      '.zip',
      'drive.google',
      'dropbox',
      'file://',
      'tải lên',
      'gửi file',
      'nộp báo cáo',
      'tài liệu',
      'báo cáo',
      'report',
      'reports'
    ],
  };

  static bool _matchesAny(String lower, List<String> patterns) =>
      patterns.any((p) => lower.contains(p));
}

// ═══════════════════════════════════════════════════════════════════════════
// BUBBLE CONTEXT PROVIDER WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class BubbleContextProvider extends StatefulWidget {
  final String conversationId;
  final Widget child;
  final BubbleContext initialContext;

  const BubbleContextProvider({
    super.key,
    required this.conversationId,
    required this.child,
    this.initialContext = const BubbleContext(),
  });

  @override
  State<BubbleContextProvider> createState() => _BubbleContextProviderState();

  static BubbleContext of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_BubbleContextScope>()
          ?.context ??
      BubbleContext(updatedAt: DateTime.now());
}

class _BubbleContextProviderState extends State<BubbleContextProvider> {
  late BubbleContext _current;
  StreamSubscription<BubbleContext>? _sub;

  @override
  void initState() {
    super.initState();
    _current = ContextualBubbleService.instance
                .getContext(widget.conversationId)
                .mode ==
            BubbleMode.normal
        ? widget.initialContext
        : ContextualBubbleService.instance.getContext(widget.conversationId);

    _sub = ContextualBubbleService.instance
        .contextStream(widget.conversationId)
        .listen((ctx) {
      if (mounted) setState(() => _current = ctx);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _BubbleContextScope(
        context: _current,
        child: widget.child,
      );
}

class _BubbleContextScope extends InheritedWidget {
  final BubbleContext context;
  const _BubbleContextScope({required this.context, required super.child});

  @override
  bool updateShouldNotify(_BubbleContextScope old) =>
      old.context.mode != context.mode ||
      old.context.detectedTopic != context.detectedTopic ||
      old.context.updatedAt != context.updatedAt;
}
