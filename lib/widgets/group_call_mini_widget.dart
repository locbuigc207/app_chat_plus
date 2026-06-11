// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/group_call_model.dart';
import '../services/group_call_service.dart';
import '../widgets/call_timer_widget.dart';

// ─── Design tokens ────────────────────────────────────────────────────────────
class _C {
  static const bg = Color(0xFF080E1C);
  static const surface = Color(0xFF111827);
  static const accent = Color(0xFF3B82F6);
  static const green = Color(0xFF22C55E);
  static const red = Color(0xFFEF4444);
  static const text = Color(0xFFF8FAFC);
  static const sub = Color(0xFF94A3B8);
  static const muted = Color(0xFF475569);
}

// ══════════════════════════════════════════════════════════════════════════════
// GroupCallMiniWidget
// Floating draggable mini-call widget that stays on top of other screens.
// Shows live participant count, timer, and quick rejoin / end controls.
// ══════════════════════════════════════════════════════════════════════════════
class GroupCallMiniWidget extends StatefulWidget {
  final GroupCallModel call;
  final String currentUserId;
  final String currentUserName;
  final String currentUserAvatar;
  final VoidCallback onExpand;
  final VoidCallback onEnd;

  const GroupCallMiniWidget({
    super.key,
    required this.call,
    required this.currentUserId,
    required this.currentUserName,
    required this.currentUserAvatar,
    required this.onExpand,
    required this.onEnd,
  });

  @override
  State<GroupCallMiniWidget> createState() => _GroupCallMiniWidgetState();
}

