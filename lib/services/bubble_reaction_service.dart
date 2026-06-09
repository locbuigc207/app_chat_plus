// lib/services/bubble_reaction_service.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';

// ═══════════════════════════════════════════════════════════════════════════
// REACTION ENTRY
// ═══════════════════════════════════════════════════════════════════════════

class ReactionEntry {
  final String emoji;
  final String userId;
  final String userName;
  final DateTime addedAt;

  const ReactionEntry({
    required this.emoji,
    required this.userId,
    required this.userName,
    required this.addedAt,
  });

  Map<String, dynamic> toMap() => {
        'emoji': emoji,
        'userId': userId,
        'userName': userName,
        'addedAt': addedAt.millisecondsSinceEpoch,
      };

  factory ReactionEntry.fromMap(Map<String, dynamic> m) => ReactionEntry(
        emoji: m['emoji'] as String,
        userId: m['userId'] as String,
        userName: m['userName'] as String? ?? '',
        addedAt: DateTime.fromMillisecondsSinceEpoch(m['addedAt'] as int),
      );
}

// Aggregated reactions for a single message
class MessageReactions {
  final String messageId;
  // emoji → list of users who reacted
  final Map<String, List<ReactionEntry>> reactions;

  const MessageReactions({
    required this.messageId,
    required this.reactions,
  });

  /// Converts to [BubbleReaction] list for [AdaptiveChatBubble].
  List<BubbleReaction> toBubbleReactions() => reactions.entries
      .where((e) => e.value.isNotEmpty)
      .map((e) => BubbleReaction(
            emoji: e.key,
            count: e.value.length,
            userIds: e.value.map((r) => r.userId).toList(),
          ))
      .toList()
    ..sort((a, b) => b.count.compareTo(a.count));

  bool hasReaction(String emoji, String userId) =>
      reactions[emoji]?.any((r) => r.userId == userId) ?? false;

  MessageReactions copyWith(Map<String, List<ReactionEntry>> updated) =>
      MessageReactions(messageId: messageId, reactions: updated);
}

// ═══════════════════════════════════════════════════════════════════════════
// SERVICE
// ═══════════════════════════════════════════════════════════════════════════

/// Manages emoji reactions on chat messages with:
///  • Optimistic UI — immediate local update before Firestore confirms.
///  • Real-time Firestore listener per conversation.
///  • Toggle semantics — adding an existing reaction removes it.
///  • Debounced writes — rapid taps are batched into a single Firestore op.
///  • LRU-like cache — keeps last [_maxCachedConversations] active.
class BubbleReactionService {
  // ── Singleton ────────────────────────────────────────────────────────────
  static final BubbleReactionService _instance = BubbleReactionService._();
  factory BubbleReactionService() => _instance;
  BubbleReactionService._();

  // ── Firebase ──────────────────────────────────────────────────────────────
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // ── Cache: conversationId → messageId → MessageReactions ─────────────────
  final _cache = <String, Map<String, MessageReactions>>{};

  // ── Stream controllers: conversationId → controller ──────────────────────
  final _controllers =
      <String, StreamController<Map<String, MessageReactions>>>{};

  // ── Firestore listeners ───────────────────────────────────────────────────
  final _listeners = <String, StreamSubscription>{};

  // ── Pending writes (debounce) ─────────────────────────────────────────────
  final _pendingWrites = <String, Timer>{}; // key: "convId/msgId/emoji"

  static const _maxCachedConversations = 10;
  static const _debounceMs = 400;

  // ═════════════════════════════════════════════════════════════════════
  // PUBLIC API
  // ═════════════════════════════════════════════════════════════════════

  /// Stream of all reactions for [conversationId].
  Stream<Map<String, MessageReactions>> reactionsStream(String conversationId) {
    _ensureController(conversationId);
    _ensureFirestoreListener(conversationId);
    return _controllers[conversationId]!.stream;
  }

  /// Get cached reactions for a single message (null if not loaded yet).
  MessageReactions? getMessageReactions(
          String conversationId, String messageId) =>
      _cache[conversationId]?[messageId];

