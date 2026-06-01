// lib/widgets/game_replay_controls.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_chat_demo/providers/game_state_provider.dart';

// ─── Design tokens ────────────────────────────────────────────────────────
abstract final class _C {
  static const bg = Color(0xFF0D0F14);
  static const surface = Color(0xFF141720);
  static const card = Color(0xFF181D2A);
  static const accent = Color(0xFF4F8EF7);
  static const active = Color(0xFF64FFDA);
  static const text1 = Color(0xFFEEF2FF);
  static const text2 = Color(0xFF8B93B0);
  static const divider = Color(0xFF252A3A);
  static const xColor = Color(0xFFFF5252);
  static const oColor = Color(0xFF40C4FF);
}

// =========================================================
// GAME REPLAY CONTROLS
// =========================================================

/// Thanh điều khiển Replay — hiển thị dưới bàn cờ khi [gs.isReplayMode].
///
/// Tính năng:
/// • Slider kéo đến bất kỳ nước nào (tap/drag)
/// • Nút ⏮ ◀ ▶/⏸ ▶ ⏭
/// • Speed chip ×1 / ×2 / ×4
/// • Move info panel: hiển thị "Nước N/Total — X đánh (row,col)"
/// • Auto-stop khi replay đến cuối
class GameReplayControls extends StatefulWidget {
  final GameStateProvider gs;

  const GameReplayControls({super.key, required this.gs});

  @override
  State<GameReplayControls> createState() => _GameReplayControlsState();
}

class _GameReplayControlsState extends State<GameReplayControls> {
  bool _isPlaying = false;
  int _speedIndex = 0;
  Timer? _autoStopTimer;

  static const _speeds = [800, 400, 200];
  static const _speedLabels = ['×1', '×2', '×4'];

  GameStateProvider get _gs => widget.gs;

  @override
  void dispose() {
    _autoStopTimer?.cancel();
    super.dispose();
  }

  // ── Transport ─────────────────────────────────────────────────────────────

  void _play() {
    setState(() => _isPlaying = true);
    _gs.replayPlay(intervalMs: _speeds[_speedIndex]);

    // Auto-stop khi hết nước
    _autoStopTimer?.cancel();
    final remaining = _gs.replayTotal - (_gs.replayIndex + 1);
    _autoStopTimer = Timer(
      Duration(milliseconds: _speeds[_speedIndex] * remaining + 200),
      () {
        if (mounted && _isPlaying) setState(() => _isPlaying = false);
      },
    );
  }

  void _pause() {
    _gs.replayPause();
    _autoStopTimer?.cancel();
    setState(() => _isPlaying = false);
  }

  void _togglePlay() {
    HapticFeedback.lightImpact();
    if (_isPlaying) {
      _pause();
    } else {
      if (!_gs.canReplayForward) {
        // Đã ở cuối → về đầu rồi phát
        _seekTo(-1);
      }
      _play();
    }
  }

  void _stepBack() {
    HapticFeedback.selectionClick();
    if (_isPlaying) _pause();
    _gs.replayBack();
  }

  void _stepForward() {
    HapticFeedback.selectionClick();
    if (_isPlaying) _pause();
    _gs.replayForward();
    // Auto-stop nếu vừa đến cuối
    if (!_gs.canReplayForward && _isPlaying) {
      setState(() => _isPlaying = false);
    }
  }

  void _goToStart() {
    HapticFeedback.mediumImpact();
    _pause();
    _seekTo(-1);
  }

  void _goToEnd() {
    HapticFeedback.mediumImpact();
    _pause();
    _seekTo(_gs.replayTotal - 1);
  }

