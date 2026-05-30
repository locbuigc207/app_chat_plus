import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/models/game_match.dart';
import 'package:flutter_chat_demo/models/message_chat.dart';
import 'package:flutter_chat_demo/providers/chat_provider.dart';
import 'package:flutter_chat_demo/providers/game_state_provider.dart';
import 'package:flutter_chat_demo/widgets/caro_infinite_board.dart';
import 'package:flutter_chat_demo/widgets/game_replay_controls.dart';
import 'package:flutter_chat_demo/widgets/spectator_panel.dart';
import 'package:provider/provider.dart';

// ─── Design tokens ────────────────────────────────────────────────────────
abstract final class _C {
  static const bg = Color(0xFF0D0F14);
  static const surface = Color(0xFF141720);
  static const card = Color(0xFF181D2A);
  static const accent = Color(0xFF4F8EF7);
  static const live = Color(0xFF00E676);
  static const danger = Color(0xFFFF5A5A);
  static const warning = Color(0xFFFFD740);
  static const text1 = Color(0xFFEEF2FF);
  static const text2 = Color(0xFF8B93B0);
  static const divider = Color(0xFF252A3A);
  static const player1c = Color(0xFFFF5252);
  static const player2c = Color(0xFF40C4FF);
}

// =========================================================
// MATCH ROOM PAGE
// =========================================================

/// Phòng đấu chính — dùng ChangeNotifierProvider cục bộ
/// để mỗi phòng có GameStateProvider riêng.
class MatchRoomPage extends StatelessWidget {
  final String matchId;
  final String currentUserId;
  final String currentUserName;
  final String currentUserAvatar;
  final String groupId;

  const MatchRoomPage({
    super.key,
    required this.matchId,
    required this.currentUserId,
    required this.currentUserName,
    required this.currentUserAvatar,
    required this.groupId,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => GameStateProvider(),
      child: _MatchRoomBody(
        matchId: matchId,
        currentUserId: currentUserId,
        currentUserName: currentUserName,
        currentUserAvatar: currentUserAvatar,
        groupId: groupId,
      ),
    );
  }
}

// ── Body (có access vào Provider) ────────────────────────────────────────

class _MatchRoomBody extends StatefulWidget {
  final String matchId;
  final String currentUserId;
  final String currentUserName;
  final String currentUserAvatar;
  final String groupId;

  const _MatchRoomBody({
    required this.matchId,
    required this.currentUserId,
    required this.currentUserName,
    required this.currentUserAvatar,
    required this.groupId,
  });

  @override
  State<_MatchRoomBody> createState() => _MatchRoomBodyState();
}

