// lib/models/message_chat.dart (FIXED - Handle Timestamp properly)
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_chat_demo/constants/constants.dart';

class MessageChat {
  final String idFrom;
  final String idTo;
  final String timestamp;
  final String content;
  final int type;
  final bool isDeleted;
  final String? editedAt;
  final bool isPinned;
  final bool isRead;
  final String? readAt;

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
  });

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
    };
  }

  // ✅ FIX: Properly handle Timestamp conversion
  factory MessageChat.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;

    if (data == null) {
      throw Exception('Document data is null');
    }

    // ✅ Helper function to convert Timestamp to String
    String _getStringValue(dynamic value) {
      if (value == null)
        return DateTime.now().millisecondsSinceEpoch.toString();
      if (value is String) return value;
      if (value is Timestamp) return value.millisecondsSinceEpoch.toString();
      if (value is int) return value.toString();
      return DateTime.now().millisecondsSinceEpoch.toString();
    }

    String? _getOptionalStringValue(dynamic value) {
      if (value == null) return null;
      if (value is String) return value;
      if (value is Timestamp) return value.millisecondsSinceEpoch.toString();
      if (value is int) return value.toString();
      return null;
    }

    return MessageChat(
      idFrom: data[FirestoreConstants.idFrom] ?? '',
      idTo: data[FirestoreConstants.idTo] ?? '',
      timestamp: _getStringValue(data[FirestoreConstants.timestamp]),
      content: data[FirestoreConstants.content] ?? '',
      type: data[FirestoreConstants.type] ?? 0,
      isDeleted: data['isDeleted'] ?? false,
      editedAt: _getOptionalStringValue(data['editedAt']),
      isPinned: data['isPinned'] ?? false,
      isRead: data['isRead'] ?? false,
      readAt: _getOptionalStringValue(data['readAt']),
    );
  }
}
