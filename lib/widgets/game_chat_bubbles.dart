import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/message_chat.dart';
import 'package:flutter_chat_demo/pages/match_room_page.dart';
import 'package:flutter_chat_demo/providers/chat_provider.dart';
import 'package:flutter_chat_demo/services/game_firebase_service.dart';
import 'package:provider/provider.dart';

// ─── Design tokens ────────────────────────────────────────────────────────
abstract final class _C {
  static const bg = Color(0xFF141720);
  static const card = Color(0xFF1A1F2E);
  static const accent = Color(0xFF4F8EF7);
  static const live = Color(0xFF00E676);
  static const waiting = Color(0xFFFFD740);
  static const danger = Color(0xFFFF5A5A);
  static const win = Color(0xFF64FFDA);
  static const text1 = Color(0xFFEEF2FF);
  static const text2 = Color(0xFF8B93B0);
  static const divider = Color(0xFF252A3A);
  static const caroGrad = [Color(0xFF667EEA), Color(0xFF764BA2)];
  static const chessGrad = [Color(0xFF11998E), Color(0xFF38EF7D)];
}

// =========================================================
// GAME INVITE CARD BUBBLE
// =========================================================

/// Card hiển thị trong nhóm chat cho tin nhắn TypeMessage.gameInvite.
///
/// Trạng thái waiting  → nút [Vào bàn]
/// Trạng thái live     → nút [Xem trực tiếp] + live indicator
/// Trạng thái finished → text "Đã kết thúc"
/// Trạng thái aborted  → text "Đã huỷ"
class GameInviteCardBubble extends StatefulWidget {
  final MessageChat message;
  final String currentUserId;
  final String currentUserName;
  final String currentUserAvatar;
  final String groupId;

  const GameInviteCardBubble({
    super.key,
    required this.message,
    required this.currentUserId,
    required this.currentUserName,
    required this.currentUserAvatar,
    required this.groupId,
  });

  @override
  State<GameInviteCardBubble> createState() => _GameInviteCardBubbleState();
}

class _GameInviteCardBubbleState extends State<GameInviteCardBubble> {
  bool _isJoining = false;
  Stream<DocumentSnapshot>? _matchStream;

  @override
  void initState() {
    super.initState();
    // Khởi tạo stream 1 lần trong initState để tránh memory leak và rebuild vô ích
    final matchId = widget.message.matchId;
    if (matchId != null && matchId.isNotEmpty) {
      _matchStream = FirebaseFirestore.instance
          .collection(FirestoreConstants.pathGameMatchCollection)
          .doc(matchId)
          .snapshots();
    }
  }

