import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/call_model.dart';
import '../pages/outgoing_call_page.dart';
import '../services/call_service.dart';

// ══════════════════════════════════════════════════════
// CALL BUTTONS  (for chat AppBar)
// ══════════════════════════════════════════════════════

/// A pair of voice + video call buttons for the chat AppBar.
class CallButtons extends StatelessWidget {
  final String peerId;
  final String peerName;
  final String peerAvatar;

  const CallButtons({
    super.key,
    required this.peerId,
    required this.peerName,
    required this.peerAvatar,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _AppBarCallBtn(
          icon: Icons.videocam_rounded,
          color: const Color(0xFF1E88E5),
          tooltip: 'Gọi video',
          onTap: () => _startCall(context, CallType.video),
        ),
        const SizedBox(width: 4),
        _AppBarCallBtn(
          icon: Icons.phone_rounded,
          color: const Color(0xFF43A047),
          tooltip: 'Gọi thoại',
          onTap: () => _startCall(context, CallType.voice),
        ),
      ],
    );
  }

  Future<void> _startCall(BuildContext context, CallType type) async {
    if (!context.mounted) return;
    HapticFeedback.lightImpact();

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Text('Đang kết nối ${type == CallType.video ? 'video' : 'thoại'}…'),
          ],
        ),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1A1F36),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );

    final call = await CallService.instance.initiateCall(
      calleeId: peerId,
      calleeName: peerName,
      calleeAvatar: peerAvatar,
      callType: type,
    );
    messenger.hideCurrentSnackBar();

    if (!context.mounted) return;

    if (call == null) {
      _showError(
          context, 'Không thể thực hiện cuộc gọi. Người dùng có thể đang bận.');
      return;
    }

    Navigator.of(context).push(
      _FadeSlideRoute(builder: (_) => OutgoingCallPage(call: call)),
    );
  }

  void _showError(BuildContext ctx, String msg) {
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.orange.shade800,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════
// VOICE CALL ICON BUTTON  (standalone)
// ══════════════════════════════════════════════════════
class VoiceCallIconButton extends StatelessWidget {
  final String peerId, peerName, peerAvatar;

  const VoiceCallIconButton({
    super.key,
    required this.peerId,
    required this.peerName,
    required this.peerAvatar,
  });

  @override
  Widget build(BuildContext context) => _AppBarCallBtn(
        icon: Icons.phone_rounded,
        color: const Color(0xFF43A047),
        tooltip: 'Gọi thoại',
        onTap: () => _call(context),
      );

  Future<void> _call(BuildContext ctx) async {
    HapticFeedback.lightImpact();
    final call = await CallService.instance.initiateCall(
      calleeId: peerId,
      calleeName: peerName,
      calleeAvatar: peerAvatar,
      callType: CallType.voice,
    );
    if (!ctx.mounted) return;
    if (call != null) {
      Navigator.of(ctx).push(
        _FadeSlideRoute(builder: (_) => OutgoingCallPage(call: call)),
      );
    } else {
      _showBusySnack(ctx);
    }
  }

  void _showBusySnack(BuildContext ctx) {
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: const Text('Không thể thực hiện cuộc gọi lúc này.'),
        backgroundColor: Colors.orange.shade800,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════
// VIDEO CALL ICON BUTTON  (standalone)
// ══════════════════════════════════════════════════════
class VideoCallIconButton extends StatelessWidget {
  final String peerId, peerName, peerAvatar;

  const VideoCallIconButton({
    super.key,
    required this.peerId,
    required this.peerName,
    required this.peerAvatar,
  });

  @override
  Widget build(BuildContext context) => _AppBarCallBtn(
        icon: Icons.videocam_rounded,
        color: const Color(0xFF1E88E5),
        tooltip: 'Gọi video',
        onTap: () => _call(context),
      );

  Future<void> _call(BuildContext ctx) async {
    HapticFeedback.lightImpact();
    final call = await CallService.instance.initiateCall(
      calleeId: peerId,
      calleeName: peerName,
      calleeAvatar: peerAvatar,
      callType: CallType.video,
    );
    if (!ctx.mounted) return;
    if (call != null) {
      Navigator.of(ctx).push(
        _FadeSlideRoute(builder: (_) => OutgoingCallPage(call: call)),
      );
    } else {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: const Text('Không thể thực hiện cuộc gọi lúc này.'),
          backgroundColor: Colors.orange.shade800,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );
    }
  }
}

// ══════════════════════════════════════════════════════
// BIG CALL BUTTON  (for profile pages)
// ══════════════════════════════════════════════════════
class BigCallButton extends StatefulWidget {
  final String peerId, peerName, peerAvatar;
  final CallType callType;

  const BigCallButton({
    super.key,
    required this.peerId,
    required this.peerName,
    required this.peerAvatar,
    required this.callType,
  });

  @override
  State<BigCallButton> createState() => _BigCallButtonState();
}

class _BigCallButtonState extends State<BigCallButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  bool _loading = false;

  Color get _color => widget.callType == CallType.video
      ? const Color(0xFF1E88E5)
      : const Color(0xFF43A047);

  IconData get _icon => widget.callType == CallType.video
      ? Icons.videocam_rounded
      : Icons.phone_rounded;

  String get _label => widget.callType == CallType.video ? 'Video' : 'Thoại';

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 90),
        reverseDuration: const Duration(milliseconds: 220));
    _scale = Tween<double>(begin: 1.0, end: 0.92)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    if (_loading) return;
    HapticFeedback.mediumImpact();
    setState(() => _loading = true);

    final call = await CallService.instance.initiateCall(
      calleeId: widget.peerId,
      calleeName: widget.peerName,
      calleeAvatar: widget.peerAvatar,
      callType: widget.callType,
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (call != null) {
      Navigator.of(context).push(
        _FadeSlideRoute(builder: (_) => OutgoingCallPage(call: call)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Người dùng đang bận hoặc không thể kết nối.'),
          backgroundColor: Colors.orange.shade800,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTapDown: (_) {
          if (!_loading) _ctrl.forward();
        },
        onTapUp: (_) {
          _ctrl.reverse();
          _onTap();
        },
        onTapCancel: () => _ctrl.reverse(),
        child: ScaleTransition(
          scale: _scale,
          child: Container(
            width: 72,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: _color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _color.withValues(alpha: 0.3)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _loading
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: _color),
                      )
                    : Icon(_icon, color: _color, size: 26),
                const SizedBox(height: 8),
                Text(
                  _label,
                  style: TextStyle(
                      color: _color, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      );
}

// ══════════════════════════════════════════════════════
// FLOATING CALL BUTTON  (for chat FAB area)
// ══════════════════════════════════════════════════════
class FloatingCallPanel extends StatelessWidget {
  final String peerId, peerName, peerAvatar;

  const FloatingCallPanel({
    super.key,
    required this.peerId,
    required this.peerName,
    required this.peerAvatar,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _FloatingBtn(
                icon: Icons.phone_rounded,
                color: const Color(0xFF43A047),
                onTap: () => _call(context, CallType.voice),
              ),
              const SizedBox(width: 4),
              _FloatingBtn(
                icon: Icons.videocam_rounded,
                color: const Color(0xFF1E88E5),
                onTap: () => _call(context, CallType.video),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _call(BuildContext ctx, CallType type) async {
    HapticFeedback.lightImpact();
    final call = await CallService.instance.initiateCall(
      calleeId: peerId,
      calleeName: peerName,
      calleeAvatar: peerAvatar,
      callType: type,
    );
    if (!ctx.mounted) return;
    if (call != null) {
      Navigator.of(ctx).push(
        _FadeSlideRoute(builder: (_) => OutgoingCallPage(call: call)),
      );
    }
  }
}

// ══════════════════════════════════════════════════════
// INTERNAL WIDGETS
// ══════════════════════════════════════════════════════

class _AppBarCallBtn extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _AppBarCallBtn({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  State<_AppBarCallBtn> createState() => _AppBarCallBtnState();
}

class _AppBarCallBtnState extends State<_AppBarCallBtn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 80),
        reverseDuration: const Duration(milliseconds: 200));
    _scale = Tween<double>(begin: 1.0, end: 0.84)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Tooltip(
        message: widget.tooltip,
        child: GestureDetector(
          onTapDown: (_) => _ctrl.forward(),
          onTapUp: (_) {
            _ctrl.reverse();
            widget.onTap();
          },
          onTapCancel: () => _ctrl.reverse(),
          child: ScaleTransition(
            scale: _scale,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(
                    color: widget.color.withValues(alpha: 0.25), width: 1),
              ),
              child: Icon(widget.icon, color: widget.color, size: 19),
            ),
          ),
        ),
      );
}

class _FloatingBtn extends StatefulWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _FloatingBtn({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  State<_FloatingBtn> createState() => _FloatingBtnState();
}

class _FloatingBtnState extends State<_FloatingBtn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 80),
        reverseDuration: const Duration(milliseconds: 180));
    _scale = Tween<double>(begin: 1.0, end: 0.85)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTapDown: (_) => _ctrl.forward(),
        onTapUp: (_) {
          _ctrl.reverse();
          widget.onTap();
        },
        onTapCancel: () => _ctrl.reverse(),
        child: ScaleTransition(
          scale: _scale,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(widget.icon, color: widget.color, size: 20),
          ),
        ),
      );
}

// ── Page route for call pages ─────────────────────────
class _FadeSlideRoute<T> extends PageRoute<T> {
  final WidgetBuilder builder;

  _FadeSlideRoute({required this.builder});

  @override
  bool get maintainState => true;

  @override
  bool get opaque => false;

  @override
  bool get barrierDismissible => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 500);

  @override
  Widget buildPage(BuildContext ctx, _, __) => builder(ctx);

  @override
  Widget buildTransitions(
    BuildContext ctx,
    Animation<double> anim,
    Animation<double> _,
    Widget child,
  ) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      ),
    );
  }
}
