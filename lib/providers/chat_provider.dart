import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Import thêm các thành phần của Gemini AI Assistant
import '../services/gemini_service.dart';

class ChatProvider {
  final SharedPreferences prefs;
  final FirebaseFirestore firebaseFirestore;
  final FirebaseStorage firebaseStorage;

  // Khởi tạo instance của Gemini Service
  final GeminiService _geminiService = GeminiService();

  ChatProvider({
    required this.firebaseFirestore,
    required this.prefs,
    required this.firebaseStorage,
  });

  UploadTask uploadFile(File image, String fileName) {
    Reference reference = firebaseStorage.ref().child(fileName);
    UploadTask uploadTask = reference.putFile(image);
    return uploadTask;
  }

  Future<void> updateDataFirestore(
    String collectionPath,
    String docPath,
    Map<String, dynamic> dataNeedUpdate,
  ) {
    return firebaseFirestore
        .collection(collectionPath)
        .doc(docPath)
        .update(dataNeedUpdate);
  }

  Stream<QuerySnapshot> getChatStream(String groupChatId, int limit) {
    return firebaseFirestore
        .collection(FirestoreConstants.pathMessageCollection)
        .doc(groupChatId)
        .collection(groupChatId)
        .orderBy(FirestoreConstants.timestamp, descending: true)
        .limit(limit)
        .snapshots();
  }

  void sendMessage(
    String content,
    int type,
    String groupChatId,
    String currentUserId,
    String peerId,
  ) {
    final documentReference = firebaseFirestore
        .collection(FirestoreConstants.pathMessageCollection)
        .doc(groupChatId)
        .collection(groupChatId)
        .doc(DateTime.now().millisecondsSinceEpoch.toString());

    final messageChat = MessageChat(
      idFrom: currentUserId,
      idTo: peerId,
      timestamp: DateTime.now().millisecondsSinceEpoch.toString(),
      content: content,
      type: type,
    );

    FirebaseFirestore.instance.runTransaction((transaction) async {
      transaction.set(
        documentReference,
        messageChat.toJson(),
      );
    });

    // Update conversation last message
    _updateConversationLastMessage(groupChatId, content, type);

    // Xử lý tự động phản hồi nếu nhắn tin với Bot
    if (peerId == AppConstants.aiAssistantId && type == TypeMessage.text) {
      _handleAiResponse(content, groupChatId, currentUserId);
    }
  }

  Future<void> _updateConversationLastMessage(
    String conversationId,
    String message,
    int messageType,
  ) async {
    try {
      final conversationDoc = await firebaseFirestore
          .collection(FirestoreConstants.pathConversationCollection)
          .doc(conversationId)
          .get();

      if (conversationDoc.exists) {
        await firebaseFirestore
            .collection(FirestoreConstants.pathConversationCollection)
            .doc(conversationId)
            .update({
          FirestoreConstants.lastMessage: message,
          FirestoreConstants.lastMessageTime:
              DateTime.now().millisecondsSinceEpoch.toString(),
          FirestoreConstants.lastMessageType: messageType,
        });
      } else {
        // If conversation doesn't exist, create it
        final participants = conversationId.split('-');
        await firebaseFirestore
            .collection(FirestoreConstants.pathConversationCollection)
            .doc(conversationId)
            .set({
          FirestoreConstants.isGroup: false,
          FirestoreConstants.participants: participants,
          FirestoreConstants.lastMessage: message,
          FirestoreConstants.lastMessageTime:
              DateTime.now().millisecondsSinceEpoch.toString(),
          FirestoreConstants.lastMessageType: messageType,
        });
      }
    } catch (e) {
      print('Error updating conversation: $e');
    }
  }

  Future<void> _handleAiResponse(
      String userMessage, String groupChatId, String currentUserId) async {
    // Gọi API của Gemini
    String aiReply = await _geminiService.sendMessage(userMessage, []);

    // Lưu câu trả lời của AI vào lại Firestore
    DocumentReference aiDocRef = firebaseFirestore
        .collection(FirestoreConstants.pathMessageCollection)
        .doc(groupChatId)
        .collection(groupChatId)
        .doc(DateTime.now().millisecondsSinceEpoch.toString());

    MessageChat aiMessage = MessageChat(
      idFrom: AppConstants.aiAssistantId,
      idTo: currentUserId,
      timestamp: DateTime.now().millisecondsSinceEpoch.toString(),
      content: aiReply,
      type: TypeMessage
          .text, // Có thể chỉnh thành TypeMessage.text để tương thích UI hiện tại của bạn
    );

    firebaseFirestore.runTransaction((transaction) async {
      transaction.set(aiDocRef, aiMessage.toJson());
    });

    // Cập nhật lại tin nhắn cuối cùng bên ngoài màn danh sách (của AI)
    _updateConversationLastMessage(groupChatId, aiReply, TypeMessage.text);
  }
}
