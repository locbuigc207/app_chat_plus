// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/group_call_model.dart';
import '../services/group_call_service.dart';
import '../widgets/call_timer_widget.dart';

class _K {
  static const bg = Color(0xFF080E1C);
  static const surface = Color(0xFF111827);
  static const s2 = Color(0xFF1C2333);
  static const accent = Color(0xFF3B82F6);
  static const green = Color(0xFF22C55E);
  static const red = Color(0xFFEF4444);
  static const amber = Color(0xFFF59E0B);
  static const text = Color(0xFFF8FAFC);
  static const sub = Color(0xFF94A3B8);
  static const muted = Color(0xFF475569);
}

// ══════════════════════════════════════════════════════════════════════════════
// WaitingRoomPage
// Full-screen waiting room shown to users before admin admits them.
// ══════════════════════════════════════════════════════════════════════════════
class GroupCallWaitingRoomPage extends StatefulWidget {
  final GroupCallModel call;
  final String currentUserId;
  final String currentUserName;
  final String currentUserAvatar;

  const GroupCallWaitingRoomPage({
    super.key,
    required this.call,
    required this.currentUserId,
    this.currentUserName = '',
    this.currentUserAvatar = '',
  });

  @override
  State<GroupCallWaitingRoomPage> createState() =>
      _GroupCallWaitingRoomPageState();
}

