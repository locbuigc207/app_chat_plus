import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/constants/app_constants.dart';
import 'package:flutter_chat_demo/models/game_match.dart';
import 'package:flutter_chat_demo/models/message_chat.dart';
import 'package:flutter_chat_demo/providers/chat_provider.dart';
import 'package:flutter_chat_demo/providers/game_state_provider.dart';
import 'package:flutter_chat_demo/providers/theme_provider.dart';
import 'package:flutter_chat_demo/services/game_firebase_service.dart';
import 'package:flutter_chat_demo/widgets/caro_infinite_board.dart';
import 'package:flutter_chat_demo/widgets/chess_board_widget.dart'; // Đã thêm thư viện Cờ vua
import 'package:flutter_chat_demo/widgets/game_replay_controls.dart';
import 'package:flutter_chat_demo/widgets/spectator_panel.dart';
import 'package:provider/provider.dart';

// ─── Design tokens ─────────────────────────────────────────────────────────
abstract final class _C {
  static const bg = Color(0xFF0D0F14);
  static const surface = Color(0xFF141720);
  static const card = Color(0xFF181D2A);
  static const live = Color(0xFF00E676);
  static const danger = Color(0xFFFF5A5A);
  static const warning = Color(0xFFFFD740);
  static const text1 = Color(0xFFEEF2FF);
  static const text2 = Color(0xFF8B93B0);
  static const divider = Color(0xFF252A3A);
  static const p1 = Color(0xFFFF5252);
  static const p2 = Color(0xFF40C4FF);
}

// ─── Main Page ────────────────────────────────────────────────────────────────

/// Phòng đấu chính — dùng ChangeNotifierProvider cục bộ
/// để mỗi phòng có GameStateProvider riêng.
class MatchRoomPage extends StatelessWidget {
  final String matchId;
  final String currentUserId;
  final String currentUserName;
  final String currentUserAvatar;
  final String groupId;

  const MatchRoomPage(
      {super.key,
      required this.matchId,
      required this.currentUserId,
      required this.currentUserName,
      required this.currentUserAvatar,
      required this.groupId});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => GameStateProvider(),
      child: _MatchRoomBody(
          matchId: matchId,
          currentUserId: currentUserId,
          currentUserName: currentUserName,
          currentUserAvatar: currentUserAvatar,
          groupId: groupId),
    );
  }
}

// ─── Body ─────────────────────────────────────────────────────────────────────

class _MatchRoomBody extends StatefulWidget {
  final String matchId;
  final String currentUserId;
  final String currentUserName;
  final String currentUserAvatar;
  final String groupId;

  const _MatchRoomBody(
      {required this.matchId,
      required this.currentUserId,
      required this.currentUserName,
      required this.currentUserAvatar,
      required this.groupId});

  @override
  State<_MatchRoomBody> createState() => _MatchRoomBodyState();
}

