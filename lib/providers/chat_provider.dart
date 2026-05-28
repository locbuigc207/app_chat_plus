import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_chat_demo/services/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

// =============================================================================
// CONSTANTS
// =============================================================================

abstract class MessageStatus {
  static const String pending = 'pending';
  static const String sent = 'sent';
  static const String delivered = 'delivered';
  static const String failed = 'failed';
}

abstract class SyncJobType {
  static const String sendMessage = 'send_message';
  static const String aiResponse = 'ai_response';
}

// =============================================================================
// ChatProvider – Offline-First Architecture
// =============================================================================
//
// Luồng GỬI:
//   sendMessage() / sendPollMessage()
//     → LocalDbService (Hive, status: pending)
//     → SyncQueue (Hive)
//     → SyncManager.startListening() [ngầm upload lên Firebase]
//
// Luồng NHẬN:
//   listenToFirebaseChanges() → snapshot → decrypt → LocalDbService (status: sent)
//
// Poll:
//   sendPollMessage()  → đóng gói JSON → sendMessage (type = TypeMessage.poll)
//   votePoll()         → Firestore Transaction (robust, backwards-compatible)
//
// Media (ảnh/video): nén qua MediaCompressionService → upload Firebase Storage
//   → chỉ URL đưa vào queue.
// =============================================================================

class ChatProvider {
  // ──────────────────────────────────────────────────────────────────────────
  // Dependencies
  // ──────────────────────────────────────────────────────────────────────────

  final SharedPreferences prefs;
  final FirebaseFirestore firebaseFirestore;
  final FirebaseStorage firebaseStorage;

  final GeminiService _geminiService = GeminiService();

  /// MediaCompressionService dùng API mới (compressImageFile / compressVideoFile)
  final MediaCompressionService _compressionService = MediaCompressionService();

  final LocalDbService _localDb = LocalDbService();
  final SyncManager _syncManager = SyncManager();
  final _uuid = const Uuid();

  ChatProvider({
    required this.firebaseFirestore,
    required this.prefs,
    required this.firebaseStorage,
  });

  // ──────────────────────────────────────────────────────────────────────────
  // UPLOAD FILE (public – dùng khi cần UploadTask để show progress)
  // ──────────────────────────────────────────────────────────────────────────

