import 'dart:ui' show Color;

import 'package:cloud_firestore/cloud_firestore.dart';





enum StoryType { image, text, video }

enum StoryPrivacy { everyone, friends }





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





class Story {
  final String id;
  final String userId;
  final String userName;
  final String userPhotoUrl;
  final StoryType type;
  final String? mediaUrl;
  final String? thumbnailUrl;
  final String? textContent;
  final String? caption;
  final Color? backgroundColor;
  final Color? textColor;
  final String? fontFamily;
  final double fontSize;
  final DateTime createdAt;
  final DateTime expiresAt;
  final List<StoryView> views;
  final List<StoryReaction> reactions;
  final StoryPrivacy privacy;
  final bool isDeleted;
  final Duration? videoDuration;

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
    required this.createdAt,
    required this.expiresAt,
    this.views = const [],
    this.reactions = const [],
    this.privacy = StoryPrivacy.friends,
    this.isDeleted = false,
    this.videoDuration,
  });

  

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isActive => !isExpired && !isDeleted;
  int get viewCount => views.length;

  Duration get remainingTime {
    final r = expiresAt.difference(DateTime.now());
    return r.isNegative ? Duration.zero : r;
  }

  
  Duration get displayDuration {
    if (type == StoryType.video && videoDuration != null) {
      return videoDuration!.clamp(
        const Duration(seconds: 1),
        const Duration(seconds: 15),
      );
    }
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
        'backgroundColor': backgroundColor?.toARGB32(),
        'textColor': textColor?.toARGB32(),
        'fontFamily': fontFamily,
        'fontSize': fontSize,
        'createdAt': createdAt.millisecondsSinceEpoch.toString(),
        'expiresAt': expiresAt.millisecondsSinceEpoch.toString(),
        'views': views.map((v) => v.toJson()).toList(),
        'reactions': reactions.map((r) => r.toJson()).toList(),
        'privacy': privacy.index,
        'isDeleted': isDeleted,
        if (videoDuration != null) 'videoDurationMs': videoDuration!.inMilliseconds,
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

    return Story(
      id: id,
      userId: data['userId']?.toString() ?? '',
      userName: data['userName']?.toString() ?? '',
      userPhotoUrl: data['userPhotoUrl']?.toString() ?? '',
      type: StoryType.values[safeIdx(data['type'], StoryType.values.length - 1)],
      mediaUrl: data['mediaUrl']?.toString(),
      thumbnailUrl: data['thumbnailUrl']?.toString(),
      textContent: data['textContent']?.toString(),
      caption: data['caption']?.toString(),
      backgroundColor: parseColor(data['backgroundColor']),
      textColor: parseColor(data['textColor']),
      fontFamily: data['fontFamily']?.toString(),
      fontSize: (data['fontSize'] as num?)?.toDouble() ?? 28.0,
      createdAt: _parseDate(data['createdAt']),
      expiresAt: _parseDate(data['expiresAt']),
      views: views,
      reactions: reactions,
      privacy: StoryPrivacy.values[safeIdx(data['privacy'], StoryPrivacy.values.length - 1)],
      isDeleted: data['isDeleted'] == true,
      videoDuration: data['videoDurationMs'] != null
          ? Duration(milliseconds: data['videoDurationMs'] as int)
          : null,
    );
  }

  Story copyWith({
    bool? isDeleted,
    List<StoryView>? views,
    List<StoryReaction>? reactions,
    String? caption,
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
        createdAt: createdAt,
        expiresAt: expiresAt,
        views: views ?? this.views,
        reactions: reactions ?? this.reactions,
        privacy: privacy,
        isDeleted: isDeleted ?? this.isDeleted,
        videoDuration: videoDuration,
      );
}





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

  Story? get latestStory => activeStories.isNotEmpty ? activeStories.last : null;

  bool hasUnseenStoriesBy(String viewerId) => activeStories.any((s) => !s.isViewedBy(viewerId));

  int unseenCountBy(String viewerId) => activeStories.where((s) => !s.isViewedBy(viewerId)).length;
}





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
