import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/game_match.dart';

class GameFirebaseService {
  static final GameFirebaseService _instance = GameFirebaseService._internal();
  factory GameFirebaseService() => _instance;
  GameFirebaseService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _matchesRef =>
      _db.collection(FirestoreConstants.pathGameMatchCollection);

  DocumentReference<Map<String, dynamic>> _matchDoc(String matchId) => _matchesRef.doc(matchId);

  CollectionReference<Map<String, dynamic>> _movesRef(String matchId) =>
      _matchDoc(matchId).collection(FirestoreConstants.pathGameMovesSubCollection);

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

  Future<void> updateMatch(
    String matchId,
    Map<String, dynamic> data,
  ) async {
    try {
      await _matchDoc(matchId).set(data, SetOptions(merge: true));
      _log('📝 Match updated: $matchId → ${data.keys.join(', ')}');
    } catch (e) {
      _log('❌ updateMatch error: $e');
      rethrow;
    }
  }

  Future<void> acceptMatch({
    required String matchId,
    required String player2Id,
    required String player2Name,
    required String player2Avatar,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch.toString();
    await updateMatch(matchId, {
      FirestoreConstants.player2Id: player2Id,
      FirestoreConstants.player2Name: player2Name,
      FirestoreConstants.player2Avatar: player2Avatar,
      FirestoreConstants.gameStatus: GameMatchStatus.playing.name,
      FirestoreConstants.startedAt: now,
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

  Stream<List<GameMatch>> watchLiveMatchesInGroup(String groupId) {
    return _matchesRef
        .where(FirestoreConstants.sourceGroupId, isEqualTo: groupId)
        .where(
          FirestoreConstants.gameStatus,
          whereIn: [
            GameMatchStatus.waiting.name,
            GameMatchStatus.playing.name,
          ],
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
        });
  }

  Future<void> addMove(String matchId, GameMove move) async {
    try {
      await _movesRef(matchId).doc(move.moveIndex.toString()).set(move.toJson());
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
      final snapshot = await _movesRef(matchId).orderBy(FirestoreConstants.moveIndex).get();
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

  Future<void> markPlayerDisconnected(
    String matchId,
    String userId,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch.toString();
    try {
      await _matchDoc(matchId).set(
        {
          'disconnectedPlayerId': userId,
          'disconnectedAt': now,
        },
        SetOptions(merge: true),
      );
      _log('⚡ Player disconnected: $userId in $matchId');
    } catch (e) {
      _log('❌ markPlayerDisconnected error: $e');
    }
  }

  Future<void> markPlayerReconnected(String matchId) async {
    try {
      await _matchDoc(matchId).update({
        'disconnectedPlayerId': FieldValue.delete(),
        'disconnectedAt': FieldValue.delete(),
      });
      _log('🔌 Player reconnected in $matchId');
    } catch (e) {
      _log('❌ markPlayerReconnected error: $e');
    }
  }

  Stream<Map<String, dynamic>?> watchDisconnectStatus(String matchId) {
    return _matchDoc(matchId).snapshots().map((doc) {
      if (!doc.exists) return null;
      final data = doc.data();
      if (data == null) return null;
      final disconnectedId = data['disconnectedPlayerId'] as String?;
      final disconnectedAt = data['disconnectedAt'] as String?;
      if (disconnectedId == null) return null;
      return {
        'userId': disconnectedId,
        'at': disconnectedAt,
      };
    }).distinct();
  }

  Future<void> linkInviteMessage(
    String matchId,
    String inviteMessageId,
  ) async {
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

  void _log(String msg) {
    debugPrint('[GameFirebaseService] $msg');
  }
}
