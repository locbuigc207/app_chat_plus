// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LOCAL DB SERVICE  — AES-256 encrypted Hive storage
// ─────────────────────────────────────────────────────────────────────────────
//
// Boxes (all encrypted):
//   chat_messages_v2   — messages          key: "<convoId>_<msgId>"
//   sync_queue_v2      — offline job queue key: auto-increment int
//   conversations_v2   — convo metadata    key: conversationId
//   drafts_v2          — unsent drafts     key: conversationId
//   reactions_v2       — emoji reactions   key: "<convoId>_<msgId>"  (value: Map<userId, emoji>)
//   pinned_v2          — pinned messages   key: "<convoId>_<msgId>"
//
// Design principles:
//   • One singleton, initialise once before runApp.
//   • All mutating methods are async (Hive writes are async).
//   • Read methods are synchronous (Hive keeps a full in-memory copy).
//   • clearAll() is called on logout and wipes everything.
// ─────────────────────────────────────────────────────────────────────────────

class LocalDbService {
  // ── Singleton ──────────────────────────────────────────────────────────────
  LocalDbService._internal();
  static final LocalDbService _instance = LocalDbService._internal();
  factory LocalDbService() => _instance;

  // ── Storage keys ───────────────────────────────────────────────────────────
  static const _kHiveKey = 'hive_secure_key_v2';
  static const _kMessagesBox = 'chat_messages_v2';
  static const _kSyncBox = 'sync_queue_v2';
  static const _kConvoBox = 'conversations_v2';
  static const _kDraftsBox = 'drafts_v2';
  static const _kReactionsBox = 'reactions_v2';
  static const _kPinnedBox = 'pinned_v2';

  // ── Internal ───────────────────────────────────────────────────────────────
  final _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  late Box _messagesBox;
  late Box _syncQueueBox;
  late Box _conversationsBox;
  late Box _draftsBox;
  late Box _reactionsBox;
  late Box _pinnedBox;

  bool _initialized = false;

  // ── Public accessors ───────────────────────────────────────────────────────
  Box get messagesBox => _messagesBox;
  Box get syncQueueBox => _syncQueueBox;
  Box get conversationsBox => _conversationsBox;
  bool get isInitialized => _initialized;

  // ─────────────────────────────────────────────────────────────────────────
  // INITIALIZE
  // ─────────────────────────────────────────────────────────────────────────

  /// Opens all encrypted boxes. Call once before `runApp`.
  Future<void> initialize() async {
    if (_initialized) return;

    await Hive.initFlutter();
    final cipher = await _resolveEncryptionCipher();

    _messagesBox = await Hive.openBox(_kMessagesBox, encryptionCipher: cipher);
    _syncQueueBox = await Hive.openBox(_kSyncBox, encryptionCipher: cipher);
    _conversationsBox =
        await Hive.openBox(_kConvoBox, encryptionCipher: cipher);
    _draftsBox = await Hive.openBox(_kDraftsBox, encryptionCipher: cipher);
    _reactionsBox =
        await Hive.openBox(_kReactionsBox, encryptionCipher: cipher);
    _pinnedBox = await Hive.openBox(_kPinnedBox, encryptionCipher: cipher);

    _initialized = true;
    debugPrint('[LocalDbService] ✅ Initialized — 6 encrypted boxes open');
  }

