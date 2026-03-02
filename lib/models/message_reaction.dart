import 'package:cloud_firestore/cloud_firestore.dart';

class MessageReaction {
  final String messageId;
  final String userId;
  final String emoji;
  final String timestamp;

  const MessageReaction({
    required this.messageId,
    required this.userId,
    required this.emoji,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'messageId': messageId,
      'userId': userId,
      'emoji': emoji,
      'timestamp': timestamp,
    };
  }

  factory MessageReaction.fromDocument(DocumentSnapshot doc) {
    return MessageReaction(
      messageId: doc.get('messageId'),
      userId: doc.get('userId'),
      emoji: doc.get('emoji'),
      timestamp: doc.get('timestamp'),
    );
  }
}