class _GroupCallWaitingRoomPageState extends State<GroupCallWaitingRoomPage>
    with TickerProviderStateMixin {
  StreamSubscription? _callSub;
  late GroupCallModel _model;
  final _joinedAt = DateTime.now();

  late AnimationController _pulseCtrl;
  late AnimationController _dotCtrl;
  late AnimationController _fadeCtrl;
  late Animation<double> _pulseAnim;
  late Animation<double> _dotAnim;
  late Animation<double> _fadeAnim;

  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _model = widget.call;
    _setupAnims();
    _watchCall();
  }

  void _setupAnims() {
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _dotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();

    _pulseAnim = Tween<double>(
      begin: 0.92,
      end: 1.08,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _dotAnim = CurvedAnimation(parent: _dotCtrl, curve: Curves.linear);
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
  }

  void _watchCall() {
    _callSub = GroupCallService.instance.watchCall(widget.call.callId).listen((
      call,
    ) {
      if (call == null || !mounted) return;
      setState(() => _model = call);

      // Đã được host chấp nhận (Admitted) → vào được call
      if (call.isParticipant(widget.currentUserId)) {
        Navigator.of(context).pop(true);
        return;
      }

      // Bị từ chối (deny/kick) khỏi waiting room
      if (call.isKicked(widget.currentUserId)) {
        Navigator.of(context).pop(false);
        return;
      }

      // Không còn trong danh sách waitingRoomUserIds và cũng không phải participant
      // → Có thể host đã bỏ qua hoặc từ chối
      final stillWaiting = call.waitingRoomUserIds.contains(
        widget.currentUserId,
      );
      final isParticipant = call.isParticipant(widget.currentUserId);
      if (!stillWaiting && !isParticipant && !call.isEnded) {
        Navigator.of(context).pop(false);
        return;
      }

      // Cuộc gọi kết thúc trong lúc đang ở phòng chờ
      if (call.isEnded) Navigator.of(context).pop(false);
    });
  }

  Future<void> _leaveWaitingRoom() async {
    if (_leaving) return;
    setState(() => _leaving = true);
    HapticFeedback.lightImpact();
    await GroupCallService.instance.declineCall(widget.call.callId);
    if (mounted) Navigator.of(context).pop(false);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _dotCtrl.dispose();
    _fadeCtrl.dispose();
    _callSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _K.bg,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background orbs
            const _BackgroundOrbs(color: _K.amber),

            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    _buildTopBar(),
                    const Spacer(flex: 2),
                    _buildAvatar(),
                    const SizedBox(height: 24),
                    _buildStatus(),
                    _buildEndedWarning(),
                    const SizedBox(height: 16),
                    _buildWaitingDots(),
                    const SizedBox(height: 28),
                    _buildCallInfo(),
                    const Spacer(flex: 3),
                    _buildParticipantPreview(),
                    const Spacer(flex: 1),
                    _buildLeaveButton(),
                    const SizedBox(height: 28),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() => Row(
    children: [
      GestureDetector(
        onTap: _leaving ? null : _leaveWaitingRoom,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.close_rounded,
            color: Colors.white54,
            size: 18,
          ),
        ),
      ),
      const Spacer(),
      CallTimerWidget(
        startTime: _joinedAt,
        style: const TextStyle(
          color: _K.muted,
          fontSize: 13,
          letterSpacing: 0.8,
        ),
      ),
    ],
  );

  Widget _buildAvatar() {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Ripple rings
        ...List.generate(
          3,
          (i) => AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, __) {
              final scale =
                  1.0 + i * 0.18 + (_pulseAnim.value - 0.92) * (i + 1) * 0.3;
              return Transform.scale(
                scale: scale,
                child: Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _K.amber.withValues(alpha: 0.12 / (i + 1)),
                      width: 1.5,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        // Avatar
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: _K.amber.withValues(alpha: 0.25),
                blurRadius: 32,
              ),
            ],
          ),
          child: CircleAvatar(
            radius: 54,
            backgroundImage: widget.currentUserAvatar.isNotEmpty
                ? NetworkImage(widget.currentUserAvatar)
                : null,
            backgroundColor: _K.s2,
            child: widget.currentUserAvatar.isEmpty
                ? Text(
                    widget.currentUserName.isNotEmpty
                        ? widget.currentUserName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                    ),
                  )
                : null,
          ),
        ),
        // Waiting badge
        Positioned(
          bottom: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _K.amber,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _K.bg, width: 2),
              boxShadow: [
                BoxShadow(
                  color: _K.amber.withValues(alpha: 0.4),
                  blurRadius: 10,
                ),
              ],
            ),
            child: const Text(
              'Đang chờ',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatus() => Column(
    children: [
      Text(
        widget.currentUserName.isNotEmpty ? widget.currentUserName : 'Bạn',
        style: const TextStyle(
          color: _K.text,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        'Bạn đang ở phòng chờ của "${_model.groupName}"',
        style: const TextStyle(color: _K.sub, fontSize: 14, height: 1.5),
        textAlign: TextAlign.center,
      ),
    ],
  );

  Widget _buildEndedWarning() {
    if (!_model.isEnded) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: _K.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _K.red.withValues(alpha: 0.25)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info_outline_rounded, color: _K.red, size: 14),
          SizedBox(width: 6),
          Text(
            'Cuộc gọi đã kết thúc',
            style: TextStyle(
              color: _K.red,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaitingDots() => AnimatedBuilder(
    animation: _dotAnim,
    builder: (_, __) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Đang chờ được cho vào',
            style: TextStyle(
              color: _K.muted.withValues(alpha: 0.8),
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 5),
          ...List.generate(3, (i) {
            final phase = (_dotAnim.value * 3 - i) % 3.0;
            final opacity = phase < 1 ? phase : (phase < 2 ? 1.0 : 3 - phase);
            return Container(
              width: 5,
              height: 5,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _K.amber.withValues(alpha: opacity.clamp(0.2, 1.0)),
              ),
            );
          }),
        ],
      );
    },
  );

  Widget _buildCallInfo() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _K.amber.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _K.amber.withValues(alpha: 0.2)),
    ),
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _K.amber.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(
            _model.isVideo ? Icons.videocam_rounded : Icons.phone_rounded,
            color: _K.amber,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _model.groupName,
                style: const TextStyle(
                  color: _K.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '${_model.isVideo ? "Video" : "Thoại"} • '
                '${_model.participantCount} người trong phòng',
                style: const TextStyle(color: _K.sub, fontSize: 11),
              ),
            ],
          ),
        ),
        // Initiator info
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Được tổ chức bởi',
              style: TextStyle(color: _K.muted, fontSize: 9),
            ),
            Text(
              _model.initiatorName,
              style: const TextStyle(
                color: _K.amber,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _buildParticipantPreview() {
    if (_model.participants.isEmpty) return const SizedBox.shrink();
    final shown = _model.participants.take(4).toList();
    final extra = _model.participantCount > 4 ? _model.participantCount - 4 : 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${_model.participantCount} người đang trong phòng',
          style: const TextStyle(color: _K.muted, fontSize: 12),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ...shown.asMap().entries.map(
              (e) => Transform.translate(
                offset: Offset(-e.key * 8.0, 0),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: _K.bg, width: 2),
                  ),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundImage: e.value.userAvatar.isNotEmpty
                        ? NetworkImage(e.value.userAvatar)
                        : null,
                    backgroundColor: _K.s2,
                    child: e.value.userAvatar.isEmpty
                        ? Text(
                            e.value.userName.isNotEmpty
                                ? e.value.userName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        : null,
                  ),
                ),
              ),
            ),
            if (extra > 0)
              Transform.translate(
                offset: Offset(-shown.length * 8.0, 0),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: _K.bg, width: 2),
                  ),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: _K.accent.withValues(alpha: 0.2),
                    child: Text(
                      '+$extra',
                      style: const TextStyle(
                        color: _K.accent,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildLeaveButton() => GestureDetector(
    onTap: _leaving ? null : _leaveWaitingRoom,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        color: _K.red.withValues(alpha: _leaving ? 0.05 : 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _K.red.withValues(alpha: 0.3)),
      ),
      child: _leaving
          ? const SizedBox(
              height: 17,
              width: 17,
              child: CircularProgressIndicator(color: _K.red, strokeWidth: 2),
            )
          : const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.exit_to_app_rounded, color: _K.red, size: 17),
                SizedBox(width: 8),
                Text(
                  'Rời phòng chờ',
                  style: TextStyle(
                    color: _K.red,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
    ),
  );
}