class _MatchRoomBodyState extends State<_MatchRoomBody>
    with WidgetsBindingObserver {
  late GameStateProvider _gs;
  bool _resultPushed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _gs.onDisconnected();
    } else if (state == AppLifecycleState.resumed) {
      _gs.onReconnected();
    }
  }

  Future<void> _init() async {
    _gs = context.read<GameStateProvider>();
    await _gs.initialize(
      matchId: widget.matchId,
      currentUserId: widget.currentUserId,
    );
    // Lắng nghe game over để push kết quả về nhóm
    _gs.addListener(_onStateChanged);
  }

  void _onStateChanged() {
    if (_gs.isGameOver && !_resultPushed && _gs.finalResult != null) {
      _resultPushed = true;
      _pushResult();
    }
  }

  Future<void> _pushResult() async {
    final match = _gs.match;
    if (match == null) return;

    try {
      final chatProvider = context.read<ChatProvider>();

      final payload = GameResultPayload(
        matchId: match.matchId,
        gameType: match.gameType,
        result: _gs.finalResult!.value,
        player1Id: match.player1Id,
        player1Name: match.player1Name,
        player1Avatar: match.player1Avatar,
        player2Id: match.player2Id ?? '',
        player2Name: match.player2Name ?? '',
        player2Avatar: match.player2Avatar ?? '',
        endReason: _gs.endReason?.label ?? 'unknown',
        durationSeconds: match.durationSeconds ?? 0,
        totalMoves: match.moveHistory.length,
      );

      await chatProvider.sendGameResultMessage(
        groupChatId: widget.groupId,
        currentUserId: widget.currentUserId,
        payload: payload,
      );

      // Update invite message status
      if (match.inviteMessageId != null) {
        await chatProvider.updateGameMessageStatus(
          groupChatId: widget.groupId,
          messageId: match.inviteMessageId!,
          newStatus: MatchStatus.finished,
        );
      }
    } catch (e) {
      debugPrint('[MatchRoomPage] _pushResult error: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _gs.removeListener(_onStateChanged);
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      body: Consumer<GameStateProvider>(
        builder: (context, gs, _) {
          if (gs.isLoading) return _buildLoading();
          if (gs.errorMessage != null) return _buildError(gs.errorMessage!);
          if (gs.match == null) return _buildLoading();
          return _buildRoom(gs);
        },
      ),
    );
  }

  // ── Loading / Error ───────────────────────────────────────────────────────

  Widget _buildLoading() => const Center(
        child: CircularProgressIndicator(color: _C.accent, strokeWidth: 2),
      );

  Widget _buildError(String msg) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: _C.danger, size: 48),
            const SizedBox(height: 12),
            Text(msg,
                style: const TextStyle(color: _C.text2),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Quay lại'),
            ),
          ],
        ),
      );

  // ── Main room ─────────────────────────────────────────────────────────────

  Widget _buildRoom(GameStateProvider gs) {
    final match = gs.match!;
    return SafeArea(
      child: Column(
        children: [
          _buildHeader(gs, match),
          if (gs.isGameOver) _buildGameOverBanner(gs, match),
          if (gs.disconnectedPlayerId != null) _buildDisconnectBanner(gs),
          if (gs.hasIncomingDrawRequest) _buildDrawRequestBanner(gs),
          _buildPlayerRow(gs, match, isTop: true),
          Expanded(child: _buildBoard(gs, match)),
          _buildPlayerRow(gs, match, isTop: false),
          if (gs.isReplayMode)
            GameReplayControls(gs: gs)
          else if (gs.isPlayer && !gs.isGameOver)
            _buildActionBar(gs),
          SpectatorPanel(
            spectatorCount: match.spectatorCount,
            matchId: match.matchId,
            currentUserId: widget.currentUserId,
            isSpectator: gs.isSpectator,
          ),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader(GameStateProvider gs, GameMatch match) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            color: _C.accent,
            onPressed: _confirmLeave,
          ),
          Expanded(
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    match.gameType.emoji,
                    style: const TextStyle(fontSize: 18),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    match.gameType.displayName,
                    style: const TextStyle(
                      color: _C.text1,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Status pill
                  _StatusPill(gs: gs),
                ],
              ),
            ),
          ),
          // Turn timer for Caro
          if (!gs.isGameOver && gs.match?.turnTimerSeconds != 0 && gs.isMyTurn)
            _TurnTimerBadge(seconds: gs.turnTimerSeconds),
          const SizedBox(width: 8),
          // Replay toggle (finished game)
          if (gs.isGameOver)
            IconButton(
              icon: Icon(
                gs.isReplayMode ? Icons.close_rounded : Icons.replay_rounded,
                color: _C.accent,
                size: 20,
              ),
              onPressed: gs.isReplayMode ? gs.stopReplay : gs.startReplay,
            ),
        ],
      ),
    );
  }

  // ── Player row (top = opponent, bottom = me) ──────────────────────────────

  Widget _buildPlayerRow(
    GameStateProvider gs,
    GameMatch match, {
    required bool isTop,
  }) {
    final isPlayer1 = !isTop; // bottom = player1 (self if role=player1)
    final isMyRow = (isPlayer1 && gs.role == PlayerRole.player1) ||
        (!isPlayer1 && gs.role == PlayerRole.player2);

    final name = isPlayer1 ? match.player1Name : (match.player2Name ?? '???');
    final avatar =
        isPlayer1 ? match.player1Avatar : (match.player2Avatar ?? '');
    final symbol = isPlayer1 ? 'X' : 'O';
    final color = isPlayer1 ? _C.player1c : _C.player2c;

    final isTheirTurn = isPlayer1 ? gs.isPlayer1Turn : !gs.isPlayer1Turn;

    final remainingMs =
        isPlayer1 ? gs.player1RemainingMs : gs.player2RemainingMs;
    final hasChessClock = (match.timeControlSeconds > 0);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color:
            isTheirTurn && !gs.isGameOver ? color.withOpacity(0.08) : _C.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isTheirTurn && !gs.isGameOver
              ? color.withOpacity(0.4)
              : _C.divider,
          width: isTheirTurn && !gs.isGameOver ? 1.5 : 0.8,
        ),
      ),
      child: Row(
        children: [
          // Avatar
          CircleAvatar(
            radius: 18,
            backgroundColor: color.withOpacity(0.2),
            backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
            child: avatar.isEmpty
                ? Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          // Name + symbol
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: _C.text1,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (isMyRow) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: _C.accent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Bạn',
                          style: TextStyle(
                            color: _C.accent,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  'Quân $symbol',
                  style: TextStyle(color: color, fontSize: 11),
                ),
              ],
            ),
          ),
          // Chess clock
          if (hasChessClock && !gs.isGameOver)
            _ClockDisplay(
              ms: remainingMs,
              isActive: isTheirTurn,
              color: color,
            ),
          // Turn indicator
          if (!gs.isGameOver)
            AnimatedOpacity(
              opacity: isTheirTurn ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(left: 8),
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.6),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Board ─────────────────────────────────────────────────────────────────

  Widget _buildBoard(GameStateProvider gs, GameMatch match) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0C12),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.hardEdge,
      child: CaroInfiniteBoard(
        board: gs.caroBoard,
        lastMove: gs.lastMove,
        winLine: gs.winLine,
        isMyTurn: gs.isMyTurn,
        isGameOver: gs.isGameOver,
        boardSize: match.boardSize,
        mySymbol: gs.role == PlayerRole.player1 ? 'X' : 'O',
        onTap: (row, col) => gs.playCaroMove(row, col),
      ),
    );
  }

  // ── Action bar (đầu hàng / xin hòa) ──────────────────────────────────────

  Widget _buildActionBar(GameStateProvider gs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: _ActionBtn(
              icon: Icons.handshake_rounded,
              label: 'Xin hòa',
              color: _C.warning,
              onTap: () {
                HapticFeedback.lightImpact();
                gs.requestDraw();
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ActionBtn(
              icon: Icons.flag_rounded,
              label: 'Đầu hàng',
              color: _C.danger,
              onTap: () => _confirmResign(gs),
            ),
          ),
        ],
      ),
    );
  }

  // ── Banners ───────────────────────────────────────────────────────────────

  Widget _buildGameOverBanner(GameStateProvider gs, GameMatch match) {
    final isWinner = gs.winnerUserId == widget.currentUserId;
    final isDraw = gs.finalResult == GameResult.draw;

    final emoji = isDraw ? '🤝' : (isWinner ? '🏆' : '💀');
    final msg =
        isDraw ? 'Hòa nhau!' : (isWinner ? 'Bạn đã thắng!' : 'Bạn đã thua!');
    final reason = gs.endReason?.displayText ?? '';

    final bgColor = isDraw
        ? _C.warning.withOpacity(0.12)
        : (isWinner ? _C.live.withOpacity(0.12) : _C.danger.withOpacity(0.12));
    final borderColor = isDraw ? _C.warning : (isWinner ? _C.live : _C.danger);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  msg,
                  style: TextStyle(
                    color: borderColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (reason.isNotEmpty)
                  Text(
                    reason,
                    style: const TextStyle(color: _C.text2, fontSize: 11.5),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Về nhóm',
              style: TextStyle(color: _C.accent, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDisconnectBanner(GameStateProvider gs) {
    final isOpponent = gs.disconnectedPlayerId != widget.currentUserId;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _C.danger.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _C.danger.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, color: _C.danger, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isOpponent
                  ? 'Đối thủ mất kết nối (${gs.disconnectCountdown}s)'
                  : 'Bạn đang mất kết nối...',
              style: const TextStyle(color: _C.danger, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawRequestBanner(GameStateProvider gs) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _C.warning.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _C.warning.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.handshake_rounded, color: _C.warning, size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Đối thủ đề nghị hòa',
              style: TextStyle(color: _C.warning, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: gs.acceptDraw,
            child: const Text(
              'Chấp nhận',
              style: TextStyle(
                  color: _C.live, fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          TextButton(
            onPressed: gs.declineDraw,
            child: const Text(
              'Từ chối',
              style: TextStyle(
                  color: _C.danger, fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  // ── Dialogs ───────────────────────────────────────────────────────────────

  Future<void> _confirmResign(GameStateProvider gs) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _C.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Đầu hàng?',
            style: TextStyle(color: _C.text1, fontWeight: FontWeight.w700)),
        content: const Text(
          'Bạn chắc chắn muốn đầu hàng? Đối thủ sẽ thắng.',
          style: TextStyle(color: _C.text2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy', style: TextStyle(color: _C.text2)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Đầu hàng',
                style:
                    TextStyle(color: _C.danger, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok == true) {
      HapticFeedback.heavyImpact();
      await gs.resign();
    }
  }

  Future<void> _confirmLeave() async {
    final gs = context.read<GameStateProvider>();
    if (gs.isPlayer && !gs.isGameOver) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _C.card,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Rời phòng?',
              style: TextStyle(color: _C.text1, fontWeight: FontWeight.w700)),
          content: const Text(
            'Rời phòng khi đang thi đấu sẽ tính là thua cuộc.',
            style: TextStyle(color: _C.text2),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Ở lại', style: TextStyle(color: _C.text2)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Rời phòng',
                  style:
                      TextStyle(color: _C.danger, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
      if (ok != true) return;
      await gs.resign();
    }
    if (mounted) Navigator.pop(context);
  }
}

// =========================================================
// SUB-WIDGETS
// =========================================================

class _StatusPill extends StatelessWidget {
  final GameStateProvider gs;
  const _StatusPill({required this.gs});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;

    if (gs.isGameOver) {
      color = _C.text2;
      label = 'Kết thúc';
    } else if (gs.match?.isPlaying == true) {
      color = _C.live;
      label = gs.isMyTurn ? 'Lượt bạn' : 'Chờ đối thủ';
    } else {
      color = _C.warning;
      label = 'Chờ đối thủ';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _TurnTimerBadge extends StatelessWidget {
  final int seconds;
  const _TurnTimerBadge({required this.seconds});

  @override
  Widget build(BuildContext context) {
    final isUrgent = seconds <= 5;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isUrgent
            ? _C.danger.withOpacity(0.2)
            : _C.warning.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isUrgent ? _C.danger : _C.warning,
          width: 1,
        ),
      ),
      child: Text(
        '${seconds}s',
        style: TextStyle(
          color: isUrgent ? _C.danger : _C.warning,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ClockDisplay extends StatelessWidget {
  final int ms;
  final bool isActive;
  final Color color;

  const _ClockDisplay({
    required this.ms,
    required this.isActive,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final text = ms < 10000
        ? GameStateProvider.formatClockPrecise(ms)
        : GameStateProvider.formatClock(ms);
    final isLow = ms < 30000;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isLow ? _C.danger.withOpacity(0.12) : color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isLow ? _C.danger.withOpacity(0.4) : color.withOpacity(0.3),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: isLow ? _C.danger : color,
          fontSize: 14,
          fontWeight: FontWeight.w800,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3), width: 0.8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
}
