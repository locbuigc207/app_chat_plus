import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_chat_demo/services/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [ChatProvider] – Offline-First Architecture
///
/// Luồng GỬI:
///   sendMessage() → LocalDbService (Hive, status: pending)
///                 → SyncQueue (Hive)
///                 → SyncManager.startListening() [ngầm upload lên Firebase]
///
/// Luồng NHẬN:
///   listenToFirebaseChanges() → snapshot → decrypt → LocalDbService (Hive, status: sent)
///
/// Media (ảnh/video) vẫn upload trực tiếp lên Firebase Storage vì file nhị phân
/// không phù hợp để lưu vào Hive; chỉ URL cuối cùng được đưa vào queue.
class ChatProvider {
  // ------------------------------------------------------------------
  // Dependencies
  // ------------------------------------------------------------------

  final SharedPreferences prefs;
  final FirebaseFirestore firebaseFirestore;
  final FirebaseStorage firebaseStorage;

  final GeminiService _geminiService = GeminiService();
  final MediaCompressionService _compressionService = MediaCompressionService();
  final LocalDbService _localDb = LocalDbService();
  final SyncManager _syncManager = SyncManager();

  ChatProvider({
    required this.firebaseFirestore,
    required this.prefs,
    required this.firebaseStorage,
  });

  // =========================================================
  // UPLOAD FILE (public – dùng khi cần UploadTask để hiển thị progress)
  // =========================================================

  UploadTask uploadFile(File image, String fileName) {
    final reference = firebaseStorage.ref().child(fileName);
    return reference.putFile(image);
  }

  // =========================================================
  // UPLOAD FILE & GET URL (internal)
  // =========================================================

  Future<String> _uploadFileAndGetUrl(File file, String fileName) async {
    final reference = firebaseStorage.ref().child(fileName);
    final snapshot = await reference.putFile(file).whenComplete(() {});
    return snapshot.ref.getDownloadURL();
  }

  // =========================================================
  // UPDATE FIRESTORE DOCUMENT (utility)
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
  // GET CHAT STREAM  ← vẫn giữ cho compatibility; UI nên ưu tiên
  //                    stream từ LocalDbService thay vì Firebase trực tiếp.
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
  // HÀM 1: GỬI TIN NHẮN – OFFLINE-FIRST
  // =========================================================

  /// Gửi tin nhắn theo mô hình Offline-First:
  ///
  /// 1. Lưu **plaintext** vào Hive ngay lập tức (status: `pending`) → UI render tức thì.
  /// 2. Đẩy job vào **SyncQueue** (Hive) để SyncManager xử lý ngầm.
  /// 3. Kích hoạt [SyncManager.startListening()] – nếu có mạng thì upload ngay,
  ///    ngược lại job được giữ lại đến lần có kết nối.
  /// 4. Nếu peer là AI Assistant, đặt thêm job `ai_response` vào queue.
  ///
  /// **Lưu ý bảo mật**: Hive được mã hóa ổ đĩa ở tầng [LocalDbService],
  /// nên plaintext trong Hive vẫn được bảo vệ ở mức thiết bị.
  /// Mã hóa E2EE (AES payload) chỉ xảy ra trong [SyncManager] ngay trước
  /// khi ghi lên Firestore.
  Future<void> sendMessage(
    String content,
    int type,
    String groupChatId,
    String currentUserId,
    String peerId,
  ) async {
    final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();

    // ------------------------------------------------------------------
    // BƯỚC 1: Lưu vào Local DB (Hive) → UI hiện ngay, không chờ mạng
    // ------------------------------------------------------------------
    final Map<String, dynamic> localMessage = {
      'messageId': timestamp,
      'idFrom': currentUserId,
      'idTo': peerId,
      'timestamp': timestamp,
      'content': content, // plaintext – Hive đã mã hóa ổ đĩa
      'type': type,
      'status': MessageStatus.pending, // 'pending'
    };
    await _localDb.saveMessage(groupChatId, timestamp, localMessage);

    // Cập nhật preview conversation ngay lập tức (offline)
    await _localDb.updateConversationPreview(
      conversationId: groupChatId,
      lastMessage: content,
      lastMessageTime: timestamp,
      lastMessageType: type,
    );

    // ------------------------------------------------------------------
    // BƯỚC 2: Đẩy job vào Sync Queue
    // ------------------------------------------------------------------
    await _localDb.addToSyncQueue({
      'type': SyncJobType.sendMessage, // 'send_message'
      'payload': {
        'conversationId': groupChatId,
        'messageId': timestamp,
        'idFrom': currentUserId,
        'idTo': peerId,
        'timestamp': timestamp,
        'content': content,
        'messageType': type,
      },
    });

    // Nếu peer là AI Assistant → thêm job yêu cầu AI reply
    if (peerId == AppConstants.aiAssistantId && type == TypeMessage.text) {
      await _localDb.addToSyncQueue({
        'type': SyncJobType.aiResponse, // 'ai_response'
        'payload': {
          'conversationId': groupChatId,
          'currentUserId': currentUserId,
          'userMessage': content,
        },
      });
    }

    // ------------------------------------------------------------------
    // BƯỚC 3: Kích hoạt SyncManager
    // ------------------------------------------------------------------
    _syncManager.startListening();
  }

  // =========================================================
  // HÀM 2: LẮNG NGHE FIREBASE & CẬP NHẬT LOCAL DB
  // =========================================================

