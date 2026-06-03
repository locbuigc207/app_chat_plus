import 'dart:async';

import 'package:flutter/material.dart';

// ══════════════════════════════════════════════════════
// CALL TIMER WIDGET
// Shows a live call duration counter that updates every second.
// Supports custom styles and an optional pulse animation.
// ══════════════════════════════════════════════════════
class CallTimerWidget extends StatefulWidget {
  final DateTime startTime;
  final TextStyle? style;
  final bool showPulse;
  final bool showIcon;

  const CallTimerWidget({
    super.key,
    required this.startTime,
    this.style,
    this.showPulse = false,
    this.showIcon = false,
  });

  @override
  State<CallTimerWidget> createState() => _CallTimerWidgetState();
}

class _CallTimerWidgetState extends State<CallTimerWidget>
    with SingleTickerProviderStateMixin {
  late Duration _elapsed;
  late Timer _tick;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _elapsed = DateTime.now().difference(widget.startTime);

    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _elapsed = DateTime.now().difference(widget.startTime);
        });
      }
    });

    // Subtle pulse every second
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.7, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _tick.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  static String _format(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:'
          '${m.toString().padLeft(2, '0')}:'
          '${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final text = _format(_elapsed);
    final style = widget.style ??
        const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
          fontFeatures: [FontFeature.tabularFigures()],
        );

    if (!widget.showIcon && !widget.showPulse) {
      return Text(text, style: style);
    }

    return Row(mainAxisSize: MainAxisSize.min, children: [
      // Pulse dot
      if (widget.showPulse)
        AnimatedBuilder(
          animation: _pulseAnim,
          builder: (_, __) => Opacity(
            opacity: _pulseAnim.value,
            child: Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.only(right: 7),
              decoration: BoxDecoration(
                color: style.color ?? Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),

      if (widget.showIcon) ...[
        Icon(Icons.access_time_rounded,
            size: 14, color: style.color ?? Colors.white),
        const SizedBox(width: 5),
      ],

      Text(text, style: style),
    ]);
  }
}

// ══════════════════════════════════════════════════════
// COMPACT TIMER  (for top bar badges)
// ══════════════════════════════════════════════════════
class CompactCallTimer extends StatefulWidget {
  final DateTime startTime;
  final Color color;
  const CompactCallTimer({
    super.key,
    required this.startTime,
    this.color = Colors.white,
  });

  @override
  State<CompactCallTimer> createState() => _CompactCallTimerState();
}

class _CompactCallTimerState extends State<CompactCallTimer> {
  late Duration _elapsed;
  late Timer _tick;

  @override
  void initState() {
    super.initState();
    _elapsed = DateTime.now().difference(widget.startTime);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _elapsed = DateTime.now().difference(widget.startTime);
        });
      }
    });
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = _elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = _elapsed.inHours;

    return Text(
      h > 0 ? '$h:$m:$s' : '$m:$s',
      style: TextStyle(
        color: widget.color,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════
// CALL DURATION TEXT  (static, for call history)
// ══════════════════════════════════════════════════════
class CallDurationText extends StatelessWidget {
  final int? durationSeconds;
  final TextStyle? style;
  const CallDurationText({super.key, this.durationSeconds, this.style});

  static String format(int? seconds) {
    if (seconds == null || seconds <= 0) return '';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '${h}g ${m.toString().padLeft(2, '0')}ph';
    }
    if (m > 0) {
      return '${m}ph ${s.toString().padLeft(2, '0')}s';
    }
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final text = format(durationSeconds);
    if (text.isEmpty) return const SizedBox.shrink();
    return Text(text,
        style: style ??
            const TextStyle(
              color: Colors.white38,
              fontSize: 12,
            ));
  }
}
