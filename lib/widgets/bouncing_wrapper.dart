import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BouncingWrapper extends StatefulWidget {
  const BouncingWrapper({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.onDoubleTap,
    this.scaleFactor = 0.92,
    this.duration = const Duration(milliseconds: 90),
    this.reverseDuration = const Duration(milliseconds: 200),
    this.enabled = true,
    this.hapticOnTap = true,
    this.hapticOnLongPress = true,
  });

  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDoubleTap;

  final double scaleFactor;

  final Duration duration;

  final Duration reverseDuration;

  final bool enabled;

  final bool hapticOnTap;
  final bool hapticOnLongPress;

  @override
  State<BouncingWrapper> createState() => _BouncingWrapperState();
}

class _BouncingWrapperState extends State<BouncingWrapper> with SingleTickerProviderStateMixin {
  late final AnimationController _ac = AnimationController(
    vsync: this,
    duration: widget.duration,
    reverseDuration: widget.reverseDuration,
    lowerBound: 0,
    upperBound: 1,
  );

  late final Animation<double> _scale = Tween<double>(
    begin: 1.0,
    end: widget.scaleFactor,
  ).animate(CurvedAnimation(parent: _ac, curve: Curves.easeOut));

  bool _cancelled = false;

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    if (!widget.enabled) return;
    _cancelled = false;
    if (widget.hapticOnTap) HapticFeedback.selectionClick();
    _ac.forward();
  }

  void _onTapUp(TapUpDetails _) {
    if (!widget.enabled || _cancelled) return;
    _ac.reverse().then((_) {
      if (!_cancelled) widget.onTap();
    });
  }

  void _onTapCancel() {
    _cancelled = true;
    _ac.reverse();
  }

  void _onLongPress() {
    if (!widget.enabled) return;
    if (widget.hapticOnLongPress) HapticFeedback.mediumImpact();
    _ac.reverse();
    widget.onLongPress?.call();
  }

  void _onDoubleTap() {
    if (!widget.enabled) return;
    HapticFeedback.lightImpact();
    widget.onDoubleTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onLongPress: widget.onLongPress != null ? _onLongPress : null,
      onDoubleTap: widget.onDoubleTap != null ? _onDoubleTap : null,
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) => Transform.scale(
          scale: _scale.value,
          child: AnimatedOpacity(
            opacity: widget.enabled ? 1.0 : 0.45,
            duration: const Duration(milliseconds: 180),
            child: child,
          ),
        ),
        child: widget.child,
      ),
    );
  }
}