class _GroupCallMiniWidgetState extends State<GroupCallMiniWidget>
    with TickerProviderStateMixin {
  // Position
  Offset _pos = const Offset(16, 120);
  bool _posInit = false;
  bool _isDragging = false;

  // Model stream
  late GroupCallModel _model;
  StreamSubscription? _sub;

  // Animations
  late AnimationController _entryCtrl;
  late AnimationController _pulseCtrl;
  late AnimationController _liveDotCtrl;
  late Animation<double> _entryScale;
  late Animation<double> _entryFade;
  late Animation<double> _pulseAnim;
  late Animation<double> _liveDotAnim;

  // Snap edge
  bool _snappedRight = false;

  @override
  void initState() {
    super.initState();
    _model = widget.call;
    _setupAnims();
    _watchCall();
  }

  void _setupAnims() {
    _entryCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _entryScale = Tween<double>(begin: 0.7, end: 1.0)
        .animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.elasticOut));
    _entryFade = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _entryCtrl.forward();

    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.96, end: 1.04)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _liveDotCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _liveDotAnim = Tween<double>(begin: 0.35, end: 1.0).animate(
        CurvedAnimation(parent: _liveDotCtrl, curve: Curves.easeInOut));
  }

  void _watchCall() {
    _sub =
        GroupCallService.instance.watchCall(widget.call.callId).listen((call) {
      if (call == null || !mounted) return;
      setState(() => _model = call);
      if (call.isEnded) widget.onEnd();
    });
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _pulseCtrl.dispose();
    _liveDotCtrl.dispose();
    _sub?.cancel();
    super.dispose();
  }

  void _onDragStart() {
    setState(() => _isDragging = true);
    HapticFeedback.selectionClick();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    setState(() => _pos += d.delta);
  }

  void _onDragEnd(DragEndDetails d, Size screen) {
    setState(() => _isDragging = false);
    _snapToEdge(screen);
  }

  void _snapToEdge(Size screen) {
    const w = 180.0;
    const h = 88.0;
    final cx = _pos.dx + w / 2;
    final snapRight = cx > screen.width / 2;

    double tx = snapRight ? screen.width - w - 12 : 12;
    double ty = _pos.dy.clamp(MediaQuery.of(context).padding.top + 8,
        screen.height - h - MediaQuery.of(context).padding.bottom - 16);

    setState(() {
      _pos = Offset(tx, ty);
      _snappedRight = snapRight;
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    if (!_posInit) {
      _pos = Offset(16, MediaQuery.of(context).padding.top + 90);
      _posInit = true;
    }

    // Clamp
    final clampX = _pos.dx.clamp(0.0, size.width - 180.0);
    final clampY = _pos.dy
        .clamp(MediaQuery.of(context).padding.top + 4.0, size.height - 100.0);

    return Positioned(
      left: clampX,
      top: clampY,
      child: GestureDetector(
        onPanStart: (_) => _onDragStart(),
        onPanUpdate: _onDragUpdate,
        onPanEnd: (d) => _onDragEnd(d, size),
        child: FadeTransition(
          opacity: _entryFade,
          child: ScaleTransition(
            scale: _entryScale,
            child: AnimatedBuilder(
              animation: _isDragging ? _pulseCtrl : _entryCtrl,
              builder: (_, child) => Transform.scale(
                scale: _isDragging ? _pulseAnim.value : 1.0,
                child: child,
              ),
              child: _buildCard(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 180,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(_isDragging ? 0.82 : 0.78),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _C.accent.withOpacity(_isDragging ? 0.5 : 0.2),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(_isDragging ? 0.6 : 0.4),
                blurRadius: _isDragging ? 32 : 20,
                offset: const Offset(0, 8),
              ),
              if (_isDragging)
                BoxShadow(
                  color: _C.accent.withOpacity(0.2),
                  blurRadius: 20,
                ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(),
              _buildParticipantsRow(),
              _buildActions(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 6),
      child: Row(
        children: [
          // Group avatar
          Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: _C.green.withOpacity(0.4), width: 1.5),
                ),
                child: CircleAvatar(
                  radius: 16,
                  backgroundImage: _model.groupAvatarUrl.isNotEmpty
                      ? NetworkImage(_model.groupAvatarUrl)
                      : null,
                  backgroundColor: const Color(0xFF1E2D40),
                  child: _model.groupAvatarUrl.isEmpty
                      ? const Icon(Icons.group_rounded,
                          color: Colors.white54, size: 16)
                      : null,
                ),
              ),
              // Live dot
              Positioned(
                right: 0,
                bottom: 0,
                child: AnimatedBuilder(
                  animation: _liveDotAnim,
                  builder: (_, __) => Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: _C.green.withOpacity(_liveDotAnim.value),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: _C.green.withOpacity(_liveDotAnim.value * 0.5),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _model.groupName,
                  style: const TextStyle(
                    color: _C.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                if (_model.createdAt != DateTime(0))
                  CallTimerWidget(
                    startTime: _model.createdAt,
                    style: const TextStyle(
                      color: _C.green,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Participants mini avatars ───────────────────────────────────────────────
  Widget _buildParticipantsRow() {
    final shown = _model.participants.take(4).toList();
    final extra = _model.participantCount > 4 ? _model.participantCount - 4 : 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          // Stacked avatars
          SizedBox(
            height: 26,
            width: shown.length * 18.0 + (extra > 0 ? 24.0 : 0),
            child: Stack(
              children: [
                ...shown.asMap().entries.map((e) {
                  final i = e.key;
                  final p = e.value;
                  return Positioned(
                    left: i * 18.0,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black, width: 1.5),
                      ),
                      child: CircleAvatar(
                        radius: 11,
                        backgroundImage: p.userAvatar.isNotEmpty
                            ? NetworkImage(p.userAvatar)
                            : null,
                        backgroundColor: const Color(0xFF1E2D40),
                        child: p.userAvatar.isEmpty
                            ? Text(
                                p.userName.isNotEmpty
                                    ? p.userName[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 8,
                                    fontWeight: FontWeight.w700),
                              )
                            : null,
                      ),
                    ),
                  );
                }),
                if (extra > 0)
                  Positioned(
                    left: shown.length * 18.0,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black, width: 1.5),
                      ),
                      child: CircleAvatar(
                        radius: 11,
                        backgroundColor: _C.accent.withOpacity(0.3),
                        child: Text('+$extra',
                            style: const TextStyle(
                                color: _C.accent,
                                fontSize: 7,
                                fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_model.participantCount} người',
              style: const TextStyle(color: _C.sub, fontSize: 10),
            ),
          ),
          // Call type icon
          Icon(
            _model.isVideo ? Icons.videocam_rounded : Icons.phone_rounded,
            color: _model.isVideo ? _C.accent : _C.green,
            size: 13,
          ),
        ],
      ),
    );
  }

  // ── Action buttons ─────────────────────────────────────────────────────────
  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
      child: Row(
        children: [
          // Expand / Rejoin
          Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.mediumImpact();
                widget.onExpand();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _C.accent,
                      _C.accent.withOpacity(0.8),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: _C.accent.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _model.isVideo
                          ? Icons.videocam_rounded
                          : Icons.phone_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                    const SizedBox(width: 5),
                    const Text(
                      'Vào lại',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // End call
          GestureDetector(
            onTap: () {
              HapticFeedback.heavyImpact();
              widget.onEnd();
            },
            child: Container(
              width: 40,
              height: 36,
              decoration: BoxDecoration(
                color: _C.red.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _C.red.withOpacity(0.35), width: 1),
              ),
              child:
                  const Icon(Icons.call_end_rounded, color: _C.red, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// GroupCallMiniManager
// Overlay manager — inserts/removes the mini widget into the widget tree.
// Usage: wrap your root app/page with this.
// ══════════════════════════════════════════════════════════════════════════════
class GroupCallMiniManager extends StatefulWidget {
  final Widget child;
  const GroupCallMiniManager({super.key, required this.child});

  static GroupCallMiniManagerState? of(BuildContext context) =>
      context.findAncestorStateOfType<GroupCallMiniManagerState>();

  @override
  State<GroupCallMiniManager> createState() => GroupCallMiniManagerState();
}

class GroupCallMiniManagerState extends State<GroupCallMiniManager> {
  GroupCallModel? _activeCall;
  String? _uid, _name, _avatar;
  VoidCallback? _expandFn;

  /// Show mini widget for an active call
  void showMini({
    required GroupCallModel call,
    required String userId,
    required String userName,
    required String userAvatar,
    required VoidCallback onExpand,
  }) {
    setState(() {
      _activeCall = call;
      _uid = userId;
      _name = userName;
      _avatar = userAvatar;
      _expandFn = onExpand;
    });
  }

  /// Dismiss mini widget
  void dismiss() {
    setState(() {
      _activeCall = null;
      _uid = null;
      _name = null;
      _avatar = null;
      _expandFn = null;
    });
  }

  Future<void> _endCall() async {
    final call = _activeCall;
    if (call == null) return;
    dismiss();
    await GroupCallService.instance.leaveCall(call.callId);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_activeCall != null && _uid != null)
          GroupCallMiniWidget(
            call: _activeCall!,
            currentUserId: _uid!,
            currentUserName: _name ?? '',
            currentUserAvatar: _avatar ?? '',
            onExpand: () {
              _expandFn?.call();
            },
            onEnd: _endCall,
          ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ActiveCallFloatingBadge
// Compact top-of-screen banner (like iOS active call bar) shown in any screen
// when the user is in an active call.
// ══════════════════════════════════════════════════════════════════════════════
class ActiveCallFloatingBadge extends StatefulWidget {
  final GroupCallModel call;
  final VoidCallback onTap;

  const ActiveCallFloatingBadge({
    super.key,
    required this.call,
    required this.onTap,
  });

  @override
  State<ActiveCallFloatingBadge> createState() =>
      _ActiveCallFloatingBadgeState();
}

class _ActiveCallFloatingBadgeState extends State<ActiveCallFloatingBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<Offset> _slide;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _slide = Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _fade = CurvedAnimation(parent: _ctrl, curve: const Interval(0, 0.4));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slide,
      child: FadeTransition(
        opacity: _fade,
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            margin: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top,
              left: 12,
              right: 12,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: _C.green,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: _C.green.withOpacity(0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                // Pulse dot
                _PulseDot(),
                const SizedBox(width: 8),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.call.groupName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Nhấn để quay lại cuộc gọi',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.75),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),

                CallTimerWidget(
                  startTime: widget.call.createdAt,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),

                const SizedBox(width: 8),
                const Icon(Icons.chevron_right_rounded,
                    color: Colors.white, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _a;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
    _a = Tween<double>(begin: 0.4, end: 1.0).animate(_c);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _a,
      builder: (_, __) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(_a.value),
          boxShadow: [
            BoxShadow(
              color: Colors.white.withOpacity(_a.value * 0.4),
              blurRadius: 8,
            ),
          ],
        ),
      ),
    );
  }
}