  /// Toggle reaction [emoji] on [messageId] in [conversationId].
  /// Returns the updated [MessageReactions] immediately (optimistic).
  Future<MessageReactions> toggleReaction({
    required String conversationId,
    required String messageId,
    required String emoji,
  }) async {
    final myId = _auth.currentUser?.uid ?? '';
    final myName = _auth.currentUser?.displayName ?? 'Tôi';
    if (myId.isEmpty) throw StateError('User not authenticated');

    final current = _cache[conversationId]?[messageId] ??
        MessageReactions(messageId: messageId, reactions: {});

    final isAdding = !current.hasReaction(emoji, myId);
    final updated = _applyToggle(current, emoji, myId, myName, isAdding);

    // 1. Optimistic update
    _updateCache(conversationId, messageId, updated);
    _emit(conversationId);

    // 2. Debounced Firestore write
    final key = '$conversationId/$messageId/$emoji';
    _pendingWrites[key]?.cancel();
    _pendingWrites[key] = Timer(Duration(milliseconds: _debounceMs), () {
      _writeToFirestore(
          conversationId, messageId, emoji, myId, myName, isAdding);
    });

    return updated;
  }

  /// Remove all reactions by [userId] across all messages in [conversationId].
  Future<void> removeAllReactions(String conversationId, String userId) async {
    final conv = _cache[conversationId];
    if (conv == null) return;
    final batch = _db.batch();
    for (final entry in conv.entries) {
      final msgId = entry.key;
      for (final emoji in entry.value.reactions.keys) {
        if (entry.value.hasReaction(emoji, userId)) {
          final ref = _reactionRef(conversationId, msgId, emoji, userId);
          batch.delete(ref);
        }
      }
    }
    await batch.commit();
  }

  /// Pre-fetch reactions for [messageIds] in [conversationId].
  Future<void> prefetch(String conversationId, List<String> messageIds) async {
    _ensureController(conversationId);
    for (final msgId in messageIds) {
      if (_cache[conversationId]?.containsKey(msgId) == true) continue;
      try {
        await _fetchMessage(conversationId, msgId);
      } catch (e) {
        debugPrint('⚠️ prefetch reaction $msgId: $e');
      }
    }
  }

  void clearConversation(String conversationId) {
    _listeners[conversationId]?.cancel();
    _listeners.remove(conversationId);
    _controllers[conversationId]?.close();
    _controllers.remove(conversationId);
    _cache.remove(conversationId);
    debugPrint('🗑️ Reactions cleared: $conversationId');
  }

  void dispose() {
    for (final sub in _listeners.values) sub.cancel();
    _listeners.clear();
    for (final ctrl in _controllers.values) ctrl.close();
    _controllers.clear();
    for (final t in _pendingWrites.values) t.cancel();
    _pendingWrites.clear();
    _cache.clear();
  }

  // ═════════════════════════════════════════════════════════════════════
  // PRIVATE — Firestore
  // ═════════════════════════════════════════════════════════════════════

  DocumentReference _reactionRef(
          String conv, String msg, String emoji, String uid) =>
      _db
          .collection('messages')
          .doc(conv)
          .collection(conv)
          .doc(msg)
          .collection('reactions')
          .doc('${emoji}_$uid');

  Future<void> _writeToFirestore(
    String conv,
    String msg,
    String emoji,
    String uid,
    String uname,
    bool add,
  ) async {
    try {
      final ref = _reactionRef(conv, msg, emoji, uid);
      if (add) {
        await ref.set(ReactionEntry(
          emoji: emoji,
          userId: uid,
          userName: uname,
          addedAt: DateTime.now(),
        ).toMap());
        debugPrint('✅ Reaction added: $emoji → $msg');
      } else {
        await ref.delete();
        debugPrint('✅ Reaction removed: $emoji → $msg');
      }
    } catch (e) {
      debugPrint('❌ _writeToFirestore reaction: $e');
      // Rollback optimistic update on error
      await _fetchMessage(conv, msg);
      _emit(conv);
    }
  }

  Future<void> _fetchMessage(String conv, String msg) async {
    final snap = await _db
        .collection('messages')
        .doc(conv)
        .collection(conv)
        .doc(msg)
        .collection('reactions')
        .get();

    final reactions = <String, List<ReactionEntry>>{};
    for (final doc in snap.docs) {
      try {
        final entry = ReactionEntry.fromMap(doc.data().cast<String, dynamic>());
        reactions.putIfAbsent(entry.emoji, () => []).add(entry);
      } catch (e) {
        debugPrint('⚠️ reaction parse: $e');
      }
    }
    _updateCache(
        conv, msg, MessageReactions(messageId: msg, reactions: reactions));
  }

