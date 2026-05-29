import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

class SwipeToReplyWrapper extends StatefulWidget {
  const SwipeToReplyWrapper({
    super.key,
    required this.child,
    required this.onSwipe,
    required this.isMe,
    this.swipeThreshold = 56.0,
    this.maxDragDistance = 80.0,
    this.iconColor,
  });

  final Widget child;
  final VoidCallback onSwipe;

  final bool isMe;

  final double swipeThreshold;

  final double maxDragDistance;

  final Color? iconColor;

  @override
  State<SwipeToReplyWrapper> createState() => _SwipeToReplyWrapperState();
}

class _SwipeToReplyWrapperState extends State<SwipeToReplyWrapper>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spring = AnimationController(vsync: this);

  double _drag = 0.0;
  bool _triggered = false;
  bool _fired = false;

  int get _sign => widget.isMe ? -1 : 1;

  @override
  void initState() {
    super.initState();
    _spring.addListener(() => setState(() => _drag = _spring.value));
  }

  @override
  void dispose() {
    _spring.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    final delta = d.delta.dx;

    if (widget.isMe && delta > 0 && _drag >= 0) return;
    if (!widget.isMe && delta < 0 && _drag <= 0) return;

    setState(() {
      final raw = _drag + delta;
      final abs = raw.abs();

      if (abs <= widget.swipeThreshold) {
        _drag = raw;
      } else if (abs <= widget.maxDragDistance) {
        final over = abs - widget.swipeThreshold;
        final friction = 1.0 - (over / widget.maxDragDistance) * 0.85;
        _drag = raw.sign * (widget.swipeThreshold + over * friction.clamp(0.05, 1.0));
      } else {
        _drag = _sign * widget.maxDragDistance;
      }
    });

    if (_drag.abs() >= widget.swipeThreshold && !_triggered) {
      _triggered = true;
      HapticFeedback.lightImpact();
    } else if (_drag.abs() < widget.swipeThreshold * 0.8) {
      _triggered = false;
    }
  }

  void _onDragEnd(DragEndDetails d) {
    if (_drag.abs() >= widget.swipeThreshold && !_fired) {
      _fired = true;
      HapticFeedback.mediumImpact();
      widget.onSwipe();
    }

    _fired = false;
    _triggered = false;
    _snapBack(d.velocity.pixelsPerSecond.dx);
  }

  void _snapBack(double velocityX) {
    final spring = SpringDescription(
      mass: 1.0,
      stiffness: 300.0,
      damping: 22.0,
    );
    final simulation = SpringSimulation(
      spring,
      _drag,
      0.0,
      velocityX * 0.25,
    );
    _spring.animateWith(simulation);
  }

  double get _progress => (_drag.abs() / widget.swipeThreshold).clamp(0.0, 1.0);

  double get _iconRotation => (1 - _progress) * 0.4 * -_sign.toDouble();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final iconColor = widget.iconColor ?? scheme.onSurfaceVariant;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: Stack(
        alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: widget.isMe ? null : 0,
            right: widget.isMe ? 0 : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Opacity(
                opacity: _progress,
                child: Transform.scale(
                  scale: 0.6 + _progress * 0.4,
                  child: Transform.rotate(
                    angle: _iconRotation,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: iconColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.reply_rounded,
                        color: _progress >= 1.0 ? scheme.primary : iconColor,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Transform.translate(
            offset: Offset(_drag, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
