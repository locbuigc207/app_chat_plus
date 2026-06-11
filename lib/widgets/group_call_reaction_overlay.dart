// ignore_for_file: deprecated_member_use
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/group_call_model.dart';

class _K {
  static const bg = Color(0xFF080E1C);
  static const surface = Color(0xFF111827);
  static const s2 = Color(0xFF1C2333);
  static const text = Color(0xFFF8FAFC);
  static const sub = Color(0xFF94A3B8);
  static const muted = Color(0xFF475569);
}

// ══════════════════════════════════════════════════════════════════════════════
// ReactionBurstOverlay
// Full-screen overlay showing a burst of emojis flying from the bottom
// ══════════════════════════════════════════════════════════════════════════════
class ReactionBurstOverlay extends StatefulWidget {
  final String emoji;
  final String senderName;
  final VoidCallback? onComplete;

  const ReactionBurstOverlay({
    super.key,
    required this.emoji,
    required this.senderName,
    this.onComplete,
  });

  @override
  State<ReactionBurstOverlay> createState() => _ReactionBurstOverlayState();
}

class _ReactionBurstOverlayState extends State<ReactionBurstOverlay>
    with TickerProviderStateMixin {
  final List<_BurstParticle> _particles = [];
  late AnimationController _masterCtrl;
  final _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _masterCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2600))
      ..forward()
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) widget.onComplete?.call();
      });

    // Spawn 8–12 particles
    final count = 8 + _rng.nextInt(5);
    for (int i = 0; i < count; i++) {
      final ctrl = AnimationController(
          vsync: this,
          duration: Duration(milliseconds: 1800 + _rng.nextInt(800)));

      final delay = _rng.nextDouble() * 0.3;
      final x = 0.15 + _rng.nextDouble() * 0.70;
      final angle = -math.pi / 2 + (_rng.nextDouble() - 0.5) * math.pi * 0.6;
      final speed = 0.55 + _rng.nextDouble() * 0.45;
      final size = 24.0 + _rng.nextDouble() * 20;
      final spin = (_rng.nextDouble() - 0.5) * 4;

      _particles.add(_BurstParticle(
        ctrl: ctrl,
        delay: delay,
        x: x,
        angle: angle,
        speed: speed,
        size: size,
        spin: spin,
      ));

      Future.delayed(Duration(milliseconds: (delay * 1000).round()), () {
        if (mounted) ctrl.forward();
      });
    }
  }

  @override
  void dispose() {
    _masterCtrl.dispose();
    for (final p in _particles) p.ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return IgnorePointer(
      child: SizedBox.expand(
        child: Stack(
          children: [
            ..._particles.map((p) => AnimatedBuilder(
                  animation: p.ctrl,
                  builder: (_, __) {
                    final t = p.ctrl.value;
                    if (t == 0) return const SizedBox.shrink();

                    final dist = t * size.height * 0.75 * p.speed;
                    final dx = math.cos(p.angle) * dist;
                    final dy =
                        math.sin(p.angle) * dist - t * t * size.height * 0.2;
                    final opacity = t < 0.15
                        ? t / 0.15
                        : t < 0.7
                            ? 1.0
                            : (1.0 - t) / 0.3;

                    return Positioned(
                      left: p.x * size.width + dx - p.size / 2,
                      bottom: 90 - dy,
                      child: Transform.rotate(
                        angle: p.spin * t * math.pi,
                        child: Opacity(
                          opacity: opacity.clamp(0.0, 1.0),
                          child: Text(
                            widget.emoji,
                            style: TextStyle(fontSize: p.size),
                          ),
                        ),
                      ),
                    );
                  },
                )),

            // Sender label at bottom
            AnimatedBuilder(
              animation: _masterCtrl,
              builder: (_, child) {
                final t = _masterCtrl.value;
                final opacity = t < 0.1
                    ? t / 0.1
                    : t < 0.7
                        ? 1.0
                        : (1.0 - t) / 0.3;
                return Positioned(
                  bottom: 60,
                  left: 0,
                  right: 0,
                  child: Opacity(
                    opacity: opacity.clamp(0.0, 1.0),
                    child: child,
                  ),
                );
              },
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(widget.emoji, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 6),
                    Text(widget.senderName,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BurstParticle {
  final AnimationController ctrl;
  final double delay, x, angle, speed, size, spin;
  const _BurstParticle({
    required this.ctrl,
    required this.delay,
    required this.x,
    required this.angle,
    required this.speed,
    required this.size,
    required this.spin,
  });
}

// ══════════════════════════════════════════════════════════════════════════════
// ReactionPickerSheet
// Modal bottom sheet for choosing a reaction
// ══════════════════════════════════════════════════════════════════════════════
class ReactionPickerSheet extends StatefulWidget {
  final ValueChanged<CallReactionType> onSelected;

  const ReactionPickerSheet({super.key, required this.onSelected});

  static Future<CallReactionType?> show(BuildContext context) {
    return showModalBottomSheet<CallReactionType>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          ReactionPickerSheet(onSelected: (t) => Navigator.of(context).pop(t)),
    );
  }

  @override
  State<ReactionPickerSheet> createState() => _ReactionPickerSheetState();
}

class _ReactionPickerSheetState extends State<ReactionPickerSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _fade;
  int? _hoveredIndex;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 380));
    _scale = Tween<double>(begin: 0.8, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(
        scale: _scale,
        alignment: Alignment.bottomCenter,
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          decoration: BoxDecoration(
            color: _K.surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 32,
                  offset: const Offset(0, 8)),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Gửi cảm xúc',
                  style: TextStyle(
                      color: _K.sub,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: CallReactionType.values.asMap().entries.map((e) {
                  final i = e.key;
                  final t = e.value;
                  return _ReactionButton(
                    type: t,
                    index: i,
                    isHovered: _hoveredIndex == i,
                    onHover: (v) =>
                        setState(() => _hoveredIndex = v ? i : null),
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      widget.onSelected(t);
                    },
                  );
                }).toList(),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ReactionButton extends StatefulWidget {
  final CallReactionType type;
  final int index;
  final bool isHovered;
  final ValueChanged<bool> onHover;
  final VoidCallback onTap;

  const _ReactionButton({
    required this.type,
    required this.index,
    required this.isHovered,
    required this.onHover,
    required this.onTap,
  });

  @override
  State<_ReactionButton> createState() => _ReactionButtonState();
}

class _ReactionButtonState extends State<_ReactionButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween<double>(begin: 1.0, end: 0.82)
        .animate(CurvedAnimation(parent: _c, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _c.forward(),
      onTapUp: (_) {
        _c.reverse();
        widget.onTap();
      },
      onTapCancel: () => _c.reverse(),
      child: MouseRegion(
        onEnter: (_) => widget.onHover(true),
        onExit: (_) => widget.onHover(false),
        child: ScaleTransition(
          scale: _scale,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: widget.isHovered
                  ? Colors.white.withOpacity(0.1)
                  : Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: widget.isHovered
                    ? Colors.white.withOpacity(0.2)
                    : Colors.white.withOpacity(0.06),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(widget.type.emoji,
                    style: TextStyle(fontSize: widget.isHovered ? 32 : 28)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ReactionCountBadge
// Shows a count badge next to an emoji (e.g. in reaction summary)
// ══════════════════════════════════════════════════════════════════════════════
class ReactionCountBadge extends StatelessWidget {
  final String emoji;
  final int count;
  final bool isSelected;
  final VoidCallback? onTap;

  const ReactionCountBadge({
    super.key,
    required this.emoji,
    required this.count,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withOpacity(0.18)
              : Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? Colors.white.withOpacity(0.35)
                : Colors.white.withOpacity(0.1),
            width: 0.8,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(emoji, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 5),
          Text('$count',
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              )),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ReactionsBar
// Horizontal bar showing aggregated reactions with counts
// ══════════════════════════════════════════════════════════════════════════════
class ReactionsBar extends StatelessWidget {
  final List<CallReaction> reactions;
  final String currentUserId;
  final ValueChanged<CallReactionType>? onTap;

  const ReactionsBar({
    super.key,
    required this.reactions,
    required this.currentUserId,
    this.onTap,
  });

  Map<CallReactionType, int> get _counts {
    final map = <CallReactionType, int>{};
    for (final r in reactions) {
      map[r.type] = (map[r.type] ?? 0) + 1;
    }
    return map;
  }

  Set<CallReactionType> get _myReactions => reactions
      .where((r) => r.userId == currentUserId)
      .map((r) => r.type)
      .toSet();

  @override
  Widget build(BuildContext context) {
    final counts = _counts;
    final my = _myReactions;
    if (counts.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: counts.entries
            .map((e) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ReactionCountBadge(
                    emoji: e.key.emoji,
                    count: e.value,
                    isSelected: my.contains(e.key),
                    onTap: onTap != null ? () => onTap!(e.key) : null,
                  ),
                ))
            .toList(),
      ),
    );
  }
}
