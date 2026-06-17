import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/game_match.dart';

// =========================================================
// GameFirebaseService
// =========================================================

class GameFirebaseService {
  // ── Singleton ─────────────────────────────────────────────────────────────
  static final GameFirebaseService _instance = GameFirebaseService._internal();
  factory GameFirebaseService() => _instance;
  GameFirebaseService._internal();

  // ── Firestore ─────────────────────────────────────────────────────────────
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Ref helpers ───────────────────────────────────────────────────────────
  CollectionReference<Map<String, dynamic>> get _matchesRef =>
      _db.collection(FirestoreConstants.pathGameMatchCollection);

  DocumentReference<Map<String, dynamic>> _matchDoc(String matchId) =>
      _matchesRef.doc(matchId);

  CollectionReference<Map<String, dynamic>> _movesRef(String matchId) =>
      _matchDoc(
        matchId,
      ).collection(FirestoreConstants.pathGameMovesSubCollection);

  CollectionReference<Map<String, dynamic>> _chatRef(String matchId) =>
      _matchDoc(
        matchId,
      ).collection(FirestoreConstants.pathSpectatorChatSubCollection);

  CollectionReference<Map<String, dynamic>> _reactionsRef(String matchId) =>
      _matchDoc(
        matchId,
      ).collection(FirestoreConstants.pathGameReactionsSubCollection);

  // =========================================================
  // 1. CREATE / UPDATE MATCH
  // =========================================================

  Future<String> createMatch(GameMatch match) async {
    try {
      await _matchDoc(match.matchId).set(match.toJson());
      _log('✅ Match created: ${match.matchId}');
      return match.matchId;
    } catch (e) {
      _log('❌ createMatch error: $e');
      rethrow;
    }
  }

  // Sử dụng update() thay vì set(merge:true) để bảo vệ tính toàn vẹn dữ liệu
  // update() sẽ thất bại (an toàn) nếu document không tồn tại
  Future<void> updateMatch(String matchId, Map<String, dynamic> data) async {
    try {
      await _matchDoc(matchId).update(data);
      _log('📝 Match updated: $matchId → ${data.keys.join(', ')}');
    } catch (e) {
      _log('❌ updateMatch error: $e');
      rethrow;
    }
  }

  // Sử dụng Transaction ngăn chặn Double-Accept
  Future<void> acceptMatch({
    required String matchId,
    required String player2Id,
    required String player2Name,
    required String player2Avatar,
  }) async {
    final docRef = _matchDoc(matchId);

    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);

      if (!snapshot.exists) {
        throw Exception('Trận đấu không tồn tại!');
      }

      final data = snapshot.data();

      // KHẮC PHỤC LỖI 4: Guard chặn race condition khi Cloud Function vừa abort match
      final status = data?[FirestoreConstants.gameStatus] as String?;
      if (status != GameMatchStatus.waiting.name) {
        throw Exception('Trận đấu đã hết hạn hoặc không còn ở trạng thái chờ!');
      }

      if (data?[FirestoreConstants.player2Id] != null) {
        throw Exception('Trận đấu đã có người tham gia!');
      }

