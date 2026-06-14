import 'dart:async';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/group_call_model.dart';
import '../pages/incoming_group_call_page.dart';
import '../providers/providers.dart';
import '../services/group_call_service.dart';

// ══════════════════════════════════════════════════════════════════════════════
// GroupCallListener
// Sits at the root widget tree. Watches Firestore for incoming group calls
// and presents the IncomingGroupCallPage as a full-screen overlay.
// ══════════════════════════════════════════════════════════════════════════════
class GroupCallListener extends StatefulWidget {
  final Widget child;

  const GroupCallListener({super.key, required this.child});

  @override
  State<GroupCallListener> createState() => _GroupCallListenerState();
}

class _GroupCallListenerState extends State<GroupCallListener>
    with WidgetsBindingObserver {
  final _service = GroupCallService.instance;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<GroupCallModel?>? _callSub;

  String? _displayedCallId;
  bool _isShowingIncoming = false;

  // Deduplicate rapid Firestore updates
  final Map<String, DateTime> _seenCallIds = {};
  static const _dedupeSeconds = 5;

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

  // ── Auth listener ──────────────────────────────────────────────────────────
  void _startAuthListener() {
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      _callSub?.cancel();
      _callSub = null;
      _displayedCallId = null;
      _isShowingIncoming = false;

      if (user != null) _subscribeToIncomingCalls(user.uid);
    });
  }

  void _subscribeToIncomingCalls(String uid) {
    _callSub = _service.incomingGroupCallStream(uid).listen(
      (call) {
        if (call == null) return;
        _handleIncomingCall(call, uid);
      },
      onError: (e) {
        debugPrint('⚠️ GroupCallListener stream error: $e');

        // FIX BUG 1a: Không nuốt lỗi (fail silent) nữa. Hiển thị lỗi ra UI
        // để cảnh báo rõ ràng nếu thiếu Composite Index trong Firestore.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Lỗi đồng bộ gọi nhóm (Có thể do thiếu Firestore Index):\n$e',
                style: const TextStyle(color: Colors.white),
              ),
              backgroundColor: Colors.red.shade800,
              duration: const Duration(seconds: 10),
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: 'Đóng',
                textColor: Colors.white,
                onPressed: () {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                },
              ),
            ),
          );
        }
      },
    );
  }

  // ── Incoming call handler ──────────────────────────────────────────────────
  void _handleIncomingCall(GroupCallModel call, String uid) {
    if (!mounted) return;

    // Already displaying this call
    if (_displayedCallId == call.callId) return;

    // Dedup rapid updates
    final lastSeen = _seenCallIds[call.callId];
    if (lastSeen != null &&
        DateTime.now().difference(lastSeen).inSeconds < _dedupeSeconds) return;
    _seenCallIds[call.callId] = DateTime.now();

    // Skip ended calls
    if (call.isEnded || call.status == GroupCallStatus.missed) return;

    // Skip if already participant
    if (call.participants.any((p) => p.userId == uid)) return;

    // Skip if kicked
    if (call.isKicked(uid)) return;

    // Dismiss current if any
    if (_isShowingIncoming) _dismissCurrentIncoming();

    _displayedCallId = call.callId;
    _isShowingIncoming = true;
    _triggerHapticAlert();
    _showIncomingScreen(call, uid);
  }

  void _triggerHapticAlert() {
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) HapticFeedback.mediumImpact();
    });
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) HapticFeedback.lightImpact();
    });
  }

  void _dismissCurrentIncoming() {
    try {
      Navigator.of(context, rootNavigator: true).pop();
    } catch (_) {}
    _isShowingIncoming = false;
    _displayedCallId = null;
  }

  void _showIncomingScreen(GroupCallModel call, String uid) {
    final auth = context.read<AuthProvider>();
    final userName = auth.currentUserName ?? '';
    final userAvatar = auth.currentUserAvatar ?? '';

    Navigator.of(context, rootNavigator: true)
        .push<void>(_IncomingCallRoute(
      builder: (_) => IncomingGroupCallPage(
        call: call,
        currentUserId: uid,
        currentUserName: userName,
        currentUserAvatar: userAvatar,
      ),
    ))
        .then((_) {
      if (mounted) {
        _isShowingIncoming = false;
        if (_displayedCallId == call.callId) _displayedCallId = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ── Custom page route for incoming call ───────────────────────────────────────
class _IncomingCallRoute<T> extends PageRouteBuilder<T> {
  final WidgetBuilder builder;

  _IncomingCallRoute({required this.builder})
      : super(
          opaque: true,
          barrierDismissible: false,
          transitionDuration: const Duration(milliseconds: 550),
          reverseTransitionDuration: const Duration(milliseconds: 320),
          pageBuilder: (ctx, anim, secondaryAnim) => builder(ctx),
          transitionsBuilder: (ctx, anim, secondaryAnim, child) {
            final slide = Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(
                CurvedAnimation(parent: anim, curve: Curves.easeOutCubic));
            final fade =
                CurvedAnimation(parent: anim, curve: const Interval(0, 0.35));
            return SlideTransition(
              position: slide,
              child: FadeTransition(opacity: fade, child: child),
            );
          },
        );
}

// ══════════════════════════════════════════════════════════════════════════════
// CallNotificationOverlay
// Compact heads-up banner (shown when user is in another screen).
// ══════════════════════════════════════════════════════════════════════════════
class CallNotificationOverlay extends StatefulWidget {
  final GroupCallModel call;
  final String currentUserId;
  final String currentUserName;
  final String currentUserAvatar;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const CallNotificationOverlay({
    super.key,
    required this.call,
    required this.currentUserId,
    required this.currentUserName,
    required this.currentUserAvatar,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  State<CallNotificationOverlay> createState() =>
      _CallNotificationOverlayState();
}

class _CallNotificationOverlayState extends State<CallNotificationOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<Offset> _slide;
  late Animation<double> _fade;
  late Animation<double> _blur;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500))
      ..forward();
    _slide = Tween<Offset>(begin: const Offset(0, -1.3), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _fade = CurvedAnimation(parent: _ctrl, curve: const Interval(0, 0.4));
    _blur = Tween<double>(begin: 0, end: 20)
        .animate(CurvedAnimation(parent: _ctrl, curve: const Interval(0, 0.5)));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.call.isVideo;
    final accentColor =
        isVideo ? const Color(0xFF3B82F6) : const Color(0xFF22C55E);

    return SlideTransition(
      position: _slide,
      child: FadeTransition(
        opacity: _fade,
        child: Material(
          color: Colors.transparent,
          child: Padding(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 10,
              left: 12,
              right: 12,
            ),
            child: AnimatedBuilder(
              animation: _blur,
              builder: (_, child) => ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                      sigmaX: _blur.value, sigmaY: _blur.value),
                  child: child!,
                ),
              ),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                decoration: BoxDecoration(
                  color: const Color(0xF0111827),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                      color: accentColor.withValues(alpha: 0.25), width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 28,
                      offset: const Offset(0, 6),
                    ),
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.12),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Avatar
                    _buildAvatar(accentColor),
                    const SizedBox(width: 12),

                    // Info
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
                          const SizedBox(height: 2),
                          Row(children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: accentColor,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              isVideo
                                  ? 'Cuộc gọi video nhóm'
                                  : 'Cuộc gọi thoại nhóm',
                              style:
                                  TextStyle(color: accentColor, fontSize: 11),
                            ),
                          ]),
                        ],
                      ),
                    ),

                    const SizedBox(width: 8),

                    // Decline
                    _actionBtn(
                      icon: Icons.call_end_rounded,
                      color: const Color(0xFFEF4444),
                      onTap: widget.onDecline,
                    ),
                    const SizedBox(width: 8),

                    // Accept
                    _actionBtn(
                      icon: isVideo
                          ? Icons.videocam_rounded
                          : Icons.phone_rounded,
                      color: accentColor,
                      onTap: widget.onAccept,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(Color accentColor) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border:
            Border.all(color: accentColor.withValues(alpha: 0.5), width: 1.5),
        boxShadow: [
          BoxShadow(color: accentColor.withValues(alpha: 0.3), blurRadius: 10),
        ],
      ),
      child: CircleAvatar(
        radius: 22,
        backgroundImage: widget.call.groupAvatarUrl.isNotEmpty
            ? NetworkImage(widget.call.groupAvatarUrl)
            : null,
        backgroundColor: const Color(0xFF1E2D40),
        child: widget.call.groupAvatarUrl.isEmpty
            ? const Icon(Icons.group_rounded, color: Colors.white54, size: 22)
            : null,
      ),
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        onTap();
      },
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
                color: color.withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// GroupCallHistoryTile — for displaying call records in chat
