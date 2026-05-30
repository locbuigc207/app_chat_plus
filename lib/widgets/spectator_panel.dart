import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─── Design tokens ────────────────────────────────────────────────────────
abstract final class _C {
  static const bg = Color(0xFF141720);
  static const surface = Color(0xFF1A1F2E);
  static const accent = Color(0xFF4F8EF7);
  static const live = Color(0xFF00E676);
  static const text1 = Color(0xFFEEF2FF);
  static const text2 = Color(0xFF8B93B0);
  static const divider = Color(0xFF252A3A);
}

const List<String> _kReactions = ['❤️', '😂', '🔥', '👏', '😮', '👍'];

// =========================================================
// SPECTATOR PANEL
// =========================================================

/// Thanh khán giả hiển thị ở dưới bàn cờ.
///
/// - Hiển thị số "Mắt xem" (viewer count)
/// - Nút thả reaction → emoji bay lên màn hình
/// - Spectator chat compact (chỉ hiện khi mở rộng)
class SpectatorPanel extends StatefulWidget {
  final int spectatorCount;
  final String matchId;
  final String currentUserId;
  final bool isSpectator;

  const SpectatorPanel({
    super.key,
    required this.spectatorCount,
    required this.matchId,
    required this.currentUserId,
    required this.isSpectator,
  });

  @override
  State<SpectatorPanel> createState() => SpectatorPanelState();
}

class SpectatorPanelState extends State<SpectatorPanel> {
  /// Danh sách reaction đang bay (quản lý bên ngoài qua GlobalKey nếu cần)
  final List<_FlyingEmoji> _flyingEmojis = [];
  bool _showReactions = false;

  // Rate limit: không spam quá 1 reaction/giây
  DateTime? _lastReaction;

  void _sendReaction(String emoji) {
    final now = DateTime.now();
    if (_lastReaction != null &&
        now.difference(_lastReaction!) < const Duration(milliseconds: 800)) {
      return;
    }
    _lastReaction = now;
    HapticFeedback.lightImpact();

    setState(() {
      _flyingEmojis.add(_FlyingEmoji(
        emoji: emoji,
        id: now.millisecondsSinceEpoch,
      ));
      _showReactions = false;
    });

    // Tự xóa sau 2.5s
    Timer(const Duration(milliseconds: 2500), () {
      if (mounted) {
        setState(() {
          _flyingEmojis.removeWhere((e) => e.id == now.millisecondsSinceEpoch);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Flying emojis layer (positioned above panel)
        ..._flyingEmojis.map((fe) => Positioned(
              bottom: 60,
              right: 20 + (fe.id % 80).toDouble(),
              child: _FlyingEmojiWidget(key: ValueKey(fe.id), emoji: fe.emoji),
            )),

        // Reaction picker popup
        if (_showReactions)
          Positioned(
            bottom: 56,
            right: 12,
            child: _ReactionPicker(
              onPick: _sendReaction,
              onDismiss: () => setState(() => _showReactions = false),
            ),
          ),

        // Panel bar
        Container(
          height: 48,
          decoration: BoxDecoration(
            color: _C.bg,
            border: Border(
              top: BorderSide(color: _C.divider, width: 0.8),
            ),
          ),
          child: Row(
            children: [
              const SizedBox(width: 12),
              // Viewer count
              _ViewerCount(count: widget.spectatorCount),
              const Spacer(),
              // Reaction button (spectator + players can react)
              GestureDetector(
                onTap: () => setState(() => _showReactions = !_showReactions),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _showReactions
                        ? _C.accent.withOpacity(0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '😊',
                        style: TextStyle(
                          fontSize: _showReactions ? 20 : 18,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Reaction',
                        style: TextStyle(
                          color: _C.text2,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Viewer count ─────────────────────────────────────────────────────────

class _ViewerCount extends StatelessWidget {
  final int count;
  const _ViewerCount({required this.count});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.remove_red_eye_rounded, color: _C.live, size: 15),
          const SizedBox(width: 5),
          Text(
            '$count đang xem',
            style: const TextStyle(
              color: _C.text2,
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
}

// ─── Reaction picker ──────────────────────────────────────────────────────

class _ReactionPicker extends StatelessWidget {
  final void Function(String) onPick;
  final VoidCallback onDismiss;

  const _ReactionPicker({required this.onPick, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onDismiss,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1E2438),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _C.divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: _kReactions
              .map((e) => GestureDetector(
                    onTap: () => onPick(e),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: Text(e, style: const TextStyle(fontSize: 22)),
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }
}

// ─── Flying emoji widget ──────────────────────────────────────────────────

class _FlyingEmoji {
  final String emoji;
  final int id;
  const _FlyingEmoji({required this.emoji, required this.id});
}

class _FlyingEmojiWidget extends StatefulWidget {
  final String emoji;
  const _FlyingEmojiWidget({super.key, required this.emoji});

  @override
  State<_FlyingEmojiWidget> createState() => _FlyingEmojiWidgetState();
}

class _FlyingEmojiWidgetState extends State<_FlyingEmojiWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fly;
  late final Animation<double> _fade;
  late final double _drift;

  @override
  void initState() {
    super.initState();
    _drift = (math.Random().nextDouble() - 0.5) * 30;
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..forward();

    _fly = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _fade = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.6, 1.0, curve: Curves.easeIn),
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final dy = -_fly.value * 120;
        final dx = _drift * _fly.value;
        return Transform.translate(
          offset: Offset(dx, dy),
          child: Opacity(
            opacity: _fade.value,
            child: Text(widget.emoji, style: const TextStyle(fontSize: 26)),
          ),
        );
      },
    );
  }
}
