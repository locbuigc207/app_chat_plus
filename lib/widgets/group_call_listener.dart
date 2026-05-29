import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:provider/provider.dart';

import '../models/group_call_model.dart';
import '../pages/incoming_group_call_page.dart';
import '../providers/providers.dart';
import '../services/group_call_service.dart';












class GroupCallListener extends StatefulWidget {
  final Widget child;

  const GroupCallListener({super.key, required this.child});

  @override
  State<GroupCallListener> createState() => _GroupCallListenerState();
}

class _GroupCallListenerState extends State<GroupCallListener> with WidgetsBindingObserver {
  final _service = GroupCallService.instance;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<GroupCallModel?>? _callSub;

  String? _displayedCallId; 
  bool _isShowingIncoming = false;

  
  final Map<String, DateTime> _seenCallIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startAuthListener();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    _callSub?.cancel();
    super.dispose();
  }

  
  
  

  void _startAuthListener() {
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      _callSub?.cancel();
      _callSub = null;
      _displayedCallId = null;
      _isShowingIncoming = false;

      if (user != null) {
        _subscribeToIncomingCalls(user.uid);
      }
    });
  }

  void _subscribeToIncomingCalls(String uid) {
    _callSub = _service.incomingGroupCallStream(uid).listen((call) {
      if (call == null) return;
      _handleIncomingCall(call, uid);
    }, onError: (e) {
      debugPrint('⚠️ GroupCallListener stream error: $e');
    });
  }

  void _handleIncomingCall(GroupCallModel call, String uid) {
    if (!mounted) return;

    
    if (_displayedCallId == call.callId) return;

    
    final lastSeen = _seenCallIds[call.callId];
    if (lastSeen != null && DateTime.now().difference(lastSeen).inSeconds < 5) {
      return;
    }
    _seenCallIds[call.callId] = DateTime.now();

    
    if (call.status == GroupCallStatus.ended) return;
    if (call.participants.any((p) => p.userId == uid)) return;

    
    if (_isShowingIncoming) {
      _dismissCurrentIncoming();
    }

    _displayedCallId = call.callId;
    _isShowingIncoming = true;

    _triggerHapticAlert();
    _showIncomingScreen(call, uid);
  }

  void _triggerHapticAlert() {
    HapticFeedback.vibrate();
    Future.delayed(const Duration(milliseconds: 350), () => HapticFeedback.vibrate());
    Future.delayed(const Duration(milliseconds: 700), () => HapticFeedback.vibrate());
  }

  void _dismissCurrentIncoming() {
    final nav = Navigator.of(context, rootNavigator: true);
    try {
      nav.pop();
    } catch (_) {}
    _isShowingIncoming = false;
    _displayedCallId = null;
  }

  void _showIncomingScreen(GroupCallModel call, String uid) {
    final auth = context.read<AuthProvider>();
    final userName = auth.currentUserName ?? '';
    final userAvatar = auth.currentUserAvatar ?? '';

    final nav = Navigator.of(context, rootNavigator: true);

    nav
        .push<void>(
      _IncomingCallRoute(
        builder: (_) => IncomingGroupCallPage(
          call: call,
          currentUserId: uid,
          currentUserName: userName,
          currentUserAvatar: userAvatar,
        ),
      ),
    )
        .then((_) {
      if (mounted) {
        _isShowingIncoming = false;
        if (_displayedCallId == call.callId) {
          _displayedCallId = null;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}





class _IncomingCallRoute<T> extends PageRouteBuilder<T> {
  final WidgetBuilder builder;

  _IncomingCallRoute({required this.builder})
      : super(
          opaque: false,
          barrierDismissible: false,
          barrierColor: Colors.black54,
          transitionDuration: const Duration(milliseconds: 500),
          reverseTransitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (ctx, anim, secondaryAnim) => builder(ctx),
          transitionsBuilder: (ctx, anim, secondaryAnim, child) {
            final slide = Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
            );
            final fade = CurvedAnimation(parent: anim, curve: const Interval(0, 0.4));
            return SlideTransition(
              position: slide,
              child: FadeTransition(opacity: fade, child: child),
            );
          },
        );
}








class CallNotificationOverlay extends StatefulWidget {
  final GroupCallModel call;
  final String currentUserId;
  final String currentUserName;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const CallNotificationOverlay({
    super.key,
    required this.call,
    required this.currentUserId,
    required this.currentUserName,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  State<CallNotificationOverlay> createState() => _CallNotificationOverlayState();
}

class _CallNotificationOverlayState extends State<CallNotificationOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<Offset> _slide;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();
    _slide = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _fade = CurvedAnimation(parent: _ctrl, curve: const Interval(0, 0.5));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.call.isVideo;

    return SlideTransition(
      position: _slide,
      child: FadeTransition(
        opacity: _fade,
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 8,
              left: 12,
              right: 12,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF0f172a),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: isVideo ? const Color(0xFF3B82F6) : const Color(0xFF22C55E),
                        width: 2),
                  ),
                  child: ClipOval(
                    child: widget.call.groupAvatarUrl.isNotEmpty
                        ? Image.network(widget.call.groupAvatarUrl, fit: BoxFit.cover)
                        : Container(
                            color: const Color(0xFF334155),
                            child: const Icon(Icons.group, color: Colors.white, size: 20),
                          ),
                  ),
                ),
                const SizedBox(width: 12),

                
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.call.groupName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        isVideo ? 'Cuộc gọi video nhóm' : 'Cuộc gọi thoại nhóm',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),

                
                _circleBtn(
                  icon: Icons.call_end_rounded,
                  color: const Color(0xFFEF4444),
                  onTap: widget.onDecline,
                ),
                const SizedBox(width: 8),
                
                _circleBtn(
                  icon: isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                  color: const Color(0xFF22C55E),
                  onTap: widget.onAccept,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _circleBtn({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.4),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}
