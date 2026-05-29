// ignore_for_file: constant_identifier_names

import 'package:flutter/material.dart';





enum BubbleState { active, minimized, expanded, closing }

enum BubbleMode { normal, work, media, location, shared, secure }

enum MiniChatMessageType { text, image, file, voice, location }

enum BubbleImplementation { bubbleApi, windowManager, none, unknown }

enum MessageDeliveryStatus { sending, sent, delivered, read, failed }





class BubbleData {
  final String userId;
  final String userName;
  final String avatarUrl;
  final String? lastMessage;
  final DateTime timestamp;
  final int unreadCount;
  final bool isOnline;
  final BubbleState state;
  final String? lastMessageType; 

  const BubbleData({
    required this.userId,
    required this.userName,
    required this.avatarUrl,
    this.lastMessage,
    required this.timestamp,
    this.unreadCount = 0,
    this.isOnline = false,
    this.state = BubbleState.active,
    this.lastMessageType,
  });

  BubbleData copyWith({
    String? userId,
    String? userName,
    String? avatarUrl,
    String? lastMessage,
    DateTime? timestamp,
    int? unreadCount,
    bool? isOnline,
    BubbleState? state,
    String? lastMessageType,
  }) =>
      BubbleData(
        userId: userId ?? this.userId,
        userName: userName ?? this.userName,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        lastMessage: lastMessage ?? this.lastMessage,
        timestamp: timestamp ?? this.timestamp,
        unreadCount: unreadCount ?? this.unreadCount,
        isOnline: isOnline ?? this.isOnline,
        state: state ?? this.state,
        lastMessageType: lastMessageType ?? this.lastMessageType,
      );

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'userName': userName,
        'avatarUrl': avatarUrl,
        'lastMessage': lastMessage,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'unreadCount': unreadCount,
        'isOnline': isOnline,
        'state': state.name,
        'lastMessageType': lastMessageType,
      };

  factory BubbleData.fromJson(Map<String, dynamic> json) => BubbleData(
        userId: json['userId'] as String? ?? '',
        userName: json['userName'] as String? ?? '',
        avatarUrl: json['avatarUrl'] as String? ?? '',
        lastMessage: json['lastMessage'] as String?,
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          json['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
        ),
        unreadCount: json['unreadCount'] as int? ?? 0,
        isOnline: json['isOnline'] as bool? ?? false,
        state: BubbleState.values.firstWhere(
          (e) => e.name == (json['state'] as String?),
          orElse: () => BubbleState.active,
        ),
        lastMessageType: json['lastMessageType'] as String?,
      );

  bool get isValid => userId.isNotEmpty && userName.isNotEmpty;

  bool get isStale => DateTime.now().difference(timestamp).inMinutes >= 1440;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BubbleData && runtimeType == other.runtimeType && userId == other.userId;

  @override
  int get hashCode => userId.hashCode;

  @override
  String toString() => 'BubbleData(userId: $userId, userName: $userName, unread: $unreadCount)';
}





class BubbleClickEvent {
  final String userId;
  final String userName;
  final String avatarUrl;
  final String message;
  final DateTime timestamp;

  BubbleClickEvent({
    required this.userId,
    required this.userName,
    required this.avatarUrl,
    this.message = '',
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() => 'BubbleClickEvent(userId: $userId, userName: $userName)';
}





class MiniChatMessage {
  final String userId;
  final String message;
  final DateTime timestamp;
  final MiniChatMessageType type;
  final String? mediaUrl;

  MiniChatMessage({
    required this.userId,
    required this.message,
    required this.timestamp,
    this.type = MiniChatMessageType.text,
    this.mediaUrl,
  });
}





class BubbleContext {
  final BubbleMode mode;
  final String? detectedTopic;
  final Map<String, dynamic>? extraData;
  final DateTime? updatedAt; 

  const BubbleContext({
    this.mode = BubbleMode.normal,
    this.detectedTopic,
    this.extraData,
    this.updatedAt, 
  });

  BubbleContext copyWith({
    BubbleMode? mode,
    String? detectedTopic,
    Map<String, dynamic>? extraData,
    DateTime? updatedAt, 
  }) =>
      BubbleContext(
        mode: mode ?? this.mode,
        detectedTopic: detectedTopic ?? this.detectedTopic,
        extraData: extraData ?? this.extraData,
        updatedAt: updatedAt ?? this.updatedAt, 
      );

  static BubbleContext detectFromMessage(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('deadline') ||
        lower.contains('task') ||
        lower.contains('meeting') ||
        lower.contains('report')) {
      return BubbleContext(
        mode: BubbleMode.work,
        detectedTopic: 'task',
        updatedAt: DateTime.now(),
      );
    }
    if (lower.contains('maps.google') || lower.contains('location') || lower.contains('📍')) {
      return BubbleContext(
        mode: BubbleMode.location,
        updatedAt: DateTime.now(),
      );
    }
    if (lower.contains('🔒') || lower.contains('secret')) {
      return BubbleContext(
        mode: BubbleMode.secure,
        updatedAt: DateTime.now(),
      );
    }
    return BubbleContext(
      mode: BubbleMode.normal,
      updatedAt: DateTime.now(),
    );
  }

  @override
  String toString() => 'BubbleContext(mode: $mode, topic: $detectedTopic, updated: $updatedAt)';
}





class BubbleConfig {
  final double size;
  final bool showUnreadBadge;
  final bool autoHideAfterRead;
  final Duration maxAge;
  final bool persistAcrossSessions;
  final int maxBubbles;

  const BubbleConfig({
    this.size = 56.0,
    this.showUnreadBadge = true,
    this.autoHideAfterRead = false,
    this.maxAge = const Duration(hours: 24),
    this.persistAcrossSessions = true,
    this.maxBubbles = 5,
  });
}





@immutable
class BubbleReaction {
  final String emoji;
  final int count;
  final List<String> userIds;

  const BubbleReaction({
    required this.emoji,
    required this.count,
    this.userIds = const [],
  });

  BubbleReaction copyWith({int? count, List<String>? userIds}) => BubbleReaction(
        emoji: emoji,
        count: count ?? this.count,
        userIds: userIds ?? this.userIds,
      );

  Map<String, dynamic> toJson() => {
        'emoji': emoji,
        'count': count,
        'userIds': userIds,
      };

  factory BubbleReaction.fromJson(Map<String, dynamic> json) => BubbleReaction(
        emoji: json['emoji'] as String,
        count: json['count'] as int? ?? 0,
        userIds: (json['userIds'] as List?)?.cast<String>() ?? [],
      );
}
