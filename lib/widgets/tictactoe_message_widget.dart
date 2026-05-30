import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/models/game_match.dart';
import 'package:flutter_chat_demo/models/message_chat.dart';
import 'package:flutter_chat_demo/pages/match_room_page.dart';
import 'package:flutter_chat_demo/services/game_firebase_service.dart';

// ─── Design tokens ────────────────────────────────────────────────────────
abstract final class _C {
  static const bg = Color(0xFF1A1A2E);
  static const surface = Color(0xFF16213E);
  static const accent = Color(0xFF64FFDA);
  static const xColor = Color(0xFFFF5252);
  static const oColor = Color(0xFF40C4FF);
  static const text1 = Color(0xFFEEF2FF);
  static const text2 = Color(0xFF8B93B0);
  static const border = Color(0xFF0F3460);
  static const live = Color(0xFF00E676);
  static const waiting = Color(0xFFFFD740);
}

// =========================================================
// TIC TAC TOE MESSAGE WIDGET (REDIRECT CARD)
// =========================================================

/// Card hiển thị trong nhóm chat cho tin nhắn type=7 (legacy game).
///
/// Chế độ hoạt động:
/// • Nếu có [matchId] (trận mới từ Game Center) → redirect vào MatchRoomPage
/// • Nếu không có matchId (legacy content JSON) → hiển thị snapshot 3x3
///   kèm nút "Mở phòng đấu" nếu trận chưa kết thúc
class TicTacToeMessageWidget extends StatelessWidget {
  final String content;
  final String messageId;
  final String groupId;
  final String currentUserId;

  // Game Center fields (optional — set khi tin nhắn được tạo từ game_setup_page)
  final String? matchId;
  final String currentUserName;
  final String currentUserAvatar;

  const TicTacToeMessageWidget({
    super.key,
    required this.content,
    required this.messageId,
    required this.groupId,
    required this.currentUserId,
    this.matchId,
    this.currentUserName = '',
    this.currentUserAvatar = '',
  });

  // ── Parse legacy content ─────────────────────────────────────────────────

  Map<String, dynamic>? get _legacyState {
    try {
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  List<String> get _board {
    final state = _legacyState;
    if (state == null) return List.filled(9, '');
    return List<String>.from(
        (state['board'] as List?)?.map((e) => e?.toString() ?? '') ??
            List.filled(9, ''));
  }

  String get _winner => _legacyState?['winner']?.toString() ?? '';
  String get _turn => _legacyState?['turn']?.toString() ?? '';
  String get _playerX => _legacyState?['playerX']?.toString() ?? '';
  String get _playerO => _legacyState?['playerO']?.toString() ?? '';

  bool get _isGameOver => _winner.isNotEmpty;
  bool get _isMyturn => _turn == currentUserId;
  String get _mySymbol {
    if (_playerX == currentUserId) return 'X';
    if (_playerO == currentUserId) return 'O';
    return '';
  }

  // ── Navigate ──────────────────────────────────────────────────────────────

  Future<void> _openRoom(BuildContext context, String mId) async {
    HapticFeedback.mediumImpact();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MatchRoomPage(
          matchId: mId,
          currentUserId: currentUserId,
          currentUserName: currentUserName,
          currentUserAvatar: currentUserAvatar,
          groupId: groupId,
        ),
      ),
    );
  }

  Future<void> _createAndOpenRoom(BuildContext context) async {
    HapticFeedback.mediumImpact();

    // Tạo GameMatch mới từ legacy content nếu chưa có matchId
    final newMatchId = '${groupId}_$messageId';

    try {
      // Kiểm tra xem match đã tồn tại chưa
      final existing = await GameFirebaseService().fetchMatch(newMatchId);
      if (existing != null) {
        if (context.mounted) _openRoom(context, newMatchId);
        return;
      }

      // Tạo match mới boardSize=3 (3×3 Tic-tac-toe)
      final match = GameMatch(
        matchId: newMatchId,
        gameType: GameType.caro,
        status:
            _isGameOver ? GameMatchStatus.finished : GameMatchStatus.playing,
        player1Id: _playerX.isNotEmpty ? _playerX : currentUserId,
        player1Name: 'Player X',
        player1Avatar: '',
        player2Id: _playerO.isNotEmpty ? _playerO : null,
        player2Name: _playerO.isNotEmpty ? 'Player O' : null,
        boardSize: 3,
        sourceGroupId: groupId,
        createdAt: DateTime.now().millisecondsSinceEpoch.toString(),
      );

      await GameFirebaseService().createMatch(match);
      if (context.mounted) _openRoom(context, newMatchId);
    } catch (e) {
      debugPrint('[TicTacToeMessageWidget] _createAndOpenRoom error: $e');
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Nếu có matchId từ Game Center → dùng redirect đơn giản
    if (matchId != null && matchId!.isNotEmpty) {
      return _GameCenterRedirectCard(
        matchId: matchId!,
        gameType: GameType.caro,
        boardSize: 3,
        isGameOver: _isGameOver,
        winner: _winner,
        onTap: () => _openRoom(context, matchId!),
      );
    }

    // Legacy: hiển thị snapshot bàn cờ 3x3 + redirect
    return _LegacySnapshotCard(
      board: _board,
      winner: _winner,
      mySymbol: _mySymbol,
      isMyturn: _isMyturn,
      isGameOver: _isGameOver,
      onOpenRoom: () => _createAndOpenRoom(context),
    );
  }
}

// =========================================================
// GAME CENTER REDIRECT CARD
// =========================================================

/// Card đơn giản cho tin nhắn type=7 được tạo từ Game Center.
/// Hiển thị thông tin trận + nút vào phòng.
class _GameCenterRedirectCard extends StatelessWidget {
  final String matchId;
  final GameType gameType;
  final int boardSize;
  final bool isGameOver;
  final String winner;
  final VoidCallback onTap;

