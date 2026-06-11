// ignore_for_file: deprecated_member_use
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/group_call_model.dart';

// ─── Tokens ───────────────────────────────────────────────────────────────────
class _K {
  static const bg = Color(0xFF080E1C);
  static const accent = Color(0xFF3B82F6);
  static const green = Color(0xFF22C55E);
  static const purple = Color(0xFF8B5CF6);
  static const text = Color(0xFFF8FAFC);
  static const sub = Color(0xFF94A3B8);
  static const muted = Color(0xFF475569);
}

// ══════════════════════════════════════════════════════════════════════════════
// VirtualBackgroundPicker
// Bottom sheet for choosing virtual background blur level / preset.
// ══════════════════════════════════════════════════════════════════════════════
class VirtualBackgroundPicker extends StatefulWidget {
  final VirtualBackground current;
  final ValueChanged<VirtualBackground> onChanged;

  const VirtualBackgroundPicker({
    super.key,
    required this.current,
    required this.onChanged,
  });

  static Future<VirtualBackground?> show(
    BuildContext context, {
    required VirtualBackground current,
  }) {
    return showModalBottomSheet<VirtualBackground>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => VirtualBackgroundPicker(
        current: current,
        onChanged: (v) => Navigator.of(context).pop(v),
      ),
    );
  }

  @override
  State<VirtualBackgroundPicker> createState() =>
      _VirtualBackgroundPickerState();
}

class _VirtualBackgroundPickerState extends State<VirtualBackgroundPicker> {
  late VirtualBackground _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.current;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
              child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 18),

          const Text('Nền ảo',
              style: TextStyle(
                  color: _K.text, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Tuỳ chỉnh nền sau camera của bạn',
              style: TextStyle(color: _K.sub, fontSize: 12)),
          const SizedBox(height: 20),

          SizedBox(
            height: 120,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: VirtualBackground.values.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) {
                final bg = VirtualBackground.values[i];
                return _BackgroundOption(
                  background: bg,
                  isSelected: _selected == bg,
                  onTap: () {
                    setState(() => _selected = bg);
                    widget.onChanged(bg);
                  },
                );
              },
            ),
          ),

          const SizedBox(height: 16),

          // Apply button
          GestureDetector(
            onTap: () => Navigator.of(context).pop(_selected),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                color: _K.accent,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                      color: _K.accent.withOpacity(0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 4))
                ],
              ),
              child: const Text('Áp dụng',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackgroundOption extends StatelessWidget {
  final VirtualBackground background;
  final bool isSelected;
  final VoidCallback onTap;

  const _BackgroundOption({
    required this.background,
    required this.isSelected,
    required this.onTap,
  });

  Color get _previewColor {
    switch (background) {
      case VirtualBackground.none:
        return const Color(0xFF1C2333);
      case VirtualBackground.blur:
        return const Color(0xFF1E3A5F);
      case VirtualBackground.blurStrong:
        return const Color(0xFF0D1B3E);
      case VirtualBackground.office:
        return const Color(0xFF1E3320);
      case VirtualBackground.nature:
        return const Color(0xFF143320);
      case VirtualBackground.space:
        return const Color(0xFF0D0D2E);
    }
  }

  IconData get _icon {
    switch (background) {
      case VirtualBackground.none:
        return Icons.block_rounded;
      case VirtualBackground.blur:
        return Icons.blur_on_rounded;
      case VirtualBackground.blurStrong:
        return Icons.blur_circular_rounded;
      case VirtualBackground.office:
        return Icons.business_rounded;
      case VirtualBackground.nature:
        return Icons.park_rounded;
      case VirtualBackground.space:
        return Icons.nights_stay_rounded;
    }
  }

  Color get _iconColor {
    switch (background) {
      case VirtualBackground.none:
        return _K.muted;
      case VirtualBackground.blur:
        return _K.accent;
      case VirtualBackground.blurStrong:
        return _K.accent;
      case VirtualBackground.office:
        return _K.green;
      case VirtualBackground.nature:
        return _K.green;
      case VirtualBackground.space:
        return _K.purple;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 90,
        decoration: BoxDecoration(
          color: _previewColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? _iconColor : Colors.white.withOpacity(0.08),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: _iconColor.withOpacity(0.35), blurRadius: 12)]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _iconColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_icon, color: _iconColor, size: 22)),
            const SizedBox(height: 8),
            Text(background.label,
                style: TextStyle(
                  color: isSelected ? _iconColor : _K.sub,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// CallBackgroundCanvas
// Animated dark background with floating orbs for voice-only calls
// ══════════════════════════════════════════════════════════════════════════════
class CallBackgroundCanvas extends StatefulWidget {
  final GroupCallType callType;
  final bool isActive;

  const CallBackgroundCanvas({
    super.key,
    required this.callType,
    this.isActive = true,
  });

  @override
  State<CallBackgroundCanvas> createState() => _CallBackgroundCanvasState();
}

class _CallBackgroundCanvasState extends State<CallBackgroundCanvas>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  final List<_Orb> _orbs = [];
  final _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _generateOrbs();
    _ctrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 12))
          ..repeat();
  }

  void _generateOrbs() {
    for (int i = 0; i < 5; i++) {
      _orbs.add(_Orb(
        x: _rng.nextDouble(),
        y: _rng.nextDouble(),
        radius: 80 + _rng.nextDouble() * 140,
        opacity: 0.04 + _rng.nextDouble() * 0.08,
        speed: 0.2 + _rng.nextDouble() * 0.5,
        phase: _rng.nextDouble() * 2 * math.pi,
      ));
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Color get _primaryColor => widget.callType == GroupCallType.video
      ? const Color(0xFF3B82F6)
      : const Color(0xFF22C55E);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => CustomPaint(
        painter: _OrbPainter(
          orbs: _orbs,
          progress: _ctrl.value,
          color: _primaryColor,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _Orb {
  final double x, y, radius, opacity, speed, phase;
  const _Orb({
    required this.x,
    required this.y,
    required this.radius,
    required this.opacity,
    required this.speed,
    required this.phase,
  });
}

class _OrbPainter extends CustomPainter {
  final List<_Orb> orbs;
  final double progress;
  final Color color;

  _OrbPainter(
      {required this.orbs, required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    // Dark base
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = _K.bg,
    );

    for (final orb in orbs) {
      final t = progress * orb.speed + orb.phase;
      final dx = math.sin(t) * size.width * 0.12;
      final dy = math.cos(t * 0.7) * size.height * 0.1;
      final cx = orb.x * size.width + dx;
      final cy = orb.y * size.height + dy;

      final paint = Paint()
        ..color = color.withOpacity(orb.opacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, orb.radius * 0.6);

      canvas.drawCircle(Offset(cx, cy), orb.radius, paint);
    }
  }

  @override
  bool shouldRepaint(_OrbPainter old) => old.progress != progress;
}

// ══════════════════════════════════════════════════════════════════════════════
// GridPattern
// Subtle dot-grid pattern overlay for visual depth
// ══════════════════════════════════════════════════════════════════════════════
class GridPatternOverlay extends StatelessWidget {
  final double opacity;
  const GridPatternOverlay({super.key, this.opacity = 0.04});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _GridPainter(opacity: opacity),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  final double opacity;
  _GridPainter({required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    const spacing = 28.0;
    const dotR = 0.8;
    final paint = Paint()
      ..color = Colors.white.withOpacity(opacity)
      ..style = PaintingStyle.fill;

    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), dotR, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.opacity != opacity;
}
