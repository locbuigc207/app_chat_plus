import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_chat_demo/constants/constants.dart';

class Conversation {
  final String id;
  final bool isGroup;
  final List<String> participants;
  final String lastMessage;
  final String lastMessageTime;
  final int lastMessageType;
  final bool isPinned;
  final String? pinnedAt;
  final bool isMuted;
  final List<String> archivedBy;
  final String contextType;

  // [FIX] Lưu dữ liệu thô (có thể là int hoặc Map) để không bị lỗi cast exception
  final dynamic rawUnreadCount;
  final Map<String, dynamic>? lastReadBy;

  final String? peerPhotoUrl;
  final bool? isOnline;
  final String? peerName;
  final bool? isTyping;
  final bool? isSentByMe;
  final bool? isRead;
  final bool? isArchived;

  const Conversation({
    required this.id,
    required this.isGroup,
    required this.participants,
    required this.lastMessage,
    required this.lastMessageTime,
    required this.lastMessageType,
    this.isPinned = false,
    this.pinnedAt,
    this.isMuted = false,
    this.archivedBy = const [],
    this.contextType = 'default',
    this.rawUnreadCount = 0, // Đổi tên constructor parameter
    this.lastReadBy,
    this.peerPhotoUrl,
    this.isOnline = false,
    this.peerName,
    this.isTyping = false,
    this.isSentByMe = false,
    this.isRead = false,
    this.isArchived = false,
  });

  // [FIX] Getter trả về tổng số lượng tin nhắn chưa đọc dạng int an toàn
  int get unreadCount {
    if (rawUnreadCount is int) return rawUnreadCount as int;
    if (rawUnreadCount is Map) {
      int total = 0;
      (rawUnreadCount as Map).forEach((_, v) {
        if (v is int) total += v;
      });
      return total;
    }
    return 0;
  }

  // [FIX] Helper method lấy số lượng unread của 1 user cụ thể (Dùng cho home_page.dart)
  int getUnreadCountForUser(String userId) {
    if (rawUnreadCount is int) return rawUnreadCount as int;
    if (rawUnreadCount is Map) {
      final v = (rawUnreadCount as Map)[userId];
      if (v is int) return v;
    }
    return 0;
  }

  Map<String, dynamic> toJson() {
    return {
      FirestoreConstants.isGroup: isGroup,
      FirestoreConstants.participants: participants,
      FirestoreConstants.lastMessage: lastMessage,
      FirestoreConstants.lastMessageTime: lastMessageTime,
      FirestoreConstants.lastMessageType: lastMessageType,
      'isPinned': isPinned,
      'pinnedAt': pinnedAt,
      'isMuted': isMuted,
      'archivedBy': archivedBy,
      'contextType': contextType,
      'unreadCount': rawUnreadCount, // Giữ nguyên cấu trúc dữ liệu khi đẩy lên Firestore
      'lastReadBy': lastReadBy,
    };
  }

  factory Conversation.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;

    if (data == null) {
      debugPrint(
        '⚠️ Warning: Conversation document data is null for ID: ${doc.id}',
      );
      return Conversation(
        id: doc.id,
        isGroup: false,
        participants: const [],
        lastMessage: '',
        lastMessageTime: '0',
        lastMessageType: 0,
      );
    }

    String getStringValue(dynamic value, {String defaultValue = '0'}) {
      if (value == null) return defaultValue;
      if (value is String) return value;
      if (value is Timestamp) {
        try {
          return value.millisecondsSinceEpoch.toString();
        } catch (e) {
          return defaultValue;
        }
      }
      if (value is int) return value.toString();
      return defaultValue;
    }

    String? getOptionalStringValue(dynamic value) {
      if (value == null) return null;
      if (value is String) return value;
      if (value is Timestamp) {
        try {
          return value.millisecondsSinceEpoch.toString();
        } catch (e) {
          return null;
        }
      }
      if (value is int) return value.toString();
      return null;
    }

    List<String> getListString(dynamic value) {
      if (value == null) return [];
      if (value is List) {
        try {
          return value.map((e) => e.toString()).toList();
        } catch (e) {
          return [];
        }
      }
      return [];
    }

    try {
      return Conversation(
        id: doc.id,
        isGroup: data[FirestoreConstants.isGroup] ?? false,
        participants: getListString(data[FirestoreConstants.participants]),
        lastMessage: data[FirestoreConstants.lastMessage] ?? '',
        lastMessageTime: getStringValue(
          data[FirestoreConstants.lastMessageTime],
          defaultValue: '0',
        ),
        lastMessageType: data[FirestoreConstants.lastMessageType] ?? 0,
        isPinned: data['isPinned'] ?? false,
        pinnedAt: getOptionalStringValue(data['pinnedAt']),
        isMuted: data['isMuted'] ?? false,
        archivedBy: getListString(data['archivedBy']),
        contextType: data['contextType'] ?? 'default',
        rawUnreadCount: data['unreadCount'] ?? 0, // Nhận an toàn mọi định dạng (int hoặc Map)
        lastReadBy: data['lastReadBy'] != null
            ? Map<String, dynamic>.from(data['lastReadBy'] as Map)
            : null,
        isArchived: data['isArchived'] ?? false,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ Error parsing Conversation ${doc.id}: $e');
      debugPrint('Stacktrace: $stackTrace');

      return Conversation(
        id: doc.id,
        isGroup: false,
        participants: const [],
        lastMessage: '',
        lastMessageTime: '0',
        lastMessageType: 0,
      );
    }
  }
}