class _MatchRoomBodyState extends State<_MatchRoomBody>
    with WidgetsBindingObserver {
  late GameStateProvider _gs;
  bool _resultPushed = false;
  Timer? _inviteTimeoutTimer;
  late Color _accent;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _accent = context.read<ThemeProvider>().primaryColor;
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
        matchId: widget.matchId, currentUserId: widget.currentUserId);

    // SỬA LỖI 7: Guard mounted sau quá trình await initialize
    if (!mounted) return;

    _gs.addListener(_onStateChanged);

    // Auto-start replay nếu vào phòng đã kết thúc
    if (_gs.match?.isFinished == true && !_gs.isReplayMode) {
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) await _gs.startReplay();
    }

    // Invite timeout: nếu waiting quá thời gian → abort
    if (_gs.match?.isWaiting == true && _gs.role == PlayerRole.player1) {
      _startInviteTimeout();
    }
  }

  void _startInviteTimeout() {
    _inviteTimeoutTimer?.cancel();
    _inviteTimeoutTimer = Timer(
        Duration(seconds: AppConstants.gameInviteTimeoutSeconds), () async {
      if (!mounted) return;
      final match = _gs.match;
      if (match == null || !match.isWaiting) return;

      // Abort match
      await GameFirebaseService().abortMatch(match.matchId, reason: 'timeout');

      // Update invite message status
      if (match.inviteMessageId != null) {
        try {
          // Lưu cache Provider trước khi xử lý nếu có thao tác rủi ro
          final chatProvider = context.read<ChatProvider>();
          await chatProvider.updateGameMessageStatus(
              groupChatId: widget.groupId,
              messageId: match.inviteMessageId!,
              newStatus: MatchStatus.aborted);
        } catch (_) {}
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Không có đối thủ chấp nhận. Trận đã huỷ.'),
            backgroundColor: _C.warning));
        Navigator.pop(context);
      }
    });
  }

  void _onStateChanged() {
    // Sửa lỗi 11: Huỷ bộ đếm timeout nếu phòng đã được chấp nhận và chơi
    if (_gs.match?.isPlaying == true) {
      _inviteTimeoutTimer?.cancel();
    }

    if (_gs.isGameOver && !_resultPushed && _gs.finalResult != null) {
      _resultPushed = true;
      _pushResult();
    }
  }

  Future<void> _pushResult() async {
    final match = _gs.match;
    if (match == null) return;

    // Sửa lỗi 9: Chỉ gửi tin nhắn Result khi bạn là người chiến thắng.
    // Trong trường hợp hoà, mặc định Player 1 đảm nhận việc gửi kết quả tránh Race Condition double send
    final shouldSend = _gs.finalResult == GameResult.draw
        ? widget.currentUserId == match.player1Id
        : _gs.winnerUserId == widget.currentUserId;

    if (!shouldSend) return;

    try {
      // Đã lấy Provider lên đầu khối try để bảo đảm cache trước khi await (Sửa lỗi 8)
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
        totalMoves: _gs.totalMoveCount,
      );

      await chatProvider.sendGameResultMessage(
          groupChatId: widget.groupId,
          currentUserId: widget.currentUserId,
          payload: payload);

      // Cập nhật thẻ message hiện tại trên group chat sang finish status (Sửa lỗi 14)
      if (match.inviteMessageId != null) {
        await chatProvider.updateGameMessageStatus(
            groupChatId: widget.groupId,
            messageId: match.inviteMessageId!,
            newStatus: MatchStatus.finished);
      }
    } catch (e) {
      debugPrint('[MatchRoomPage] _pushResult error: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _gs.removeListener(_onStateChanged);
    _inviteTimeoutTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _accent = context.watch<ThemeProvider>().primaryColor;
    final isDark = context.watch<ThemeProvider>().isDark;

    return Theme(
      data: isDark ? ThemeData.dark() : ThemeData.light(),
      child: Scaffold(
        backgroundColor: _C.bg,
        body: Consumer<GameStateProvider>(
          builder: (context, gs, _) {
            if (gs.isLoading) return _buildLoading();
            if (gs.errorMessage != null) return _buildError(gs.errorMessage!);
            if (gs.match == null) return _buildLoading();
            return _buildRoom(gs);
          },
        ),
      ),
    );
  }

  Widget _buildLoading() =>
      Center(child: CircularProgressIndicator(color: _accent, strokeWidth: 2));

  Widget _buildError(String msg) => Center(
          child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline_rounded, color: _C.danger, size: 48),
          const SizedBox(height: 12),
          Text(msg,
              style: const TextStyle(color: _C.text2),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _C.surface, foregroundColor: _C.text1),
              child: const Text('Quay lại')),
        ]),
      ));

  Widget _buildRoom(GameStateProvider gs) {
    final match = gs.match!;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: SafeArea(
          child: Column(children: [
        _buildHeader(gs, match),

        // Banners
        if (gs.isGameOver) _buildBanner(gs, match, _BannerType.gameOver),
        if (gs.disconnectedPlayerId != null)
          _buildBanner(gs, match, _BannerType.disconnect),
        if (gs.hasIncomingDrawRequest)
          _buildBanner(gs, match, _BannerType.drawRequest),
        if (match.isWaiting) _buildWaitingBanner(match),

        // Players
        _buildPlayerRow(gs, match, isTop: true),

        // Board
        Expanded(child: _buildBoard(gs, match)),

        // Bottom controls
        _buildPlayerRow(gs, match, isTop: false),

        if (gs.isReplayMode)
          GameReplayControls(gs: gs)
        else if (gs.isPlayer && !gs.isGameOver && match.isPlaying)
          _buildActionBar(gs),

        SpectatorPanel(
            spectatorCount: match.spectatorCount,
            matchId: match.matchId,
            currentUserId: widget.currentUserId,
            // Cờ đánh dấu spectator đã được fix logic update role bên trong GameStateProvider init
            isSpectator: gs.isSpectator),
      ])),
    );
  }

  Widget _buildHeader(GameStateProvider gs, GameMatch match) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
      child: Row(children: [
        IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded,
                size: 18, color: _accent),
            onPressed: _confirmLeave),
        Expanded(
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(match.gameType.emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 6),
          Text(match.gameType.displayName,
              style: const TextStyle(
                  color: _C.text1, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          _StatusPill(gs: gs, match: match, accent: _accent),
        ])),

        // Turn timer
        if (!gs.isGameOver && match.turnTimerSeconds != 0 && gs.isMyTurn)
          _TurnTimerBadge(seconds: gs.turnTimerSeconds),

        // Replay toggle
        if (gs.isGameOver || match.isFinished)
          IconButton(
            icon: Icon(
                gs.isReplayMode ? Icons.close_rounded : Icons.replay_rounded,
                color: _accent,
                size: 20),
            onPressed: gs.isReplayMode ? gs.stopReplay : gs.startReplay,
          ),
      ]),
    );
  }

  Widget _buildWaitingBanner(GameMatch match) => Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
            color: _C.warning.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _C.warning.withValues(alpha: 0.3))),
        child: Row(children: [
          const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 1.5, color: _C.warning)),
          const SizedBox(width: 10),
          const Expanded(
              child: Text('Đang chờ đối thủ chấp nhận...',
                  style: TextStyle(color: _C.warning, fontSize: 12.5))),
          Text('Hết hạn sau ${AppConstants.gameInviteTimeoutSeconds ~/ 60}p',
              style: const TextStyle(color: _C.text2, fontSize: 10.5)),
        ]),
      );

  Widget _buildPlayerRow(GameStateProvider gs, GameMatch match,
      {required bool isTop}) {
    // isTop = đối thủ (hiển thị trên bàn cờ)
    // bottom = mình (hoặc player1 nếu spectator)
    final isPlayer1 = !isTop;
    final isMyRow = (isPlayer1 && gs.role == PlayerRole.player1) ||
        (!isPlayer1 && gs.role == PlayerRole.player2);

    final name = isPlayer1 ? match.player1Name : (match.player2Name ?? '???');
    final avatar =
        isPlayer1 ? match.player1Avatar : (match.player2Avatar ?? '');
    final symbol = isPlayer1 ? 'X' : 'O';
    final color = isPlayer1 ? _C.p1 : _C.p2;
    final isTheirTurn = isPlayer1 ? gs.isPlayer1Turn : !gs.isPlayer1Turn;
    final remainingMs =
        isPlayer1 ? gs.player1RemainingMs : gs.player2RemainingMs;
    final hasChessClock = match.timeControlSeconds > 0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isTheirTurn && !gs.isGameOver
            ? color.withValues(alpha: 0.08)
            : _C.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isTheirTurn && !gs.isGameOver
                ? color.withValues(alpha: 0.4)
                : _C.divider,
            width: isTheirTurn && !gs.isGameOver ? 1.5 : 0.8),
      ),
      child: Row(children: [
        CircleAvatar(
            radius: 18,
            backgroundColor: color.withValues(alpha: 0.2),
            backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
            child: avatar.isEmpty
                ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: TextStyle(color: color, fontWeight: FontWeight.w700))
                : null),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(
                child: Text(name,
                    style: const TextStyle(
                        color: _C.text1,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis)),
            if (isMyRow) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4)),
                child: Text('Bạn',
                    style: TextStyle(
                        color: _accent,
                        fontSize: 9,
                        fontWeight: FontWeight.w700)),
              )
            ],
          ]),
          Text('Quân $symbol', style: TextStyle(color: color, fontSize: 10.5)),
        ])),
        if (hasChessClock && !gs.isGameOver)
          _ClockDisplay(ms: remainingMs, isActive: isTheirTurn, color: color),
        if (!gs.isGameOver)
          AnimatedOpacity(
              opacity: isTheirTurn ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.only(left: 8),
                  decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                            color: color.withValues(alpha: 0.6), blurRadius: 6)
                      ]))),
      ]),
    );
  }

  // SỬA LỖI 2 & 9: Phân loại linh hoạt Cờ Vua và Caro
  Widget _buildBoard(GameStateProvider gs, GameMatch match) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
            color: const Color(0xFF0A0C12),
            borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.hardEdge,
        child: match.gameType == GameType.chess
            ? _buildChessBoard(gs, match)
            : CaroInfiniteBoard(
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

  Widget _buildChessBoard(GameStateProvider gs, GameMatch match) {
    return ChessBoardWidget(
      fen: gs.chessFen,
      isMyTurn: gs.isMyTurn,
      myRole: gs.role,
      onMove: (from, to) => gs.playChessMove(from, to),
    );
  }

  Widget _buildActionBar(GameStateProvider gs) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        child: Row(children: [
          Expanded(
              child: _ActionBtn(
                  icon: Icons.handshake_rounded,
                  label: 'Xin hòa',
                  color: _C.warning,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    gs.requestDraw();
                  })),
          const SizedBox(width: 10),
          Expanded(
              child: _ActionBtn(
                  icon: Icons.flag_rounded,
                  label: 'Đầu hàng',
                  color: _C.danger,
                  onTap: () => _confirmResign(gs))),
        ]),
      );

  // ─── Banners ───────────────────────────────────────────────────────────────

  Widget _buildBanner(GameStateProvider gs, GameMatch match, _BannerType type) {
    switch (type) {
      case _BannerType.gameOver:
        final isWinner = gs.winnerUserId == widget.currentUserId;
        final isDraw = gs.finalResult == GameResult.draw;
        final emoji = isDraw ? '🤝' : (isWinner ? '🏆' : '💀');
        final msg = isDraw
            ? 'Hòa nhau!'
            : (isWinner ? 'Bạn đã thắng!' : 'Bạn đã thua!');
        final borderColor =
            isDraw ? _C.warning : (isWinner ? _C.live : _C.danger);

        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
              color: borderColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor.withValues(alpha: 0.35))),
          child: Row(children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(msg,
                      style: TextStyle(
                          color: borderColor,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700)),
                  if (gs.endReason?.displayText.isNotEmpty == true)
                    Text(gs.endReason!.displayText,
                        style: const TextStyle(color: _C.text2, fontSize: 11)),
                ])),
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Về nhóm',
                    style: TextStyle(
                        color: _accent, fontWeight: FontWeight.w700))),
          ]),
        );

      case _BannerType.disconnect:
        final isOpponent = gs.disconnectedPlayerId != widget.currentUserId;
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
              color: _C.danger.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _C.danger.withValues(alpha: 0.3))),
          child: Row(children: [
            const Icon(Icons.wifi_off_rounded, color: _C.danger, size: 16),
            const SizedBox(width: 8),
            Text(
                isOpponent
                    ? 'Đối thủ mất kết nối (${gs.disconnectCountdown}s)'
                    : 'Bạn đang mất kết nối...',
                style: const TextStyle(color: _C.danger, fontSize: 12)),
          ]),
        );

      case _BannerType.drawRequest:
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
              color: _C.warning.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _C.warning.withValues(alpha: 0.3))),
          child: Row(children: [
            const Icon(Icons.handshake_rounded, color: _C.warning, size: 16),
            const SizedBox(width: 8),
            const Expanded(
                child: Text('Đối thủ đề nghị hòa',
                    style: TextStyle(color: _C.warning, fontSize: 12))),
            TextButton(
                onPressed: gs.acceptDraw,
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 28)),
                child: const Text('Chấp nhận',
                    style: TextStyle(
                        color: _C.live,
                        fontSize: 11,
                        fontWeight: FontWeight.w700))),
            TextButton(
                onPressed: gs.declineDraw,
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 28)),
                child: const Text('Từ chối',
                    style: TextStyle(
                        color: _C.danger,
                        fontSize: 11,
                        fontWeight: FontWeight.w700))),
          ]),
        );
    }
  }

  // ─── Dialogs ───────────────────────────────────────────────────────────────

  Future<void> _confirmResign(GameStateProvider gs) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              backgroundColor: _C.card,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: const Text('Đầu hàng?',
                  style:
                      TextStyle(color: _C.text1, fontWeight: FontWeight.w700)),
              content: const Text(
                  'Bạn chắc chắn muốn đầu hàng? Đối thủ sẽ thắng.',
                  style: TextStyle(color: _C.text2)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child:
                        const Text('Hủy', style: TextStyle(color: _C.text2))),
                TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Đầu hàng',
                        style: TextStyle(
                            color: _C.danger, fontWeight: FontWeight.w700))),
              ],
            ));
    if (ok == true) {
      HapticFeedback.heavyImpact();
      await gs.resign();
    }
  }

  Future<void> _confirmLeave() async {
    final gs = context.read<GameStateProvider>();

    // SỬA LỖI 6: Xử lý giải phóng Spectator dứt điểm trước khi Navigator.pop thay vì gọi async trong dispose()
    if (gs.isSpectator && gs.match != null) {
      await gs.leaveAsSpectator();
    }

    if (gs.isPlayer && !gs.isGameOver && gs.match?.isPlaying == true) {
      final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
                backgroundColor: _C.card,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                title: const Text('Rời phòng?',
                    style: TextStyle(
                        color: _C.text1, fontWeight: FontWeight.w700)),
                content: const Text(
                    'Rời phòng khi đang thi đấu sẽ tính là thua cuộc.',
                    style: TextStyle(color: _C.text2)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Ở lại',
                          style: TextStyle(color: _C.text2))),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Rời phòng',
                          style: TextStyle(
                              color: _C.danger, fontWeight: FontWeight.w700))),
                ],
              ));
      if (ok != true) return;
      await gs.resign();
    }
    if (mounted) Navigator.pop(context);
  }
}

