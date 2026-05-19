
import 'package:cloud_firestore/cloud_firestore.dart';
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
  });

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
    };
  }

  factory Conversation.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;

    if (data == null) {
      throw Exception('Conversation document data is null');
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
      );
    } catch (e) {
      return Conversation(
        id: doc.id,
        isGroup: false,
        participants: [],
        lastMessage: '',
        lastMessageTime: '0',
        lastMessageType: 0,
      );
    }
  }
}
