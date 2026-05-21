import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_chat_demo/constants/constants.dart';

// =========================================================
// TYPE MESSAGE CONSTANTS
// =========================================================

/// Hằng số xác định loại nội dung tin nhắn.
/// Dùng thống nhất trong [MessageChat], [ChatProvider], [AdaptiveChatBubble].
class TypeMessage {
  const TypeMessage._();

  static const int text = 0;
  static const int image = 1;
  static const int sticker = 2;
  static const int file = 3;
}

// =========================================================
// MESSAGE CHAT MODEL
// =========================================================

class MessageChat {
  final String idFrom;
  final String idTo;
  final String timestamp;
  final String content;
  final int type;

  /// Tin nhắn đã bị xóa mềm hay chưa.
  final bool isDeleted;

  /// Thời điểm chỉnh sửa lần cuối (null nếu chưa chỉnh sửa).
  final String? editedAt;

  /// Tin nhắn có được ghim hay không.
  final bool isPinned;

  /// Người nhận đã đọc tin nhắn hay chưa.
  final bool isRead;

  /// Thời điểm đọc tin nhắn (null nếu chưa đọc).
  final String? readAt;

  /// Cờ cảnh báo scam do AI Backend phân tích.
  /// - `null` hoặc `false`: chưa cảnh báo / an toàn.
  /// - `true`: AI đã phát hiện dấu hiệu lừa đảo.
  ///
  /// Được kiểm tra trong [AdaptiveChatBubble] để quyết định
  /// có gọi [AIBackendService.analyzeDecryptedMessage] nữa hay không.
  final bool? scamWarning;

  const MessageChat({
    required this.idFrom,
    required this.idTo,
    required this.timestamp,
    required this.content,
    required this.type,
    this.isDeleted = false,
    this.editedAt,
    this.isPinned = false,
    this.isRead = false,
    this.readAt,
    this.scamWarning,
  });

  // =========================================================
  // SERIALIZATION
  // =========================================================

  Map<String, dynamic> toJson() {
    return {
      FirestoreConstants.idFrom: idFrom,
      FirestoreConstants.idTo: idTo,
      FirestoreConstants.timestamp: timestamp,
      FirestoreConstants.content: content,
      FirestoreConstants.type: type,
      'isDeleted': isDeleted,
      'editedAt': editedAt,
      'isPinned': isPinned,
      'isRead': isRead,
      'readAt': readAt,
      'scamWarning': scamWarning,
    };
  }

  // =========================================================
  // DESERIALIZATION
  // =========================================================

  factory MessageChat.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;

    if (data == null) {
      throw Exception('MessageChat.fromDocument: data is null (id: ${doc.id})');
    }

    return MessageChat(
      idFrom: data[FirestoreConstants.idFrom] as String? ?? '',
      idTo: data[FirestoreConstants.idTo] as String? ?? '',
      timestamp: _parseTimestamp(data[FirestoreConstants.timestamp]),
      content: data[FirestoreConstants.content] as String? ?? '',
      type: data[FirestoreConstants.type] as int? ?? TypeMessage.text,
      isDeleted: data['isDeleted'] as bool? ?? false,
      editedAt: _parseOptionalTimestamp(data['editedAt']),
      isPinned: data['isPinned'] as bool? ?? false,
      isRead: data['isRead'] as bool? ?? false,
      readAt: _parseOptionalTimestamp(data['readAt']),
      scamWarning: data['scamWarning'] as bool?,
    );
  }

  // =========================================================
  // COPY WITH
  // =========================================================

  MessageChat copyWith({
    String? content,
    String? editedAt,
    bool? isPinned,
    bool? isRead,
    String? readAt,
    bool? scamWarning,
  }) {
    return MessageChat(
      idFrom: idFrom,
      idTo: idTo,
      timestamp: timestamp,
      content: content ?? this.content,
      type: type,
      isDeleted: isDeleted,
      editedAt: editedAt ?? this.editedAt,
      isPinned: isPinned ?? this.isPinned,
      isRead: isRead ?? this.isRead,
      readAt: readAt ?? this.readAt,
      scamWarning: scamWarning ?? this.scamWarning,
    );
  }

  // =========================================================
  // PRIVATE HELPERS
  // =========================================================

  /// Chuyển đổi mọi kiểu timestamp từ Firestore về String milliseconds.
  static String _parseTimestamp(dynamic value) {
    if (value is String) return value;
    if (value is Timestamp) return value.millisecondsSinceEpoch.toString();
    if (value is int) return value.toString();
    return DateTime.now().millisecondsSinceEpoch.toString();
  }

  /// Như [_parseTimestamp] nhưng trả về null nếu không có giá trị.
  static String? _parseOptionalTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    if (value is Timestamp) return value.millisecondsSinceEpoch.toString();
    if (value is int) return value.toString();
    return null;
  }
}
