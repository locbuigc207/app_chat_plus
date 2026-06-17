import 'dart:ui' show Color;

import 'package:cloud_firestore/cloud_firestore.dart';

enum StoryType { image, text, video, boomerang }

enum StoryPrivacy { everyone, friends, closeFriends, onlyMe }

enum StoryTextEffect { none, typewriter, bounce, glow, neon, shadow3d }

enum StoryFilter {
  none,
  clarendon,
  gingham,
  moon,
  lark,
  reyes,
  juno,
  slumber,
  crema,
  ludwig,
  aden,
  perpetua,
}

// ─── StoryView ────────────────────────────────────────────────────────────────

class StoryView {
  final String userId;
  final String userName;
  final String photoUrl;
  final DateTime viewedAt;

  const StoryView({
    required this.userId,
    required this.userName,
    required this.photoUrl,
    required this.viewedAt,
  });

  factory StoryView.fromJson(Map<String, dynamic> json) => StoryView(
    userId: json['userId']?.toString() ?? '',
    userName: json['userName']?.toString() ?? '',
    photoUrl: json['photoUrl']?.toString() ?? '',
    viewedAt: _parseDate(json['viewedAt']),
  );

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'userName': userName,
    'photoUrl': photoUrl,
    'viewedAt': viewedAt.millisecondsSinceEpoch.toString(),
  };
}

// ─── StoryReaction ────────────────────────────────────────────────────────────

class StoryReaction {
  final String userId;
  final String userName;
  final String photoUrl;
  final String emoji;
  final DateTime reactedAt;

  const StoryReaction({
    required this.userId,
    required this.userName,
    required this.photoUrl,
    required this.emoji,
    required this.reactedAt,
  });

  factory StoryReaction.fromJson(Map<String, dynamic> json) => StoryReaction(
    userId: json['userId']?.toString() ?? '',
    userName: json['userName']?.toString() ?? '',
    photoUrl: json['photoUrl']?.toString() ?? '',
    emoji: json['emoji']?.toString() ?? '❤️',
    reactedAt: _parseDate(json['reactedAt']),
  );

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'userName': userName,
    'photoUrl': photoUrl,
    'emoji': emoji,
    'reactedAt': reactedAt.millisecondsSinceEpoch.toString(),
  };
}

// ─── StorySticker ─────────────────────────────────────────────────────────────

class StorySticker {
  final String
  type; // 'emoji', 'location', 'mention', 'hashtag', 'poll', 'countdown', 'music'
  final String content;
  final double x; // 0.0–1.0 relative position
  final double y;
  final double scale;
  final double rotation;
  final Map<String, dynamic> extra; // type-specific data

  const StorySticker({
    required this.type,
    required this.content,
    this.x = 0.5,
    this.y = 0.5,
    this.scale = 1.0,
    this.rotation = 0.0,
    this.extra = const {},
  });

  factory StorySticker.fromJson(Map<String, dynamic> json) => StorySticker(
    type: json['type']?.toString() ?? 'emoji',
    content: json['content']?.toString() ?? '',
    x: (json['x'] as num?)?.toDouble() ?? 0.5,
    y: (json['y'] as num?)?.toDouble() ?? 0.5,
    scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
    rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
    extra: (json['extra'] as Map<String, dynamic>?) ?? {},
  );

  Map<String, dynamic> toJson() => {
    'type': type,
    'content': content,
    'x': x,
    'y': y,
    'scale': scale,
    'rotation': rotation,
    'extra': extra,
  };

  StorySticker copyWith(
      {double? x, double? y, double? scale, double? rotation}) =>
      StorySticker(
        type: type,
        content: content,
        x: x ?? this.x,
        y: y ?? this.y,
        scale: scale ?? this.scale,
        rotation: rotation ?? this.rotation,
        extra: extra,
      );
}

// ─── StoryTextLayer ───────────────────────────────────────────────────────────

class StoryTextLayer {
  final String text;
  final Color color;
  final Color? backgroundColor;
  final String? fontFamily;
  final double fontSize;
  final double x;
  final double y;
  final double rotation;
  final StoryTextEffect effect;
  final bool isBold;
  final bool hasBackground;

  const StoryTextLayer({
    required this.text,
    required this.color,
    this.backgroundColor,
    this.fontFamily,
    this.fontSize = 28.0,
    this.x = 0.5,
    this.y = 0.5,
    this.rotation = 0.0,
    this.effect = StoryTextEffect.none,
    this.isBold = true,
    this.hasBackground = false,
  });

