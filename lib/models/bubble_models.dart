// lib/models/bubble_models.dart
// ✅ SHARED MODELS - Dùng chung cho tất cả bubble services

/// Bubble data model
class BubbleData {
  final String userId;
  final String userName;
  final String avatarUrl;
  final String? lastMessage;
  final DateTime timestamp;
  final int unreadCount;

  BubbleData({
    required this.userId,
    required this.userName,
    required this.avatarUrl,
    this.lastMessage,
    required this.timestamp,
    this.unreadCount = 0,
  });

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'userName': userName,
      'avatarUrl': avatarUrl,
      'lastMessage': lastMessage,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'unreadCount': unreadCount,
    };
  }

  factory BubbleData.fromJson(Map<String, dynamic> json) {
    return BubbleData(
      userId: json['userId'] ?? '',
      userName: json['userName'] ?? '',
      avatarUrl: json['avatarUrl'] ?? '',
      lastMessage: json['lastMessage'],
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        json['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
      ),
      unreadCount: json['unreadCount'] ?? 0,
    );
  }
}

/// Bubble click event
class BubbleClickEvent {
  final String userId;
  final String userName;
  final String avatarUrl;
  final String message;

  BubbleClickEvent({
    required this.userId,
    required this.userName,
    required this.avatarUrl,
    this.message = '',
  });
}

/// Mini chat message event
class MiniChatMessage {
  final String userId;
  final String message;
  final DateTime timestamp;

  MiniChatMessage({
    required this.userId,
    required this.message,
    required this.timestamp,
  });
}
