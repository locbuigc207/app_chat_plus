


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

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'userName': userName,
        'photoUrl': photoUrl,
        'viewedAt': viewedAt.millisecondsSinceEpoch.toString(),
      };

  factory StoryView.fromJson(Map<String, dynamic> json) => StoryView(
        userId: json['userId']?.toString() ?? '',
        userName: json['userName']?.toString() ?? '',
        photoUrl: json['photoUrl']?.toString() ?? '',
        viewedAt: DateTime.fromMillisecondsSinceEpoch(
          int.tryParse(json['viewedAt']?.toString() ?? '0') ?? 0,
        ),
      );
}





class Story {
  final String id;
  final String userId;
  final String userName;
  final String userPhotoUrl;
  final StoryType type;
  final String? mediaUrl;
  final String? textContent;
  final String? caption;
  final Color? backgroundColor;
  final Color? textColor;
  final String? fontFamily;
  final double fontSize;
  final DateTime createdAt;
  final DateTime expiresAt;
  final List<StoryView> views;
  final StoryPrivacy privacy;
  final bool isDeleted;

  const Story({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userPhotoUrl,
    required this.type,
    this.mediaUrl,
    this.textContent,
    this.caption,
    this.backgroundColor,
    this.textColor,
    this.fontFamily,
    this.fontSize = 28.0,
    required this.createdAt,
    required this.expiresAt,
    this.views = const [],
    this.privacy = StoryPrivacy.friends,
    this.isDeleted = false,
  });

  

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isActive => !isExpired && !isDeleted;
  int get viewCount => views.length;

  bool isViewedBy(String uid) => views.any((v) => v.userId == uid);

  Duration get remainingTime =>
      isExpired ? Duration.zero : expiresAt.difference(DateTime.now());

  

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'userName': userName,
        'userPhotoUrl': userPhotoUrl,
        'type': type.index,
        'mediaUrl': mediaUrl,
        'textContent': textContent,
        'caption': caption,
        'backgroundColor': backgroundColor?.value,
        'textColor': textColor?.value,
        'fontFamily': fontFamily,
        'fontSize': fontSize,
        'createdAt': createdAt.millisecondsSinceEpoch.toString(),
        'expiresAt': expiresAt.millisecondsSinceEpoch.toString(),
        'views': views.map((v) => v.toJson()).toList(),
        'privacy': privacy.index,
        'isDeleted': isDeleted,
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

    
    int parseTs(dynamic raw) => int.tryParse(raw?.toString() ?? '0') ?? 0;

    
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

    return Story(
      id: id,
      userId: data['userId']?.toString() ?? '',
      userName: data['userName']?.toString() ?? '',
      userPhotoUrl: data['userPhotoUrl']?.toString() ?? '',
      type:
          StoryType.values[safeIdx(data['type'], StoryType.values.length - 1)],
      mediaUrl: data['mediaUrl']?.toString(),
      textContent: data['textContent']?.toString(),
      caption: data['caption']?.toString(),
      backgroundColor: parseColor(data['backgroundColor']),
      textColor: parseColor(data['textColor']),
      fontFamily: data['fontFamily']?.toString(),
      fontSize: (data['fontSize'] as num?)?.toDouble() ?? 28.0,
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(parseTs(data['createdAt'])),
      expiresAt:
          DateTime.fromMillisecondsSinceEpoch(parseTs(data['expiresAt'])),
      views: views,
      privacy: StoryPrivacy
          .values[safeIdx(data['privacy'], StoryPrivacy.values.length - 1)],
      isDeleted: data['isDeleted'] == true,
    );
  }

  Story copyWith({
    bool? isDeleted,
    List<StoryView>? views,
    String? caption,
  }) =>
      Story(
        id: id,
        userId: userId,
        userName: userName,
        userPhotoUrl: userPhotoUrl,
        type: type,
        mediaUrl: mediaUrl,
        textContent: textContent,
        caption: caption ?? this.caption,
        backgroundColor: backgroundColor,
        textColor: textColor,
        fontFamily: fontFamily,
        fontSize: fontSize,
        createdAt: createdAt,
        expiresAt: expiresAt,
        views: views ?? this.views,
        privacy: privacy,
        isDeleted: isDeleted ?? this.isDeleted,
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

  bool hasUnseenStoriesBy(String viewerId) =>
      activeStories.any((s) => !s.isViewedBy(viewerId));

  Story? get latestStory =>
      activeStories.isNotEmpty ? activeStories.last : null;
}
