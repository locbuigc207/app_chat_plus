import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_chat_demo/services/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChatProvider {
  final SharedPreferences prefs;
  final FirebaseFirestore firebaseFirestore;
  final FirebaseStorage firebaseStorage;

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

    // BẢO MẬT: Mã hóa tin nhắn trước khi lưu lên Firestore
    final String secureContent = type == TypeMessage.text
        ? EncryptionService().encryptMessage(content, groupChatId)
        : content; // Không mã hóa nếu là ảnh/file (lưu URL gốc)

    final messageChat = MessageChat(
      idFrom: currentUserId,
      idTo: peerId,
      timestamp: DateTime.now().millisecondsSinceEpoch.toString(),
      content: secureContent, // Sử dụng nội dung đã mã hóa
      type: type,
    );

    FirebaseFirestore.instance.runTransaction((transaction) async {
      transaction.set(
        documentReference,
        messageChat.toJson(),
      );
    });

    // Cập nhật tin nhắn cuối cùng trong conversation (dùng content gốc để hiển thị preview)
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
        // Nếu conversation chưa tồn tại thì tạo mới
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
    // Gọi API của Gemini (truyền nội dung gốc, không mã hóa)
    final String aiReply = await _geminiService.sendMessage(userMessage, []);

    // BẢO MẬT: Mã hóa phản hồi của AI trước khi lưu
    final String secureAiReply =
        EncryptionService().encryptMessage(aiReply, groupChatId);

    final DocumentReference aiDocRef = firebaseFirestore
        .collection(FirestoreConstants.pathMessageCollection)
        .doc(groupChatId)
        .collection(groupChatId)
        .doc(DateTime.now().millisecondsSinceEpoch.toString());

    final MessageChat aiMessage = MessageChat(
      idFrom: AppConstants.aiAssistantId,
      idTo: currentUserId,
      timestamp: DateTime.now().millisecondsSinceEpoch.toString(),
      content: secureAiReply, // Lưu phản hồi AI đã mã hóa
      type: TypeMessage.text,
    );

    firebaseFirestore.runTransaction((transaction) async {
      transaction.set(aiDocRef, aiMessage.toJson());
    });

    // Cập nhật preview conversation với nội dung gốc (chưa mã hóa)
    _updateConversationLastMessage(groupChatId, aiReply, TypeMessage.text);
  }
}
