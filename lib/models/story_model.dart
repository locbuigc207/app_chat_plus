import 'dart:ui' show Color;

import 'package:cloud_firestore/cloud_firestore.dart';

enum StoryType { image, text, video }

enum StoryPrivacy { everyone, friends, custom }

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
        userId: json['userId'] ?? '',
        userName: json['userName'] ?? '',
        photoUrl: json['photoUrl'] ?? '',
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
  final String? mediaUrl; // For image/video stories
  final String? textContent; // For text stories
  final String? caption;
  final Color? backgroundColor; // For text stories
  final Color? textColor; // For text stories
  final String? fontFamily;
  final double fontSize;
  final DateTime createdAt;
  final DateTime expiresAt; // createdAt + 24h
  final List<StoryView> views;
  final StoryPrivacy privacy;
  final bool isDeleted;
  final String? musicUrl;
  final String? musicTitle;
  final List<String>? stickers;
  final Map<String, dynamic>? textAlignment;

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
    this.fontSize = 24.0,
    required this.createdAt,
    required this.expiresAt,
    this.views = const [],
    this.privacy = StoryPrivacy.friends,
    this.isDeleted = false,
    this.musicUrl,
    this.musicTitle,
    this.stickers,
    this.textAlignment,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  bool get isActive => !isExpired && !isDeleted;

  int get viewCount => views.length;

  bool isViewedBy(String userId) => views.any((v) => v.userId == userId);

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
        'musicUrl': musicUrl,
        'musicTitle': musicTitle,
        'stickers': stickers,
        'textAlignment': textAlignment,
      };

  factory Story.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Story.fromJson(data, doc.id);
  }

  factory Story.fromJson(Map<String, dynamic> data, String id) {
    int? bgColorValue =
        data['backgroundColor'] is int ? data['backgroundColor'] as int : null;
    int? textColorValue =
        data['textColor'] is int ? data['textColor'] as int : null;

    List<StoryView> views = [];
    if (data['views'] is List) {
      views = (data['views'] as List)
          .map((v) => StoryView.fromJson(v as Map<String, dynamic>))
          .toList();
    }

    return Story(
      id: id,
      userId: data['userId'] ?? '',
      userName: data['userName'] ?? '',
      userPhotoUrl: data['userPhotoUrl'] ?? '',
      type: StoryType.values[data['type'] as int? ?? 0],
      mediaUrl: data['mediaUrl'],
      textContent: data['textContent'],
      caption: data['caption'],
      backgroundColor: bgColorValue != null ? Color(bgColorValue) : null,
      textColor: textColorValue != null ? Color(textColorValue) : null,
      fontFamily: data['fontFamily'],
      fontSize: (data['fontSize'] as num?)?.toDouble() ?? 24.0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        int.tryParse(data['createdAt']?.toString() ?? '0') ?? 0,
      ),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        int.tryParse(data['expiresAt']?.toString() ?? '0') ?? 0,
      ),
      views: views,
      privacy: StoryPrivacy.values[data['privacy'] as int? ?? 1],
      isDeleted: data['isDeleted'] ?? false,
      musicUrl: data['musicUrl'],
      musicTitle: data['musicTitle'],
      stickers: data['stickers'] != null
          ? List<String>.from(data['stickers'] as List)
          : null,
      textAlignment: data['textAlignment'] as Map<String, dynamic>?,
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
        musicUrl: musicUrl,
        musicTitle: musicTitle,
        stickers: stickers,
        textAlignment: textAlignment,
      );
}

/// Groups stories by user
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

  List<Story> get activeStories => stories.where((s) => s.isActive).toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  bool get hasUnseenStories =>
      activeStories.isNotEmpty; // Simplified; full impl checks viewer

  bool hasUnseenStoriesBy(String viewerId) =>
      activeStories.any((s) => !s.isViewedBy(viewerId));

  Story? get latestStory =>
      activeStories.isNotEmpty ? activeStories.last : null;
}
