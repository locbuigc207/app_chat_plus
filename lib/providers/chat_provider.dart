import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
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
// ChatProvider — Decoupled Data & Service Layer
// * Đã loại bỏ hoàn toàn các liên kết cứng với UI/Bubble (Decoupling)
// * Chỉ chuyên trách việc tương tác dữ liệu Firebase Firestore/Storage và LocalDb
// =============================================================================

class ChatProvider {
  // ── Dependencies ──────────────────────────────────────────────────────────
  final SharedPreferences prefs;
  final FirebaseFirestore firebaseFirestore;
  final FirebaseStorage firebaseStorage;

  final MediaCompressionService _compressionService = MediaCompressionService();
  final LocalDbService _localDb = LocalDbService();
  final SyncManager _syncManager = SyncManager();
  final _uuid = const Uuid();

  ChatProvider({
    required this.firebaseFirestore,
    required this.prefs,
    required this.firebaseStorage,
  });

  // [SỬA LỖI P0/P1]: Đã xóa bỏ hàm attachBubbleService và _bubbleService.
  // Giao lại toàn bộ việc xử lý UI (âm thanh, hiển thị bong bóng, cập nhật bong bóng)
  // cho các lớp Controller (ChatPage, GroupChatPage).
  void attachBubbleService(dynamic svc) {
    // Để trống nhằm giữ khả năng tương thích ngược nếu các file cũ vẫn đang gọi hàm này.
    // Logic thực tế đã bị gỡ bỏ.
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static Map<String, dynamic> _toStringMap(dynamic raw) {
    if (raw == null) return {};
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return raw.map((k, v) => MapEntry(k.toString(), v));
    return {};
  }

  static List<Map<String, dynamic>> _toOptionList(dynamic raw) {
    if (raw is! List) return [];
    return raw.map((e) => _toStringMap(e)).toList();
  }

  void _log(String message) => debugPrint('☁️ [ChatProvider] $message');

  // ── Storage ───────────────────────────────────────────────────────────────

  UploadTask uploadFile(File image, String fileName) =>
      firebaseStorage.ref().child(fileName).putFile(image);

  Future<String> _uploadFileAndGetUrl(File file, String fileName) async {
    final snap = await firebaseStorage
        .ref()
        .child(fileName)
        .putFile(file)
        .whenComplete(() {});
    return snap.ref.getDownloadURL();
  }

  Future<String?> uploadFileAndGetUrl(File file, String groupId) async {
    try {
      final ts = DateTime.now().millisecondsSinceEpoch.toString();
      final originalName = file.path.split('/').last;
      final storagePath =
          '${FirestoreConstants.pathDocumentStorage}/$groupId/${ts}_$originalName';
      final uploadTask = firebaseStorage
          .ref()
          .child(storagePath)
          .putFile(
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

  // ── Stream ────────────────────────────────────────────────────────────────

  Stream<QuerySnapshot> getChatStream(String groupChatId, int limit) =>
      firebaseFirestore
          .collection(FirestoreConstants.pathMessageCollection)
          .doc(groupChatId)
          .collection(groupChatId)
          .orderBy(FirestoreConstants.timestamp, descending: true)
          .limit(limit)
          .snapshots();

  Future<void> updateDataFirestore(
    String collectionPath,
    String docPath,
    Map<String, dynamic> dataNeedUpdate,
  ) => firebaseFirestore
      .collection(collectionPath)
      .doc(docPath)
      .update(dataNeedUpdate);

  // ── URL extraction ────────────────────────────────────────────────────────

  static final _urlRegex = RegExp(
    r'(https?://[^\s<>"]+|www\.[^\s<>"]+\.[^\s<>"]{2,})',
    caseSensitive: false,
  );

  List<String> _extractUrls(String text) {
    return _urlRegex.allMatches(text).map((m) {
      var url = m.group(0)!;
      if (!url.startsWith('http')) url = 'https://$url';
      return url;
    }).toList();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONVERSATION FALLBACK UPDATE
  // ═══════════════════════════════════════════════════════════════════════════

  // [SỬA LỖI]: Dùng transaction để ngăn chặn race condition khi 50 tin nhắn được load song song.
  Future<void> _updateConversationLastMessage({
    required String groupChatId,
    required String currentUserId,
    required String peerId,
    required String content,
    required int type,
    required String timestamp,
  }) async {
    try {
      final docRef = firebaseFirestore
          .collection(FirestoreConstants.pathConversationCollection)
          .doc(groupChatId);

      final newTime = int.tryParse(timestamp) ?? 0;

      await firebaseFirestore.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        final currentTime =
            int.tryParse(snap.data()?['lastMessageTime']?.toString() ?? '0') ??
            0;

        // Chỉ cập nhật nếu document chưa tồn tại hoặc tin nhắn này thực sự mới hơn.
        if (!snap.exists || newTime > currentTime) {
          tx.set(docRef, {
            'participants': FieldValue.arrayUnion([currentUserId, peerId]),
            'lastMessage': _previewFor(content, type),
            'lastMessageTime': timestamp,
            'lastMessageType': type,
          }, SetOptions(merge: true));
        }
      });
    } catch (e) {
      _log('⚠️ _updateConversationLastMessage error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SEND MESSAGE
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> sendMessage(
    String content,
    int type,
    String groupChatId,
    String currentUserId,
    String peerId,
  ) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();

    // Extract URL for link preview
    String? previewUrl;
    if (type == TypeMessage.text) {
      final urls = _extractUrls(content);
      if (urls.isNotEmpty) previewUrl = urls.first;
    }

    final localMessage = <String, dynamic>{
      'messageId': timestamp,
      'idFrom': currentUserId,
      'idTo': peerId,
      'timestamp': timestamp,
      'content': content,
      'type': type,
      'status': MessageStatus.pending,
      if (previewUrl != null) 'previewUrl': previewUrl,
    };

    await _localDb.saveMessage(groupChatId, timestamp, localMessage);
    await _localDb.updateConversationPreview(
      conversationId: groupChatId,
      lastMessage: _previewFor(content, type),
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
        if (previewUrl != null) 'previewUrl': previewUrl,
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

  // [SỬA LỖI]: Cập nhật đầy đủ các type và chặn không cho raw JSON hoặc mã hóa hiển thị ra Home Page.
  String _previewFor(String content, int type) {
    switch (type) {
      case TypeMessage.image:
        return '📷 Ảnh';
      case TypeMessage.video:
        return '🎬 Video';
      case TypeMessage.sticker:
        return '😊 Sticker';
      case TypeMessage.document:
        return '📄 Tài liệu';
      case TypeMessage.poll:
        return '📊 Bình chọn';
      case TypeMessage.geoLocked:
        return '📍 Tin nhắn địa điểm';
      case 3:
        return '🎤 Tin nhắn thoại';
    }

    if (type == TypeMessage.gameInvite) return '🎮 Lời mời chơi game';
    if (type == TypeMessage.gameResult) return '🏆 Kết quả game';
    if (type == TypeMessage.gameLive) return '🎮 Đang chơi game';

    // Guard cuối: không bao giờ trả về chuỗi mã hóa làm preview
    if (content.startsWith('{"iv":') && content.contains('"data":')) {
      return '🔒 Tin nhắn';
    }
    if (content.startsWith('{') && content.contains('"matchId"')) {
      return '🎮 Game';
    }
    return content;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // POLL
  // ═══════════════════════════════════════════════════════════════════════════

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
      await Future.delayed(Duration(milliseconds: baseDelayMs * (attempt + 1)));
    }

    if (!docExists) {
      throw Exception(
        'Poll message $messageId không tồn tại sau $maxAttempts lần thử.',
      );
    }

    try {
      await firebaseFirestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(messageRef);
        if (!snapshot.exists)
          throw Exception('Poll message $messageId không tồn tại.');

        final data = _toStringMap(snapshot.data());
        final contentStr = data[FirestoreConstants.content] as String? ?? '{}';

        Map<String, dynamic> pollData;
        try {
          pollData = _toStringMap(jsonDecode(contentStr));
        } catch (_) {
          pollData = {};
        }

        final expiresAtStr = pollData['expiresAt'] as String?;
        if (expiresAtStr != null) {
          final expiresAt = DateTime.tryParse(expiresAtStr);
          if (expiresAt != null && DateTime.now().isAfter(expiresAt)) {
            throw Exception('Poll đã hết hạn.');
          }
        }

        final List<Map<String, dynamic>> options;
        if (pollData['options'] is List &&
            (pollData['options'] as List).isNotEmpty) {
          options = _toOptionList(pollData['options']);
        } else if (data['options'] is List) {
          options = _toOptionList(data['options']);
        } else {
          throw Exception('Dữ liệu options không hợp lệ.');
        }

        final targetIndex = options.indexWhere(
          (o) => o['id'].toString() == optionId,
        );
        if (targetIndex == -1)
          throw Exception('Option $optionId không tồn tại.');

        final isMultipleChoice =
            (pollData['isMultipleChoice'] ?? data['isMultipleChoice'] ?? false)
                as bool;
        if (!isMultipleChoice) {
          for (final opt in options) {
            final votes = List<dynamic>.from(opt['votes'] as List? ?? []);
            votes.remove(userId);
            opt['votes'] = votes;
          }
        }
        final targetVotes = List<dynamic>.from(
          options[targetIndex]['votes'] as List? ?? [],
        );
        if (targetVotes.contains(userId))
          targetVotes.remove(userId);
        else
          targetVotes.add(userId);
        options[targetIndex]['votes'] = targetVotes;
        pollData['options'] = options;

        transaction.update(messageRef, {
          FirestoreConstants.content: jsonEncode(pollData),
          'options': options,
          'lastVotedAt': FieldValue.serverTimestamp(),
        });
      });

      // ── Optimistic Update (Cập nhật Local DB ngay lập tức) ─────────────────
      try {
        final updatedSnap = await messageRef.get();
        if (updatedSnap.exists) {
          final updatedData = _toStringMap(updatedSnap.data());
          final key = '${groupChatId}_$messageId';
          final existingRaw = _localDb.messagesBox.get(key);
          final existing = _toStringMap(existingRaw);

          if (existing.isNotEmpty) {
            final newOptions = _toOptionList(
              updatedData['options'] ?? existing['options'] ?? [],
            );

            // Rebuild content JSON từ options mới để PollMessageWidget parse đúng
            String updatedContent = existing['content'] as String? ?? '{}';
            try {
              final pollMap =
                  jsonDecode(updatedContent) as Map<String, dynamic>;
              pollMap['options'] = newOptions;
              updatedContent = jsonEncode(pollMap);
            } catch (_) {}

            await _localDb.saveMessage(groupChatId, messageId, {
              ...existing,
              'options': newOptions,
              'content': updatedContent,
              'lastVotedAt': DateTime.now().millisecondsSinceEpoch.toString(),
            });
          }
        }
      } catch (e) {
        _log('⚠️ votePoll local DB update: $e');
        // Non-fatal: listener sẽ bắt và sync sau
      }
      _log('✅ votePoll completed successfully.');
    } on FirebaseException catch (e) {
      _log('❌ votePoll FirebaseException [${e.code}]: ${e.message}');
      rethrow;
    } catch (e) {
      _log('❌ votePoll error: $e');
      rethrow;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FIREBASE LISTENER — INCOMING MESSAGES
  // ═══════════════════════════════════════════════════════════════════════════

  // [SỬA LỖI P0]: Trả về StreamSubscription để Controller (Page) nắm giữ và hủy bỏ
  // khi màn hình Dispose, ngăn ngừa rò rỉ bộ nhớ (memory leak).
  StreamSubscription<QuerySnapshot> listenToFirebaseChanges(
    String groupChatId,
    String currentUserId,
    String peerId,
  ) {
    return firebaseFirestore
        .collection(FirestoreConstants.pathMessageCollection)
        .doc(groupChatId)
        .collection(groupChatId)
        .orderBy(FirestoreConstants.timestamp, descending: true)
        .limit(50)
        .snapshots()
        .listen(
          (snapshot) async {
            // [SỬA LỖI P0]: Chỉ xử lý các thay đổi dựa trên docChanges thay vì quét lại toàn bộ snapshot.docs
            for (final change in snapshot.docChanges) {
              try {
                await _processIncomingDocChange(
                  change: change,
                  groupChatId: groupChatId,
                  currentUserId: currentUserId,
                  peerId: peerId,
                );
              } catch (e) {
                _log(
                  '❌ _processIncomingDocChange error [${change.doc.id}]: $e',
                );
              }
            }
          },
          onError: (Object e, StackTrace st) {
            _log('❌ listenToFirebaseChanges stream error: $e');
          },
        );
  }

  Future<void> _processIncomingDocChange({
    required DocumentChange<Map<String, dynamic>> change,
    required String groupChatId,
    required String currentUserId,
    required String peerId,
  }) async {
    final doc = change.doc;
    final data = _toStringMap(doc.data());
    final messageId = doc.id;
    final isFromMe = data['idFrom'] == currentUserId;
    final type = data['type'] as int? ?? TypeMessage.text;

    // ── Own message (Sync Status & Polls) ────────────────────────
    if (isFromMe) {
      final key = '${groupChatId}_$messageId';
      final existingRaw = _localDb.messagesBox.get(key);
      final existing = _toStringMap(existingRaw);

      if (existing.isNotEmpty) {
        final currentStatus = existing['status'] as String? ?? '';
        final newStatus = currentStatus == MessageStatus.pending
            ? MessageStatus.sent
            : currentStatus;

        final merged = <String, dynamic>{
          ...existing,
          'status': newStatus,
          if (data.containsKey('options'))
            'options': _toOptionList(data['options']),
          if (data.containsKey('content') &&
              (data['type'] as int? ?? 0) == TypeMessage.poll)
            'content': data[FirestoreConstants.content],
          if (data.containsKey('lastVotedAt'))
            'lastVotedAt': data['lastVotedAt']?.toString(),
        };

        await _localDb.saveMessage(groupChatId, messageId, merged);
      }
      return;
    }

    // ── Incoming message ──────────────────────────────────────────────────────

    // [SỬA LỖI]: Track the original encrypted content
    String content = data[FirestoreConstants.content] as String? ?? '';
    final String _originalEncryptedContent = content;

    // Bỏ qua decrypt cho Game Message
    if (type == TypeMessage.gameInvite ||
        type == TypeMessage.gameResult ||
        type == TypeMessage.gameLive) {
      // Bảo toàn JSON
    } else if (type == TypeMessage.text &&
        content.isNotEmpty &&
        data['isDeleted'] != true) {
      // CẬP NHẬT ĐIỀU KIỆN Ở ĐÂY
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

    String? previewUrl = data['previewUrl'] as String?;
    if (previewUrl == null && type == TypeMessage.text) {
      final urls = _extractUrls(content);
      if (urls.isNotEmpty) previewUrl = urls.first;
    }

    final updatedMessage = <String, dynamic>{
      'messageId': messageId,
      'idFrom': data['idFrom'],
      'idTo': data['idTo'],
      'timestamp': data['timestamp'],
      'content': content,
      'type': type,
      'status': MessageStatus.sent,
      if (previewUrl != null) 'previewUrl': previewUrl,
      if (data.containsKey('options'))
        'options': _toOptionList(data['options']),
      if (data.containsKey('isViewOnce')) 'isViewOnce': data['isViewOnce'],
      if (data.containsKey('isPinned')) 'isPinned': data['isPinned'],
      if (data.containsKey('isDeleted')) 'isDeleted': data['isDeleted'],
      if (data.containsKey('scamWarning')) 'scamWarning': data['scamWarning'],
      if (data.containsKey('scamReason')) 'scamReason': data['scamReason'],
      if (data.containsKey('hasReminder')) 'hasReminder': data['hasReminder'],
      if (data.containsKey('isHateful')) 'isHateful': data['isHateful'],
      if (data.containsKey('lastVotedAt'))
        'lastVotedAt': data['lastVotedAt']?.toString(),
      if (data.containsKey(FirestoreConstants.matchId))
        FirestoreConstants.matchId: data[FirestoreConstants.matchId],
      if (data.containsKey(FirestoreConstants.gameType))
        FirestoreConstants.gameType: data[FirestoreConstants.gameType],
      if (data.containsKey(FirestoreConstants.matchStatus))
        FirestoreConstants.matchStatus: data[FirestoreConstants.matchStatus],
    };

    // Save to local DB first
    await _localDb.saveMessage(groupChatId, messageId, updatedMessage);

    // [SỬA LỖI]: Fallback Update Conversation Last Message
    // Chỉ cập nhật nếu giải mã thành công, không bao giờ ghi chuỗi mã hóa lên Firestore
    final bool _decryptSucceeded =
        type != TypeMessage.text ||
        (content != _originalEncryptedContent &&
            !content.startsWith('🔒 [') &&
            !content.startsWith('⚠️ [') &&
            !(content.startsWith('{"iv":') && content.contains('"data":')));

    if (change.type == DocumentChangeType.added &&
        content.isNotEmpty &&
        _decryptSucceeded &&
        data['idFrom'] != AppConstants.aiAssistantId) {
      unawaited(
        _updateConversationLastMessage(
          groupChatId: groupChatId,
          currentUserId: currentUserId,
          peerId: peerId,
          content: content,
          type: type,
          timestamp:
              data['timestamp']?.toString() ??
              DateTime.now().millisecondsSinceEpoch.toString(),
        ),
      );
    }

    // ════════════════════════════════════════════════════════════════════════
    // AI Auto-Analysis (parallel, non-blocking)
    // ════════════════════════════════════════════════════════════════════════

    // [SỬA LỖI P0]: Chỉ thực hiện Cloud AI Check (phát sinh chi phí API)
    // khi đây là tin nhắn MỚI ĐƯỢC THÊM (DocumentChangeType.added).
    // Bỏ qua khi có các sự kiện modified (như đổi status isRead, vote poll).
    if (change.type == DocumentChangeType.added &&
        type == TypeMessage.text &&
        content.isNotEmpty &&
        content.length > 15 &&
        data['idFrom'] != AppConstants.aiAssistantId) {
      // 1) Scam + reminder + sentiment
      unawaited(
        AIBackendService()
            .analyzeDecryptedClientMessage(
              plainTextContent: content,
              conversationId: groupChatId,
              messageId: messageId,
              idTo: currentUserId,
            )
            .catchError((e) => _log('AI analysis skipped: $e')),
      );

      // 2) Hate speech detection
      unawaited(
        AIBackendService()
            .detectHateSpeech(content)
            .then((isHateful) async {
              if (!isHateful) return;
              final key = '${groupChatId}_$messageId';
              final existing = _localDb.messagesBox.get(key);
              if (existing != null) {
                await _localDb.saveMessage(groupChatId, messageId, {
                  ...Map<String, dynamic>.from(existing as Map),
                  'isHateful': true,
                  'hateSpeechCategory': 'hate',
                });
              }
              firebaseFirestore
                  .collection(FirestoreConstants.pathMessageCollection)
                  .doc(groupChatId)
                  .collection(groupChatId)
                  .doc(messageId)
                  .update({'isHateful': true})
                  .catchError((_) {});
            })
            .catchError((e) => _log('HateSpeech check skipped: $e')),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MEDIA
  // ═══════════════════════════════════════════════════════════════════════════

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
        final thumbnail = await _compressionService.getVideoThumbnail(
          originalFile,
        );
        if (thumbnail != null) {
          final thumbPath =
              '${FirestoreConstants.pathMediaStorage}/$groupChatId/${ts}_thumb.jpg';
          final thumbUrl = await _uploadFileAndGetUrl(thumbnail, thumbPath);
          contentPayload = '$fileUrl|$thumbUrl';
        }
      }

      final msgType = isVideo ? TypeMessage.video : TypeMessage.image;
      await sendMessage(
        contentPayload,
        msgType,
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
      _compressionService.clearCache().catchError(
        (e) => _log('⚠️ clearCache error: $e'),
      );
    }
  }

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
          final ts = '${DateTime.now().millisecondsSinceEpoch}_$i';
          final storagePath =
              '${FirestoreConstants.pathMediaStorage}/$groupChatId/$ts.jpg';
          final fileUrl = await _uploadFileAndGetUrl(
            compressedFile,
            storagePath,
          );
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
      _compressionService.clearCache().catchError(
        (e) => _log('⚠️ clearCache error: $e'),
      );
    }
    return successCount;
  }

  Future<void> cancelMediaCompression() async =>
      _compressionService.cancelCompression();

  // ═══════════════════════════════════════════════════════════════════════════
  // GAME CENTER METHODS
  // ═══════════════════════════════════════════════════════════════════════════

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
      await firebaseFirestore
          .collection(FirestoreConstants.pathMessageCollection)
          .doc(groupChatId)
          .collection(groupChatId)
          .doc(timestamp)
          .set(messageData);

      await _localDb.saveMessage(groupChatId, timestamp, {
        ...messageData,
        'messageId': timestamp,
        'status': MessageStatus.sent,
      });

      final challengeType = payload.targetUserId != null
          ? 'thách @${payload.targetUserName ?? "thành viên"}'
          : 'thách đấu mở';
      final preview =
          '${payload.gameType.emoji} ${payload.challengerName} $challengeType ${payload.gameType.displayName}';

      await _localDb.updateConversationPreview(
        conversationId: groupChatId,
        lastMessage: preview,
        lastMessageTime: timestamp,
        lastMessageType: TypeMessage.gameInvite,
      );

      // [SỬA LỖI]: Cập nhật Firestore để home page của cả hai phía thấy preview đúng
      try {
        await firebaseFirestore
            .collection(FirestoreConstants.pathConversationCollection)
            .doc(groupChatId)
            .set({
              'lastMessage': preview,
              'lastMessageTime': timestamp,
              'lastMessageType': TypeMessage.gameInvite,
              'participants': FieldValue.arrayUnion([currentUserId]),
            }, SetOptions(merge: true));
      } catch (e) {
        _log('⚠️ Game invite convo update error: $e');
      }

      // [SỬA LỖI P0]: Xóa logic gọi RPC native cũ của ChatBubbleService vì đã dọn dẹp khỏi Kotlin.
      // Firebase Cloud Functions sẽ lo nhiệm vụ gửi Notification thay thế.

      _log('🎮 Game invite sent: ${payload.matchId} → $groupChatId');
      return timestamp;
    } catch (e) {
      _log('❌ sendGameInviteMessage error: $e');
      rethrow;
    }
  }

  Future<String> sendGameResultMessage({
    required String groupChatId,
    required String currentUserId,
    required GameResultPayload payload,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final content = jsonEncode(payload.toJson());

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

      await _localDb.saveMessage(groupChatId, timestamp, {
        ...messageData,
        'messageId': timestamp,
        'status': MessageStatus.sent,
      });

      await _localDb.updateConversationPreview(
        conversationId: groupChatId,
        lastMessage: previewText,
        lastMessageTime: timestamp,
        lastMessageType: TypeMessage.gameResult,
      );

      // [SỬA LỖI]: Cập nhật Firestore để home page của cả hai phía thấy preview đúng
      try {
        await firebaseFirestore
            .collection(FirestoreConstants.pathConversationCollection)
            .doc(groupChatId)
            .set({
              'lastMessage': previewText,
              'lastMessageTime': timestamp,
              'lastMessageType': TypeMessage.gameResult,
              'participants': FieldValue.arrayUnion([currentUserId]),
            }, SetOptions(merge: true));
      } catch (e) {
        _log('⚠️ Game result convo update error: $e');
      }

      _log('🏁 Game result sent: ${payload.matchId} → $groupChatId');
      return timestamp;
    } catch (e) {
      _log('❌ sendGameResultMessage error: $e');
      rethrow;
    }
  }

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

      await firebaseFirestore.runTransaction((tx) async {
        final doc = await tx.get(docRef);
        // Ngăn chặn lỗi khi document messageId không tồn tại trên Firestore
        if (!doc.exists) {
          _log(
            '⚠️ [updateGameMessageStatus] Document messageId: $messageId không tồn tại trên Firestore.',
          );
          return;
        }
        final data = doc.data()!;
        final currentType = data[FirestoreConstants.type] as int? ?? 0;
        if (currentType != TypeMessage.gameInvite &&
            currentType != TypeMessage.gameLive &&
            currentType != TypeMessage.gameResult)
          return;

        final rawContent = data[FirestoreConstants.content] as String? ?? '{}';
        String updatedContent = rawContent;
        try {
          final payloadMap = jsonDecode(rawContent) as Map<String, dynamic>;
          payloadMap['matchStatus'] = newStatus.name;
          if (spectatorCount != null)
            payloadMap['spectatorCount'] = spectatorCount;
          updatedContent = jsonEncode(payloadMap);
        } catch (_) {}

        final newType = newStatus == MatchStatus.live
            ? TypeMessage.gameLive
            : currentType;
        tx.update(docRef, {
          FirestoreConstants.matchStatus: newStatus.name,
          FirestoreConstants.content: updatedContent,
          FirestoreConstants.type: newType,
        });
      });

      // Sync local DB
      final localKey = '${groupChatId}_$messageId';
      final existingRaw = _localDb.messagesBox.get(localKey);
      final existing = _toStringMap(existingRaw);
      if (existing.isNotEmpty) {
        final rawContent =
            existing[FirestoreConstants.content] as String? ?? '{}';
        String updatedContent = rawContent;
        try {
          final payloadMap = jsonDecode(rawContent) as Map<String, dynamic>;
          payloadMap['matchStatus'] = newStatus.name;
          if (spectatorCount != null)
            payloadMap['spectatorCount'] = spectatorCount;
          updatedContent = jsonEncode(payloadMap);
        } catch (_) {}
        final currentType = existing[FirestoreConstants.type] as int? ?? 0;
        final newType = newStatus == MatchStatus.live
            ? TypeMessage.gameLive
            : currentType;
        await _localDb.saveMessage(groupChatId, messageId, {
          ...existing,
          FirestoreConstants.matchStatus: newStatus.name,
          FirestoreConstants.content: updatedContent,
          FirestoreConstants.type: newType,
        });
      }

      _log('🔄 Game message status updated: $messageId → ${newStatus.name}');
    } catch (e) {
      _log('❌ updateGameMessageStatus error: $e');
    }
  }
}
