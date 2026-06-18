// lib/widgets/chess_clock_widget.dart
//
// Widget đồng hồ cờ vua hiển thị trong MatchRoomPage khi gameType == chess.
// Hiển thị 2 đồng hồ: player trên (đối thủ) và player dưới (mình).
// Tích hợp với GameStateProvider qua Consumer.

import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/providers/game_state_provider.dart';
import 'package:provider/provider.dart';

// ─── Design tokens ────────────────────────────────────────────────────────────
abstract final class _CC {
  static const bg = Color(0xFF1A0E08);
  static const activeCard = Color(0xFFF5E6D3);
  static const idleCard = Color(0xFF2C1810);
  static const activeText = Color(0xFF1A0E08);
  static const idleText = Color(0xFF7A5C40);
  static const lowColor = Color(0xFFE63946);
  static const border = Color(0xFF5C3520);
  static const activeBorder = Color(0xFFB58863);
}

class ChessClockWidget extends StatelessWidget {
  /// Player 1 name (white)
  final String player1Name;

  /// Player 2 name (black)
  final String player2Name;

  /// Player 1 avatar URL
  final String player1Avatar;

  /// Player 2 avatar URL
  final String player2Avatar;

  /// Màu của current user: 'white' hoặc 'black'
  final String myColor;

  const ChessClockWidget({
    super.key,
    required this.player1Name,
    required this.player2Name,
    required this.player1Avatar,
    required this.player2Avatar,
    required this.myColor,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<GameStateProvider>(
      builder: (context, gs, _) {
        final match = gs.match;
        if (match == null || match.timeControlSeconds <= 0) {
          return const SizedBox.shrink();
        }

        final isPlayer1Turn = gs.isPlayer1Turn;
        final p1Ms = gs.player1RemainingMs;
        final p2Ms = gs.player2RemainingMs;
        final isGameOver = gs.isGameOver;

        // Xác định top/bottom theo màu người chơi
        // Nếu myColor == 'white' → tôi là white (player1), đối thủ là black (player2) ở trên
        final topIsPlayer1 = myColor == 'black'; // đối thủ ở trên

        final topMs = topIsPlayer1 ? p1Ms : p2Ms;
        final bottomMs = topIsPlayer1 ? p2Ms : p1Ms;
        final topActive = topIsPlayer1 ? isPlayer1Turn : !isPlayer1Turn;
        final botActive = !topActive;
        final topName = topIsPlayer1 ? player1Name : player2Name;
        final botName = topIsPlayer1 ? player2Name : player1Name;
        final topAvatar = topIsPlayer1 ? player1Avatar : player2Avatar;
        final botAvatar = topIsPlayer1 ? player2Avatar : player1Avatar;

        return Container(
          color: _CC.bg,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Đồng hồ đối thủ (trên)
              _ClockTile(
                name: topName,
                avatarUrl: topAvatar,
                remainingMs: topMs,
                isActive: topActive && !isGameOver,
                isTop: true,
              ),
              // Divider
              Container(height: 1, color: _CC.border),
              // Đồng hồ mình (dưới)
              _ClockTile(
                name: botName,
                avatarUrl: botAvatar,
                remainingMs: bottomMs,
                isActive: botActive && !isGameOver,
                isTop: false,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Clock Tile ───────────────────────────────────────────────────────────────

class _ClockTile extends StatelessWidget {
  final String name;
  final String avatarUrl;
  final int remainingMs;
  final bool isActive;
  final bool isTop;

  const _ClockTile({
    required this.name,
    required this.avatarUrl,
    required this.remainingMs,
    required this.isActive,
    required this.isTop,
  });

  @override
  Widget build(BuildContext context) {
    final isLow = remainingMs < 30000; // < 30 giây
    final textColor = isActive
        ? (isLow ? _CC.lowColor : _CC.activeText)
        : _CC.idleText;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: isActive ? _CC.activeCard : _CC.idleCard,
        border: Border(
          left: BorderSide(
            color: isActive ? _CC.activeBorder : _CC.border,
            width: isActive ? 3 : 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Avatar
          CircleAvatar(
            radius: 16,
            backgroundColor: isActive
                ? const Color(0xFF8B4513).withValues(alpha: 0.2)
                : const Color(0xFF5C3520).withValues(alpha: 0.3),
            backgroundImage: avatarUrl.isNotEmpty
                ? NetworkImage(avatarUrl)
                : null,
            child: avatarUrl.isEmpty
                ? Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: TextStyle(
                      color: isActive ? const Color(0xFF4A2518) : _CC.idleText,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 10),

          // Name
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                color: isActive ? _CC.activeText : _CC.idleText,
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Clock display
          _ClockDisplay(
            remainingMs: remainingMs,
            isActive: isActive,
            isLow: isLow,
            textColor: textColor,
          ),
        ],
      ),
    );
  }
}

// ─── Clock Display (số giờ) ────────────────────────────────────────────────────

class _ClockDisplay extends StatelessWidget {
  final int remainingMs;
  final bool isActive;
  final bool isLow;
  final Color textColor;

  const _ClockDisplay({
    required this.remainingMs,
    required this.isActive,
    required this.isLow,
    required this.textColor,
  });

  String _format(int ms) {
    if (ms <= 0) return '0:00';
    if (ms < 10000) {
      // Hiển thị thập phân khi < 10 giây
      final s = ms ~/ 1000;
      final tenth = (ms % 1000) ~/ 100;
      return '0:0$s.$tenth';
    }
    final totalSec = (ms / 1000).ceil();
    final m = totalSec ~/ 60;
    final s = totalSec % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isLow && isActive
            ? _CC.lowColor.withValues(alpha: 0.12)
            : (isActive
                  ? const Color(0xFF8B4513).withValues(alpha: 0.08)
                  : Colors.transparent),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isLow && isActive
              ? _CC.lowColor.withValues(alpha: 0.4)
              : (isActive
                    ? const Color(0xFFB58863).withValues(alpha: 0.3)
                    : Colors.transparent),
        ),
      ),
      child: Text(
        _format(remainingMs),
        style: TextStyle(
          color: textColor,
          fontSize: isActive ? 22 : 18,
          fontWeight: FontWeight.w800,
          fontFeatures: const [FontFeature.tabularFigures()],
          letterSpacing: isActive ? -0.5 : -0.3,
        ),
      ),
    );
  }
}