// ══════════════════════════════════════════════════════════════════════════════
class GroupCallHistoryTile extends StatelessWidget {
  final GroupCallModel call;
  final String currentUserId;
  final VoidCallback? onRejoin;

  const GroupCallHistoryTile({
    super.key,
    required this.call,
    required this.currentUserId,
    this.onRejoin,
  });

  bool get _wasParticipant =>
      call.participants.any((p) => p.userId == currentUserId) ||
      call.initiatorId == currentUserId;

  String get _statusLabel {
    switch (call.status) {
      case GroupCallStatus.ended:
        return call.durationSeconds != null && call.durationSeconds! > 0
            ? call.formattedDuration
            : 'Đã kết thúc';
      case GroupCallStatus.missed:
        return 'Nhỡ';
      case GroupCallStatus.calling:
      case GroupCallStatus.ongoing:
      case GroupCallStatus.waiting:
        return 'Đang diễn ra';
    }
  }

  Color _statusColor(BuildContext context) {
    switch (call.status) {
      case GroupCallStatus.missed:
        return const Color(0xFFEF4444);
      case GroupCallStatus.ongoing:
      case GroupCallStatus.calling:
        return const Color(0xFF22C55E);
      default:
        return Colors.white38;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = call.callType == GroupCallType.video;
    final iconColor =
        isVideo ? const Color(0xFF3B82F6) : const Color(0xFF22C55E);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          // Icon
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isVideo ? Icons.videocam_rounded : Icons.phone_rounded,
              color: iconColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isVideo ? 'Cuộc gọi video nhóm' : 'Cuộc gọi thoại nhóm',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Row(children: [
                  Icon(Icons.access_time_rounded,
                      size: 10, color: _statusColor(context)),
                  const SizedBox(width: 4),
                  Text(
                    _statusLabel,
                    style:
                        TextStyle(color: _statusColor(context), fontSize: 11),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.people_rounded,
                      size: 10, color: Colors.white30),
                  const SizedBox(width: 3),
                  Text(
                    '${call.participantCount} người',
                    style: const TextStyle(color: Colors.white30, fontSize: 10),
                  ),
                ]),
              ],
            ),
          ),

          // Rejoin if ongoing
          if (call.isOngoing && onRejoin != null)
            GestureDetector(
              onTap: onRejoin,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Vào lại',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
