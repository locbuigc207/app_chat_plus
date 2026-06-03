import 'dart:async';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/call_model.dart';
import '../pages/incoming_call_page.dart';
import '../services/call_service.dart';

// ══════════════════════════════════════════════════════
// CALL LISTENER
// Sits at the root of the widget tree and watches for
// incoming calls, presenting IncomingCallPage when one arrives.
// ══════════════════════════════════════════════════════
class CallListener extends StatefulWidget {
  final Widget child;
  final String? currentUserId;

  const CallListener({
    super.key,
    required this.child,
    this.currentUserId,
  });

  @override
  State<CallListener> createState() => _CallListenerState();
}

class _CallListenerState extends State<CallListener>
    with WidgetsBindingObserver {
  final _callService = CallService.instance;

  StreamSubscription<CallModel?>? _incomingSub;
  StreamSubscription<User?>? _authSub;

  String? _activeCallId;
  bool _inBackground = false;
  bool _showingIncoming = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    if (widget.currentUserId != null) {
      _subscribe(widget.currentUserId!);
    } else {
      _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
        _unsubscribe();
        if (user != null) _subscribe(user.uid);
      });
    }
  }

  void _subscribe(String uid) {
    _incomingSub = _callService.incomingCallStream.listen((call) {
      if (!mounted || call == null) return;

      // Skip if same call already being shown
      if (call.callId == _activeCallId) return;

      // Skip inactive
      if (!call.status.isActive) return;

      _activeCallId = call.callId;
      _showIncomingCall(call);
    }, onError: (e) {
      debugPrint('⚠️ [CallListener] Stream error: $e');
    });
  }

  void _unsubscribe() {
    _incomingSub?.cancel();
    _incomingSub = null;
    _activeCallId = null;
    _showingIncoming = false;
  }

  void _showIncomingCall(CallModel call) {
    if (!mounted || _showingIncoming) return;
    _showingIncoming = true;
    HapticFeedback.heavyImpact();

    final navigator = Navigator.of(context, rootNavigator: true);
    navigator
        .push<void>(
      _CallOverlayRoute(call: call),
    )
        .then((_) {
      _activeCallId = null;
      _showingIncoming = false;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _inBackground = state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _unsubscribe();
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ══════════════════════════════════════════════════════
// INCOMING CALL OVERLAY ROUTE
// Uses a custom PageRoute for smooth slide-from-bottom.
// ══════════════════════════════════════════════════════
class _CallOverlayRoute extends PageRoute<void> {
  final CallModel call;

  _CallOverlayRoute({required this.call});

  @override
  bool get maintainState => true;

  @override
  bool get opaque => true;

  @override
  bool get barrierDismissible => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 560);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation) {
    return IncomingCallPage(call: call);
  }

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    );
  }
}

// ══════════════════════════════════════════════════════
// MINI INCOMING CALL BANNER
// Shown as an overlay banner when user is in a different screen.
// (Useful for heads-up notification style)
// ══════════════════════════════════════════════════════
class IncomingCallBanner extends StatefulWidget {
  final CallModel call;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const IncomingCallBanner({
    super.key,
    required this.call,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  State<IncomingCallBanner> createState() => _IncomingCallBannerState();
}

class _IncomingCallBannerState extends State<IncomingCallBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 450));
    _slide = Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
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
    final name = widget.call.callerName;
    final avatar = widget.call.callerAvatar;
    final isVid = widget.call.isVideoCall;

    return SlideTransition(
      position: _slide,
      child: FadeTransition(
        opacity: _fade,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xF0111827),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.15)),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 4)),
                  ],
                ),
                child: Row(children: [
                  // Avatar
                  Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                          colors: [Color(0xFF3949AB), Color(0xFF1E88E5)]),
                    ),
                    child: ClipOval(
                      child: avatar.isNotEmpty
                          ? Image.network(avatar,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _Initial(name: name))
                          : _Initial(name: name),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Info
                  Expanded(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Row(children: [
                        Icon(
                            isVid
                                ? Icons.videocam_rounded
                                : Icons.phone_rounded,
                            size: 12,
                            color: Colors.white54),
                        const SizedBox(width: 4),
                        Text(isVid ? 'Gọi video đến' : 'Gọi thoại đến',
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12)),
                      ]),
                    ],
                  )),

                  const SizedBox(width: 8),

                  // Decline
                  _BannerBtn(
                    icon: Icons.call_end_rounded,
                    color: const Color(0xFFFF3B30),
                    onTap: widget.onDecline,
                  ),
                  const SizedBox(width: 8),

                  // Accept
                  _BannerBtn(
                    icon: isVid ? Icons.videocam_rounded : Icons.phone_rounded,
                    color: const Color(0xFF34C759),
                    onTap: widget.onAccept,
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Initial extends StatelessWidget {
  final String name;
  const _Initial({required this.name});

  @override
  Widget build(BuildContext context) => Center(
          child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: const TextStyle(
            color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
      ));
}

class _BannerBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _BannerBtn(
      {required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () {
          HapticFeedback.mediumImpact();
          onTap();
        },
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 3))
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      );
}
