import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

/// Widget bọc ngoài cho tính năng vuốt-để-trả-lời (swipe-to-reply) —
/// chuẩn WhatsApp / Telegram.
///
/// Tính năng nâng cấp so với bản gốc:
///  • Spring physics bật ngược chân thực hơn (mass/stiffness/damping tinh chỉnh)
///  • Icon reply scale + fade + rotate theo chiều vuốt
///  • Giới hạn kéo mềm (rubber-band) khi vượt ngưỡng
///  • Hỗ trợ cả tin nhắn trái (bạn) và phải (mình) với logic đối xứng
///  • Haptic 2 tầng: lightImpact khi chạm ngưỡng, mediumImpact khi xác nhận
///  • Callback onSwipe an toàn — chỉ gọi 1 lần mỗi gesture
///  • maxDragDistance tuỳ chỉnh (mặc định 72px)
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

  /// true → tin nhắn của mình (bên phải, vuốt sang trái).
  /// false → tin nhắn của đối phương (bên trái, vuốt sang phải).
  final bool isMe;

  /// Khoảng cách vuốt để kích hoạt reply (px).
  final double swipeThreshold;

  /// Giới hạn kéo tối đa trước khi rubber-band (px).
  final double maxDragDistance;

  /// Màu icon reply. Mặc định dùng màu scheme.
  final Color? iconColor;

  @override
  State<SwipeToReplyWrapper> createState() => _SwipeToReplyWrapperState();
}

class _SwipeToReplyWrapperState extends State<SwipeToReplyWrapper>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spring = AnimationController(vsync: this);

  double _drag = 0.0;
  bool _triggered = false; // Đã kích hoạt haptic threshold chưa
  bool _fired = false; // Đã gọi onSwipe chưa trong gesture này

  // ─── Drag direction sign ───────────────────────────────────────────────────
  // isMe → vuốt trái → drag âm; !isMe → vuốt phải → drag dương
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

  // ─── Gesture handlers ──────────────────────────────────────────────────────

  void _onDragUpdate(DragUpdateDetails d) {
    final delta = d.delta.dx;

    // Chặn chiều ngược lại ngay từ đầu
    if (widget.isMe && delta > 0 && _drag >= 0) return;
    if (!widget.isMe && delta < 0 && _drag <= 0) return;

    setState(() {
      final raw = _drag + delta;
      final abs = raw.abs();

      if (abs <= widget.swipeThreshold) {
        // Kéo tự do trong vùng ngưỡng
        _drag = raw;
      } else if (abs <= widget.maxDragDistance) {
        // Vùng rubber-band: ma sát tăng dần
        final over = abs - widget.swipeThreshold;
        final friction = 1.0 - (over / widget.maxDragDistance) * 0.85;
        _drag = raw.sign *
            (widget.swipeThreshold + over * friction.clamp(0.05, 1.0));
      } else {
        // Hard cap
        _drag = _sign * widget.maxDragDistance;
      }
    });

    // Haptic khi chạm ngưỡng
    if (_drag.abs() >= widget.swipeThreshold && !_triggered) {
      _triggered = true;
      HapticFeedback.lightImpact();
    } else if (_drag.abs() < widget.swipeThreshold * 0.8) {
      _triggered = false;
    }
  }

  void _onDragEnd(DragEndDetails d) {
    // Kích hoạt callback chỉ 1 lần
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
      velocityX * 0.25, // Dùng 1 phần vận tốc cho tự nhiên hơn
    );
    _spring.animateWith(simulation);
  }

  // ─── Derived values ────────────────────────────────────────────────────────

  /// Tiến độ 0→1 dựa trên khoảng cách kéo so với ngưỡng.
  double get _progress => (_drag.abs() / widget.swipeThreshold).clamp(0.0, 1.0);

  /// Góc xoay icon reply (−π/6 → 0) khi tiến độ tăng.
  double get _iconRotation => (1 - _progress) * 0.4 * -_sign.toDouble();

  // ─── Build ─────────────────────────────────────────────────────────────────

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
          // ── Reply icon ──────────────────────────────────────────────────
          Positioned(
            left: widget.isMe ? null : 0,
            right: widget.isMe ? 0 : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Opacity(
                opacity: _progress,
                child: Transform.scale(
                  scale: 0.6 + _progress * 0.4, // 0.6 → 1.0
                  child: Transform.rotate(
                    angle: _iconRotation,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: iconColor.withOpacity(0.12),
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

          // ── Tin nhắn dịch chuyển ─────────────────────────────────────────
          Transform.translate(
            offset: Offset(_drag, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
