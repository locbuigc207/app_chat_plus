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
// ChatProvider — with complete bubble integration
// =============================================================================

class ChatProvider {
  // ── Dependencies ──────────────────────────────────────────────────────────
  final SharedPreferences prefs;
  final FirebaseFirestore firebaseFirestore;
  final FirebaseStorage firebaseStorage;

  /// Optional bubble service — set via [attachBubbleService] after construction.
  /// When null, all bubble-related calls are silently skipped.
  UnifiedBubbleService? _bubbleService;

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

  // ── Bubble service injection ───────────────────────────────────────────────

  /// Call once in your app's Provider setup:
  ///   chatProvider.attachBubbleService(ref.read(unifiedBubbleServiceProvider));
  void attachBubbleService(UnifiedBubbleService? svc) {
    _bubbleService = svc;
    _log('🫧 BubbleService attached: ${svc != null}');
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

  void _log(String message) => debugPrint('[ChatProvider] $message');

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
  ) =>
      firebaseFirestore
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
  // BUBBLE — core helpers (no BuildContext, pure service layer)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Map message [type] → bubble messageType string.
  String _bubbleTypeStr(int type) => switch (type) {
        TypeMessage.image => 'image',
        TypeMessage.video => 'video',
        3 => 'voice', // voice
        TypeMessage.geoLocked => 'location',
        TypeMessage.document => 'file',
        TypeMessage.poll => 'poll',
        TypeMessage.gameInvite => 'game',
        TypeMessage.gameResult => 'game',
        _ => 'text',
      };

  /// Short display string for bubble notification.
  String _bubblePreview(String content, int type, {String? senderName}) {
    final base = switch (type) {
      TypeMessage.image => '📷 Hình ảnh',
      TypeMessage.video => '🎬 Video',
      3 => '🎤 Tin nhắn thoại',
      TypeMessage.geoLocked => '📍 Tin nhắn vị trí',
      TypeMessage.document => '📎 Tệp đính kèm',
      TypeMessage.sticker => '😊 Sticker',
      TypeMessage.poll => '📊 Bình chọn',
      TypeMessage.gameInvite => '🎮 Lời mời chơi game',
      TypeMessage.gameResult => '🏆 Kết quả game',
      _ => content.contains('maps.google.com') || content.contains('Location:')
          ? '📍 Vị trí'
          : (content.length > 60 ? '${content.substring(0, 60)}…' : content),
    };
    return senderName != null ? '$senderName: $base' : base;
  }

  /// Send bubble notification for an INCOMING message (fromUser = false)
  /// or an OUTGOING message update (fromUser = true).
  /// Safely no-ops when bubble disabled or not active.
  Future<void> _tryUpdateBubble({
    required String conversationId,
    required String userName,
    required String avatarUrl,
    required String content,
    required int type,
    required bool fromUser,
    String? senderName, // for group chats
  }) async {
    try {
      final settings = BubbleSettingsService();
      if (!settings.isEnabled) return;

      // Do not push bubble when user is actively inside the chat
      if (settings.settings.autoHideWhenChatOpen && !fromUser) return;

      final svc = _bubbleService;
      if (svc == null) return;
      if (!svc.isBubbleActive(conversationId)) return;

      final preview = _bubblePreview(content, type, senderName: senderName);

      await svc.sendMessage(
        userId: conversationId,
        userName: userName,
        message: preview,
        avatarUrl: avatarUrl,
        messageType: _bubbleTypeStr(type),
      );
    } catch (e) {
      _log('⚠️ _tryUpdateBubble: $e');
    }
  }

  /// Show the bubble popup for a conversation (creates if not already active).
  /// Called when a message arrives and app is backgrounded.
  Future<void> _tryShowBubble({
    required String conversationId,
    required String userName,
    required String avatarUrl,
  }) async {
    try {
      final settings = BubbleSettingsService();
      if (!settings.isEnabled) return;
      final svc = _bubbleService;
      if (svc == null || !svc.isSupported) return;
      await svc.showChatBubble(
          userId: conversationId, userName: userName, avatarUrl: avatarUrl);
    } catch (e) {
      _log('⚠️ _tryShowBubble: $e');
    }
  }