// ── Background orbs ───────────────────────────────────────────────────────────
class _BackgroundOrbs extends StatefulWidget {
  final Color color;
  const _BackgroundOrbs({required this.color});
  @override
  State<_BackgroundOrbs> createState() => _BackgroundOrbsState();
}

class _BackgroundOrbsState extends State<_BackgroundOrbs>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 8))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, __) => CustomPaint(
      painter: _OrbsPainter(progress: _c.value, color: widget.color),
      child: const SizedBox.expand(),
    ),
  );
}

class _OrbsPainter extends CustomPainter {
  final double progress;
  final Color color;
  _OrbsPainter({required this.progress, required this.color});
  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, s.width, s.height),
      Paint()..color = _K.bg,
    );
    final positions = [(0.15, 0.2), (0.85, 0.75), (0.5, 0.1), (0.2, 0.8)];
    for (int i = 0; i < positions.length; i++) {
      final (px, py) = positions[i];
      final dx = math.sin(progress * 2 * math.pi + i) * s.width * 0.06;
      final dy = math.cos(progress * 2 * math.pi * 0.7 + i) * s.height * 0.05;
      canvas.drawCircle(
        Offset(px * s.width + dx, py * s.height + dy),
        80 + i * 30.0,
        Paint()
          ..color = color.withValues(alpha: 0.05)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60),
      );
    }
  }

  @override
  bool shouldRepaint(_OrbsPainter o) => o.progress != progress;
}

// ══════════════════════════════════════════════════════════════════════════════
// WaitingRoomAdminPanel
// Shown inside the participants panel for admins to manage waiting users.
// ══════════════════════════════════════════════════════════════════════════════
class WaitingRoomAdminPanel extends StatelessWidget {
  final String callId;
  final VoidCallback? onAdmitAll;

  const WaitingRoomAdminPanel({
    super.key,
    required this.callId,
    this.onAdmitAll,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<GroupCallModel?>(
      stream: GroupCallService.instance.watchCall(callId),
      builder: (context, snap) {
        final call = snap.data;
        if (call == null) return const SizedBox.shrink();
        final waiting = call.waitingRoomUserIds;
        if (waiting.isEmpty) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _K.amber.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _K.amber.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: _K.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.hourglass_top_rounded,
                        color: _K.amber,
                        size: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Phòng chờ (${waiting.length})',
                            style: const TextStyle(
                              color: _K.amber,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Text(
                            'Đang chờ được cho vào',
                            style: TextStyle(color: _K.muted, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                    if (waiting.length > 1)
                      GestureDetector(
                        onTap: onAdmitAll,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: _K.green,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Cho vào tất',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              Divider(color: _K.amber.withValues(alpha: 0.12), height: 1),

              // Users list
              ...waiting.map(
                (uid) => _WaitingUserRow(userId: uid, callId: call.callId),
              ),

              const SizedBox(height: 6),
            ],
          ),
        );
      },
    );
  }
}

class _WaitingUserRow extends StatelessWidget {
  final String userId;
  final String callId;

  const _WaitingUserRow({required this.userId, required this.callId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(userId).get(),
      builder: (context, snap) {
        String name = userId;
        String avatar = '';
        if (snap.hasData && snap.data!.exists) {
          final data = snap.data!.data() as Map<String, dynamic>;
          name = data['nickname'] as String? ?? userId;
          avatar = data['photoUrl'] as String? ?? '';
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: _K.s2,
                backgroundImage: avatar.isNotEmpty
                    ? NetworkImage(avatar)
                    : null,
                child: avatar.isEmpty
                    ? Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(color: _K.sub, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // Admit
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  GroupCallService.instance.admitFromWaitingRoom(
                    callId: callId,
                    targetUserId: userId,
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _K.green,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Cho vào',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),

              // Deny
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  GroupCallService.instance.kickParticipant(
                    callId: callId,
                    targetUserId: userId,
                  );
                },
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: _K.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _K.red.withValues(alpha: 0.25)),
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    color: _K.red,
                    size: 14,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