  Future<HiveAesCipher> _resolveEncryptionCipher() async {
    String? keyStr = await _secureStorage.read(key: _kHiveKey);
    if (keyStr == null) {
      final newKey = Hive.generateSecureKey();
      keyStr = base64UrlEncode(newKey);
      await _secureStorage.write(key: _kHiveKey, value: keyStr);
    }
    return HiveAesCipher(base64Url.decode(keyStr));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MESSAGES
  // ─────────────────────────────────────────────────────────────────────────

  /// Upsert a single message.
  Future<void> saveMessage(
    String conversationId,
    String messageId,
    Map<String, dynamic> data,
  ) async {
    _assertInit();
    await _messagesBox.put('${conversationId}_$messageId', data);
  }

  /// All messages for a conversation, newest first.
  List<Map<dynamic, dynamic>> getMessages(String conversationId) {
    _assertInit();
    final prefix = '${conversationId}_';
    final msgs = _messagesBox.keys
        .where((k) => k.toString().startsWith(prefix))
        .map((k) => _messagesBox.get(k) as Map<dynamic, dynamic>)
        .toList();

    msgs.sort((a, b) {
      final ta = _ts(a['timestamp']);
      final tb = _ts(b['timestamp']);
      return tb.compareTo(ta);
    });
    return msgs;
  }

  /// Returns a page of messages, newest first.
  List<Map<dynamic, dynamic>> getMessagesPaged(
    String conversationId, {
    int offset = 0,
    int limit = 30,
  }) {
    final all = getMessages(conversationId);
    if (offset >= all.length) return [];
    return all.sublist(offset, (offset + limit).clamp(0, all.length));
  }

  /// Lookup by messageId — O(1).
  Map<dynamic, dynamic>? getMessage(String conversationId, String messageId) {
    _assertInit();
    return _messagesBox.get('${conversationId}_$messageId')
        as Map<dynamic, dynamic>?;
  }

  Future<void> deleteMessage(String conversationId, String messageId) async {
    _assertInit();
    await _messagesBox.delete('${conversationId}_$messageId');
  }

  int countMessages(String conversationId) {
    final prefix = '${conversationId}_';
    return _messagesBox.keys
        .where((k) => k.toString().startsWith(prefix))
        .length;
  }

  Future<void> clearConversationMessages(String conversationId) async {
    _assertInit();
    final prefix = '${conversationId}_';
    final keys = _messagesBox.keys
        .where((k) => k.toString().startsWith(prefix))
        .toList();
    await _messagesBox.deleteAll(keys);
    debugPrint(
        '[LocalDbService] 🗑 Cleared ${keys.length} messages for $conversationId');
  }

  /// Updates the `status` field of a stored message (e.g. sent → delivered → read).
  Future<void> updateMessageStatus(
    String conversationId,
    String messageId,
    String status,
  ) async {
    _assertInit();
    final key = '${conversationId}_$messageId';
    final local = _messagesBox.get(key);
    if (local == null) return;
    final updated = Map<String, dynamic>.from(local as Map)
      ..['status'] = status;
    await _messagesBox.put(key, updated);
  }

  /// Marks all unread messages in a conversation as read.
  Future<int> markAllAsRead(String conversationId, String currentUserId) async {
    _assertInit();
    final prefix = '${conversationId}_';
    int count = 0;
    final updates = <String, Map<String, dynamic>>{};

    for (final key in _messagesBox.keys) {
      if (!key.toString().startsWith(prefix)) continue;
      final msg = _messagesBox.get(key) as Map?;
      if (msg == null) continue;
      if (msg['idTo'] == currentUserId && msg['status'] != 'read') {
        updates[key.toString()] = Map<String, dynamic>.from(msg)
          ..['status'] = 'read';
        count++;
      }
    }

    for (final e in updates.entries) {
      await _messagesBox.put(e.key, e.value);
    }
    return count;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CONVERSATIONS
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> updateConversationPreview({
    required String conversationId,
    required String lastMessage,
    required String lastMessageTime,
    required int lastMessageType,
  }) async {
    _assertInit();
    final existing =
        _conversationsBox.get(conversationId) as Map<dynamic, dynamic>?;

    if (existing != null) {
      await _conversationsBox.put(conversationId, {
        ...Map<String, dynamic>.from(existing),
        'lastMessage': lastMessage,
        'lastMessageTime': lastMessageTime,
        'lastMessageType': lastMessageType,
      });
    } else {
      final parts = conversationId.split('-');
      await _conversationsBox.put(conversationId, <String, dynamic>{
        'conversationId': conversationId,
        'participants': parts,
        'isGroup': false,
        'lastMessage': lastMessage,
        'lastMessageTime': lastMessageTime,
        'lastMessageType': lastMessageType,
      });
    }
  }

  Future<void> saveConversation(
      String conversationId, Map<String, dynamic> data) async {
    _assertInit();
    await _conversationsBox.put(conversationId, data);
  }

  Map<dynamic, dynamic>? getConversation(String conversationId) {
    _assertInit();
    return _conversationsBox.get(conversationId) as Map<dynamic, dynamic>?;
  }

  /// All conversations sorted newest-first by lastMessageTime.
  List<Map<dynamic, dynamic>> getAllConversations() {
    _assertInit();
    final list =
        _conversationsBox.values.cast<Map<dynamic, dynamic>>().toList();
    list.sort((a, b) =>
        _ts(b['lastMessageTime']).compareTo(_ts(a['lastMessageTime'])));
    return list;
  }

  /// Paginated — returns [limit] conversations starting at [offset].
  List<Map<dynamic, dynamic>> getConversationsPaged({
    int offset = 0,
    int limit = 20,
  }) {
    final all = getAllConversations();
    if (offset >= all.length) return [];
    return all.sublist(offset, (offset + limit).clamp(0, all.length));
  }

  Future<void> deleteConversation(String conversationId) async {
    _assertInit();
    await _conversationsBox.delete(conversationId);
    await clearConversationMessages(conversationId);
    await clearDraft(conversationId);
    await _clearPinnedForConversation(conversationId);
    await _clearReactionsForConversation(conversationId);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DRAFT MESSAGES
  // ─────────────────────────────────────────────────────────────────────────

  /// Saves an unsent draft for [conversationId]. Pass empty string to clear.
  Future<void> saveDraft(String conversationId, String text) async {
    _assertInit();
    if (text.isEmpty) {
      await _draftsBox.delete(conversationId);
    } else {
      await _draftsBox.put(conversationId, {
        'text': text,
        'savedAt': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  /// Returns the unsent draft text for [conversationId], or null.
  String? getDraft(String conversationId) {
    _assertInit();
    final data = _draftsBox.get(conversationId) as Map?;
    return data?['text'] as String?;
  }

  Future<void> clearDraft(String conversationId) async {
    _assertInit();
    await _draftsBox.delete(conversationId);
  }

  /// Map of conversationId → draft text for all pending drafts.
  Map<String, String> getAllDrafts() {
    _assertInit();
    final result = <String, String>{};
    for (final key in _draftsBox.keys) {
      final data = _draftsBox.get(key) as Map?;
      final text = data?['text'] as String?;
      if (text != null && text.isNotEmpty) {
        result[key.toString()] = text;
      }
    }
    return result;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // REACTIONS
  // Key scheme: "<conversationId>_<messageId>"
  // Value: Map<String, String>  →  { userId: emoji }
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> saveReaction({
    required String conversationId,
    required String messageId,
    required String userId,
    required String emoji,
  }) async {
    _assertInit();
    final key = '${conversationId}_$messageId';
    final existing =
        (_reactionsBox.get(key) as Map?)?.cast<String, String>() ?? {};
    existing[userId] = emoji;
    await _reactionsBox.put(key, existing);
  }

  /// Returns Map<userId, emoji> for [messageId].
  Map<String, String> getReactions(String conversationId, String messageId) {
    _assertInit();
    final key = '${conversationId}_$messageId';
    return (_reactionsBox.get(key) as Map?)?.cast<String, String>() ?? {};
  }

  Future<void> removeReaction({
    required String conversationId,
    required String messageId,
    required String userId,
  }) async {
    _assertInit();
    final key = '${conversationId}_$messageId';
    final existing =
        (_reactionsBox.get(key) as Map?)?.cast<String, String>() ?? {};
    existing.remove(userId);
    if (existing.isEmpty) {
      await _reactionsBox.delete(key);
    } else {
      await _reactionsBox.put(key, existing);
    }
  }

  Future<void> _clearReactionsForConversation(String conversationId) async {
    final prefix = '${conversationId}_';
    final keys = _reactionsBox.keys
        .where((k) => k.toString().startsWith(prefix))
        .toList();
    await _reactionsBox.deleteAll(keys);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PINNED MESSAGES
  // Key: "<conversationId>_<messageId>"   Value: full message Map
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> pinMessage(
      String conversationId, Map<String, dynamic> message) async {
    _assertInit();
    final msgId = message['messageId']?.toString() ??
        message['timestamp']?.toString() ??
        '';
    if (msgId.isEmpty) return;
    await _pinnedBox.put('${conversationId}_$msgId', {
      ...message,
      'pinnedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  List<Map<dynamic, dynamic>> getPinnedMessages(String conversationId) {
    _assertInit();
    final prefix = '${conversationId}_';
    final list = _pinnedBox.keys
        .where((k) => k.toString().startsWith(prefix))
        .map((k) => _pinnedBox.get(k) as Map<dynamic, dynamic>)
        .toList();
    list.sort((a, b) => _ts(b['pinnedAt']).compareTo(_ts(a['pinnedAt'])));
    return list;
  }

  Future<void> unpinMessage(String conversationId, String messageId) async {
    _assertInit();
    await _pinnedBox.delete('${conversationId}_$messageId');
  }

  Future<void> _clearPinnedForConversation(String conversationId) async {
    final prefix = '${conversationId}_';
    final keys =
        _pinnedBox.keys.where((k) => k.toString().startsWith(prefix)).toList();
    await _pinnedBox.deleteAll(keys);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LOCAL SEARCH
  // ─────────────────────────────────────────────────────────────────────────

  /// Full-text search within a single conversation (case-insensitive).
  /// Returns results sorted newest-first.
  List<Map<dynamic, dynamic>> searchMessages(
    String conversationId,
    String query, {
    int limit = 50,
  }) {
    _assertInit();
    if (query.trim().isEmpty) return [];

    final lq = query.toLowerCase();
    final prefix = '${conversationId}_';

    final results = <Map<dynamic, dynamic>>[];
    for (final key in _messagesBox.keys) {
      if (!key.toString().startsWith(prefix)) continue;
      final msg = _messagesBox.get(key) as Map?;
      if (msg == null) continue;
      final content = msg['content']?.toString().toLowerCase() ?? '';
      if (content.contains(lq)) {
        results.add(msg as Map<dynamic, dynamic>);
      }
    }

    results.sort((a, b) => _ts(b['timestamp']).compareTo(_ts(a['timestamp'])));
    return results.take(limit).toList();
  }

  /// Global search across ALL conversations.
  List<MessageSearchHit> searchGlobal(String query, {int limit = 100}) {
    _assertInit();
    if (query.trim().isEmpty) return [];

    final lq = query.toLowerCase();
    final hits = <_SearchHit>[];

    for (final key in _messagesBox.keys) {
      final msg = _messagesBox.get(key) as Map?;
      if (msg == null) continue;
      final content = msg['content']?.toString().toLowerCase() ?? '';
      if (!content.contains(lq)) continue;

      final keyStr = key.toString();
      final underscoreIdx = keyStr.indexOf('_');
      final conversationId =
          underscoreIdx > 0 ? keyStr.substring(0, underscoreIdx) : keyStr;

      hits.add(_SearchHit(
        conversationId: conversationId,
        message: msg as Map<dynamic, dynamic>,
        matchedContent: msg['content']?.toString() ?? '',
        timestamp: _ts(msg['timestamp']),
      ));
    }

    hits.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    // Convert to public model
    return hits.take(limit).map((hit) => MessageSearchHit.from(hit)).toList();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // EXPORT
  // ─────────────────────────────────────────────────────────────────────────

  /// Formats a conversation as a plain-text transcript suitable for sharing.
  String exportConversationText({
    required String conversationId,
    required String currentUserId,
    String myName = 'Me',
    String peerName = 'Peer',
    int messageLimit = 500,
  }) {
    _assertInit();
    final msgs = getMessages(conversationId).reversed.take(messageLimit);
    final buffer = StringBuffer();

    buffer.writeln('── Chat Export ──');
    buffer.writeln(
        'Exported: ${DateTime.now().toIso8601String().substring(0, 16)}');
    buffer.writeln('');

    for (final m in msgs) {
      final isMine = m['idFrom']?.toString() == currentUserId;
      final sender = isMine ? myName : peerName;
      final content = m['content']?.toString() ?? '';
      final ts = _ts(m['timestamp']);
      final dateStr = ts > 0
          ? DateTime.fromMillisecondsSinceEpoch(ts)
              .toIso8601String()
              .substring(0, 16)
              .replaceAll('T', ' ')
          : '';

      buffer.writeln('[$dateStr] $sender: $content');
    }

    return buffer.toString();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SYNC QUEUE
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> addToSyncQueue(Map<String, dynamic> task) async {
    _assertInit();
    await _syncQueueBox.add({
      ...task,
      'retries': 0,
      'nextRetryAt': 0,
      'addedAt': DateTime.now().toIso8601String(),
    });
  }

  Future<void> removeFromSyncQueue(int key) async {
    _assertInit();
    await _syncQueueBox.delete(key);
  }

  Future<void> updateSyncJob(int key, Map<String, dynamic> data) async {
    _assertInit();
    final existing = _syncQueueBox.get(key) as Map?;
    if (existing == null) return;
    await _syncQueueBox.put(key, {
      ...Map<String, dynamic>.from(existing),
      ...data,
    });
  }

  int get syncQueueLength => _syncQueueBox.length;

  /// Returns all jobs that are ready to process (nextRetryAt <= now).
  List<MapEntry<dynamic, Map<String, dynamic>>> getReadySyncJobs({
    int batchSize = 20,
  }) {
    _assertInit();
    final now = DateTime.now().millisecondsSinceEpoch;
    final result = <MapEntry<dynamic, Map<String, dynamic>>>[];

    for (final key in _syncQueueBox.keys) {
      if (result.length >= batchSize) break;
      final raw = _syncQueueBox.get(key) as Map?;
      if (raw == null) continue;
      final job = Map<String, dynamic>.from(raw);
      final nextRetryAt = job['nextRetryAt'] as int? ?? 0;
      if (nextRetryAt <= now) {
        result.add(MapEntry(key, job));
      }
    }

    return result;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MAINTENANCE
  // ─────────────────────────────────────────────────────────────────────────

  /// Full wipe — call on logout.
  Future<void> clearAll() async {
    _assertInit();
    await Future.wait([
      _messagesBox.clear(),
      _syncQueueBox.clear(),
      _conversationsBox.clear(),
      _draftsBox.clear(),
      _reactionsBox.clear(),
      _pinnedBox.clear(),
    ]);
    debugPrint('[LocalDbService] 🧹 All local data cleared');
  }

  /// Deletes messages older than [days] days.
  /// Returns the count of pruned messages.
  Future<int> pruneOldMessages({int days = 30}) async {
    _assertInit();
    final cutoff =
        DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;

    final toDelete = _messagesBox.keys.where((k) {
      final msg = _messagesBox.get(k) as Map?;
      if (msg == null) return false;
      return _ts(msg['timestamp']) < cutoff;
    }).toList();

    await _messagesBox.deleteAll(toDelete);
    debugPrint('[LocalDbService] 🗑 Pruned ${toDelete.length} old messages');
    return toDelete.length;
  }

  /// Keeps only the newest [keepCount] messages per conversation and
  /// removes everything older.  More aggressive than pruneOldMessages.
  Future<int> pruneByCount({int keepCount = 200}) async {
    _assertInit();
    int totalPruned = 0;

    // Group keys by conversationId
    final grouped = <String, List<String>>{};
    for (final key in _messagesBox.keys) {
      final ks = key.toString();
      final idx = ks.lastIndexOf('_');
      if (idx < 0) continue;
      final convo = ks.substring(0, idx);
      grouped.putIfAbsent(convo, () => []).add(ks);
    }

    for (final entry in grouped.entries) {
      final keys = entry.value;
      if (keys.length <= keepCount) continue;

      // Sort by timestamp ascending so we delete the oldest first
      keys.sort((a, b) {
        final ma = _messagesBox.get(a) as Map?;
        final mb = _messagesBox.get(b) as Map?;
        return _ts(ma?['timestamp']).compareTo(_ts(mb?['timestamp']));
      });

      final toDelete = keys.sublist(0, keys.length - keepCount);
      await _messagesBox.deleteAll(toDelete);
      totalPruned += toDelete.length;
    }

    if (totalPruned > 0) {
      debugPrint(
          '[LocalDbService] ✂️ pruneByCount removed $totalPruned messages');
    }
    return totalPruned;
  }

  /// Compacts all Hive boxes to reclaim deleted-entry space.
  Future<void> vacuum() async {
    _assertInit();
    await Future.wait([
      _messagesBox.compact(),
      _syncQueueBox.compact(),
      _conversationsBox.compact(),
      _draftsBox.compact(),
      _reactionsBox.compact(),
      _pinnedBox.compact(),
    ]);
    debugPrint('[LocalDbService] 🔧 Vacuum complete');
  }

  /// Storage statistics.
  Map<String, int> get stats => {
        'messages': _messagesBox.length,
        'syncQueue': _syncQueueBox.length,
        'conversations': _conversationsBox.length,
        'drafts': _draftsBox.length,
        'reactions': _reactionsBox.length,
        'pinned': _pinnedBox.length,
      };

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  void _assertInit() {
    assert(_initialized,
        'LocalDbService chưa được khởi tạo. Gọi initialize() trước.');
  }

  static int _ts(dynamic raw) => int.tryParse(raw?.toString() ?? '0') ?? 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// Search result model
// ─────────────────────────────────────────────────────────────────────────────

class _SearchHit {
  final String conversationId;
  final Map<dynamic, dynamic> message;
  final String matchedContent;
  final int timestamp;

  const _SearchHit({
    required this.conversationId,
    required this.message,
    required this.matchedContent,
    required this.timestamp,
  });
}

/// Public-facing search hit — exposed from [LocalDbService.searchGlobal].
class MessageSearchHit {
  final String conversationId;
  final Map<dynamic, dynamic> message;
  final String matchedContent;
  final DateTime timestamp;

  const MessageSearchHit({
    required this.conversationId,
    required this.message,
    required this.matchedContent,
    required this.timestamp,
  });

  factory MessageSearchHit.from(_SearchHit hit) => MessageSearchHit(
        conversationId: hit.conversationId,
        message: hit.message,
        matchedContent: hit.matchedContent,
        timestamp: hit.timestamp > 0
            ? DateTime.fromMillisecondsSinceEpoch(hit.timestamp)
            : DateTime.now(),
      );
}