  /// Play receive sound based on current BubbleMode for the conversation.
  Future<void> _tryPlayReceiveSound(String conversationId) async {
    try {
      if (!BubbleSettingsService().settings.soundEnabled) return;
      final ctx = ContextualBubbleService.instance.getContext(conversationId);
      await BubbleSoundService().playReceive(ctx.mode);
    } catch (e) {
      _log('⚠️ _tryPlayReceiveSound: $e');
    }
  }

  /// Update conversation context for auto-mode detection.
  void _updateBubbleContext(String conversationId, String messageContent) {
    try {
      ContextualBubbleService.instance.updateContext(
        conversationId: conversationId,
        message: messageContent,
      );
    } catch (e) {
      _log('⚠️ _updateBubbleContext: $e');
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

    // ── Bubble: update context + bubble message after send ────────────────
    _updateBubbleContext(groupChatId, content);
    unawaited(_tryUpdateBubble(
      conversationId: groupChatId,
      userName: peerId,
      avatarUrl: '',
      content: content,
      type: type,
      fromUser: true,
    ));
  }

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
        return '📊 Cuộc khảo sát';
      case TypeMessage.geoLocked:
        return '🔐 Tin nhắn ẩn địa điểm';
      case 3:
        return '🎤 Tin nhắn thoại';
      default:
        return content;
    }
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
        .map((text) => <String, dynamic>{
              'id': _uuid.v4(),
              'text': text.trim(),
              'votes': <String>[],
            })
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
        pollJson, TypeMessage.poll, groupChatId, currentUserId, peerId);
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
          'Poll message $messageId không tồn tại sau $maxAttempts lần thử.');
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

        final targetIndex =
            options.indexWhere((o) => o['id'].toString() == optionId);
        if (targetIndex == -1)
          throw Exception('Option $optionId không tồn tại.');

        final isMultipleChoice = (pollData['isMultipleChoice'] ??
            data['isMultipleChoice'] ??
            false) as bool;
        if (!isMultipleChoice) {
          for (final opt in options) {
            final votes = List<dynamic>.from(opt['votes'] as List? ?? []);
            votes.remove(userId);
            opt['votes'] = votes;
          }
        }
        final targetVotes =
            List<dynamic>.from(options[targetIndex]['votes'] as List? ?? []);
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
    } on FirebaseException catch (e) {
      _log('❌ votePoll FirebaseException [${e.code}]: ${e.message}');
      rethrow;
    } catch (e) {
      _log('❌ votePoll error: $e');
      rethrow;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FIREBASE LISTENER — INCOMING MESSAGES + BUBBLE
  // ═══════════════════════════════════════════════════════════════════════════

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
            _log('❌ _processIncomingDoc error [${doc.id}]: $e');
          }
        }
      },
      onError: (Object e, StackTrace st) {
        _log('❌ listenToFirebaseChanges stream error: $e');
      },
    );
  }

  // ── Track processed messages to avoid duplicate bubble/sound ─────────────
  final Set<String> _processedIncomingIds = {};

  Future<void> _processIncomingDoc({
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required String groupChatId,
    required String currentUserId,
    required String peerId,
  }) async {
    final data = _toStringMap(doc.data());
    final messageId = doc.id;
    final isFromMe = data['idFrom'] == currentUserId;
    final type = data['type'] as int? ?? TypeMessage.text;

    // ── Own message: mark as sent ────────────────────────────────────────────
    if (isFromMe) {
      final key = '${groupChatId}_$messageId';
      if (_localDb.messagesBox.containsKey(key)) {
        final existingRaw = _localDb.messagesBox.get(key);
        final existing = _toStringMap(existingRaw);
        if (existing.isNotEmpty &&
            existing['status'] == MessageStatus.pending) {
          await _localDb.saveMessage(groupChatId, messageId,
              {...existing, 'status': MessageStatus.sent});
        }
      }
      return;
    }

    // ── Incoming message ──────────────────────────────────────────────────────

    String content = data[FirestoreConstants.content] as String? ?? '';

    // Decrypt text messages
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
      }
    }

    // Link preview extraction
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

    // ════════════════════════════════════════════════════════════════════════
    // BUBBLE INTEGRATION for INCOMING messages
    // ════════════════════════════════════════════════════════════════════════

    // Deduplicate: only trigger bubble+sound once per new message
    final bubbleKey = '${groupChatId}_${messageId}_bubble';
    if (!_processedIncomingIds.contains(bubbleKey) &&
        data['idFrom'] != AppConstants.aiAssistantId &&
        content.isNotEmpty) {
      _processedIncomingIds.add(bubbleKey);
      // Prevent unbounded growth
      if (_processedIncomingIds.length > 500) {
        _processedIncomingIds.remove(_processedIncomingIds.first);
      }

      // 1. Update contextual bubble service — auto-detect mode from content
      _updateBubbleContext(groupChatId, content);

      // 2. Play notification sound based on BubbleMode
      unawaited(_tryPlayReceiveSound(groupChatId));

      // 3. Determine peer display info
      final senderAvatar = await _fetchPeerAvatar(peerId);
      final senderName = await _fetchPeerName(peerId);

      // 4. Update bubble message (if bubble already active)
      unawaited(_tryUpdateBubble(
        conversationId: groupChatId,
        userName: senderName,
        avatarUrl: senderAvatar,
        content: content,
        type: type,
        fromUser: false,
      ));

      // 5. Show bubble if app is in background and no bubble exists yet
      final settings = BubbleSettingsService();
      if (settings.isEnabled &&
          _bubbleService != null &&
          !_bubbleService!.isBubbleActive(groupChatId)) {
        unawaited(_tryShowBubble(
          conversationId: groupChatId,
          userName: senderName,
          avatarUrl: senderAvatar,
        ));
      }
    }

    // ════════════════════════════════════════════════════════════════════════
    // AI Auto-Analysis (parallel, non-blocking — unchanged)
    // ════════════════════════════════════════════════════════════════════════

    if (type == TypeMessage.text &&
        content.isNotEmpty &&
        content.length > 15 &&
        data['idFrom'] != AppConstants.aiAssistantId) {
      // 1) Scam + reminder + sentiment
      unawaited(AIBackendService()
          .analyzeDecryptedClientMessage(
              plainTextContent: content,
              conversationId: groupChatId,
              messageId: messageId,
              idTo: currentUserId)
          .catchError((e) => _log('AI analysis skipped: $e')));

      // 2) Hate speech detection
      unawaited(
          AIBackendService().detectHateSpeech(content).then((isHateful) async {
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
            .update({'isHateful': true}).catchError((_) {});
      }).catchError((e) => _log('HateSpeech check skipped: $e')));
    }
  }

  // ── Peer info helpers ─────────────────────────────────────────────────────

  /// Simple in-memory cache: userId → avatarUrl
  final Map<String, String> _avatarCache = {};
  final Map<String, String> _nameCache = {};

  Future<String> _fetchPeerAvatar(String userId) async {
    if (_avatarCache.containsKey(userId)) return _avatarCache[userId]!;
    try {
      final doc = await firebaseFirestore
          .collection(FirestoreConstants.pathUserCollection)
          .doc(userId)
          .get();
      final url = doc.data()?[FirestoreConstants.photoUrl] as String? ?? '';
      _avatarCache[userId] = url;
      return url;
    } catch (_) {
      return '';
    }
  }

  Future<String> _fetchPeerName(String userId) async {
    if (_nameCache.containsKey(userId)) return _nameCache[userId]!;
    try {
      final doc = await firebaseFirestore
          .collection(FirestoreConstants.pathUserCollection)
          .doc(userId)
          .get();
      final name =
          doc.data()?[FirestoreConstants.nickname] as String? ?? 'User';
      _nameCache[userId] = name;
      return name;
    } catch (_) {
      return 'User';
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
            onProgress: onCompressionProgress);
      } else {
        compressedFile = await _compressionService
            .compressImageFile(originalFile, config: compressionConfig);
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

      final msgType = isVideo ? TypeMessage.video : TypeMessage.image;
      await sendMessage(
          contentPayload, msgType, groupChatId, currentUserId, peerId);

      // ── Bubble: update with media type immediately ──────────────────────
      unawaited(_tryUpdateBubble(
        conversationId: groupChatId,
        userName: peerId,
        avatarUrl: '',
        content: contentPayload,
        type: msgType,
        fromUser: true,
      ));

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
      final compressed = await _compressionService.compressImageBatch(files,
          config: compressionConfig,
          onProgress: (done, total) => _log('🗜 Batch compress: $done/$total'));

      for (int i = 0; i < compressed.length; i++) {
        try {
          final compressedFile = compressed[i].file;
          final ts = '${DateTime.now().millisecondsSinceEpoch}_$i';
          final storagePath =
              '${FirestoreConstants.pathMediaStorage}/$groupChatId/$ts.jpg';
          final fileUrl =
              await _uploadFileAndGetUrl(compressedFile, storagePath);
          await sendMessage(
              fileUrl, TypeMessage.image, groupChatId, currentUserId, peerId);
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

  Future<void> cancelMediaCompression() async =>
      _compressionService.cancelCompression();

  // ═══════════════════════════════════════════════════════════════════════════
  // GAME CENTER METHODS + BUBBLE
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
        'status': MessageStatus.sent
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

      // ── Bubble: game invite notification ─────────────────────────────────
      _updateBubbleContext(groupChatId, '🎮 game invite');
      unawaited(_tryUpdateBubble(
        conversationId: groupChatId,
        userName: payload.challengerName,
        avatarUrl: payload.challengerAvatar,
        content: preview,
        type: TypeMessage.gameInvite,
        fromUser: true,
      ));

      // Push notification to target player
      if (payload.targetUserId?.isNotEmpty == true) {
        unawaited(ChatBubbleService().sendGameChallengeNotification(
          targetUserId: payload.targetUserId!,
          challengerName: payload.challengerName,
          challengerAvatar: payload.challengerAvatar,
          matchId: payload.matchId,
          groupId: groupChatId,
          gameType: payload.gameType.name,
          timeControlLabel: _resolveTimeLabel(payload),
        ));
      }

      _log('🎮 Game invite sent: ${payload.matchId} → $groupChatId');
      return timestamp;
    } catch (e) {
      _log('❌ sendGameInviteMessage error: $e');
      rethrow;
    }
  }

  String _resolveTimeLabel(GameInvitePayload payload) {
    if (payload.gameType == GameType.chess && payload.timeControlSeconds > 0) {
      return '${payload.timeControlSeconds ~/ 60} phút';
    }
    if (payload.gameType == GameType.caro) {
      return payload.boardSize == 3 ? '3×3' : 'vô hạn';
    }
    return '';
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
        'status': MessageStatus.sent
      });

      await _localDb.updateConversationPreview(
        conversationId: groupChatId,
        lastMessage: previewText,
        lastMessageTime: timestamp,
        lastMessageType: TypeMessage.gameResult,
      );

      // ── Bubble: game result notification ─────────────────────────────────
      unawaited(_tryUpdateBubble(
        conversationId: groupChatId,
        userName: payload.player1Name,
        avatarUrl: '',
        content: previewText,
        type: TypeMessage.gameResult,
        fromUser: false,
      ));
      // Play special sound for game result
      unawaited(_tryPlayReceiveSound(groupChatId));

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
        if (!doc.exists) return;
        final data = doc.data()!;
        final currentType = data[FirestoreConstants.type] as int? ?? 0;
        if (currentType != TypeMessage.gameInvite &&
            currentType != TypeMessage.gameLive &&
            currentType != TypeMessage.gameResult) return;

        final rawContent = data[FirestoreConstants.content] as String? ?? '{}';
        String updatedContent = rawContent;
        try {
          final payloadMap = jsonDecode(rawContent) as Map<String, dynamic>;
          payloadMap['matchStatus'] = newStatus.name;
          if (spectatorCount != null)
            payloadMap['spectatorCount'] = spectatorCount;
          updatedContent = jsonEncode(payloadMap);
        } catch (_) {}

        final newType =
            newStatus == MatchStatus.live ? TypeMessage.gameLive : currentType;
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
        final newType =
            newStatus == MatchStatus.live ? TypeMessage.gameLive : currentType;
        await _localDb.saveMessage(groupChatId, messageId, {
          ...existing,
          FirestoreConstants.matchStatus: newStatus.name,
          FirestoreConstants.content: updatedContent,
          FirestoreConstants.type: newType,
        });
      }

      // ── Bubble: live game status update ───────────────────────────────────
      if (newStatus == MatchStatus.live) {
        unawaited(_tryUpdateBubble(
          conversationId: groupChatId,
          userName: 'Game',
          avatarUrl: '',
          content: '🔴 Trận đấu đang diễn ra trực tiếp!',
          type: TypeMessage.gameLive,
          fromUser: false,
        ));
      }

      _log('🔄 Game message status updated: $messageId → ${newStatus.name}');
    } catch (e) {
      _log('❌ updateGameMessageStatus error: $e');
    }
  }
}
