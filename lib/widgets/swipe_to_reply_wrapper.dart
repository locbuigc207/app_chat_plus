import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

class SwipeToReplyWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback onSwipe;
  final bool isMe; // Để xác định vuốt từ bên nào

  const SwipeToReplyWrapper({
    super.key,
    required this.child,
    required this.onSwipe,
    required this.isMe,
  });

  @override
  State<SwipeToReplyWrapper> createState() => _SwipeToReplyWrapperState();
}

class _SwipeToReplyWrapperState extends State<SwipeToReplyWrapper>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  double _dragExtent = 0.0;
  bool _hasTriggeredHaptic = false;

  // Ngưỡng vuốt tối đa để kích hoạt Reply
  final double _swipeThreshold = 60.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _controller.addListener(() {
      setState(() {
        _dragExtent = _controller.value;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    // Nếu là tin nhắn của mình, vuốt sang trái (âm). Nếu là của bạn, vuốt sang phải (dương)
    if (widget.isMe && details.delta.dx > 0) return; // Khóa chiều ngược lại
    if (!widget.isMe && details.delta.dx < 0) return;

    setState(() {
      _dragExtent += details.delta.dx;

      // Giảm xóc (Friction) khi kéo quá xa
      if (_dragExtent.abs() > _swipeThreshold + 20) {
        _dragExtent += (details.delta.dx * 0.1);
      }
    });

    // Kích hoạt rung nhẹ 1 lần duy nhất khi chạm ngưỡng
    if (_dragExtent.abs() >= _swipeThreshold && !_hasTriggeredHaptic) {
      _hasTriggeredHaptic = true;
      HapticFeedback.lightImpact(); // Micro-interaction rung phản hồi
    } else if (_dragExtent.abs() < _swipeThreshold) {
      _hasTriggeredHaptic = false;
    }
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (_dragExtent.abs() >= _swipeThreshold) {
      widget.onSwipe();
      HapticFeedback.mediumImpact(); // Rung mạnh hơn khi chốt lệnh Reply
    }

    // Hiệu ứng lò xo (Spring Physics) kéo tin nhắn bật ngược lại
    final spring = SpringDescription(
      mass: 30,
      stiffness: 1,
      damping: 1,
    );

    final simulation = SpringSimulation(
      spring,
      _dragExtent, // Vị trí bắt đầu
      0.0, // Vị trí kết thúc (Về 0)
      details.velocity.pixelsPerSecond.dx, // Vận tốc quán tính
    );

    _controller.animateWith(simulation);
    _hasTriggeredHaptic = false;
  }

  @override
  Widget build(BuildContext context) {
    // Biểu tượng Reply hiện ra mờ dần dựa trên khoảng cách vuốt
    final double iconOpacity =
        (_dragExtent.abs() / _swipeThreshold).clamp(0.0, 1.0);

    return GestureDetector(
      onHorizontalDragUpdate: _onHorizontalDragUpdate,
      onHorizontalDragEnd: _onHorizontalDragEnd,
      child: Stack(
        alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
        children: [
          // Icon Reply hiển thị ngầm phía dưới
          Opacity(
            opacity: iconOpacity,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Transform.scale(
                scale: iconOpacity,
                child: const Icon(
                  Icons.reply_rounded,
                  color: Colors.grey,
                  size: 24,
                ),
              ),
            ),
          ),
          // Khối tin nhắn chính bị dịch chuyển
          Transform.translate(
            offset: Offset(_dragExtent, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