  const _GameCenterRedirectCard({
    required this.matchId,
    required this.gameType,
    required this.boardSize,
    required this.isGameOver,
    required this.winner,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label = boardSize == 3 ? 'Tic-tac-toe 3×3' : 'Caro';
    final statusColor = isGameOver ? _C.text2 : _C.live;
    final statusLabel = isGameOver
        ? (winner == 'Hòa' ? '🤝 Hòa' : '🏆 Kết thúc')
        : '🎮 Đang diễn ra';

    return GestureDetector(
      onTap: isGameOver ? null : onTap,
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _C.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _C.border, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(gameType.emoji, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: _C.text1,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              statusLabel,
              style: TextStyle(color: statusColor, fontSize: 11),
            ),
            if (!isGameOver) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 32,
                child: ElevatedButton(
                  onPressed: onTap,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _C.accent.withValues(alpha: 0.15),
                    foregroundColor: _C.accent,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: _C.accent.withValues(alpha: 0.4)),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: const Text('Vào phòng đấu'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// =========================================================
// LEGACY SNAPSHOT CARD
// =========================================================

/// Card hiển thị snapshot bàn 3x3 từ content JSON cũ.
/// Không cho đánh cờ trực tiếp — chỉ hiển thị trạng thái + redirect.
class _LegacySnapshotCard extends StatelessWidget {
  final List<String> board;
  final String winner;
  final String mySymbol;
  final bool isMyturn;
  final bool isGameOver;
  final VoidCallback onOpenRoom;

  const _LegacySnapshotCard({
    required this.board,
    required this.winner,
    required this.mySymbol,
    required this.isMyturn,
    required this.isGameOver,
    required this.onOpenRoom,
  });

  // ── Win detection ─────────────────────────────────────────────────────────

  String _checkWinner() {
    const lines = [
      [0, 1, 2],
      [3, 4, 5],
      [6, 7, 8],
      [0, 3, 6],
      [1, 4, 7],
      [2, 5, 8],
      [0, 4, 8],
      [2, 4, 6],
    ];
    for (final l in lines) {
      if (board[l[0]].isNotEmpty &&
          board[l[0]] == board[l[1]] &&
          board[l[1]] == board[l[2]]) {
        return board[l[0]];
      }
    }
    return '';
  }

  List<int> _winLine() {
    const lines = [
      [0, 1, 2],
      [3, 4, 5],
      [6, 7, 8],
      [0, 3, 6],
      [1, 4, 7],
      [2, 5, 8],
      [0, 4, 8],
      [2, 4, 6],
    ];
    for (final l in lines) {
      if (board[l[0]].isNotEmpty &&
          board[l[0]] == board[l[1]] &&
          board[l[1]] == board[l[2]]) {
        return l;
      }
    }
    return [];
  }

  @override
  Widget build(BuildContext context) {
    final detectedWinner = winner.isNotEmpty ? winner : _checkWinner();
    final winLine = _winLine();
    final isDraw = detectedWinner.isEmpty && !board.contains('');

    // Status label
    String statusText;
    Color statusColor;
    if (detectedWinner == 'Hòa' || isDraw) {
      statusText = '🤝 Hòa nhau!';
      statusColor = _C.waiting;
    } else if (detectedWinner.isNotEmpty) {
      final isIWon = detectedWinner == mySymbol;
      statusText = isIWon ? '🏆 Bạn thắng!' : '💀 Bạn thua!';
      statusColor = isIWon ? _C.live : const Color(0xFFFF5A5A);
    } else if (mySymbol.isEmpty) {
      statusText = '👀 Quan sát';
      statusColor = _C.text2;
    } else if (isMyturn) {
      statusText = 'Lượt của bạn ($mySymbol)';
      statusColor = _C.accent;
    } else {
      statusText = 'Chờ đối thủ...';
      statusColor = _C.text2;
    }

    return Container(
      width: 240,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F3460).withValues(alpha: 0.5),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Status header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: _C.border, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: statusColor.withValues(alpha: 0.7),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      statusText,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Text(
                    '3×3',
                    style: TextStyle(
                        color: _C.text2, fontSize: 10, letterSpacing: 0.5),
                  ),
                ],
              ),
            ),

            // Board snapshot
            Padding(
              padding: const EdgeInsets.all(14),
              child: _SnapshotGrid(board: board, winLine: winLine),
            ),

            // CTA
            if (!isGameOver && detectedWinner.isEmpty && !isDraw)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: SizedBox(
                  width: double.infinity,
                  height: 34,
                  child: ElevatedButton(
                    onPressed: onOpenRoom,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _C.accent.withValues(alpha: 0.12),
                      foregroundColor: _C.accent,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side:
                            BorderSide(color: _C.accent.withValues(alpha: 0.3)),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: const Text('Mở phòng đấu'),
                  ),
                ),
              )
            else
              const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

// ─── Snapshot Grid (Read-only Stack 3x3 with Painters) ───────────────────

class _SnapshotGrid extends StatelessWidget {
  final List<String> board;
  final List<int> winLine;

  const _SnapshotGrid({required this.board, required this.winLine});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Stack(
        children: [
          Column(
            children: List.generate(3, (row) {
              return Expanded(
                child: Row(
                  children: List.generate(3, (col) {
                    final index = row * 3 + col;
                    final isWinCell = winLine.contains(index);
                    final symbol = index < board.length ? board[index] : '';

                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(3.5),
                        child: _SnapshotCell(
                          symbol: symbol,
                          isWin: isWinCell,
                        ),
                      ),
                    );
                  }),
                ),
              );
            }),
          ),
          if (winLine.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _WinLinePainter(
                    winLine: winLine,
                    progress: 1.0, // Vẽ tĩnh vì đây là Snapshot Read-only
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SnapshotCell extends StatelessWidget {
  final String symbol;
  final bool isWin;

  const _SnapshotCell({required this.symbol, required this.isWin});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: isWin ? const Color(0xFF0F3460) : const Color(0xFF0A0A1A),
        border: Border.all(
          color: isWin
              ? _C.accent.withValues(alpha: 0.6)
              : _C.border.withValues(alpha: 0.6),
          width: isWin ? 1.8 : 1.2,
        ),
        boxShadow: isWin
            ? [
                BoxShadow(
                  color: _C.accent.withValues(alpha: 0.18),
                  blurRadius: 10,
                )
              ]
            : [],
      ),
      child: Center(
        child: symbol.isEmpty
            ? const SizedBox.shrink()
            : _buildSymbol(symbol, isWin),
      ),
    );
  }

  Widget _buildSymbol(String symbol, bool isWinCell) {
    if (symbol == 'X') {
      return CustomPaint(
        size: const Size(28, 28),
        painter: _XPainter(
          color: isWinCell ? const Color(0xFFFF8A80) : const Color(0xFFFF5252),
          strokeWidth: 3.0,
        ),
      );
    } else {
      return CustomPaint(
        size: const Size(28, 28),
        painter: _OPainter(
          color: isWinCell ? const Color(0xFF80D8FF) : const Color(0xFF40C4FF),
          strokeWidth: 3.0,
        ),
      );
    }
  }
}

// ─── Custom Painters ───────────────────────────────────────────────────────

class _XPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  _XPainter({required this.color, this.strokeWidth = 3.0});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final pad = size.width * 0.1;
    canvas.drawLine(
        Offset(pad, pad), Offset(size.width - pad, size.height - pad), paint);
    canvas.drawLine(
        Offset(size.width - pad, pad), Offset(pad, size.height - pad), paint);
  }

  @override
  bool shouldRepaint(_XPainter old) =>
      old.color != color || old.strokeWidth != strokeWidth;
}

class _OPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  _OPainter({required this.color, this.strokeWidth = 3.0});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) * 0.78;
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(_OPainter old) =>
      old.color != color || old.strokeWidth != strokeWidth;
}

class _WinLinePainter extends CustomPainter {
  final List<int> winLine;
  final double progress;

  _WinLinePainter({required this.winLine, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (winLine.isEmpty || progress <= 0) return;

    final cellW = size.width / 3;
    final cellH = size.height / 3;

    Offset cellCenter(int idx) {
      final row = idx ~/ 3;
      final col = idx % 3;
      return Offset(col * cellW + cellW / 2, row * cellH + cellH / 2);
    }

    final start = cellCenter(winLine.first);
    final end = cellCenter(winLine.last);

    final current = Offset.lerp(start, end, progress)!;

    final paint = Paint()
      ..color = const Color(0xFF64FFDA).withValues(alpha: 0.85)
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    canvas.drawLine(start, current, paint);
  }

  @override
  bool shouldRepaint(_WinLinePainter old) =>
      old.progress != progress || old.winLine != winLine;
}
