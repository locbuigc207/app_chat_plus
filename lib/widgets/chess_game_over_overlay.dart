// lib/widgets/chess_game_over_overlay.dart
//
// Overlay hiển thị kết quả ván cờ vua.
// Xuất hiện khi GameStateProvider.isGameOver == true và gameType == chess.
// Có animation slide-in từ dưới lên.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/models/game_match.dart';
import 'package:flutter_chat_demo/providers/game_state_provider.dart';

// ─── Design tokens ────────────────────────────────────────────────────────────
abstract final class _CO {
  static const bg = Color(0xFF2C1810);
  static const surface = Color(0xFF3D2314);
  static const border = Color(0xFF6B3A2A);
  static const gold = Color(0xFFD4A96A);
  static const text1 = Color(0xFFF5E6D3);
  static const text2 = Color(0xFFB8956A);
  static const win = Color(0xFFD4A96A);
  static const lose = Color(0xFF8B5E3C);
  static const draw = Color(0xFF9E7B5E);
  static const btn = Color(0xFF6B3A2A);
  static const btnBorder = Color(0xFFB58863);
}

class ChessGameOverOverlay extends StatefulWidget {
  final GameStateProvider gs;
  final String currentUserId;
  final String player1Name;
  final String player2Name;
  final VoidCallback onBackToGroup;
  final VoidCallback onViewReplay;

  const ChessGameOverOverlay({
    super.key,
    required this.gs,
    required this.currentUserId,
    required this.player1Name,
    required this.player2Name,
    required this.onBackToGroup,
    required this.onViewReplay,
  });

  @override
  State<ChessGameOverOverlay> createState() => _ChessGameOverOverlayState();
}

class _ChessGameOverOverlayState extends State<ChessGameOverOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
    HapticFeedback.heavyImpact();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gs = widget.gs;
    final isDraw = gs.finalResult == GameResult.draw;
    final isWinner = gs.winnerUserId == widget.currentUserId;

    final String emoji;
    final String headline;
    final Color accentColor;

    if (isDraw) {
      emoji = '🤝';
      headline = 'Ván cờ hòa!';
      accentColor = _CO.draw;
    } else if (isWinner) {
      emoji = '🏆';
      headline = 'Bạn đã thắng!';
      accentColor = _CO.win;
    } else {
      emoji = '♟️';
      headline = 'Bạn đã thua!';
      accentColor = _CO.lose;
    }

    final reasonText = _buildReasonText(gs.endReason);
    final moveCount = gs.chessSanHistory.length;

    return FadeTransition(
      opacity: _fade,
      child: Container(
        color: Colors.black.withValues(alpha: 0.75),
        child: Center(
          child: SlideTransition(
            position: _slide,
            child: Container(
              width: 300,
              margin: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _CO.bg,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: accentColor.withValues(alpha: 0.5),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 32,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.08),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                      border: Border(
                        bottom: BorderSide(
                          color: accentColor.withValues(alpha: 0.2),
                        ),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(emoji, style: const TextStyle(fontSize: 44)),
                        const SizedBox(height: 8),
                        Text(
                          headline,
                          style: TextStyle(
                            color: accentColor,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        if (reasonText.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            reasonText,
                            style: const TextStyle(
                              color: _CO.text2,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Stats
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    child: Column(
                      children: [
                        // VS row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _PlayerResult(
                              name: widget.player1Name,
                              label: 'Trắng ♔',
                              isWinner: gs.finalResult == GameResult.player1Win,
                              isDraw: isDraw,
                            ),
                            Text(
                              'VS',
                              style: const TextStyle(
                                color: _CO.text2,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 2,
                              ),
                            ),
                            _PlayerResult(
                              name: widget.player2Name,
                              label: 'Đen ♚',
                              isWinner: gs.finalResult == GameResult.player2Win,
                              isDraw: isDraw,
                              alignRight: true,
                            ),
                          ],
                        ),

                        const SizedBox(height: 14),
                        Container(height: 1, color: _CO.border),
                        const SizedBox(height: 14),

                        // Move count
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.swap_horiz_rounded,
                              color: _CO.text2,
                              size: 14,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '$moveCount nước đi',
                              style: const TextStyle(
                                color: _CO.text2,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Buttons
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    child: Column(
                      children: [
                        // Replay button
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: ElevatedButton.icon(
                            onPressed: widget.onViewReplay,
                            icon: const Icon(Icons.replay_rounded, size: 16),
                            label: const Text('Xem lại ván cờ'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accentColor.withValues(
                                alpha: 0.15,
                              ),
                              foregroundColor: accentColor,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: accentColor.withValues(alpha: 0.4),
                                ),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Back button
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: TextButton(
                            onPressed: widget.onBackToGroup,
                            style: TextButton.styleFrom(
                              foregroundColor: _CO.text2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Về nhóm',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _buildReasonText(EndReason? reason) {
    return switch (reason) {
      EndReason.checkmate => 'Chiếu bí',
      EndReason.stalemate => 'Bế tắc — hòa',
      EndReason.insufficientMaterial => 'Thiếu quân — hòa',
      EndReason.drawAgreed => 'Đồng ý hòa',
      EndReason.resign => 'Đầu hàng',
      EndReason.timeout => 'Hết giờ',
      EndReason.disconnect => 'Mất kết nối',
      _ => '',
    };
  }
}

class _PlayerResult extends StatelessWidget {
  final String name;
  final String label;
  final bool isWinner;
  final bool isDraw;
  final bool alignRight;

  const _PlayerResult({
    required this.name,
    required this.label,
    required this.isWinner,
    required this.isDraw,
    this.alignRight = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDraw ? _CO.draw : (isWinner ? _CO.win : _CO.lose);

    return Column(
      crossAxisAlignment: alignRight
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: _CO.text2, fontSize: 10.5)),
        const SizedBox(height: 2),
        Text(
          name.length > 10 ? '${name.substring(0, 9)}…' : name,
          style: TextStyle(
            color: color,
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          isDraw ? '½' : (isWinner ? '1' : '0'),
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}