  void _ensureFirestoreListener(String conversationId) {
    if (_listeners.containsKey(conversationId)) return;

    // Listen to all reaction sub-collection changes in this conversation
    // via a collection group query scoped to this conversation
    _listeners[conversationId] = _db
        .collection('messages')
        .doc(conversationId)
        .collection(conversationId)
        .snapshots()
        .listen(
      (snap) {
        for (final change in snap.docChanges) {
          if (change.type != DocumentChangeType.removed) {
            // Re-fetch reactions for changed messages
            _fetchMessage(conversationId, change.doc.id)
                .then((_) => _emit(conversationId));
          }
        }
      },
      onError: (e) => debugPrint('❌ reaction listener: $e'),
      cancelOnError: false,
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // PRIVATE — Local state
  // ═════════════════════════════════════════════════════════════════════

  MessageReactions _applyToggle(
    MessageReactions current,
    String emoji,
    String uid,
    String uname,
    bool adding,
  ) {
    final updated = Map<String, List<ReactionEntry>>.from(
      current.reactions.map((k, v) => MapEntry(k, List<ReactionEntry>.from(v))),
    );

    final list = updated.putIfAbsent(emoji, () => []);
    if (adding) {
      list.add(ReactionEntry(
          emoji: emoji, userId: uid, userName: uname, addedAt: DateTime.now()));
    } else {
      list.removeWhere((r) => r.userId == uid);
    }
    if (list.isEmpty) updated.remove(emoji);

    return current.copyWith(updated);
  }

  void _updateCache(String conv, String msgId, MessageReactions reactions) {
    _evictIfNeeded();
    _cache.putIfAbsent(conv, () => {})[msgId] = reactions;
  }

  void _emit(String conv) {
    final ctrl = _controllers[conv];
    if (ctrl != null && !ctrl.isClosed) {
      ctrl.add(Map.unmodifiable(_cache[conv] ?? {}));
    }
  }

  void _ensureController(String conv) {
    if (_controllers[conv] == null || _controllers[conv]!.isClosed) {
      _controllers[conv] =
          StreamController<Map<String, MessageReactions>>.broadcast();
    }
  }

  void _evictIfNeeded() {
    while (_cache.length >= _maxCachedConversations) {
      final oldest = _cache.keys.first;
      clearConversation(oldest);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// REACTION BAR WIDGET (standalone, reusable)
// ═══════════════════════════════════════════════════════════════════════════

/// Shows current reactions and lets the user tap to toggle.
/// Wire to [BubbleReactionService] via its stream.
class ReactionBar extends StatefulWidget {
  final String conversationId;
  final String messageId;
  final bool isMe;
  final void Function(String emoji)? onReact;

  const ReactionBar({
    super.key,
    required this.conversationId,
    required this.messageId,
    required this.isMe,
    this.onReact,
  });

  @override
  State<ReactionBar> createState() => _ReactionBarState();
}

class _ReactionBarState extends State<ReactionBar> {
  final _svc = BubbleReactionService();
  final _myId = FirebaseAuth.instance.currentUser?.uid ?? '';
  MessageReactions? _data;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _data = _svc.getMessageReactions(widget.conversationId, widget.messageId);
    _sub = _svc.reactionsStream(widget.conversationId).listen((map) {
      final entry = map[widget.messageId];
      if (mounted && entry != null) {
        setState(() => _data = entry);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reactions = _data?.toBubbleReactions() ?? [];
    if (reactions.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(
        top: 3,
        left: widget.isMe ? 0 : 44,
        right: widget.isMe ? 18 : 0,
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 3,
        children: reactions.map((r) {
          final myReacted = _data?.hasReaction(r.emoji, _myId) ?? false;
          return _ReactionChip(
            reaction: r,
            myReacted: myReacted,
            onTap: () async {
              await _svc.toggleReaction(
                conversationId: widget.conversationId,
                messageId: widget.messageId,
                emoji: r.emoji,
              );
              widget.onReact?.call(r.emoji);
            },
          );
        }).toList(),
      ),
    );
  }
}

class _ReactionChip extends StatefulWidget {
  final BubbleReaction reaction;
  final bool myReacted;
  final VoidCallback onTap;
  const _ReactionChip(
      {required this.reaction, required this.myReacted, required this.onTap});

  @override
  State<_ReactionChip> createState() => _ReactionChipState();
}

class _ReactionChipState extends State<_ReactionChip>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 100));
    _scale = Tween<double>(begin: 1, end: 0.82)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeIn));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c =
        widget.myReacted ? const Color(0xFF2979FF) : Colors.blueGrey.shade200;

    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: c.withOpacity(widget.myReacted ? 0.12 : 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: c.withOpacity(0.4), width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.reaction.emoji,
                  style: const TextStyle(fontSize: 14, height: 1.1)),
              const SizedBox(width: 3),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  '${widget.reaction.count}',
                  key: ValueKey(widget.reaction.count),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: widget.myReacted
                          ? const Color(0xFF2979FF)
                          : Colors.black54),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
