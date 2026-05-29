import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../models/bubble_models.dart';
import '../pages/chat_page.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CONSTANTS & DESIGN TOKENS
// ═══════════════════════════════════════════════════════════════════════════

class _K {
  // Geometry
  static const double minW = 300.0;
  static const double maxW = 420.0;
  static const double minH = 420.0;
  static const double maxH = 680.0;
  static const double headerH = 56.0;
  static const double pipW = 72.0;
  static const double pipH = 72.0;
  static const double radius = 20.0;
  static const double edgePad = 10.0;
  static const double resizeHandleSize = 22.0;

  // Physics
  static const double springStiffness = 400.0;
  static const double springDamping = 28.0;
  static const double snapVelocityThreshold = 600.0;

  // Animation durations
  static const Duration openDur = Duration(milliseconds: 380);
  static const Duration closeDur = Duration(milliseconds: 260);
  static const Duration pipDur = Duration(milliseconds: 320);
  static const Duration modeDur = Duration(milliseconds: 280);

  // Colors
  static const Color grad1 = Color(0xFF1565C0);
  static const Color grad2 = Color(0xFF0D47A1);
  static const Color grad3 = Color(0xFF1A237E);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color border = Color(0xFF1976D2);
  static const Color handle = Color(0x40FFFFFF);
  static const Color shadow = Color(0x3300000);
}

// ═══════════════════════════════════════════════════════════════════════════
// MINI CHAT OVERLAY WIDGET  —  main entry point
// ═══════════════════════════════════════════════════════════════════════════

/// Full-featured floating mini-chat window:
/// • Spring-physics drag with edge snapping
/// • Corner-resize handle
/// • Picture-in-picture (PiP) pill mode with unread badge
/// • Entrance / exit / PiP animations
/// • Backdrop blur behind header
/// • Keyboard-aware repositioning
/// • Swipe-down to minimise, swipe-up from PiP to expand
/// • BubbleContext-aware adaptive header colour
/// • Haptic feedback on snap, PiP toggle, close
class MiniChatOverlayWidget extends StatefulWidget {
  final String peerId;
  final String peerNickname;
  final String peerAvatar;
  final bool isPeerOnline;
  final int unreadCount;
  final BubbleContext bubbleCtx;
  final VoidCallback onMinimize;
  final VoidCallback onClose;
  final VoidCallback? onExpand;
  final void Function(BubbleContext ctx)? onContextChanged;

  const MiniChatOverlayWidget({
    super.key,
    required this.peerId,
    required this.peerNickname,
    required this.peerAvatar,
    this.isPeerOnline = false,
    this.unreadCount = 0,
    this.bubbleCtx = const BubbleContext(),
    required this.onMinimize,
    required this.onClose,
    this.onExpand,
    this.onContextChanged,
  });

  @override
  State<MiniChatOverlayWidget> createState() => _MiniChatOverlayWidgetState();
}

