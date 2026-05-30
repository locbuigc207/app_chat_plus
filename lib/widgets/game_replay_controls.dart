import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/providers/game_state_provider.dart';

// ─── Design tokens ────────────────────────────────────────────────────────
abstract final class _C {
  static const bg = Color(0xFF141720);
  static const surface = Color(0xFF1A1F2E);
  static const accent = Color(0xFF4F8EF7);
  static const text1 = Color(0xFFEEF2FF);
  static const text2 = Color(0xFF8B93B0);
  static const divider = Color(0xFF252A3A);
  static const active = Color(0xFF64FFDA);
}

// =========================================================
// GAME REPLAY CONTROLS
// =========================================================

/// Thanh điều khiển Replay hiển thị dưới bàn cờ khi đang xem lại.
///
/// Gồm:
///   ⏮ Về đầu  ◀ Lùi 1  ▶/⏸ Phát/Tạm dừng  ▶ Tiến 1  ⏭ Về cuối
///   Tốc độ: x1 / x2 / x4
///   Progress bar: số nước / tổng
class GameReplayControls extends StatefulWidget {
  final GameStateProvider gs;

  const GameReplayControls({super.key, required this.gs});

  @override
  State<GameReplayControls> createState() => _GameReplayControlsState();
}

class _GameReplayControlsState extends State<GameReplayControls> {
  bool _isPlaying = false;
  int _speedIndex = 0; // 0=x1, 1=x2, 2=x4

  static const _speeds = [800, 400, 200];
  static const _speedLabels = ['×1', '×2', '×4'];

  GameStateProvider get _gs => widget.gs;

  void _togglePlay() {
    HapticFeedback.lightImpact();
    setState(() => _isPlaying = !_isPlaying);

    if (_isPlaying) {
      _gs.replayPlay(intervalMs: _speeds[_speedIndex]);
      // Auto-stop khi replay xong
      final total = _gs.replayTotal;
      Future.delayed(
        Duration(
            milliseconds: _speeds[_speedIndex] * (total - _gs.replayIndex)),
        () {
          if (mounted) setState(() => _isPlaying = false);
        },
      );
    } else {
      _gs.replayPause();
    }
  }

  void _goBack() {
    HapticFeedback.selectionClick();
    if (_isPlaying) {
      _gs.replayPause();
      setState(() => _isPlaying = false);
    }
    _gs.replayBack();
  }

  void _goForward() {
    HapticFeedback.selectionClick();
    if (_isPlaying) {
      _gs.replayPause();
      setState(() => _isPlaying = false);
    }
    _gs.replayForward();
  }

  void _goToStart() {
    HapticFeedback.mediumImpact();
    _gs.replayPause();
    setState(() => _isPlaying = false);
    // Tua về đầu
    while (_gs.canReplayBack) {
      _gs.replayBack();
    }
  }

  void _goToEnd() {
    HapticFeedback.mediumImpact();
    _gs.replayPause();
    setState(() => _isPlaying = false);
    while (_gs.canReplayForward) {
      _gs.replayForward();
    }
  }

  void _cycleSpeed() {
    HapticFeedback.lightImpact();
    setState(() => _speedIndex = (_speedIndex + 1) % _speeds.length);
    if (_isPlaying) {
      _gs.replayPause();
      _gs.replayPlay(intervalMs: _speeds[_speedIndex]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _gs,
      builder: (context, _) {
        final current = _gs.replayIndex + 1; // 0-based → 1-based display
        final total = _gs.replayTotal;
        final progress =
            total > 0 ? ((_gs.replayIndex + 1) / total).clamp(0.0, 1.0) : 0.0;

        return Container(
          color: _C.bg,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Progress bar
              _ProgressBar(progress: progress),
              // Controls row
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: Row(
                  children: [
                    // Move counter
                    SizedBox(
                      width: 64,
                      child: Text(
                        total > 0 ? '${current.clamp(0, total)}/$total' : '—',
                        style: const TextStyle(
                          color: _C.text2,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const Spacer(),
                    // ⏮
                    _CtrlBtn(
                      icon: Icons.skip_previous_rounded,
                      enabled: _gs.canReplayBack,
                      onTap: _goToStart,
                    ),
                    const SizedBox(width: 4),
                    // ◀
                    _CtrlBtn(
                      icon: Icons.chevron_left_rounded,
                      enabled: _gs.canReplayBack,
                      onTap: _goBack,
                      size: 28,
                    ),
                    const SizedBox(width: 4),
                    // ▶/⏸ — main button
                    _PlayBtn(
                      isPlaying: _isPlaying,
                      enabled: total > 0,
                      onTap: _togglePlay,
                    ),
                    const SizedBox(width: 4),
                    // ▶
                    _CtrlBtn(
                      icon: Icons.chevron_right_rounded,
                      enabled: _gs.canReplayForward,
                      onTap: _goForward,
                      size: 28,
                    ),
                    const SizedBox(width: 4),
                    // ⏭
                    _CtrlBtn(
                      icon: Icons.skip_next_rounded,
                      enabled: _gs.canReplayForward,
                      onTap: _goToEnd,
                    ),
                    const Spacer(),
                    // Speed chip
                    GestureDetector(
                      onTap: _cycleSpeed,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 44,
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        decoration: BoxDecoration(
                          color: _speedIndex > 0
                              ? _C.active.withOpacity(0.12)
                              : _C.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _speedIndex > 0
                                ? _C.active.withOpacity(0.4)
                                : _C.divider,
                          ),
                        ),
                        child: Text(
                          _speedLabels[_speedIndex],
                          style: TextStyle(
                            color: _speedIndex > 0 ? _C.active : _C.text2,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
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
}

// ─── Progress bar ─────────────────────────────────────────────────────────

class _ProgressBar extends StatelessWidget {
  final double progress;
  const _ProgressBar({required this.progress});

  @override
  Widget build(BuildContext context) => Container(
        height: 3,
        margin: const EdgeInsets.symmetric(horizontal: 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: _C.divider,
            valueColor: const AlwaysStoppedAnimation(_C.active),
            minHeight: 3,
          ),
        ),
      );
}

// ─── Control button ───────────────────────────────────────────────────────

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
            color: enabled ? _C.text1 : _C.text2.withOpacity(0.35),
            size: size,
          ),
        ),
      );
}

// ─── Play/Pause button ────────────────────────────────────────────────────

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