  UploadTask uploadFile(File image, String fileName) {
    return firebaseStorage.ref().child(fileName).putFile(image);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // INTERNAL: upload & get download URL
  // ──────────────────────────────────────────────────────────────────────────

  Future<String> _uploadFileAndGetUrl(File file, String fileName) async {
    final ref = firebaseStorage.ref().child(fileName);
    final snapshot = await ref.putFile(file).whenComplete(() {});
    return snapshot.ref.getDownloadURL();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // PUBLIC: upload document (PDF/DOC/XLS/PPT…) & get URL
  // ──────────────────────────────────────────────────────────────────────────

  Future<String?> uploadFileAndGetUrl(File file, String groupId) async {
    try {
      final ts = DateTime.now().millisecondsSinceEpoch.toString();
      final originalName = file.path.split('/').last;
      final storagePath =
          '${FirestoreConstants.pathDocumentStorage}/$groupId/${ts}_$originalName';

      final uploadTask = firebaseStorage.ref().child(storagePath).putFile(
            file,
            SettableMetadata(contentType: _resolveContentType(originalName)),
          );

      final snapshot = await uploadTask.whenComplete(() {});
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      _log('❌ uploadFileAndGetUrl error: $e');
      return null;
    }
  }

  String _resolveContentType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    const mimeMap = <String, String>{
      'pdf': 'application/pdf',
      'doc': 'application/msword',
      'docx':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx':
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'ppt': 'application/vnd.ms-powerpoint',
      'pptx':
          'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'txt': 'text/plain',
    };
    return mimeMap[ext] ?? 'application/octet-stream';
  }

  // ──────────────────────────────────────────────────────────────────────────
  // GET CHAT STREAM
  // ──────────────────────────────────────────────────────────────────────────

  Stream<QuerySnapshot> getChatStream(String groupChatId, int limit) {
    return firebaseFirestore
        .collection(FirestoreConstants.pathMessageCollection)
        .doc(groupChatId)
        .collection(groupChatId)
        .orderBy(FirestoreConstants.timestamp, descending: true)
        .limit(limit)
        .snapshots();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // UPDATE FIRESTORE DOCUMENT (utility)
  // ──────────────────────────────────────────────────────────────────────────

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

  // ──────────────────────────────────────────────────────────────────────────
  // HÀM 1: GỬI TIN NHẮN VĂN BẢN / MEDIA – OFFLINE-FIRST
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> sendMessage(
    String content,
    int type,
    String groupChatId,
    String currentUserId,
    String peerId,
  ) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();

    // Bước 1: Lưu vào Local DB (Hive) – status: pending
    final localMessage = <String, dynamic>{
      'messageId': timestamp,
      'idFrom': currentUserId,
      'idTo': peerId,
      'timestamp': timestamp,
      'content': content,
      'type': type,
      'status': MessageStatus.pending,
    };

    await _localDb.saveMessage(groupChatId, timestamp, localMessage);
    await _localDb.updateConversationPreview(
      conversationId: groupChatId,
      lastMessage: content,
      lastMessageTime: timestamp,
      lastMessageType: type,
    );

    // Bước 2: Đẩy job vào Sync Queue
    await _localDb.addToSyncQueue({
      'type': SyncJobType.sendMessage,
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

    // Bước 2b: Nếu chat với AI → thêm job phản hồi AI
    if (peerId == AppConstants.aiAssistantId && type == TypeMessage.text) {
      await _localDb.addToSyncQueue({
        'type': SyncJobType.aiResponse,
        'payload': {
          'conversationId': groupChatId,
          'currentUserId': currentUserId,
          'userMessage': content,
        },
      });
    }

    // Bước 3: Kích hoạt SyncManager
    _syncManager.startListening();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // HÀM 2: GỬI POLL – OFFLINE-FIRST
  // ──────────────────────────────────────────────────────────────────────────

  /// Đóng gói dữ liệu poll thành JSON và gửi như một tin nhắn type=poll.
  ///
  /// [question]         Câu hỏi bình chọn
  /// [optionTexts]      Danh sách văn bản các lựa chọn (min 2, max 10)
  /// [isMultipleChoice] Cho phép chọn nhiều đáp án
  /// [isAnonymous]      Ẩn danh – không hiển thị userId đã bình chọn
  /// [expiresAt]        Thời hạn tự động đóng poll (null = không giới hạn)
  Future<void> sendPollMessage({
    required String question,
    required List<String> optionTexts,
    required String groupChatId,
    required String currentUserId,
    required String peerId,
    bool isMultipleChoice = false,
    bool isAnonymous = false,
    DateTime? expiresAt,
  }) async {
    assert(optionTexts.length >= 2, 'Poll phải có ít nhất 2 lựa chọn');
    assert(optionTexts.length <= 10, 'Poll tối đa 10 lựa chọn');

    final options = optionTexts
        .map(
          (text) => <String, dynamic>{
            'id': _uuid.v4(),
            'text': text.trim(),
            'votes': <String>[],
          },
        )
        .toList();

    final pollJson = jsonEncode(<String, dynamic>{
      'question': question.trim(),
      'options': options,
      'isMultipleChoice': isMultipleChoice,
      'isAnonymous': isAnonymous,
      'expiresAt': expiresAt?.toIso8601String(),
      'createdAt': DateTime.now().toIso8601String(),
    });

    await sendMessage(
      pollJson,
      TypeMessage.poll,
      groupChatId,
      currentUserId,
      peerId,
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // HÀM 3: VOTE POLL – Firestore Transaction (Robust)
  // ──────────────────────────────────────────────────────────────────────────

  /// Toggle vote của [userId] trên [optionId] trong poll [messageId].
  ///
  /// - Single-choice: xoá userId khỏi tất cả options cũ trước khi thêm vào mới.
  /// - Multiple-choice: chỉ toggle trên option đã chọn.
  /// - Tương thích ngược: đọc options từ JSON content hoặc root field.
  Future<void> votePoll({
    required String groupChatId,
    required String messageId,
    required String optionId,
    required String userId,
  }) async {
    final messageRef = firebaseFirestore
        .collection(FirestoreConstants.pathMessageCollection)
        .doc(groupChatId)
        .collection(groupChatId)
        .doc(messageId);

    try {
      await firebaseFirestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(messageRef);

        if (!snapshot.exists) {
          throw Exception('Poll message $messageId không tồn tại.');
        }

        final data = snapshot.data() as Map<String, dynamic>;

        // 1. Đọc & parse JSON content
        final contentStr = data[FirestoreConstants.content] as String? ?? '{}';
        Map<String, dynamic> pollData;
        try {
          pollData = jsonDecode(contentStr) as Map<String, dynamic>;
        } catch (_) {
          pollData = {};
        }

        // 2. Kiểm tra poll đã hết hạn chưa
        final expiresAtStr = pollData['expiresAt'] as String?;
        if (expiresAtStr != null) {
          final expiresAt = DateTime.tryParse(expiresAtStr);
          if (expiresAt != null && DateTime.now().isAfter(expiresAt)) {
            throw Exception('Poll đã hết hạn, không thể bình chọn.');
          }
        }

        // 3. Lấy options (hỗ trợ tương thích ngược)
        List<dynamic> rawOptions;
        if (pollData['options'] is List &&
            (pollData['options'] as List).isNotEmpty) {
          rawOptions = List.from(pollData['options'] as List);
        } else if (data['options'] is List) {
          rawOptions = List.from(data['options'] as List);
        } else {
          throw Exception('Dữ liệu options không hợp lệ.');
        }

        final options =
            rawOptions.map((o) => Map<String, dynamic>.from(o as Map)).toList();

        // 4. Tìm option đích
        final targetIndex =
            options.indexWhere((o) => o['id'].toString() == optionId);
        if (targetIndex == -1) {
          final ids = options.map((e) => e['id']).toList();
          throw Exception('Option $optionId không tồn tại. Hiện có: $ids');
        }

        // 5. Lấy config poll
        final isMultipleChoice = (pollData['isMultipleChoice'] ??
            data['isMultipleChoice'] ??
            false) as bool;

        // 6. Single-choice: clear tất cả votes cũ của user
        if (!isMultipleChoice) {
          for (final opt in options) {
            final votes = List<dynamic>.from(opt['votes'] as List? ?? []);
            votes.remove(userId);
            opt['votes'] = votes;
          }
        }

        // 7. Toggle vote trên option đích
        final targetVotes =
            List<dynamic>.from(options[targetIndex]['votes'] as List? ?? []);
        if (targetVotes.contains(userId)) {
          targetVotes.remove(userId);
        } else {
          targetVotes.add(userId);
        }
        options[targetIndex]['votes'] = targetVotes;

        // 8. Ghi lại: cập nhật JSON content + root options (backwards compat)
        pollData['options'] = options;

        transaction.update(messageRef, {
          FirestoreConstants.content: jsonEncode(pollData),
          'options': options,
          'lastVotedAt': FieldValue.serverTimestamp(),
        });
      });
    } on FirebaseException catch (e) {
      _log('❌ votePoll FirebaseException [${e.code}]: ${e.message}');
      rethrow;
    } catch (e) {
      _log('❌ votePoll error: $e');
      rethrow;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // HÀM 4: LẮNG NGHE FIREBASE & CẬP NHẬT LOCAL DB
  // ──────────────────────────────────────────────────────────────────────────

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
        final messageId = doc.id;
        final isFromMe = data['idFrom'] == currentUserId;
        final type = data['type'] as int? ?? TypeMessage.text;

        // Tin nhắn của mình → chỉ cập nhật status pending → sent
        if (isFromMe) {
          final key = '${groupChatId}_$messageId';
          if (_localDb.messagesBox.containsKey(key)) {
            final existing =
                _localDb.messagesBox.get(key) as Map<String, dynamic>?;
            if (existing != null &&
                existing['status'] == MessageStatus.pending) {
              await _localDb.saveMessage(
                groupChatId,
                messageId,
                {...existing, 'status': MessageStatus.sent},
              );
            }
          }
          continue;
        }

        // Tin nhắn của người khác → decrypt (chỉ text) → lưu local
        String content = data[FirestoreConstants.content] as String? ?? '';

        if (type == TypeMessage.text) {
          try {
            content = await EncryptionService().decryptPayload(
              content,
              groupChatId,
              [currentUserId, peerId],
              currentUserId,
            );
          } catch (e) {
            _log('⚠️ Decrypt failed for $messageId: $e');
          }
        }

        final updatedMessage = <String, dynamic>{
          'messageId': messageId,
          'idFrom': data['idFrom'],
          'idTo': data['idTo'],
          'timestamp': data['timestamp'],
          'content': content,
          'type': type,
          'status': MessageStatus.sent,
          if (data.containsKey('options')) 'options': data['options'],
          if (data.containsKey('isViewOnce')) 'isViewOnce': data['isViewOnce'],
          if (data.containsKey('isPinned')) 'isPinned': data['isPinned'],
          if (data.containsKey('isDeleted')) 'isDeleted': data['isDeleted'],
          if (data.containsKey('scamWarning'))
            'scamWarning': data['scamWarning'],
          if (data.containsKey('scamReason')) 'scamReason': data['scamReason'],
          if (data.containsKey('hasReminder'))
            'hasReminder': data['hasReminder'],
          if (data.containsKey('lastVotedAt'))
            'lastVotedAt': data['lastVotedAt']?.toString(),
        };

        await _localDb.saveMessage(groupChatId, messageId, updatedMessage);
      }
    });
  }

  // ──────────────────────────────────────────────────────────────────────────
  // HÀM 5: GỬI MEDIA (ảnh / video) – dùng API mới của MediaCompressionService
  // ──────────────────────────────────────────────────────────────────────────

  /// Nén, upload ảnh hoặc video và gửi tin nhắn media.
  ///
  /// [onProgress] nhận tiến trình nén video (0.0 → 1.0).
  /// Trả về `true` nếu thành công.
  Future<bool> sendMediaMessage({
    required File originalFile,
    required bool isVideo,
    required String groupChatId,
    required String currentUserId,
    required String peerId,
    required Function(bool) onLoadingStatusChanged,
    MediaCompressionConfig compressionConfig = MediaCompressionConfig.chat,
    void Function(double progress)? onCompressionProgress,
  }) async {
    onLoadingStatusChanged(true);

    try {
      final ts = DateTime.now().millisecondsSinceEpoch.toString();

      // ── Nén file ──────────────────────────────────────────────────────────
      final File compressedFile;
      if (isVideo) {
        compressedFile = await _compressionService.compressVideoFile(
          originalFile,
          config: compressionConfig,
          onProgress: onCompressionProgress,
        );
      } else {
        compressedFile = await _compressionService.compressImageFile(
          originalFile,
          config: compressionConfig,
        );
      }

      // ── Upload file chính ─────────────────────────────────────────────────
      final ext = isVideo ? 'mp4' : 'jpg';
      final storagePath =
          '${FirestoreConstants.pathMediaStorage}/$groupChatId/$ts.$ext';

      final fileUrl = await _uploadFileAndGetUrl(compressedFile, storagePath);

      // ── Tạo payload (video có thêm thumbnail) ────────────────────────────
      String contentPayload = fileUrl;

      if (isVideo) {
        final thumbnail =
            await _compressionService.getVideoThumbnail(originalFile);
        if (thumbnail != null) {
          final thumbPath =
              '${FirestoreConstants.pathMediaStorage}/$groupChatId/${ts}_thumb.jpg';
          final thumbUrl = await _uploadFileAndGetUrl(thumbnail, thumbPath);
          contentPayload = '$fileUrl|$thumbUrl';
        }
      }

      // ── Gửi tin nhắn ──────────────────────────────────────────────────────
      await sendMessage(
        contentPayload,
        isVideo ? TypeMessage.video : TypeMessage.image,
        groupChatId,
        currentUserId,
        peerId,
      );

      return true;
    } on MediaCompressionException catch (e) {
      _log('❌ sendMediaMessage compression error: $e');
      return false;
    } catch (e) {
      _log('❌ sendMediaMessage error: $e');
      return false;
    } finally {
      onLoadingStatusChanged(false);
      // Dọn cache sau khi gửi xong
      _compressionService
          .clearCache()
          .catchError((e) => _log('⚠️ clearCache error: $e'));
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // HÀM 6: GỬI MEDIA BATCH (nhiều ảnh cùng lúc)
  // ──────────────────────────────────────────────────────────────────────────

  /// Nén và gửi nhiều ảnh cùng lúc.
  ///
  /// [onProgress] nhận (sent, total) – số ảnh đã gửi / tổng số ảnh.
  Future<int> sendImageBatch({
    required List<File> files,
    required String groupChatId,
    required String currentUserId,
    required String peerId,
    required Function(bool) onLoadingStatusChanged,
    MediaCompressionConfig compressionConfig = MediaCompressionConfig.chat,
    void Function(int sent, int total)? onProgress,
  }) async {
    if (files.isEmpty) return 0;
    onLoadingStatusChanged(true);

    int successCount = 0;
    try {
      // Nén hàng loạt trước
      final compressed = await _compressionService.compressImageBatch(
        files,
        config: compressionConfig,
        onProgress: (done, total) => _log('🗜 Batch compress: $done/$total'),
      );

      for (int i = 0; i < compressed.length; i++) {
        try {
          final compressedFile = compressed[i].file;
          final ts = DateTime.now().millisecondsSinceEpoch.toString() + '_$i';
          final storagePath =
              '${FirestoreConstants.pathMediaStorage}/$groupChatId/$ts.jpg';

          final fileUrl =
              await _uploadFileAndGetUrl(compressedFile, storagePath);
          await sendMessage(
            fileUrl,
            TypeMessage.image,
            groupChatId,
            currentUserId,
            peerId,
          );
          successCount++;
          onProgress?.call(successCount, files.length);
        } catch (e) {
          _log('❌ sendImageBatch item $i error: $e');
        }
      }
    } catch (e) {
      _log('❌ sendImageBatch error: $e');
    } finally {
      onLoadingStatusChanged(false);
      _compressionService
          .clearCache()
          .catchError((e) => _log('⚠️ clearCache error: $e'));
    }
    return successCount;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // HÀM 7: HUỶ NÉN VIDEO
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> cancelMediaCompression() async {
    await _compressionService.cancelCompression();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // UTILITY
  // ──────────────────────────────────────────────────────────────────────────

  void _log(String message) {
    // ignore: avoid_print
    print('[ChatProvider] $message');
  }
}
