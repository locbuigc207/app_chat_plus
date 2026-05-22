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
  final MediaCompressionService _compressionService = MediaCompressionService();

  ChatProvider({
    required this.firebaseFirestore,
    required this.prefs,
    required this.firebaseStorage,
  });

  // =========================================================
  // UPLOAD FILE
  // =========================================================

  UploadTask uploadFile(File image, String fileName) {
    final reference = firebaseStorage.ref().child(fileName);
    return reference.putFile(image);
  }

  // =========================================================
  // UPLOAD FILE & GET URL (dùng nội bộ)
  // =========================================================

  Future<String> _uploadFileAndGetUrl(File file, String fileName) async {
    final reference = firebaseStorage.ref().child(fileName);
    final uploadTask = reference.putFile(file);
    final snapshot = await uploadTask.whenComplete(() {});
    return await snapshot.ref.getDownloadURL();
  }

  // =========================================================
  // UPDATE FIRESTORE DOCUMENT
  // =========================================================

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

  // =========================================================
  // GET CHAT STREAM
  // =========================================================

  Stream<QuerySnapshot> getChatStream(String groupChatId, int limit) {
    return firebaseFirestore
        .collection(FirestoreConstants.pathMessageCollection)
        .doc(groupChatId)
        .collection(groupChatId)
        .orderBy(FirestoreConstants.timestamp, descending: true)
        .limit(limit)
        .snapshots();
  }

  // =========================================================
  // SEND MEDIA MESSAGE (ảnh / video)
  // =========================================================

  /// Nén → Upload → Gửi tin nhắn media.
  /// Trả về `true` nếu thành công, `false` nếu nén thất bại.
  ///
  /// - Ảnh : nén qua [MediaCompressionService.compressImage], type = [TypeMessage.image]
  /// - Video: nén + lấy thumbnail, content = `"videoUrl|thumbnailUrl"`, type = [TypeMessage.video]
  /// - Firebase Storage URL đã có token bảo mật nên không áp dụng E2EE cho URL media.
  Future<bool> sendMediaMessage({
    required File originalFile,
    required bool isVideo,
    required String groupChatId,
    required String currentUserId,
    required String peerId,
  }) async {
    try {
      File? fileToUpload;
      File? videoThumbnail;

      // 1. Nén file
      if (isVideo) {
        fileToUpload = await _compressionService.compressVideo(originalFile);
        videoThumbnail =
            await _compressionService.getVideoThumbnail(originalFile);
      } else {
        fileToUpload = await _compressionService.compressImage(originalFile);
      }

      if (fileToUpload == null) return false; // Nén thất bại

      // 2. Upload file đã nén lên Firebase Storage
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String ext = isVideo ? 'mp4' : 'jpg';
      final String fileUrl = await _uploadFileAndGetUrl(
        fileToUpload,
        '${FirestoreConstants.pathMediaStorage}/$groupChatId/$timestamp.$ext',
      );

      // 3. Tạo content payload
      String contentPayload = fileUrl;
      if (isVideo && videoThumbnail != null) {
        final String thumbnailUrl = await _uploadFileAndGetUrl(
          videoThumbnail,
          '${FirestoreConstants.pathMediaStorage}/$groupChatId/${timestamp}_thumb.jpg',
        );
        contentPayload = '$fileUrl|$thumbnailUrl';
      }

      // 4. Gửi tin nhắn (URL media không áp dụng E2EE)
      await sendMessage(
        contentPayload,
        isVideo ? TypeMessage.video : TypeMessage.image,
        groupChatId,
        currentUserId,
        peerId,
      );

      // 5. Dọn dẹp bộ nhớ tạm
      _compressionService.clearCache();

      return true;
    } catch (e) {
      print('❌ Error sending media message: $e');
      _compressionService.clearCache();
      return false;
    }
  }

  // =========================================================
  // SEND MESSAGE
  // =========================================================

  /// Gửi tin nhắn với mã hóa E2EE đầu cuối (nếu là văn bản).
  /// - Văn bản : mã hóa qua [EncryptionService.encryptPayload] trước khi lưu.
  /// - File/ảnh: lưu URL gốc, không mã hóa.
  /// - Nếu peer là AI Assistant: kích hoạt luồng phản hồi tự động.
  Future<void> sendMessage(
    String content,
    int type,
    String groupChatId,
    String currentUserId,
    String peerId,
  ) async {
    final documentReference = firebaseFirestore
        .collection(FirestoreConstants.pathMessageCollection)
        .doc(groupChatId)
        .collection(groupChatId)
        .doc(DateTime.now().millisecondsSinceEpoch.toString());

    // 🔐 Mã hóa E2EE nếu là tin nhắn văn bản
    String encryptedContent = content;
    if (type == TypeMessage.text) {
      encryptedContent = await EncryptionService().encryptPayload(
        content,
        groupChatId,
        [currentUserId, peerId],
        currentUserId,
      );
    }

    final messageChat = MessageChat(
      idFrom: currentUserId,
      idTo: peerId,
      timestamp: DateTime.now().millisecondsSinceEpoch.toString(),
      content: encryptedContent,
      type: type,
    );

    FirebaseFirestore.instance.runTransaction((transaction) async {
      transaction.set(documentReference, messageChat.toJson());
    });

    // Cập nhật preview tin nhắn cuối (lưu nội dung gốc chưa mã hóa)
    _updateConversationLastMessage(groupChatId, content, type);

    // Kích hoạt phản hồi AI nếu đang chat với AI Assistant
    if (peerId == AppConstants.aiAssistantId && type == TypeMessage.text) {
      _handleAiResponse(content, groupChatId, currentUserId);
    }
  }

  // =========================================================
  // UPDATE CONVERSATION LAST MESSAGE
  // =========================================================

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
        // Document chưa tồn tại → tạo mới với thông tin participants
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
      print('❌ Error updating conversation: $e');
    }
  }

  // =========================================================
  // HANDLE AI RESPONSE
  // =========================================================

  Future<void> _handleAiResponse(
    String userMessage,
    String groupChatId,
    String currentUserId,
  ) async {
    // Lấy phản hồi từ Gemini
    final String aiReply = await _geminiService.sendMessage(userMessage, []);

    // 🔐 Mã hóa E2EE phản hồi AI trước khi lưu
    final String encryptedAiReply = await EncryptionService().encryptPayload(
      aiReply,
      groupChatId,
      [currentUserId, AppConstants.aiAssistantId],
      AppConstants.aiAssistantId,
    );

    final DocumentReference aiDocRef = firebaseFirestore
        .collection(FirestoreConstants.pathMessageCollection)
        .doc(groupChatId)
        .collection(groupChatId)
        .doc(DateTime.now().millisecondsSinceEpoch.toString());

    final MessageChat aiMessage = MessageChat(
      idFrom: AppConstants.aiAssistantId,
      idTo: currentUserId,
      timestamp: DateTime.now().millisecondsSinceEpoch.toString(),
      content: encryptedAiReply,
      type: TypeMessage.text,
    );

    firebaseFirestore.runTransaction((transaction) async {
      transaction.set(aiDocRef, aiMessage.toJson());
    });

    // Cập nhật preview tin nhắn cuối (lưu nội dung gốc chưa mã hóa)
    _updateConversationLastMessage(groupChatId, aiReply, TypeMessage.text);
  }
}