  GameInvitePayload? get _payload {
    try {
      return GameInvitePayload.fromJson(
        jsonDecode(widget.message.content) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  GameType get _gameType => widget.message.parsedGameType;

  List<Color> get _gradient =>
      _gameType == GameType.chess ? _C.chessGrad : _C.caroGrad;

  // ── Join match ────────────────────────────────────────────────────────────

  Future<void> _joinMatch(String matchId, MatchStatus currentStatus) async {
    if (_isJoining) return;

    // KHẮC PHỤC LỖI 8: Kiểm tra challengerId (người dùng gốc bằng UUID) thay vì challengerName (tên dễ trùng)
    final payload = _payload;
    if (payload?.targetUserId != null &&
        payload!.targetUserId != widget.currentUserId &&
        payload.challengerId != widget.currentUserId) {
      // Đối với người ngoài, họ sẽ tham gia dưới dạng khán giả (Spectator)
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MatchRoomPage(
            matchId: matchId,
            currentUserId: widget.currentUserId,
            currentUserName: widget.currentUserName,
            currentUserAvatar: widget.currentUserAvatar,
            groupId: widget.groupId,
          ),
        ),
      );
      return;
    }

    setState(() => _isJoining = true);
    HapticFeedback.mediumImpact();

    try {
      final chatProvider = context.read<ChatProvider>();

      // Kiểm tra trạng thái Realtime thay vì trạng thái tĩnh của tin nhắn
      if (currentStatus == MatchStatus.waiting) {
        // Hàm acceptMatch trong GameFirebaseService đã áp dụng Transaction để tránh Double-Accept
        await GameFirebaseService().acceptMatch(
          matchId: matchId,
          player2Id: widget.currentUserId,
          player2Name: widget.currentUserName,
          player2Avatar: widget.currentUserAvatar,
        );

        // Cập nhật tin nhắn → live
        await chatProvider.updateGameMessageStatus(
          groupChatId: widget.groupId,
          messageId: widget.message.timestamp,
          newStatus: MatchStatus.live,
        );
      }

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MatchRoomPage(
            matchId: matchId,
            currentUserId: widget.currentUserId,
            currentUserName: widget.currentUserName,
            currentUserAvatar: widget.currentUserAvatar,
            groupId: widget.groupId,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không thể vào phòng: $e'),
            backgroundColor: _C.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final payload = _payload;
    final matchId = widget.message.matchId ?? '';
    if (matchId.isEmpty || _matchStream == null) return const SizedBox.shrink();

    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: _C.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.divider, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: StreamBuilder<DocumentSnapshot>(
          stream: _matchStream,
          builder: (context, snap) {
            MatchStatus liveStatus = widget.message.parsedMatchStatus;
            int spectatorCount = payload?.spectatorCount ?? 0;

            if (snap.hasData && snap.data!.exists) {
              final data = snap.data!.data() as Map<String, dynamic>?;
              final statusStr = data?[FirestoreConstants.gameStatus] as String?;
              if (statusStr != null) {
                liveStatus = MatchStatus.fromString(statusStr);
              }
              final ids = data?[FirestoreConstants.spectatorIds] as List?;
              spectatorCount = ids?.length ?? spectatorCount;
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header gradient
                Container(
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: _gradient),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Text(
                        _gameType.emoji,
                        style: const TextStyle(fontSize: 22),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Thách đấu ${_gameType.displayName}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (payload?.timeControlSeconds != null &&
                                payload!.timeControlSeconds > 0)
                              Text(
                                '${(payload.timeControlSeconds / 60).round()} phút',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 10.5,
                                ),
                              ),
                          ],
                        ),
                      ),
                      _StatusBadge(status: liveStatus),
                    ],
                  ),
                ),

                // Body
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Challenger info
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: _C.accent.withOpacity(0.2),
                            backgroundImage:
                                payload?.challengerAvatar.isNotEmpty == true
                                ? NetworkImage(payload!.challengerAvatar)
                                : null,
                            child: payload?.challengerAvatar.isEmpty != false
                                ? const Icon(
                                    Icons.person_rounded,
                                    size: 14,
                                    color: _C.accent,
                                  )
                                : null,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  payload?.challengerName ?? '...',
                                  style: const TextStyle(
                                    color: _C.text1,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (payload?.targetUserName != null)
                                  Text(
                                    'thách @${payload!.targetUserName}',
                                    style: const TextStyle(
                                      color: _C.text2,
                                      fontSize: 10.5,
                                    ),
                                  )
                                else
                                  const Text(
                                    'thách đấu mở',
                                    style: TextStyle(
                                      color: _C.text2,
                                      fontSize: 10.5,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          // Spectator count
                          if (liveStatus == MatchStatus.live &&
                              spectatorCount > 0)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.remove_red_eye_rounded,
                                  size: 12,
                                  color: _C.live,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '$spectatorCount',
                                  style: const TextStyle(
                                    color: _C.live,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      // CTA button theo trạng thái realtime
                      _buildCTA(matchId, liveStatus),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCTA(String matchId, MatchStatus liveStatus) {
    switch (liveStatus) {
      case MatchStatus.waiting:
        // KHẮC PHỤC LỖI 8: So sánh quyền challenger bằng ID thay vì hiển thị
        final isChallenger = _payload?.challengerId == widget.currentUserId;
        if (isChallenger) {
          return const _WaitingChip();
        }
        return _CTAButton(
          label: 'Vào bàn',
          icon: Icons.sports_esports_rounded,
          color: _C.accent,
          isLoading: _isJoining,
          onTap: () => _joinMatch(matchId, liveStatus),
        );

      case MatchStatus.live:
        return _CTAButton(
          label: 'Xem trực tiếp',
          icon: Icons.live_tv_rounded,
          color: _C.live,
          isLoading: _isJoining,
          onTap: () => _joinMatch(matchId, liveStatus),
        );

      case MatchStatus.finished:
        return const _EndedChip(label: 'Đã kết thúc', color: _C.text2);

      case MatchStatus.aborted:
        return const _EndedChip(label: 'Đã huỷ', color: _C.danger);
    }
  }
}

// =========================================================
// GAME RESULT CARD BUBBLE
// =========================================================

/// Card kết quả hiển thị trong nhóm chat cho TypeMessage.gameResult.
/// Có nút [Xem lại] để mở Replay.
class GameResultCardBubble extends StatelessWidget {
  final MessageChat message;
  final String currentUserId;
  final String currentUserName;
  final String currentUserAvatar;
  final String groupId;

  const GameResultCardBubble({
    super.key,
    required this.message,
    required this.currentUserId,
    required this.currentUserName,
    required this.currentUserAvatar,
    required this.groupId,
  });

  GameResultPayload? get _payload {
    try {
      return GameResultPayload.fromJson(
        jsonDecode(message.content) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final payload = _payload;
    final matchId = message.matchId ?? '';
    if (payload == null || matchId.isEmpty) return const SizedBox.shrink();

    final isDraw = payload.result == 'draw';
    final isWinner = payload.winnerId == currentUserId;
    final winnerName = isDraw
        ? null
        : (payload.winnerId == payload.player1Id
              ? payload.player1Name
              : payload.player2Name);

    final emoji = isDraw ? '🤝' : (isWinner ? '🏆' : '⚔️');
    final headline = isDraw ? 'Hòa nhau!' : '$winnerName đã thắng!';

    final List<Color> gradient = isDraw
        ? [const Color(0xFF2C3E50), const Color(0xFF3498DB)]
        : [const Color(0xFF1A2980), const Color(0xFF26D0CE)];

    final mins = payload.durationSeconds ~/ 60;
    final secs = payload.durationSeconds % 60;
    final duration = payload.durationSeconds > 0
        ? '${mins > 0 ? "${mins}p" : ""}${secs}s'
        : '';

    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: _C.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.divider, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            // Header
            Container(
              height: 60,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: gradient),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 8),
                  Text(
                    headline,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),

            // VS row
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
              child: Row(
                children: [
                  Expanded(
                    child: _PlayerResultChip(
                      name: payload.player1Name,
                      avatar: payload.player1Avatar,
                      isWinner: payload.result == 'player1_win',
                      isDraw: isDraw,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      'VS',
                      style: TextStyle(
                        color: _C.text2,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _PlayerResultChip(
                      name: payload.player2Name,
                      avatar: payload.player2Avatar,
                      isWinner: payload.result == 'player2_win',
                      isDraw: isDraw,
                    ),
                  ),
                ],
              ),
            ),

            // Meta row
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 2, 14, 0),
              child: Row(
                children: [
                  Text(
                    '${payload.gameType.emoji} ${payload.gameType.displayName}',
                    style: const TextStyle(color: _C.text2, fontSize: 10.5),
                  ),
                  if (duration.isNotEmpty) ...[
                    const Text(
                      ' · ',
                      style: TextStyle(color: _C.text2, fontSize: 10),
                    ),
                    Text(
                      duration,
                      style: const TextStyle(color: _C.text2, fontSize: 10.5),
                    ),
                  ],
                  if (payload.totalMoves > 0) ...[
                    const Text(
                      ' · ',
                      style: TextStyle(color: _C.text2, fontSize: 10),
                    ),
                    Text(
                      '${payload.totalMoves} nước',
                      style: const TextStyle(color: _C.text2, fontSize: 10.5),
                    ),
                  ],
                ],
              ),
            ),

            // Replay button
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              child: _CTAButton(
                label: 'Xem lại',
                icon: Icons.replay_rounded,
                color: _C.accent,
                onTap: () => _openReplay(context, matchId),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openReplay(BuildContext context, String matchId) {
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MatchRoomPage(
          matchId: matchId,
          currentUserId: currentUserId,
          currentUserName: currentUserName,
          currentUserAvatar: currentUserAvatar,
          groupId: groupId,
        ),
      ),
    );
  }
}

// =========================================================
// SUPPORTING WIDGETS
// =========================================================

class _StatusBadge extends StatelessWidget {
  final MatchStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;

    switch (status) {
      case MatchStatus.waiting:
        color = _C.waiting;
        label = 'Chờ';
        break;
      case MatchStatus.live:
        color = _C.live;
        label = 'Live';
        break;
      case MatchStatus.finished:
        color = _C.text2;
        label = 'Xong';
        break;
      case MatchStatus.aborted:
        color = _C.danger;
        label = 'Huỷ';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CTAButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool isLoading;

  const _CTAButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 36,
    child: ElevatedButton.icon(
      onPressed: isLoading ? null : onTap,
      icon: isLoading
          ? SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          : Icon(icon, size: 16),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withOpacity(0.15),
        foregroundColor: color,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: color.withOpacity(0.4)),
        ),
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
      ),
    ),
  );
}

class _WaitingChip extends StatelessWidget {
  const _WaitingChip();

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    height: 36,
    decoration: BoxDecoration(
      color: _C.waiting.withOpacity(0.08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: _C.waiting.withOpacity(0.3)),
    ),
    child: const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: _C.waiting),
        ),
        SizedBox(width: 7),
        Text(
          'Chờ đối thủ chấp nhận...',
          style: TextStyle(
            color: _C.waiting,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _EndedChip extends StatelessWidget {
  final String label;
  final Color color;
  const _EndedChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    height: 30,
    decoration: BoxDecoration(
      color: color.withOpacity(0.07),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Center(
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

class _PlayerResultChip extends StatelessWidget {
  final String name;
  final String avatar;
  final bool isWinner;
  final bool isDraw;

  const _PlayerResultChip({
    required this.name,
    required this.avatar,
    required this.isWinner,
    required this.isDraw,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDraw ? _C.text2 : (isWinner ? _C.win : _C.danger);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: color.withOpacity(0.2),
            backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
            child: avatar.isEmpty
                ? Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 4),
          Text(
            name.length > 8 ? '${name.substring(0, 7)}…' : name,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (!isDraw)
            Text(isWinner ? '🏆' : '💀', style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