  /// Seek trực tiếp đến nước thứ [targetIndex] (0-based, -1 = trước nước đầu).
  void _seekTo(int targetIndex) {
    final clamped = targetIndex.clamp(-1, _gs.replayTotal - 1);
    if (clamped == _gs.replayIndex) return;

    if (clamped < _gs.replayIndex) {
      // Lùi về: dùng replayBack()
      while (_gs.replayIndex > clamped && _gs.canReplayBack) {
        _gs.replayBack();
      }
      if (_gs.replayIndex > clamped) {
        // Nếu vẫn chưa đến -1 (vị trí trước nước đầu)
        _gs.replayBack();
      }
    } else {
      // Tiến lên: dùng replayForward()
      while (_gs.replayIndex < clamped && _gs.canReplayForward) {
        _gs.replayForward();
      }
    }
  }

  void _cycleSpeed() {
    HapticFeedback.lightImpact();
    setState(() => _speedIndex = (_speedIndex + 1) % _speeds.length);
    if (_isPlaying) {
      _gs.replayPause();
      _autoStopTimer?.cancel();
      _play();
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _gs,
      builder: (context, _) {
        // Auto-stop nếu đến cuối và đang play
        if (_isPlaying && !_gs.canReplayForward) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _isPlaying) setState(() => _isPlaying = false);
          });
        }

        final total = _gs.replayTotal;
        final current = _gs.replayIndex; // -1..total-1
        final displayNum = current + 1; // 0..total (0 = chưa đánh)
        final progress =
            total > 0 ? ((current + 1) / total).clamp(0.0, 1.0) : 0.0;

        // Thông tin nước đi hiện tại
        final moveInfo = _buildMoveInfo(current, total);

        return Container(
          color: _C.bg,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Slider progress ──────────────────────────────────────
              _SliderBar(
                progress: progress,
                total: total,
                onSeek: (v) {
                  if (_isPlaying) _pause();
                  final target = (v * total).round() - 1;
                  _seekTo(target.clamp(-1, total - 1));
                },
              ),

              // ── Move info panel ──────────────────────────────────────
              if (moveInfo != null) _MoveInfoPanel(info: moveInfo),

              // ── Controls row ─────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: Row(
                  children: [
                    // Counter
                    SizedBox(
                      width: 52,
                      child: Text(
                        total > 0
                            ? '${displayNum.clamp(0, total)}/$total'
                            : '—',
                        style: const TextStyle(
                          color: _C.text2,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const Spacer(),

                    // ⏮ Go to start
                    _CtrlBtn(
                      icon: Icons.skip_previous_rounded,
                      enabled: current > -1,
                      onTap: _goToStart,
                    ),
                    const SizedBox(width: 2),

                    // ◀ Step back
                    _CtrlBtn(
                      icon: Icons.chevron_left_rounded,
                      enabled: _gs.canReplayBack || current >= 0,
                      onTap: _stepBack,
                      size: 28,
                    ),
                    const SizedBox(width: 2),

                    // ▶/⏸ Play/Pause
                    _PlayBtn(
                      isPlaying: _isPlaying,
                      enabled: total > 0,
                      onTap: _togglePlay,
                    ),
                    const SizedBox(width: 2),

                    // ▶ Step forward
                    _CtrlBtn(
                      icon: Icons.chevron_right_rounded,
                      enabled: _gs.canReplayForward,
                      onTap: _stepForward,
                      size: 28,
                    ),
                    const SizedBox(width: 2),

                    // ⏭ Go to end
                    _CtrlBtn(
                      icon: Icons.skip_next_rounded,
                      enabled: _gs.canReplayForward,
                      onTap: _goToEnd,
                    ),

                    const Spacer(),

                    // Speed chip
                    _SpeedChip(
                      label: _speedLabels[_speedIndex],
                      isActive: _speedIndex > 0,
                      onTap: _cycleSpeed,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Move info builder ─────────────────────────────────────────────────────

  _MoveInfo? _buildMoveInfo(int current, int total) {
    if (total == 0 || current < 0) return null;

    final match = _gs.match;
    if (match == null) return null;

    // Lấy thông tin nước đi từ replayIndex (dùng current turn parity để suy ra symbol)
    final isPlayer1Move = current.isEven;
    final symbol = isPlayer1Move ? 'X' : 'O';
    final playerName =
        isPlayer1Move ? match.player1Name : (match.player2Name ?? '?');
    final color = isPlayer1Move ? _C.xColor : _C.oColor;

    // Thông tin từ lastMove (đã được cập nhật sau replayForward)
    final lastMove = _gs.lastMove;
    String posText = '';
    if (lastMove != null && match.gameType == GameType.caro) {
      posText = '(${lastMove.row}, ${lastMove.col})';
    }

    return _MoveInfo(
      moveNum: current + 1,
      playerName: playerName,
      symbol: symbol,
      posText: posText,
      color: color,
      remainingMs: 0, // Sẽ cập nhật nếu có dữ liệu đồng hồ
    );
  }
}

// =========================================================
// SLIDER BAR
// =========================================================

class _SliderBar extends StatelessWidget {
  final double progress;
  final int total;
  final void Function(double) onSeek;

  const _SliderBar({
    required this.progress,
    required this.total,
    required this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
        activeTrackColor: _C.active,
        inactiveTrackColor: _C.divider,
        thumbColor: _C.active,
        overlayColor: _C.active.withOpacity(0.2),
      ),
      child: Slider(
        value: progress,
        min: 0,
        max: 1,
        onChanged: total > 0 ? onSeek : null,
      ),
    );
  }
}

// =========================================================
// MOVE INFO PANEL
// =========================================================

class _MoveInfo {
  final int moveNum;
  final String playerName;
  final String symbol;
  final String posText;
  final Color color;
  final int remainingMs;

  const _MoveInfo({
    required this.moveNum,
    required this.playerName,
    required this.symbol,
    required this.posText,
    required this.color,
    required this.remainingMs,
  });
}

class _MoveInfoPanel extends StatelessWidget {
  final _MoveInfo info;

  const _MoveInfoPanel({required this.info});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _C.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _C.divider, width: 0.8),
      ),
      child: Row(
        children: [
          // Symbol badge
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: info.color.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(color: info.color.withOpacity(0.4), width: 1),
            ),
            child: Center(
              child: Text(
                info.symbol,
                style: TextStyle(
                  color: info.color,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Player name
          Expanded(
            child: Text(
              info.playerName,
              style: TextStyle(
                color: info.color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Position (Caro)
          if (info.posText.isNotEmpty)
            Text(
              info.posText,
              style: const TextStyle(
                color: _C.text2,
                fontSize: 11,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),

          const SizedBox(width: 8),

          // Move number
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _C.accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'Nước ${info.moveNum}',
              style: const TextStyle(
                color: _C.accent,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =========================================================
// CONTROL WIDGETS
// =========================================================

class _CtrlBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final double size;

  const _CtrlBtn({
    required this.icon,
    required this.enabled,
    required this.onTap,
    this.size = 22,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            icon,
            color: enabled ? _C.text1 : _C.text2.withOpacity(0.3),
            size: size,
          ),
        ),
      );
}

class _PlayBtn extends StatelessWidget {
  final bool isPlaying;
  final bool enabled;
  final VoidCallback onTap;

  const _PlayBtn({
    required this.isPlaying,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: enabled ? _C.accent.withOpacity(0.15) : _C.surface,
            shape: BoxShape.circle,
            border: Border.all(
              color: enabled ? _C.accent.withOpacity(0.5) : _C.divider,
            ),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              key: ValueKey(isPlaying),
              color: enabled ? _C.accent : _C.text2,
              size: 22,
            ),
          ),
        ),
      );
}

class _SpeedChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _SpeedChip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 40,
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            color: isActive ? _C.active.withOpacity(0.12) : _C.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isActive ? _C.active.withOpacity(0.4) : _C.divider,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isActive ? _C.active : _C.text2,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
}
