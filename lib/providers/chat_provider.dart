import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/message_chat.dart';
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
//   votePoll()         → chờ doc tồn tại (retry) → Firestore Transaction
//
// Game Center:
//   sendGameInviteMessage()   → gửi TypeMessage.gameInvite vào nhóm
//   sendGameResultMessage()   → gửi TypeMessage.gameResult vào nhóm
//   updateGameMessageStatus() → cập nhật matchStatus trực tiếp trên Firestore
//                               (waiting → live → finished)
//
// =============================================================================

class ChatProvider {
  // ──────────────────────────────────────────────────────────────────────────
  // Dependencies
  // ──────────────────────────────────────────────────────────────────────────

  final SharedPreferences prefs;
  final FirebaseFirestore firebaseFirestore;
  final FirebaseStorage firebaseStorage;

  final GeminiService _geminiService = GeminiService();
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
  // PRIVATE HELPERS
  // ──────────────────────────────────────────────────────────────────────────

  /// **FIX #2** – Firestore trả về `_Map<dynamic, dynamic>` thay vì
  /// `Map<String, dynamic>`, gây ClassCastException khi dùng `as Map<String,dynamic>`.
  /// Helper này convert an toàn mà không ném exception.
  static Map<String, dynamic> _toStringMap(dynamic raw) {
    if (raw == null) return {};
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v));
    }
    return {};
  }

  /// Cast an toàn một List<dynamic> của options,
  /// mỗi phần tử có thể là `_Map<dynamic,dynamic>`.
  static List<Map<String, dynamic>> _toOptionList(dynamic raw) {
    if (raw is! List) return [];
    return raw.map((e) => _toStringMap(e)).toList();
  }

  void _log(String message) {
    // ignore: avoid_print
    print('[ChatProvider] $message');
  }

  // ──────────────────────────────────────────────────────────────────────────
  // UPLOAD FILE
  // ──────────────────────────────────────────────────────────────────────────

  UploadTask uploadFile(File image, String fileName) {
    return firebaseStorage.ref().child(fileName).putFile(image);
  }

  Future<String> _uploadFileAndGetUrl(File file, String fileName) async {
    final ref = firebaseStorage.ref().child(fileName);
    final snapshot = await ref.putFile(file).whenComplete(() {});
    return snapshot.ref.getDownloadURL();
  }

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

    _syncManager.startListening();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // HÀM 2: GỬI POLL – OFFLINE-FIRST
  // ──────────────────────────────────────────────────────────────────────────

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
  // HÀM 3: VOTE POLL – Firestore Transaction với retry
  // ──────────────────────────────────────────────────────────────────────────
  //
  // **FIX #1** – Race condition: người dùng bấm vote ngay sau khi gửi poll,
  // nhưng SyncManager chưa kịp đẩy document lên Firestore.
  // Giải pháp: retry tối đa 5 lần với exponential backoff trước khi transaction.
  //
  // Backoff schedule: 500 → 1000 → 1500 → 2000 → 2500 ms (tổng ~7.5s)
  // ──────────────────────────────────────────────────────────────────────────

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

    // ── Bước 1: Đợi document xuất hiện (retry backoff) ──────────────────
    const maxAttempts = 5;
    const baseDelayMs = 500;
    bool docExists = false;

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final snap = await messageRef.get();
        if (snap.exists) {
          docExists = true;
          break;
        }
      } catch (e) {
        _log('⚠️ votePoll check attempt $attempt error: $e');
      }

      final delayMs =
          baseDelayMs * (attempt + 1); // 500, 1000, 1500, 2000, 2500
      _log(
        '⏳ votePoll: message $messageId chưa tồn tại trên Firestore, '
        'thử lại sau ${delayMs}ms (${attempt + 1}/$maxAttempts)',
      );
      await Future.delayed(Duration(milliseconds: delayMs));
    }

    if (!docExists) {
      throw Exception(
        'Poll message $messageId không tồn tại sau $maxAttempts lần thử. '
        'Tin nhắn chưa đồng bộ lên server – hãy thử lại sau.',
      );
    }

    // ── Bước 2: Chạy Firestore Transaction ──────────────────────────────
    try {
      await firebaseFirestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(messageRef);

        if (!snapshot.exists) {
          throw Exception('Poll message $messageId không tồn tại.');
        }

        // **FIX #2** – dùng _toStringMap để tránh ClassCastException
        final data = _toStringMap(snapshot.data());

        // 1. Parse JSON content
        final contentStr = data[FirestoreConstants.content] as String? ?? '{}';
        Map<String, dynamic> pollData;
        try {
          pollData = _toStringMap(jsonDecode(contentStr));
        } catch (_) {
          pollData = {};
        }

        // 2. Kiểm tra hết hạn
        final expiresAtStr = pollData['expiresAt'] as String?;
        if (expiresAtStr != null) {
          final expiresAt = DateTime.tryParse(expiresAtStr);
          if (expiresAt != null && DateTime.now().isAfter(expiresAt)) {
            throw Exception('Poll đã hết hạn, không thể bình chọn.');
          }
        }

        // 3. Lấy options – tương thích ngược (có thể ở pollData hoặc root)
        final List<Map<String, dynamic>> options;
        if (pollData['options'] is List &&
            (pollData['options'] as List).isNotEmpty) {
          options = _toOptionList(pollData['options']);
        } else if (data['options'] is List) {
          options = _toOptionList(data['options']);
        } else {
          throw Exception('Dữ liệu options không hợp lệ.');
        }

        // 4. Tìm option đích
        final targetIndex =
            options.indexWhere((o) => o['id'].toString() == optionId);
        if (targetIndex == -1) {
          final ids = options.map((e) => e['id']).toList();
          throw Exception('Option $optionId không tồn tại. Hiện có: $ids');
        }

        // 5. Lấy config
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

        // 8. Ghi lại Firestore
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
  //
  // **FIX #2** – Dùng _toStringMap() thay vì
  //   `doc.data() as Map<String, dynamic>?`   ← gây ClassCastException
  //
  // Firestore snapshot trả về `_InternalLinkedHashMap<dynamic, dynamic>`
  // (internal class của Dart), không thể cast trực tiếp về Map<String,dynamic>.
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
        .listen(
      (snapshot) async {
        for (final doc in snapshot.docs) {
          try {
            await _processIncomingDoc(
              doc: doc,
              groupChatId: groupChatId,
              currentUserId: currentUserId,
              peerId: peerId,
            );
          } catch (e) {
            // Bắt lỗi từng doc, không để crash toàn bộ listener
            _log('❌ _processIncomingDoc error [${doc.id}]: $e');
          }
        }
      },
      onError: (Object e, StackTrace st) {
        _log('❌ listenToFirebaseChanges stream error: $e');
      },
    );
  }

  /// Xử lý một document từ Firestore snapshot.
  /// Tách riêng để dễ test và bắt lỗi từng document.
  Future<void> _processIncomingDoc({
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required String groupChatId,
    required String currentUserId,
    required String peerId,
  }) async {
    // **FIX #2** – Không dùng `doc.data() as Map<String, dynamic>?`
    // Dùng _toStringMap để xử lý _Map<dynamic,dynamic> từ Firestore
    final data = _toStringMap(doc.data());
    final messageId = doc.id;
    final isFromMe = data['idFrom'] == currentUserId;
    final type = data['type'] as int? ?? TypeMessage.text;

    // ── Tin nhắn của mình → chỉ cập nhật status pending → sent ──────────
    if (isFromMe) {
      final key = '${groupChatId}_$messageId';
      if (_localDb.messagesBox.containsKey(key)) {
        // **FIX** – Hive cũng có thể trả về _Map<dynamic,dynamic>
        final existingRaw = _localDb.messagesBox.get(key);
        final existing = _toStringMap(existingRaw);
        if (existing.isNotEmpty &&
            existing['status'] == MessageStatus.pending) {
          await _localDb.saveMessage(
            groupChatId,
            messageId,
            {...existing, 'status': MessageStatus.sent},
          );
        }
      }
      return;
    }

    // ── Tin nhắn của người khác → decrypt nếu là text thường ─────────────
    // Game messages (gameInvite / gameResult) không cần decrypt
    String content = data[FirestoreConstants.content] as String? ?? '';

    if (type == TypeMessage.text && content.isNotEmpty) {
      try {
        content = await EncryptionService().decryptPayload(
          content,
          groupChatId,
          [currentUserId, peerId],
          currentUserId,
        );
      } catch (e) {
        _log('⚠️ Decrypt failed for $messageId: $e');
        // Giữ nguyên content gốc thay vì crash
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
      // **FIX** – Normalize options để tránh _Map<dynamic,dynamic> lưu vào Hive
      if (data.containsKey('options'))
        'options': _toOptionList(data['options']),
      if (data.containsKey('isViewOnce')) 'isViewOnce': data['isViewOnce'],
      if (data.containsKey('isPinned')) 'isPinned': data['isPinned'],
      if (data.containsKey('isDeleted')) 'isDeleted': data['isDeleted'],
      if (data.containsKey('scamWarning')) 'scamWarning': data['scamWarning'],
      if (data.containsKey('scamReason')) 'scamReason': data['scamReason'],
      if (data.containsKey('hasReminder')) 'hasReminder': data['hasReminder'],
      if (data.containsKey('lastVotedAt'))
        'lastVotedAt': data['lastVotedAt']?.toString(),
      // Game fields
      if (data.containsKey(FirestoreConstants.matchId))
        FirestoreConstants.matchId: data[FirestoreConstants.matchId],
      if (data.containsKey(FirestoreConstants.gameType))
        FirestoreConstants.gameType: data[FirestoreConstants.gameType],
      if (data.containsKey(FirestoreConstants.matchStatus))
        FirestoreConstants.matchStatus: data[FirestoreConstants.matchStatus],
    };

    await _localDb.saveMessage(groupChatId, messageId, updatedMessage);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // HÀM 5: GỬI MEDIA (ảnh / video)
  // ──────────────────────────────────────────────────────────────────────────

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

      final ext = isVideo ? 'mp4' : 'jpg';
      final storagePath =
          '${FirestoreConstants.pathMediaStorage}/$groupChatId/$ts.$ext';

      final fileUrl = await _uploadFileAndGetUrl(compressedFile, storagePath);

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
      _compressionService
          .clearCache()
          .catchError((e) => _log('⚠️ clearCache error: $e'));
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // HÀM 6: GỬI MEDIA BATCH (nhiều ảnh cùng lúc)
  // ──────────────────────────────────────────────────────────────────────────

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

  // ══════════════════════════════════════════════════════════════════════════
  // GAME CENTER — Các hàm gửi tin nhắn game vào nhóm chat
  // ══════════════════════════════════════════════════════════════════════════

  // ──────────────────────────────────────────────────────────────────────────
  // HÀM 8: GỬI LỜI MỜI CHƠI GAME (GAME INVITE)
  // ──────────────────────────────────────────────────────────────────────────

  /// Gửi tin nhắn thách đấu vào nhóm chat.
  ///
  /// Luồng:
  ///   1. Serialize [GameInvitePayload] → JSON → content
  ///   2. Ghi trực tiếp lên Firestore (không qua SyncQueue vì cần messageId ngay)
  ///   3. Lưu vào LocalDb với status = sent
  ///   4. Trả về messageId để game_firebase_service.linkInviteMessage()
  ///
  /// [groupChatId]  : ID nhóm chat hoặc conversation
  /// [currentUserId]: ID người tạo thách đấu
  /// [payload]      : Dữ liệu thách đấu
  ///
  /// Trả về messageId (timestamp) của tin nhắn vừa tạo.
  Future<String> sendGameInviteMessage({
    required String groupChatId,
    required String currentUserId,
    required GameInvitePayload payload,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final content = jsonEncode(payload.toJson());

    final messageData = <String, dynamic>{
      FirestoreConstants.idFrom: currentUserId,
      FirestoreConstants.idTo: groupChatId,
      FirestoreConstants.timestamp: timestamp,
      FirestoreConstants.content: content,
      FirestoreConstants.type: TypeMessage.gameInvite,
      FirestoreConstants.matchId: payload.matchId,
      FirestoreConstants.gameType: payload.gameType.name,
      FirestoreConstants.matchStatus: payload.matchStatus.name,
      'isRead': false,
      'isDeleted': false,
      'isPinned': false,
    };

    try {
      // Ghi trực tiếp lên Firestore để có messageId ngay lập tức
      await firebaseFirestore
          .collection(FirestoreConstants.pathMessageCollection)
          .doc(groupChatId)
          .collection(groupChatId)
          .doc(timestamp)
          .set(messageData);

      // Lưu vào local DB
      await _localDb.saveMessage(
        groupChatId,
        timestamp,
        {...messageData, 'messageId': timestamp, 'status': MessageStatus.sent},
      );

      // Cập nhật conversation preview
      await _localDb.updateConversationPreview(
        conversationId: groupChatId,
        lastMessage:
            '${payload.gameType.emoji} ${payload.challengerName} thách đấu ${payload.gameType.displayName}',
        lastMessageTime: timestamp,
        lastMessageType: TypeMessage.gameInvite,
      );

      _log('🎮 Game invite sent: ${payload.matchId} → $groupChatId');
      return timestamp;
    } catch (e) {
      _log('❌ sendGameInviteMessage error: $e');
      rethrow;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // HÀM 9: GỬI KẾT QUẢ TRẬN ĐẤU (GAME RESULT)
  // ──────────────────────────────────────────────────────────────────────────

  /// Đẩy tin nhắn kết quả trận đấu vào nhóm chat sau khi game kết thúc.
  ///
  /// Luồng:
  ///   1. Serialize [GameResultPayload] → JSON → content
  ///   2. Ghi trực tiếp lên Firestore
  ///   3. Lưu vào LocalDb
  ///
  /// [groupChatId]  : ID nhóm chat
  /// [currentUserId]: ID người gửi (thường là server-side trigger,
  ///                  nhưng trong app sẽ do player cuối cùng trigger)
  /// [payload]      : Dữ liệu kết quả
  Future<String> sendGameResultMessage({
    required String groupChatId,
    required String currentUserId,
    required GameResultPayload payload,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final content = jsonEncode(payload.toJson());

    // Tạo text summary để hiển thị trong conversation preview
    final winner = payload.winnerId == currentUserId
        ? payload.player1Name
        : (payload.result == 'draw' ? null : payload.player2Name);
    final previewText = payload.result == 'draw'
        ? '🤝 ${payload.player1Name} và ${payload.player2Name} hòa nhau!'
        : '🏆 $winner đã thắng trận ${payload.gameType.displayName}!';

    final messageData = <String, dynamic>{
      FirestoreConstants.idFrom: currentUserId,
      FirestoreConstants.idTo: groupChatId,
      FirestoreConstants.timestamp: timestamp,
      FirestoreConstants.content: content,
      FirestoreConstants.type: TypeMessage.gameResult,
      FirestoreConstants.matchId: payload.matchId,
      FirestoreConstants.gameType: payload.gameType.name,
      FirestoreConstants.matchStatus: MatchStatus.finished.name,
      'isRead': false,
      'isDeleted': false,
      'isPinned': false,
    };

    try {
      await firebaseFirestore
          .collection(FirestoreConstants.pathMessageCollection)
          .doc(groupChatId)
          .collection(groupChatId)
          .doc(timestamp)
          .set(messageData);

      await _localDb.saveMessage(
        groupChatId,
        timestamp,
        {...messageData, 'messageId': timestamp, 'status': MessageStatus.sent},
      );

      await _localDb.updateConversationPreview(
        conversationId: groupChatId,
        lastMessage: previewText,
        lastMessageTime: timestamp,
        lastMessageType: TypeMessage.gameResult,
      );

      _log('🏁 Game result sent: ${payload.matchId} → $groupChatId');
      return timestamp;
    } catch (e) {
      _log('❌ sendGameResultMessage error: $e');
      rethrow;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // HÀM 10: CẬP NHẬT TRẠNG THÁI TIN NHẮN GAME
  // ──────────────────────────────────────────────────────────────────────────

  /// Cập nhật trạng thái của tin nhắn game invite trực tiếp trên Firestore.
  ///
  /// Dùng cho các trường hợp:
  ///   - waiting → live    : Khi player2 chấp nhận vào phòng
  ///   - live → finished   : Khi trận kết thúc (card invite chuyển thành "Đã kết thúc")
  ///   - waiting → aborted : Khi hết thời gian chờ
  ///
  /// Cũng cập nhật số khán giả [spectatorCount] nếu được cung cấp.
  ///
  /// [groupChatId]    : ID nhóm chat
  /// [messageId]      : Timestamp (ID) của tin nhắn cần update
  /// [newStatus]      : Trạng thái mới
  /// [spectatorCount] : Số khán giả hiện tại (optional)
  Future<void> updateGameMessageStatus({
    required String groupChatId,
    required String messageId,
    required MatchStatus newStatus,
    int? spectatorCount,
  }) async {
    try {
      final docRef = firebaseFirestore
          .collection(FirestoreConstants.pathMessageCollection)
          .doc(groupChatId)
          .collection(groupChatId)
          .doc(messageId);

      final doc = await docRef.get();
      if (!doc.exists) {
        _log('⚠️ updateGameMessageStatus: message $messageId not found');
        return;
      }

      // **FIX #2** – Dùng _toStringMap để tránh ClassCastException
      final data = _toStringMap(doc.data());
      final currentContent = data[FirestoreConstants.content] as String? ?? '';

      // Parse và update payload
      String updatedContent = currentContent;
      try {
        final payloadMap = _toStringMap(jsonDecode(currentContent));
        payloadMap['matchStatus'] = newStatus.name;
        if (spectatorCount != null) {
          payloadMap['spectatorCount'] = spectatorCount;
        }
        updatedContent = jsonEncode(payloadMap);
      } catch (e) {
        _log('⚠️ updateGameMessageStatus: failed to parse content: $e');
        // Tiếp tục update field matchStatus kể cả khi không parse được content
      }

      await docRef.update({
        FirestoreConstants.matchStatus: newStatus.name,
        FirestoreConstants.content: updatedContent,
      });

      // Sync lại local DB
      final localKey = '${groupChatId}_$messageId';
      final existingRaw = _localDb.messagesBox.get(localKey);
      final existing = _toStringMap(existingRaw);
      if (existing.isNotEmpty) {
        await _localDb.saveMessage(
          groupChatId,
          messageId,
          {
            ...existing,
            FirestoreConstants.matchStatus: newStatus.name,
            FirestoreConstants.content: updatedContent,
          },
        );
      }

      _log('🔄 Game message status updated: $messageId → ${newStatus.name}');
    } catch (e) {
      _log('❌ updateGameMessageStatus error: $e');
      // Không rethrow — status update thất bại không nên crash app
    }
  }
}