class _MiniChatOverlayWidgetState extends State<MiniChatOverlayWidget>
    with TickerProviderStateMixin {
  // ── Geometry ────────────────────────────────────────────────────────────
  late double _x;
  late double _y;
  late double _w;
  late double _h;
  bool _initialized = false;

  // ── Drag state ──────────────────────────────────────────────────────────
  Offset _dragStart = Offset.zero;
  Offset _posStart = Offset.zero;

  // ── Resize state ────────────────────────────────────────────────────────
  double _resizeStartW = 0;
  double _resizeStartH = 0;
  Offset _resizeDragStart = Offset.zero;

  // ── PiP / mode ──────────────────────────────────────────────────────────
  bool _isPip = false;
  double _pipSwipeY = 0;

  // ── Animations ──────────────────────────────────────────────────────────
  late AnimationController _openCtrl;
  late AnimationController _closeCtrl;
  late AnimationController _pipCtrl;
  late AnimationController _springCtrl;
  late AnimationController _pulseCtrl;
  late AnimationController _shakeCtrl;

  late Animation<double> _openScale;
  late Animation<double> _openFade;
  late Animation<Offset> _openSlide;

  late Animation<double> _pipScale;
  late Animation<double> _pipFade;

  late Simulation _springSimX;
  late Simulation _springSimY;
  double _springTargetX = 0;
  double _springTargetY = 0;

  // ── Header gradient (mode-aware) ─────────────────────────────────────────
  List<Color> get _headerColors => switch (widget.bubbleCtx.mode) {
        BubbleMode.work => [
            const Color(0xFF0D1B2A),
            const Color(0xFF1E2D40),
          ],
        BubbleMode.media => [
            const Color(0xFF880E4F),
            const Color(0xFFAD1457),
          ],
        BubbleMode.location => [
            const Color(0xFF1B5E20),
            const Color(0xFF388E3C),
          ],
        BubbleMode.secure => [
            const Color(0xFF0A0E1A),
            const Color(0xFF1A2A50),
          ],
        BubbleMode.shared => [
            const Color(0xFF311B92),
            const Color(0xFF5E35B1),
          ],
        _ => [_K.grad1, _K.grad3],
      };

  // ═════════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═════════════════════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    // Defer geometry init until we have MediaQuery
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _initGeometry();
      _openCtrl.forward();
    });
  }

  void _setupAnimations() {
    // Open
    _openCtrl = AnimationController(vsync: this, duration: _K.openDur);
    _openScale = Tween<double>(begin: 0.72, end: 1.0)
        .animate(CurvedAnimation(parent: _openCtrl, curve: Curves.easeOutBack));
    _openFade = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _openCtrl, curve: const Interval(0.0, 0.6)));
    _openSlide = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(
            CurvedAnimation(parent: _openCtrl, curve: Curves.easeOutCubic));

    // Close (plays in reverse for dismiss)
    _closeCtrl = AnimationController(vsync: this, duration: _K.closeDur);

    // PiP transition
    _pipCtrl = AnimationController(vsync: this, duration: _K.pipDur);
    _pipScale = Tween<double>(begin: 1.0, end: 0.0)
        .animate(CurvedAnimation(parent: _pipCtrl, curve: Curves.easeInOut));
    _pipFade = Tween<double>(begin: 1.0, end: 0.0)
        .animate(CurvedAnimation(parent: _pipCtrl, curve: Curves.easeIn));

    // Spring (for snap animation)
    _springCtrl = AnimationController(vsync: this);

    // Pulse (for PiP unread badge)
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);

    // Shake (when at boundary)
    _shakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 320));
  }

  void _initGeometry() {
    final size = MediaQuery.of(context).size;
    final safeBottom = MediaQuery.of(context).padding.bottom;

    _w = (size.width * 0.82).clamp(_K.minW, _K.maxW);
    _h = (size.height * 0.62).clamp(_K.minH, _K.maxH);
    _x = (size.width - _w) / 2;
    _y = (size.height - _h - safeBottom) * 0.12 + 40;
    if (mounted) setState(() => _initialized = true);
  }

  @override
  void dispose() {
    _openCtrl.dispose();
    _closeCtrl.dispose();
    _pipCtrl.dispose();
    _springCtrl.dispose();
    _pulseCtrl.dispose();
    _shakeCtrl.dispose();
    super.dispose();
  }

  // ═════════════════════════════════════════════════════════════════════════
  // DRAG HANDLERS
  // ═════════════════════════════════════════════════════════════════════════

  void _onDragStart(DragStartDetails d) {
    _dragStart = d.globalPosition;
    _posStart = Offset(_x, _y);
    _springCtrl.stop();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    final screen = MediaQuery.of(context).size;
    final delta = d.globalPosition - _dragStart;
    setState(() {
      _x = (_posStart.dx + delta.dx)
          .clamp(_K.edgePad, screen.width - _w - _K.edgePad);
      _y = (_posStart.dy + delta.dy).clamp(
          _K.edgePad + MediaQuery.of(context).padding.top,
          screen.height -
              _h -
              _K.edgePad -
              MediaQuery.of(context).padding.bottom);
    });
  }

  void _onDragEnd(DragEndDetails d) {
    final screen = MediaQuery.of(context).size;
    final vel = d.velocity.pixelsPerSecond;

    // Fast downward swipe → minimise to PiP
    if (vel.dy > _K.snapVelocityThreshold && !_isPip) {
      _enterPip();
      return;
    }

    // Snap to nearest safe edge with spring
    final targetX = _x < (screen.width - _w) / 2
        ? _K.edgePad
        : screen.width - _w - _K.edgePad;
    _springTo(targetX, _y, vel);
  }

  void _springTo(double tx, double ty, Offset velocity) {
    _springTargetX = tx;
    _springTargetY = ty;

    final simX = SpringSimulation(
      SpringDescription(
          mass: 1, stiffness: _K.springStiffness, damping: _K.springDamping),
      _x,
      tx,
      velocity.dx,
    );
    final simY = SpringSimulation(
      SpringDescription(
          mass: 1, stiffness: _K.springStiffness, damping: _K.springDamping),
      _y,
      ty,
      velocity.dy,
    );

    double curX = _x, curY = _y;
    _springCtrl.reset();
    _springCtrl.duration = const Duration(milliseconds: 700);
    _springCtrl.addListener(() {
      final t = _springCtrl.value;
      setState(() {
        _x = lerpDouble(curX, tx, simX.x(t * 0.7).clamp(0, 1))!;
        _y = lerpDouble(curY, ty, simY.x(t * 0.7).clamp(0, 1))!;
      });
    });
    _springCtrl.forward(from: 0);
    HapticFeedback.lightImpact();
  }

  // ═════════════════════════════════════════════════════════════════════════
  // RESIZE HANDLERS
  // ═════════════════════════════════════════════════════════════════════════

  void _onResizeStart(DragStartDetails d) {
    _resizeStartW = _w;
    _resizeStartH = _h;
    _resizeDragStart = d.globalPosition;
  }

  void _onResizeUpdate(DragUpdateDetails d) {
    final screen = MediaQuery.of(context).size;
    final delta = d.globalPosition - _resizeDragStart;
    setState(() {
      _w = (_resizeStartW + delta.dx)
          .clamp(_K.minW, math.min(_K.maxW, screen.width - _x - _K.edgePad));
      _h = (_resizeStartH + delta.dy).clamp(
          _K.minH,
          math.min(
              _K.maxH,
              screen.height -
                  _y -
                  _K.edgePad -
                  MediaQuery.of(context).padding.bottom));
    });
  }

  // ═════════════════════════════════════════════════════════════════════════
  // PiP
  // ═════════════════════════════════════════════════════════════════════════

  void _enterPip() {
    HapticFeedback.mediumImpact();
    _pipCtrl.forward().then((_) {
      if (mounted) setState(() => _isPip = true);
    });
  }

  void _exitPip() {
    HapticFeedback.mediumImpact();
    setState(() => _isPip = false);
    _pipCtrl.reverse();
    // Snap window back to a comfortable position
    final screen = MediaQuery.of(context).size;
    _x = (screen.width - _w) / 2;
    _y = (screen.height - _h) * 0.12 + 40;
  }

  void _onPipSwipeUpdate(DragUpdateDetails d) {
    setState(() => _pipSwipeY += d.delta.dy);
  }

  void _onPipSwipeEnd(DragEndDetails d) {
    if (_pipSwipeY < -30 || d.velocity.pixelsPerSecond.dy < -300) {
      _exitPip();
    }
    setState(() => _pipSwipeY = 0);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // CLOSE
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> _handleClose() async {
    HapticFeedback.mediumImpact();
    await _openCtrl.reverse();
    widget.onClose();
  }

  Future<void> _handleMinimize() async {
    HapticFeedback.lightImpact();
    _enterPip();
  }

  // ═════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (!_initialized) return const SizedBox.shrink();

    return Stack(
      children: [
        // ── PiP bubble ──────────────────────────────────────────────────
        if (_isPip) _buildPip(),

        // ── Full window ─────────────────────────────────────────────────
        if (!_isPip) _buildWindow(),
      ],
    );
  }

  // ─── PiP pill ───────────────────────────────────────────────────────────
  Widget _buildPip() {
    final screen = MediaQuery.of(context).size;
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      left: _x.clamp(8.0, screen.width - _K.pipW - 8),
      top: (_y + _h - _K.pipH - 12 + _pipSwipeY)
          .clamp(60.0, screen.height - _K.pipH - 60),
      child: GestureDetector(
        onTap: _exitPip,
        onVerticalDragUpdate: _onPipSwipeUpdate,
        onVerticalDragEnd: _onPipSwipeEnd,
        child: AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (_, child) {
            return Transform.scale(
              scale: 1.0 + _pulseCtrl.value * 0.04,
              child: child,
            );
          },
          child: Container(
            width: _K.pipW,
            height: _K.pipH,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _headerColors,
              ),
              boxShadow: [
                BoxShadow(
                  color: _headerColors.first.withOpacity(0.5),
                  blurRadius: 20,
                  spreadRadius: 2,
                  offset: const Offset(0, 6),
                ),
              ],
              border:
                  Border.all(color: Colors.white.withOpacity(0.25), width: 2),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Avatar
                CircleAvatar(
                  radius: 22,
                  backgroundImage: widget.peerAvatar.isNotEmpty
                      ? NetworkImage(widget.peerAvatar)
                      : null,
                  backgroundColor: Colors.white.withOpacity(0.15),
                  child: widget.peerAvatar.isEmpty
                      ? Text(
                          widget.peerNickname.isNotEmpty
                              ? widget.peerNickname[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 20,
                          ),
                        )
                      : null,
                ),

                // Unread badge
                if (widget.unreadCount > 0)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: _UnreadBadge(count: widget.unreadCount),
                  ),

                // Swipe-up hint
                Positioned(
                  bottom: 6,
                  child: Column(
                    children: [
                      Icon(Icons.keyboard_arrow_up_rounded,
                          color: Colors.white.withOpacity(0.7), size: 14),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Full window ────────────────────────────────────────────────────────
  Widget _buildWindow() {
    return Positioned(
      left: _x,
      top: _y,
      child: FadeTransition(
        opacity: _openFade,
        child: SlideTransition(
          position: _openSlide,
          child: ScaleTransition(
            scale: _openScale,
            alignment: Alignment.center,
            child: _WindowFrame(
              width: _w,
              height: _h,
              radius: _K.radius,
              headerColors: _headerColors,
              onDragStart: _onDragStart,
              onDragUpdate: _onDragUpdate,
              onDragEnd: _onDragEnd,
              onResizeStart: _onResizeStart,
              onResizeUpdate: _onResizeUpdate,
              header: _Header(
                peerName: widget.peerNickname,
                peerAvatar: widget.peerAvatar,
                isOnline: widget.isPeerOnline,
                unreadCount: widget.unreadCount,
                bubbleCtx: widget.bubbleCtx,
                colors: _headerColors,
                onMinimize: _handleMinimize,
                onClose: _handleClose,
                onExpand: widget.onExpand,
              ),
              body: _Body(
                peerId: widget.peerId,
                peerNickname: widget.peerNickname,
                peerAvatar: widget.peerAvatar,
              ),
              resizeHandle: _ResizeHandle(
                onStart: _onResizeStart,
                onUpdate: _onResizeUpdate,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// WINDOW FRAME
// ═══════════════════════════════════════════════════════════════════════════

class _WindowFrame extends StatelessWidget {
  final double width;
  final double height;
  final double radius;
  final List<Color> headerColors;
  final GestureDragStartCallback onDragStart;
  final GestureDragUpdateCallback onDragUpdate;
  final GestureDragEndCallback onDragEnd;
  final GestureDragStartCallback onResizeStart;
  final GestureDragUpdateCallback onResizeUpdate;
  final Widget header;
  final Widget body;
  final Widget resizeHandle;

  const _WindowFrame({
    required this.width,
    required this.height,
    required this.radius,
    required this.headerColors,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onResizeStart,
    required this.onResizeUpdate,
    required this.header,
    required this.body,
    required this.resizeHandle,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      elevation: 0,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(
              color: headerColors.first.withOpacity(0.28),
              blurRadius: 32,
              spreadRadius: 0,
              offset: const Offset(0, 12),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Stack(
            children: [
              // Main column
              Column(
                children: [
                  // Draggable header
                  GestureDetector(
                    onPanStart: onDragStart,
                    onPanUpdate: onDragUpdate,
                    onPanEnd: onDragEnd,
                    behavior: HitTestBehavior.opaque,
                    child: header,
                  ),
                  // Chat body
                  Expanded(child: body),
                ],
              ),

              // Bottom-right resize handle
              Positioned(
                right: 0,
                bottom: 0,
                child: resizeHandle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// HEADER
// ═══════════════════════════════════════════════════════════════════════════

class _Header extends StatefulWidget {
  final String peerName;
  final String peerAvatar;
  final bool isOnline;
  final int unreadCount;
  final BubbleContext bubbleCtx;
  final List<Color> colors;
  final VoidCallback onMinimize;
  final AsyncCallback onClose;
  final VoidCallback? onExpand;

  const _Header({
    required this.peerName,
    required this.peerAvatar,
    required this.isOnline,
    required this.unreadCount,
    required this.bubbleCtx,
    required this.colors,
    required this.onMinimize,
    required this.onClose,
    this.onExpand,
  });

  @override
  State<_Header> createState() => _HeaderState();
}

class _HeaderState extends State<_Header> with SingleTickerProviderStateMixin {
  late AnimationController _onlineCtrl;

  @override
  void initState() {
    super.initState();
    _onlineCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (widget.isOnline) _onlineCtrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_Header old) {
    super.didUpdateWidget(old);
    if (widget.isOnline && !_onlineCtrl.isAnimating) {
      _onlineCtrl.repeat(reverse: true);
    } else if (!widget.isOnline) {
      _onlineCtrl.stop();
    }
  }

  @override
  void dispose() {
    _onlineCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _K.headerH,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: widget.colors,
        ),
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                // ── Drag grip ───────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      3,
                      (_) => Container(
                        margin: const EdgeInsets.symmetric(vertical: 1.5),
                        width: 16,
                        height: 2,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.35),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Avatar ──────────────────────────────────────────────
                Stack(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Colors.white.withOpacity(0.3), width: 2),
                        image: widget.peerAvatar.isNotEmpty
                            ? DecorationImage(
                                image: NetworkImage(widget.peerAvatar),
                                fit: BoxFit.cover)
                            : null,
                        color: Colors.white.withOpacity(0.15),
                      ),
                      child: widget.peerAvatar.isEmpty
                          ? Center(
                              child: Text(
                                widget.peerName.isNotEmpty
                                    ? widget.peerName[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                            )
                          : null,
                    ),
                    if (widget.isOnline)
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: AnimatedBuilder(
                          animation: _onlineCtrl,
                          builder: (_, __) => Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color.lerp(
                                const Color(0xFF69F0AE),
                                const Color(0xFF00E676),
                                _onlineCtrl.value,
                              ),
                              border:
                                  Border.all(color: Colors.white, width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF69F0AE)
                                      .withOpacity(0.6 * _onlineCtrl.value),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (widget.unreadCount > 0)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: _UnreadBadge(count: widget.unreadCount),
                      ),
                  ],
                ),

                const SizedBox(width: 10),

                // ── Name + status ────────────────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        widget.peerName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          letterSpacing: 0.1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      _StatusLine(
                        isOnline: widget.isOnline,
                        mode: widget.bubbleCtx.mode,
                        topic: widget.bubbleCtx.detectedTopic,
                      ),
                    ],
                  ),
                ),

                // ── Action buttons ───────────────────────────────────────
                if (widget.onExpand != null)
                  _HBtn(
                    icon: Icons.open_in_full_rounded,
                    tooltip: 'Mở rộng',
                    onTap: widget.onExpand!,
                  ),
                const SizedBox(width: 2),
                _HBtn(
                  icon: Icons.picture_in_picture_alt_rounded,
                  tooltip: 'Thu nhỏ',
                  onTap: widget.onMinimize,
                ),
                const SizedBox(width: 2),
                _HBtn(
                  icon: Icons.close_rounded,
                  tooltip: 'Đóng',
                  onTap: widget.onClose,
                  isClose: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STATUS LINE
// ═══════════════════════════════════════════════════════════════════════════

class _StatusLine extends StatelessWidget {
  final bool isOnline;
  final BubbleMode mode;
  final String? topic;

  const _StatusLine({
    required this.isOnline,
    required this.mode,
    this.topic,
  });

  @override
  Widget build(BuildContext context) {
    String text;
    String? badge;

    switch (mode) {
      case BubbleMode.work:
        badge = '💼';
        text = topic != null ? 'Work · $topic' : 'Work Mode';
        break;
      case BubbleMode.media:
        badge = '🎵';
        text = 'Đang phát media';
        break;
      case BubbleMode.location:
        badge = '📍';
        text = 'Đang chia sẻ vị trí';
        break;
      case BubbleMode.secure:
        badge = '🔒';
        text = 'Bảo mật đầu cuối';
        break;
      case BubbleMode.shared:
        badge = '🎨';
        text = 'Shared Space';
        break;
      default:
        badge = null;
        text = isOnline ? 'Đang trực tuyến' : 'Ngoại tuyến';
    }

    return Row(
      children: [
        if (badge != null) ...[
          Text(badge, style: const TextStyle(fontSize: 10)),
          const SizedBox(width: 3),
        ],
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              color: Colors.white.withOpacity(0.72),
              fontSize: 11,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// HEADER BUTTON
// ═══════════════════════════════════════════════════════════════════════════

class _HBtn extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool isClose;

  const _HBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isClose = false,
  });

  @override
  State<_HBtn> createState() => _HBtnState();
}

class _HBtnState extends State<_HBtn> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 80));
    _scale = Tween<double>(begin: 1.0, end: 0.80)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeIn));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: GestureDetector(
        onTapDown: (_) => _ctrl.forward(),
        onTapUp: (_) {
          _ctrl.reverse();
          HapticFeedback.lightImpact();
          widget.onTap();
        },
        onTapCancel: () => _ctrl.reverse(),
        child: ScaleTransition(
          scale: _scale,
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: widget.isClose
                  ? Colors.red.withOpacity(0.18)
                  : Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(9),
              border: widget.isClose
                  ? Border.all(color: Colors.red.withOpacity(0.35), width: 1)
                  : null,
            ),
            child: Icon(
              widget.icon,
              color: Colors.white.withOpacity(0.9),
              size: 15,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// BODY
// ═══════════════════════════════════════════════════════════════════════════

class _Body extends StatelessWidget {
  final String peerId;
  final String peerNickname;
  final String peerAvatar;

  const _Body({
    required this.peerId,
    required this.peerNickname,
    required this.peerAvatar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FAFB),
      child: ClipRRect(
        child: ChatPage(
          arguments: ChatPageArguments(
            peerId: peerId,
            peerAvatar: peerAvatar,
            peerNickname: peerNickname,
          ),
          isMiniChat: true,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// RESIZE HANDLE
// ═══════════════════════════════════════════════════════════════════════════

class _ResizeHandle extends StatefulWidget {
  final GestureDragStartCallback onStart;
  final GestureDragUpdateCallback onUpdate;

  const _ResizeHandle({required this.onStart, required this.onUpdate});

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (d) {
        HapticFeedback.selectionClick();
        widget.onStart(d);
      },
      onPanUpdate: widget.onUpdate,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        cursor: SystemMouseCursors.resizeDownRight,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: _K.resizeHandleSize,
          height: _K.resizeHandleSize,
          decoration: BoxDecoration(
            color: _hovering
                ? Colors.blueGrey.withOpacity(0.15)
                : Colors.transparent,
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(6),
                bottomRight: Radius.circular(_K.radius)),
          ),
          child: CustomPaint(painter: _ResizePainter(active: _hovering)),
        ),
      ),
    );
  }
}

class _ResizePainter extends CustomPainter {
  final bool active;
  const _ResizePainter({required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = (active ? Colors.blueGrey : Colors.blueGrey.withOpacity(0.35))
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final lines = [
      [
        Offset(size.width * 0.55, size.height * 0.2),
        Offset(size.width * 0.8, size.height * 0.8)
      ],
      [
        Offset(size.width * 0.25, size.height * 0.5),
        Offset(size.width * 0.5, size.height * 0.8)
      ],
    ];
    for (final l in lines) {
      canvas.drawLine(l[0], l[1], paint);
    }
  }

  @override
  bool shouldRepaint(_ResizePainter old) => old.active != active;
}

// ═══════════════════════════════════════════════════════════════════════════
// UNREAD BADGE
// ═══════════════════════════════════════════════════════════════════════════

class _UnreadBadge extends StatelessWidget {
  final int count;
  const _UnreadBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(
              color: Colors.red.withOpacity(0.5),
              blurRadius: 6,
              spreadRadius: 1),
        ],
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SIMPLE STATIC VARIANT (for non-overlay use e.g. dialog)
// ═══════════════════════════════════════════════════════════════════════════

/// A non-draggable, fixed-size mini-chat panel — useful inside dialogs
/// or split-screen containers.
class MiniChatOverlay extends StatelessWidget {
  final String peerId;
  final String peerNickname;
  final String peerAvatar;
  final bool isPeerOnline;
  final VoidCallback? onMinimize;
  final VoidCallback? onClose;
  final VoidCallback? onExpand;

  const MiniChatOverlay({
    super.key,
    required this.peerId,
    required this.peerNickname,
    required this.peerAvatar,
    this.isPeerOnline = false,
    this.onMinimize,
    this.onClose,
    this.onExpand,
  });

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final w = (screen.width * 0.85).clamp(300.0, 420.0);
    final h = (screen.height * 0.70).clamp(420.0, 650.0);

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_K.radius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.22),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_K.radius),
            child: Column(
              children: [
                _StaticHeader(
                  peerName: peerNickname,
                  peerAvatar: peerAvatar,
                  isOnline: isPeerOnline,
                  onMinimize: onMinimize,
                  onClose: onClose,
                  onExpand: onExpand,
                ),
                Expanded(
                  child: _Body(
                    peerId: peerId,
                    peerNickname: peerNickname,
                    peerAvatar: peerAvatar,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StaticHeader extends StatelessWidget {
  final String peerName;
  final String peerAvatar;
  final bool isOnline;
  final VoidCallback? onMinimize;
  final VoidCallback? onClose;
  final VoidCallback? onExpand;

  const _StaticHeader({
    required this.peerName,
    required this.peerAvatar,
    required this.isOnline,
    this.onMinimize,
    this.onClose,
    this.onExpand,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _K.headerH,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_K.grad1, _K.grad3],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          _AvatarWidget(url: peerAvatar, name: peerName, isOnline: isOnline),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(peerName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(
                  isOnline ? 'Đang trực tuyến' : 'Ngoại tuyến',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.7), fontSize: 11),
                ),
              ],
            ),
          ),
          if (onExpand != null)
            _HBtn(
                icon: Icons.open_in_full_rounded,
                tooltip: 'Mở rộng',
                onTap: onExpand!),
          if (onMinimize != null) ...[
            const SizedBox(width: 3),
            _HBtn(
                icon: Icons.remove_rounded,
                tooltip: 'Thu nhỏ',
                onTap: onMinimize!),
          ],
          if (onClose != null) ...[
            const SizedBox(width: 3),
            _HBtn(
                icon: Icons.close_rounded,
                tooltip: 'Đóng',
                onTap: onClose!,
                isClose: true),
          ],
        ],
      ),
    );
  }
}

class _AvatarWidget extends StatelessWidget {
  final String url;
  final String name;
  final bool isOnline;

  const _AvatarWidget(
      {required this.url, required this.name, required this.isOnline});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        CircleAvatar(
          radius: 17,
          backgroundColor: Colors.white.withOpacity(0.2),
          backgroundImage: url.isNotEmpty ? NetworkImage(url) : null,
          child: url.isEmpty
              ? Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14),
                )
              : null,
        ),
        if (isOnline)
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
          ),
      ],
    );
  }
}
