import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/game_match.dart';

// =========================================================
// GameFirebaseService
// =========================================================
//
// Trách nhiệm:
//   1. CRUD cho document game_matches/{matchId}
//   2. Stream theo dõi trạng thái trận đấu realtime
//   3. Ghi/đọc sub-collection moves (lịch sử nước đi → Replay)
//   4. Quản lý danh sách spectators (join/leave)
//   5. Đồng bộ trạng thái đồng hồ (ghi remainingTimeMs vào move)
//   6. Xử lý disconnect: cập nhật field 'disconnectedAt' để
//      game_state_provider đếm ngược 60s rồi xử thua
//
// Lưu ý kiến trúc:
//   - Service này CHỈ xử lý Firebase I/O, không chứa game logic.
//   - Game logic (thắng thua, timer, validate move) nằm ở game_state_provider.
//   - Chat integration (gửi tin nhắn vào nhóm) nằm ở chat_provider.
// =========================================================

class GameFirebaseService {
  // ── Singleton ─────────────────────────────────────────────────────────────
  static final GameFirebaseService _instance = GameFirebaseService._internal();
  factory GameFirebaseService() => _instance;
  GameFirebaseService._internal();

  // ── Dependencies ──────────────────────────────────────────────────────────
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Collection references ─────────────────────────────────────────────────
  CollectionReference<Map<String, dynamic>> get _matchesRef =>
      _db.collection(FirestoreConstants.pathGameMatchCollection);

  DocumentReference<Map<String, dynamic>> _matchDoc(String matchId) =>
      _matchesRef.doc(matchId);

  CollectionReference<Map<String, dynamic>> _movesRef(String matchId) =>
      _matchDoc(matchId)
          .collection(FirestoreConstants.pathGameMovesSubCollection);

  // =========================================================
  // 1. TẠO TRẬN ĐẤU MỚI
  // =========================================================

  /// Tạo document trận đấu mới trong Firestore.
  /// Trả về [matchId] vừa tạo.
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

  // =========================================================
  // 2. CẬP NHẬT TRẬN ĐẤU
  // =========================================================

  /// Cập nhật partial fields của trận đấu (merge = true).
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

  /// Player2 chấp nhận thách đấu → update player2 info + status = playing.
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

  /// Kết thúc trận đấu với kết quả.
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

  /// Huỷ trận đấu (hết thời gian chờ, không ai chấp nhận).
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
  // 3. STREAM THEO DÕI TRẬN ĐẤU REALTIME
  // =========================================================

  /// Stream theo dõi document trận đấu — emit mỗi khi có thay đổi.
  /// Dùng trong match_room_page để cập nhật UI realtime.
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

  /// Stream theo dõi danh sách trận đang live trong một nhóm.
  /// Dùng trong game_center_hub_page để hiển thị các trận đang diễn ra.
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

  // =========================================================
  // 4. NƯỚC ĐI (MOVES SUB-COLLECTION)
  // =========================================================

  /// Ghi một nước đi vào sub-collection.
  /// DocumentID = moveIndex.toString() để dễ sắp xếp.
  Future<void> addMove(String matchId, GameMove move) async {
    try {
      await _movesRef(matchId)
          .doc(move.moveIndex.toString())
          .set(move.toJson());
      _log('♟️ Move ${move.moveIndex} added to $matchId');
    } catch (e) {
      _log('❌ addMove error: $e');
      rethrow;
    }
  }

  /// Stream theo dõi nước đi mới nhất — emit ngay khi có nước đi mới.
  /// Dùng trong match_room_page để cập nhật bàn cờ cho cả 2 player và spectator.
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

  /// Tải toàn bộ lịch sử nước đi — dùng cho Replay.
  Future<List<GameMove>> fetchAllMoves(String matchId) async {
    try {
      final snapshot =
          await _movesRef(matchId).orderBy(FirestoreConstants.moveIndex).get();
      final moves = snapshot.docs.map(GameMove.fromDocument).toList();
      _log('📜 Loaded ${moves.length} moves for $matchId');
      return moves;
    } catch (e) {
      _log('❌ fetchAllMoves error: $e');
      return [];
    }
  }

  /// Tải một nước đi theo index — dùng khi Replay tua từng bước.
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
  // 5. QUẢN LÝ SPECTATORS
  // =========================================================

  /// Khán giả vào phòng: thêm userId vào spectatorIds (arrayUnion).
  Future<void> joinAsSpectator(String matchId, String userId) async {
    try {
      await _matchDoc(matchId).update({
        FirestoreConstants.spectatorIds: FieldValue.arrayUnion([userId]),
      });
      _log('👀 $userId joined as spectator: $matchId');
    } catch (e) {
      _log('❌ joinAsSpectator error: $e');
      // Không rethrow — spectator join không nên crash app
    }
  }

  /// Khán giả rời phòng: xóa userId khỏi spectatorIds (arrayRemove).
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
  // 6. DISCONNECT HANDLING
  // =========================================================

  /// Ghi nhận khi một player bị mất kết nối.
  /// game_state_provider sẽ watch field này và đếm ngược 60s.
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

  /// Xóa trạng thái disconnect khi player kết nối lại.
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

  /// Stream theo dõi trạng thái disconnect — emit khi có thay đổi.
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

  // =========================================================
  // 7. INVITE MESSAGE SYNC
  // =========================================================

  /// Cập nhật matchId vào inviteMessageId trong document trận —
  /// được gọi sau khi ChatProvider đã push tin nhắn vào nhóm
  /// và có được messageId từ Firestore.
  Future<void> linkInviteMessage(
    String matchId,
    String inviteMessageId,
  ) async {
    await updateMatch(matchId, {
      FirestoreConstants.inviteMessageId: inviteMessageId,
    });
  }

  // =========================================================
  // 8. FETCH SINGLE MATCH
  // =========================================================

  /// Lấy document trận đấu một lần (không stream).
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

  // =========================================================
  // PRIVATE
  // =========================================================

  void _log(String msg) {
    debugPrint('[GameFirebaseService] $msg');
  }
}