  factory StoryTextLayer.fromJson(Map<String, dynamic> json) {
    Color? parseColor(dynamic raw) {
      if (raw == null) return null;
      if (raw is int) return Color(raw);
      if (raw is double) return Color(raw.toInt());
      final s = raw?.toString();
      if (s != null) {
        final i = int.tryParse(s);
        if (i != null) return Color(i);
      }
      return null;
    }

    return StoryTextLayer(
      text: json['text']?.toString() ?? '',
      color: parseColor(json['color']) ?? const Color(0xFFFFFFFF),
      backgroundColor: parseColor(json['backgroundColor']),
      fontFamily: json['fontFamily']?.toString(),
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 28.0,
      x: (json['x'] as num?)?.toDouble() ?? 0.5,
      y: (json['y'] as num?)?.toDouble() ?? 0.5,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
      effect: StoryTextEffect.values[((json['effect'] as num?)?.toInt() ?? 0)
          .clamp(0, StoryTextEffect.values.length - 1)],
      isBold: json['isBold'] == true,
      hasBackground: json['hasBackground'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'text': text,
    'color': color.value,
    'backgroundColor': backgroundColor?.value,
    'fontFamily': fontFamily,
    'fontSize': fontSize,
    'x': x,
    'y': y,
    'rotation': rotation,
    'effect': effect.index,
    'isBold': isBold,
    'hasBackground': hasBackground,
  };
}

// ─── StoryMusicInfo ───────────────────────────────────────────────────────────

class StoryMusicInfo {
  final String title;
  final String artist;
  final String? artworkUrl;
  final String? previewUrl;
  final double startSeconds;

  const StoryMusicInfo({
    required this.title,
    required this.artist,
    this.artworkUrl,
    this.previewUrl,
    this.startSeconds = 0.0,
  });

  factory StoryMusicInfo.fromJson(Map<String, dynamic> json) => StoryMusicInfo(
    title: json['title']?.toString() ?? '',
    artist: json['artist']?.toString() ?? '',
    artworkUrl: json['artworkUrl']?.toString(),
    previewUrl: json['previewUrl']?.toString(),
    startSeconds: (json['startSeconds'] as num?)?.toDouble() ?? 0.0,
  );

  Map<String, dynamic> toJson() => {
    'title': title,
    'artist': artist,
    'artworkUrl': artworkUrl,
    'previewUrl': previewUrl,
    'startSeconds': startSeconds,
  };
}

// ─── Story ────────────────────────────────────────────────────────────────────

class Story {
  final String id;
  final String userId;
  final String userName;
  final String userPhotoUrl;
  final StoryType type;
  final String? mediaUrl;
  final String? thumbnailUrl;

  // Text story (legacy single-layer)
  final String? textContent;
  final String? caption;
  final Color? backgroundColor;
  final Color? textColor;
  final String? fontFamily;
  final double fontSize;

  // Rich layers
  final List<StoryTextLayer> textLayers;
  final List<StorySticker> stickers;

  // Visual
  final StoryFilter filter;
  final List<Color>? gradientColors; // for gradient backgrounds
  final String?
  backgroundPattern; // 'none', 'dots', 'lines', 'grid', 'sparkles'

  // Music
  final StoryMusicInfo? music;
  final String? audioMixUrl; // user-picked audio merged

  // Meta
  final DateTime createdAt;
  final DateTime expiresAt;
  final List<StoryView> views;
  final List<StoryReaction> reactions;
  final StoryPrivacy privacy;
  final bool isDeleted;
  final bool isArchived;
  final Duration? videoDuration;

  // Engagement
  final bool allowReplies;
  final bool allowReactions;
  final bool showViewCount;

  const Story({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userPhotoUrl,
    required this.type,
    this.mediaUrl,
    this.thumbnailUrl,
    this.textContent,
    this.caption,
    this.backgroundColor,
    this.textColor,
    this.fontFamily,
    this.fontSize = 28.0,
    this.textLayers = const [],
    this.stickers = const [],
    this.filter = StoryFilter.none,
    this.gradientColors,
    this.backgroundPattern,
    this.music,
    this.audioMixUrl,
    required this.createdAt,
    required this.expiresAt,
    this.views = const [],
    this.reactions = const [],
    this.privacy = StoryPrivacy.friends,
    this.isDeleted = false,
    this.isArchived = false,
    this.videoDuration,
    this.allowReplies = true,
    this.allowReactions = true,
    this.showViewCount = true,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isActive => !isExpired && !isDeleted;
  int get viewCount => views.length;

  Duration get remainingTime {
    final r = expiresAt.difference(DateTime.now());
    return r.isNegative ? Duration.zero : r;
  }

  double get remainingFraction {
    final total = expiresAt.difference(createdAt);
    final elapsed = DateTime.now().difference(createdAt);
    if (total.inSeconds == 0) return 0;
    return (elapsed.inSeconds / total.inSeconds).clamp(0.0, 1.0);
  }

  Duration get displayDuration {
    if (type == StoryType.video && videoDuration != null) {
      return videoDuration!
          .clamp(const Duration(seconds: 1), const Duration(seconds: 15));
    }
    if (type == StoryType.boomerang) return const Duration(seconds: 3);
    return const Duration(seconds: 5);
  }

  bool isViewedBy(String uid) => views.any((v) => v.userId == uid);

  String? reactionBy(String uid) {
    try {
      return reactions.firstWhere((r) => r.userId == uid).emoji;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'userName': userName,
    'userPhotoUrl': userPhotoUrl,
    'type': type.index,
    'mediaUrl': mediaUrl,
    'thumbnailUrl': thumbnailUrl,
    'textContent': textContent,
    'caption': caption,
    'backgroundColor': backgroundColor?.value,
    'textColor': textColor?.value,
    'fontFamily': fontFamily,
    'fontSize': fontSize,
    'textLayers': textLayers.map((l) => l.toJson()).toList(),
    'stickers': stickers.map((s) => s.toJson()).toList(),
    'filter': filter.index,
    'gradientColors': gradientColors?.map((c) => c.value).toList(),
    'backgroundPattern': backgroundPattern,
    'music': music?.toJson(),
    'audioMixUrl': audioMixUrl,
    'createdAt': createdAt.millisecondsSinceEpoch.toString(),
    'expiresAt': expiresAt.millisecondsSinceEpoch.toString(),
    'views': views.map((v) => v.toJson()).toList(),
    'reactions': reactions.map((r) => r.toJson()).toList(),
    'privacy': privacy.index,
    'isDeleted': isDeleted,
    'isArchived': isArchived,
    if (videoDuration != null)
      'videoDurationMs': videoDuration!.inMilliseconds,
    'allowReplies': allowReplies,
    'allowReactions': allowReactions,
    'showViewCount': showViewCount,
  };

  factory Story.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return Story.fromJson(data, doc.id);
  }

  factory Story.fromJson(Map<String, dynamic> data, String id) {
    Color? parseColor(dynamic raw) {
      if (raw == null) return null;
      if (raw is int) return Color(raw);
      if (raw is double) return Color(raw.toInt());
      final s = raw?.toString();
      if (s != null) {
        final i = int.tryParse(s);
        if (i != null) return Color(i);
      }
      return null;
    }

    int safeIdx(dynamic raw, int maxIdx) {
      final i = raw is int ? raw : int.tryParse(raw?.toString() ?? '0') ?? 0;
      return i.clamp(0, maxIdx);
    }

    final List<StoryView> views = [];
    final rawViews = data['views'];
    if (rawViews is List) {
      for (final v in rawViews) {
        if (v is Map<String, dynamic>) {
          try {
            views.add(StoryView.fromJson(v));
          } catch (_) {}
        }
      }
    }

    final List<StoryReaction> reactions = [];
    final rawReactions = data['reactions'];
    if (rawReactions is List) {
      for (final r in rawReactions) {
        if (r is Map<String, dynamic>) {
          try {
            reactions.add(StoryReaction.fromJson(r));
          } catch (_) {}
        }
      }
    }

    final List<StoryTextLayer> textLayers = [];
    final rawLayers = data['textLayers'];
    if (rawLayers is List) {
      for (final l in rawLayers) {
        if (l is Map<String, dynamic>) {
          try {
            textLayers.add(StoryTextLayer.fromJson(l));
          } catch (_) {}
        }
      }
    }

    final List<StorySticker> stickers = [];
    final rawStickers = data['stickers'];
    if (rawStickers is List) {
      for (final s in rawStickers) {
        if (s is Map<String, dynamic>) {
          try {
            stickers.add(StorySticker.fromJson(s));
          } catch (_) {}
        }
      }
    }

    List<Color>? gradientColors;
    final rawGradient = data['gradientColors'];
    if (rawGradient is List) {
      gradientColors =
          rawGradient.map((c) => parseColor(c)).whereType<Color>().toList();
      if (gradientColors.isEmpty) gradientColors = null;
    }

    StoryMusicInfo? music;
    final rawMusic = data['music'];
    if (rawMusic is Map<String, dynamic>) {
      try {
        music = StoryMusicInfo.fromJson(rawMusic);
      } catch (_) {}
    }

    return Story(
      id: id,
      userId: data['userId']?.toString() ?? '',
      userName: data['userName']?.toString() ?? '',
      userPhotoUrl: data['userPhotoUrl']?.toString() ?? '',
      type:
      StoryType.values[safeIdx(data['type'], StoryType.values.length - 1)],
      mediaUrl: data['mediaUrl']?.toString(),
      thumbnailUrl: data['thumbnailUrl']?.toString(),
      textContent: data['textContent']?.toString(),
      caption: data['caption']?.toString(),
      backgroundColor: parseColor(data['backgroundColor']),
      textColor: parseColor(data['textColor']),
      fontFamily: data['fontFamily']?.toString(),
      fontSize: (data['fontSize'] as num?)?.toDouble() ?? 28.0,
      textLayers: textLayers,
      stickers: stickers,
      filter: StoryFilter
          .values[safeIdx(data['filter'], StoryFilter.values.length - 1)],
      gradientColors: gradientColors,
      backgroundPattern: data['backgroundPattern']?.toString(),
      music: music,
      audioMixUrl: data['audioMixUrl']?.toString(),
      createdAt: _parseDate(data['createdAt']),
      expiresAt: _parseDate(data['expiresAt']),
      views: views,
      reactions: reactions,
      privacy: StoryPrivacy
          .values[safeIdx(data['privacy'], StoryPrivacy.values.length - 1)],
      isDeleted: data['isDeleted'] == true,
      // Đảm bảo parse chính xác giá trị isArchived (tránh lỗi ngầm định là false khi không có)
      isArchived: data['isArchived'] == true,
      videoDuration: data['videoDurationMs'] != null
          ? Duration(milliseconds: data['videoDurationMs'] as int)
          : null,
      allowReplies: data['allowReplies'] != false,
      allowReactions: data['allowReactions'] != false,
      showViewCount: data['showViewCount'] != false,
    );
  }

  Story copyWith({
    bool? isDeleted,
    bool? isArchived,
    List<StoryView>? views,
    List<StoryReaction>? reactions,
    String? caption,
    StoryPrivacy? privacy,
  }) =>
      Story(
        id: id,
        userId: userId,
        userName: userName,
        userPhotoUrl: userPhotoUrl,
        type: type,
        mediaUrl: mediaUrl,
        thumbnailUrl: thumbnailUrl,
        textContent: textContent,
        caption: caption ?? this.caption,
        backgroundColor: backgroundColor,
        textColor: textColor,
        fontFamily: fontFamily,
        fontSize: fontSize,
        textLayers: textLayers,
        stickers: stickers,
        filter: filter,
        gradientColors: gradientColors,
        backgroundPattern: backgroundPattern,
        music: music,
        audioMixUrl: audioMixUrl,
        createdAt: createdAt,
        expiresAt: expiresAt,
        views: views ?? this.views,
        reactions: reactions ?? this.reactions,
        privacy: privacy ?? this.privacy,
        isDeleted: isDeleted ?? this.isDeleted,
        isArchived: isArchived ?? this.isArchived,
        videoDuration: videoDuration,
        allowReplies: allowReplies,
        allowReactions: allowReactions,
        showViewCount: showViewCount,
      );
}

// ─── UserStories ──────────────────────────────────────────────────────────────

class UserStories {
  final String userId;
  final String userName;
  final String userPhotoUrl;
  final List<Story> stories;
  final bool isCurrentUser;

  const UserStories({
    required this.userId,
    required this.userName,
    required this.userPhotoUrl,
    required this.stories,
    this.isCurrentUser = false,
  });

  List<Story> get activeStories {
    final active = stories.where((s) => s.isActive).toList();
    active.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return active;
  }

  Story? get latestStory =>
      activeStories.isNotEmpty ? activeStories.last : null;

  bool hasUnseenStoriesBy(String viewerId) =>
      activeStories.any((s) => !s.isViewedBy(viewerId));

  int unseenCountBy(String viewerId) =>
      activeStories.where((s) => !s.isViewedBy(viewerId)).length;
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

DateTime _parseDate(dynamic value) {
  if (value == null) return DateTime.now();
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String) {
    final ms = int.tryParse(value);
    if (ms != null) return DateTime.fromMillisecondsSinceEpoch(ms);
    return DateTime.tryParse(value) ?? DateTime.now();
  }
  if (value is Timestamp) return value.toDate();
  return DateTime.now();
}

extension DurationClamp on Duration {
  Duration clamp(Duration min, Duration max) {
    if (this < min) return min;
    if (this > max) return max;
    return this;
  }
}