// ─── Enums & Sub-widgets ──────────────────────────────────────────────────────

enum _BannerType { gameOver, disconnect, drawRequest }

class _StatusPill extends StatelessWidget {
  final GameStateProvider gs;
  final GameMatch match;
  final Color accent;

  const _StatusPill(
      {required this.gs, required this.match, required this.accent});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;

    if (gs.isGameOver || match.isFinished) {
      color = _C.text2;
      label = 'Kết thúc';
    } else if (match.isWaiting) {
      color = _C.warning;
      label = 'Chờ đối thủ';
    } else if (gs.isMyTurn) {
      color = _C.live;
      label = 'Lượt bạn';
    } else {
      color = _C.text2;
      label = 'Chờ đối thủ';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 10.5, fontWeight: FontWeight.w700)),
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
            ? _C.danger.withValues(alpha: 0.2)
            : _C.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isUrgent ? _C.danger : _C.warning),
      ),
      child: Text('${seconds}s',
          style: TextStyle(
              color: isUrgent ? _C.danger : _C.warning,
              fontSize: 13,
              fontWeight: FontWeight.w800)),
    );
  }
}

class _ClockDisplay extends StatelessWidget {
  final int ms;
  final bool isActive;
  final Color color;

  const _ClockDisplay(
      {required this.ms, required this.isActive, required this.color});

  @override
  Widget build(BuildContext context) {
    final text = ms < 10000
        ? GameStateProvider.formatClockPrecise(ms)
        : GameStateProvider.formatClock(ms);
    final isLow = ms < 30000;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isLow
            ? _C.danger.withValues(alpha: 0.1)
            : color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: isLow
                ? _C.danger.withValues(alpha: 0.4)
                : color.withValues(alpha: 0.3)),
      ),
      child: Text(text,
          style: TextStyle(
              color: isLow ? _C.danger : color,
              fontSize: 14,
              fontWeight: FontWeight.w800)),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 40,
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.3))),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ]),
        ),
      );
}