  /// Mở Firebase snapshot listener để kéo tin nhắn mới từ server về.
  ///
  /// Chỉ xử lý document chưa có trong Hive **hoặc** tin nhắn do người khác gửi
  /// (để cập nhật status từ `pending` → `sent` cho tin của mình nếu cần).
  ///
  /// Quy trình mỗi document:
  /// 1. Kiểm tra Hive – bỏ qua nếu đã tồn tại và không phải tin đến.
  /// 2. Giải mã E2EE nếu là văn bản.
  /// 3. Lưu/ghi-đè vào Hive (status: `sent`).
  void listenToFirebaseChanges(
    String groupChatId,
    String currentUserId,
    String peerId,
  ) {
    firebaseFirestore
        .collection(FirestoreConstants.pathMessageCollection)
        .doc(groupChatId)
        .collection(groupChatId)
        .orderBy(FirestoreConstants.timestamp, descending: true)
        .limit(50)
        .snapshots()
        .listen((snapshot) async {
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final String messageId = doc.id;
        final bool isFromMe = data['idFrom'] == currentUserId;

        // Bỏ qua nếu Hive đã có và là tin của chính mình
        // (tin của mình đã được lưu lúc sendMessage())
        if (isFromMe &&
            _localDb.messagesBox.containsKey('${groupChatId}_$messageId')) {
          // Chỉ cập nhật status → 'sent' nếu đang là 'pending'
          final existing =
              _localDb.messagesBox.get('${groupChatId}_$messageId');
          if (existing != null && existing['status'] == MessageStatus.pending) {
            await _localDb.saveMessage(
              groupChatId,
              messageId,
              {...existing, 'status': MessageStatus.sent},
            );
          }
          continue;
        }

        // ------------------------------------------------------------------
        // Giải mã E2EE tin nhắn kéo từ server
        // ------------------------------------------------------------------
        String plainText = data['content'] as String? ?? '';
        if (data['type'] == TypeMessage.text) {
          try {
            plainText = await EncryptionService().decryptPayload(
              plainText,
              groupChatId,
              [currentUserId, peerId],
              currentUserId,
            );
          } catch (e) {
            print('⚠️ Decrypt failed for $messageId: $e');
            // Giữ nguyên ciphertext nếu giải mã lỗi, tránh mất tin
          }
        }

        // ------------------------------------------------------------------
        // Lưu vào Hive
        // ------------------------------------------------------------------
        final Map<String, dynamic> updatedMessage = {
          'messageId': messageId,
          'idFrom': data['idFrom'],
          'idTo': data['idTo'],
          'timestamp': data['timestamp'],
          'content': plainText,
          'type': data['type'],
          'status': MessageStatus.sent,
        };
        await _localDb.saveMessage(groupChatId, messageId, updatedMessage);
      }
    });
  }

  // =========================================================
  // HÀM 3: GỬI MEDIA (ảnh / video) – direct-upload + loading callback
  // =========================================================

  /// Upload media trực tiếp lên Firebase Storage (file nhị phân không qua Hive),
  /// sau đó gọi [sendMessage] với URL → đưa URL vào Offline-First queue như bình thường.
  ///
  /// [onLoadingStatusChanged] được gọi với `true` khi bắt đầu xử lý và `false`
  /// khi hoàn tất (dù thành công hay lỗi) – dùng để bật/tắt loading indicator trên UI.
  ///
  /// Trả về `true` nếu thành công.
  Future<bool> sendMediaMessage({
    required File originalFile,
    required bool isVideo,
    required String groupChatId,
    required String currentUserId,
    required String peerId,
    required Function(bool) onLoadingStatusChanged,
  }) async {
    // 1. Kích hoạt Loading UI trên màn hình Chat
    onLoadingStatusChanged(true);

    try {
      File? fileToUpload;
      File? videoThumbnail;

      // 2. Nén file trước khi upload
      if (isVideo) {
        fileToUpload = await _compressionService.compressVideo(originalFile);
        videoThumbnail =
            await _compressionService.getVideoThumbnail(originalFile);
      } else {
        fileToUpload = await _compressionService.compressImage(originalFile);
      }

      if (fileToUpload == null) return false;

      // 3. Upload lên Firebase Storage
      final String ts = DateTime.now().millisecondsSinceEpoch.toString();
      final String ext = isVideo ? 'mp4' : 'jpg';

      final String fileUrl = await _uploadFileAndGetUrl(
        fileToUpload,
        '${FirestoreConstants.pathMediaStorage}/$groupChatId/$ts.$ext',
      );

      // 4. Tạo content payload (video kèm thumbnail URL)
      String contentPayload = fileUrl;
      if (isVideo && videoThumbnail != null) {
        final String thumbnailUrl = await _uploadFileAndGetUrl(
          videoThumbnail,
          '${FirestoreConstants.pathMediaStorage}/$groupChatId/${ts}_thumb.jpg',
        );
        contentPayload = '$fileUrl|$thumbnailUrl';
      }

      // 5. Gửi qua Offline-First pipeline (URL media không mã hóa E2EE)
      await sendMessage(
        contentPayload,
        isVideo ? TypeMessage.video : TypeMessage.image,
        groupChatId,
        currentUserId,
        peerId,
      );

      return true;
    } catch (e) {
      print('❌ Lỗi upload media: $e');
      return false;
    } finally {
      // 6. Tắt Loading UI dù thành công hay thất bại
      onLoadingStatusChanged(false);
      _compressionService.clearCache();
    }
  }
}

// =============================================================================
// CONSTANTS GỢI Ý – Thêm vào file constants tương ứng nếu chưa có
// =============================================================================

/// Trạng thái của một tin nhắn trong Local DB.
abstract class MessageStatus {
  static const String pending = 'pending'; // Chưa lên server
  static const String sent = 'sent'; // Đã có trên server
  static const String failed = 'failed'; // Gửi thất bại (mạng, server lỗi)
}

/// Loại job trong SyncQueue.
abstract class SyncJobType {
  static const String sendMessage = 'send_message';
  static const String aiResponse = 'ai_response';
}
