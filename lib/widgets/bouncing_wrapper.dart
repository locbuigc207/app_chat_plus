import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BouncingWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final double scaleFactor;

  const BouncingWrapper({
    super.key,
    required this.child,
    required this.onTap,
    this.scaleFactor = 0.92, // Mức độ thu nhỏ khi bấm (0.92 là chuẩn Apple)
  });

  @override
  State<BouncingWrapper> createState() => _BouncingWrapperState();
}

class _BouncingWrapperState extends State<BouncingWrapper> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        HapticFeedback.selectionClick(); // Rung micro-interaction siêu nhẹ
        setState(() => _isPressed = true);
      },
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () {
        setState(() => _isPressed = false);
      },
      child: AnimatedScale(
        scale: _isPressed ? widget.scaleFactor : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}