      final now = DateTime.now().millisecondsSinceEpoch.toString();
      transaction.update(docRef, {
        FirestoreConstants.player2Id: player2Id,
        FirestoreConstants.player2Name: player2Name,
        FirestoreConstants.player2Avatar: player2Avatar,
        FirestoreConstants.gameStatus: GameMatchStatus.playing.name,
        FirestoreConstants.startedAt: now,
      });
    });

    _log('🎮 Match accepted by $player2Name: $matchId');
  }

  Future<void> finishMatch({
    required String matchId,
    required GameResult result,
    required String endReason,
    required int totalMoves,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch.toString();
    await updateMatch(matchId, {
      FirestoreConstants.gameStatus: GameMatchStatus.finished.name,
      FirestoreConstants.gameResult: result.value,
      FirestoreConstants.gameEndReason: endReason,
      FirestoreConstants.endedAt: now,
    });
    _log('🏁 Match finished: $matchId → ${result.value} ($endReason)');
  }

  Future<void> abortMatch(String matchId, {String reason = 'timeout'}) async {
    final now = DateTime.now().millisecondsSinceEpoch.toString();
    await updateMatch(matchId, {
      FirestoreConstants.gameStatus: GameMatchStatus.aborted.name,
      FirestoreConstants.gameEndReason: reason,
      FirestoreConstants.endedAt: now,
    });
    _log('🚫 Match aborted: $matchId ($reason)');
  }

  // =========================================================
  // 2. STREAMS
  // =========================================================

  Stream<GameMatch?> watchMatch(String matchId) {
    return _matchDoc(matchId).snapshots().map((doc) {
      if (!doc.exists) return null;
      try {
        return GameMatch.fromDocument(doc);
      } catch (e) {
        _log('❌ watchMatch parse error: $e');
        return null;
      }
    });
  }

  // Truy vấn này yêu cầu tạo Compound Index trên Firebase Console:
  // Collection: GameMatch
  // Fields: sourceGroupId (Ascending) + gameStatus (Arrays/In) + createdAt (Descending)
  Stream<List<GameMatch>> watchLiveMatchesInGroup(String groupId) {
    return _matchesRef
        .where(FirestoreConstants.sourceGroupId, isEqualTo: groupId)
        .where(
          FirestoreConstants.gameStatus,
          whereIn: [GameMatchStatus.waiting.name, GameMatchStatus.playing.name],
        )
        .orderBy(FirestoreConstants.createdAt, descending: true)
        .limit(20)
        .snapshots()
        .map((snapshot) {
          final matches = <GameMatch>[];
          for (final doc in snapshot.docs) {
            try {
              matches.add(GameMatch.fromDocument(doc));
            } catch (e) {
              _log('❌ watchLiveMatchesInGroup parse error: $e');
            }
          }
          return matches;
        })
        .transform(
          StreamTransformer.fromHandlers(
            handleError: (error, stackTrace, sink) {
              _log('⚠️ watchLiveMatchesInGroup index error: $error');
              sink.add(const <GameMatch>[]);
            },
          ),
        );
  }

  // =========================================================
  // 3. MOVES
  // =========================================================

  Future<void> addMove(String matchId, GameMove move) async {
    try {
      await _movesRef(
        matchId,
      ).doc(move.moveIndex.toString()).set(move.toJson());
      _log('♟️ Move ${move.moveIndex} added to $matchId');
    } catch (e) {
      _log('❌ addMove error: $e');
      rethrow;
    }
  }

  Stream<GameMove?> watchLatestMove(String matchId) {
    return _movesRef(matchId)
        .orderBy(FirestoreConstants.moveIndex, descending: true)
        .limit(1)
        .snapshots()
        .map((snap) {
          if (snap.docs.isEmpty) return null;
          try {
            return GameMove.fromDocument(snap.docs.first);
          } catch (e) {
            _log('❌ watchLatestMove parse error: $e');
            return null;
          }
        });
  }

  Future<List<GameMove>> fetchAllMoves(String matchId) async {
    try {
      final snapshot = await _movesRef(
        matchId,
      ).orderBy(FirestoreConstants.moveIndex).get();
      final moves = snapshot.docs.map(GameMove.fromDocument).toList();
      _log('📜 Loaded ${moves.length} moves for $matchId');
      return moves;
    } catch (e) {
      _log('❌ fetchAllMoves error: $e');
      return [];
    }
  }

  Future<GameMove?> fetchMove(String matchId, int moveIndex) async {
    try {
      final doc = await _movesRef(matchId).doc(moveIndex.toString()).get();
      if (!doc.exists) return null;
      return GameMove.fromDocument(doc);
    } catch (e) {
      _log('❌ fetchMove error: $e');
      return null;
    }
  }

  // =========================================================
  // 4. SPECTATORS
  // =========================================================

  Future<void> joinAsSpectator(String matchId, String userId) async {
    try {
      await _matchDoc(matchId).update({
        FirestoreConstants.spectatorIds: FieldValue.arrayUnion([userId]),
      });
      _log('👀 $userId joined as spectator: $matchId');
    } catch (e) {
      _log('❌ joinAsSpectator error: $e');
    }
  }

  Future<void> leaveAsSpectator(String matchId, String userId) async {
    try {
      await _matchDoc(matchId).update({
        FirestoreConstants.spectatorIds: FieldValue.arrayRemove([userId]),
      });
      _log('👋 $userId left spectator: $matchId');
    } catch (e) {
      _log('❌ leaveAsSpectator error: $e');
    }
  }

  // =========================================================
  // 5. SPECTATOR CHAT
  // =========================================================

  Future<void> sendSpectatorMessage({
    required String matchId,
    required String userId,
    required String text,
  }) async {
    if (text.trim().isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch.toString();
    try {
      await _chatRef(matchId).doc(now).set({
        FirestoreConstants.spectatorUserId: userId,
        FirestoreConstants.spectatorText: text.trim(),
        FirestoreConstants.spectatorSentAt: now,
      });
    } catch (e) {
      _log('❌ sendSpectatorMessage error: $e');
    }
  }

  Stream<List<SpectatorChatMessage>> watchSpectatorMessages(String matchId) {
    return _chatRef(matchId)
        .orderBy(FirestoreConstants.spectatorSentAt, descending: true)
        .limit(50)
        .snapshots()
        .map(
          (snap) => snap.docs.map((doc) {
            final d = doc.data();
            return SpectatorChatMessage(
              userId: d[FirestoreConstants.spectatorUserId] as String? ?? '',
              text: d[FirestoreConstants.spectatorText] as String? ?? '',
              sentAt: d[FirestoreConstants.spectatorSentAt] as String? ?? '',
            );
          }).toList(),
        );
  }

  // =========================================================
  // 6. REACTIONS (live feed)
  // =========================================================

  Future<void> sendReaction({
    required String matchId,
    required String userId,
    required String emoji,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch.toString();
    try {
      await _reactionsRef(matchId).doc(now).set({
        FirestoreConstants.reactionUserId: userId,
        FirestoreConstants.reactionEmoji: emoji,
        FirestoreConstants.reactionSentAt: now,
      });
    } catch (e) {
      _log('⚠️ sendReaction error: $e');
    }
  }

  Stream<List<GameReaction>> watchRecentReactions(String matchId) {
    return _reactionsRef(matchId)
        .orderBy(FirestoreConstants.reactionSentAt, descending: true)
        .limit(10)
        .snapshots()
        .map(
          (snap) => snap.docs.map((doc) {
            final d = doc.data();
            return GameReaction(
              userId: d[FirestoreConstants.reactionUserId] as String? ?? '',
              emoji: d[FirestoreConstants.reactionEmoji] as String? ?? '',
              sentAt: d[FirestoreConstants.reactionSentAt] as String? ?? '',
            );
          }).toList(),
        );
  }

  // =========================================================
  // 7. DRAW REQUEST
  // =========================================================

  Future<void> updateDrawRequest({
    required String matchId,
    required String requesterId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch.toString();
    try {
      await _matchDoc(matchId).update({
        FirestoreConstants.drawRequest: {
          'requesterId': requesterId,
          'sentAt': now,
        },
      });
    } catch (e) {
      _log('❌ updateDrawRequest error: $e');
    }
  }

  Future<void> clearDrawRequest(String matchId) async {
    try {
      await _matchDoc(
        matchId,
      ).update({FirestoreConstants.drawRequest: FieldValue.delete()});
    } catch (e) {
      _log('⚠️ clearDrawRequest error: $e');
    }
  }

  Stream<DrawRequestInfo?> watchDrawRequest(String matchId) {
    return _matchDoc(matchId).snapshots().map((doc) {
      if (!doc.exists) return null;
      final data = doc.data();
      final req =
          data?[FirestoreConstants.drawRequest] as Map<String, dynamic>?;
      if (req == null) return null;
      return DrawRequestInfo(
        requesterId: req['requesterId'] as String? ?? '',
        sentAt: req['sentAt'] as String? ?? '',
      );
    }).distinct();
  }

  // =========================================================
  // 8. DISCONNECT
  // =========================================================

  Future<void> markPlayerDisconnected(String matchId, String userId) async {
    final now = DateTime.now().millisecondsSinceEpoch.toString();
    try {
      await _matchDoc(matchId).update({
        FirestoreConstants.disconnectedPlayerId: userId,
        FirestoreConstants.disconnectedAt: now,
      });
      _log('⚡ Player disconnected: $userId in $matchId');
    } catch (e) {
      _log('❌ markPlayerDisconnected error: $e');
    }
  }

  Future<void> markPlayerReconnected(String matchId) async {
    try {
      await _matchDoc(matchId).update({
        FirestoreConstants.disconnectedPlayerId: FieldValue.delete(),
        FirestoreConstants.disconnectedAt: FieldValue.delete(),
      });
      _log('🔌 Player reconnected in $matchId');
    } catch (e) {
      _log('❌ markPlayerReconnected error: $e');
    }
  }

  Stream<DisconnectInfo?> watchDisconnectStatus(String matchId) {
    return _matchDoc(matchId).snapshots().map((doc) {
      if (!doc.exists) return null;
      final data = doc.data();
      if (data == null) return null;

      final disconnectedId =
          data[FirestoreConstants.disconnectedPlayerId] as String? ??
          data['disconnectedPlayerId'] as String?;
      final disconnectedAt =
          data[FirestoreConstants.disconnectedAt] as String? ??
          data['disconnectedAt'] as String?;

      if (disconnectedId == null) return null;
      return DisconnectInfo(userId: disconnectedId, at: disconnectedAt ?? '');
    }).distinct();
  }

  // =========================================================
  // 9. MISC & CLEANUP
  // =========================================================

  Future<void> linkInviteMessage(String matchId, String inviteMessageId) async {
    await updateMatch(matchId, {
      FirestoreConstants.inviteMessageId: inviteMessageId,
    });
  }

  Future<GameMatch?> fetchMatch(String matchId) async {
    try {
      final doc = await _matchDoc(matchId).get();
      if (!doc.exists) return null;
      return GameMatch.fromDocument(doc);
    } catch (e) {
      _log('❌ fetchMatch error: $e');
      return null;
    }
  }

  Future<void> cleanupMatchData(String matchId) async {
    try {
      await Future.wait([
        _deleteCollection(_movesRef(matchId)),
        _deleteCollection(_chatRef(matchId)),
        _deleteCollection(_reactionsRef(matchId)),
      ]);
      _log('🧹 Cleanup done for $matchId');
    } catch (e) {
      _log('⚠️ cleanupMatchData error: $e');
    }
  }

  Future<void> _deleteCollection(
    CollectionReference<Map<String, dynamic>> ref,
  ) async {
    const batchSize = 100;
    while (true) {
      final snap = await ref.limit(batchSize).get();
      if (snap.docs.isEmpty) break;
      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      if (snap.docs.length < batchSize) break;
    }
  }

  void _log(String msg) {
    debugPrint('[GameFirebaseService] $msg');
  }
}

// =========================================================
// VALUE OBJECTS
// =========================================================

class SpectatorChatMessage {
  final String userId;
  final String text;
  final String sentAt;

  const SpectatorChatMessage({
    required this.userId,
    required this.text,
    required this.sentAt,
  });
}

class GameReaction {
  final String userId;
  final String emoji;
  final String sentAt;

  const GameReaction({
    required this.userId,
    required this.emoji,
    required this.sentAt,
  });
}

class DrawRequestInfo {
  final String requesterId;
  final String sentAt;

  const DrawRequestInfo({required this.requesterId, required this.sentAt});
}

class DisconnectInfo {
  final String userId;
  final String at;

  const DisconnectInfo({required this.userId, required this.at});
}
