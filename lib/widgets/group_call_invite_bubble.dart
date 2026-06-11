// ignore_for_file: deprecated_member_use
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/group_call_model.dart';
import '../pages/pages.dart';
import '../services/group_call_service.dart';

// ─── Design tokens ────────────────────────────────────────────────────────────
class _K {
  static const bg = Color(0xFF080E1C);
  static const surface = Color(0xFF111827);
  static const s2 = Color(0xFF1C2333);
  static const accent = Color(0xFF3B82F6);
  static const green = Color(0xFF22C55E);
  static const red = Color(0xFFEF4444);
  static const amber = Color(0xFFF59E0B);
  static const purple = Color(0xFF8B5CF6);
  static const text = Color(0xFFF8FAFC);
  static const sub = Color(0xFF94A3B8);
  static const muted = Color(0xFF475569);
}

// ══════════════════════════════════════════════════════════════════════════════
// GroupCallInviteBubble
// Message bubble shown inside group chat when a call is started/ended.
// Shows live participant list and a "Join" button while the call is active.
// ══════════════════════════════════════════════════════════════════════════════
class GroupCallInviteBubble extends StatefulWidget {
  final String callId;
  final GroupCallType callType;
  final String initiatorName;
  final String groupName;
  final String groupAvatarUrl;
  final DateTime createdAt;
  final bool isSentByMe;
  final String currentUserId;
  final String currentUserName;
  final String currentUserAvatar;

  const GroupCallInviteBubble({
    super.key,
    required this.callId,
    required this.callType,
    required this.initiatorName,
    required this.groupName,
    required this.groupAvatarUrl,
    required this.createdAt,
    required this.isSentByMe,
    required this.currentUserId,
    required this.currentUserName,
    required this.currentUserAvatar,
  });

  @override
  State<GroupCallInviteBubble> createState() => _GroupCallInviteBubbleState();
}

class _GroupCallInviteBubbleState extends State<GroupCallInviteBubble>
    with SingleTickerProviderStateMixin {
  GroupCallModel? _call;
  bool _joining = false;
  bool _loading = true;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  bool get _isActive => _call != null && (_call!.isOngoing || _call!.isCalling);

  bool get _alreadyIn =>
      _call?.participants.any((p) => p.userId == widget.currentUserId) ?? false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.94, end: 1.06)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _loadCall();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCall() async {
    final call = await GroupCallService.instance.getCall(widget.callId);
    if (mounted)
      setState(() {
        _call = call;
        _loading = false;
      });
  }

  Future<void> _join() async {
    if (_joining || _alreadyIn || _call == null) return;
    setState(() => _joining = true);
    HapticFeedback.mediumImpact();

    final ok = await GroupCallService.instance.joinCall(widget.callId);
    if (!mounted) return;
    setState(() => _joining = false);

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Không thể tham gia cuộc gọi'),
        backgroundColor: _K.red,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GroupCallPage(
        call: _call!,
        isInitiator: false,
        currentUserId: widget.currentUserId,
        currentUserName: widget.currentUserName,
        currentUserAvatar: widget.currentUserAvatar,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.callType == GroupCallType.video;
    final color = isVideo ? _K.accent : _K.green;

    return Align(
      alignment:
          widget.isSentByMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.72,
        ),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: ClipRRect(
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(widget.isSentByMe ? 18 : 4),
            bottomRight: Radius.circular(widget.isSentByMe ? 4 : 18),
          ),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    color.withOpacity(0.12),
                    _K.surface,
                  ],
                ),
                border: Border.all(
                  color: color.withOpacity(0.22),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(isVideo, color),
                  if (_loading)
                    _buildLoading()
                  else if (_isActive)
                    _buildActiveBody(color)
                  else
                    _buildEndedBody(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _buildHeader(bool isVideo, Color color) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isVideo ? Icons.videocam_rounded : Icons.phone_rounded,
              color: color,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isVideo ? 'Cuộc gọi video nhóm' : 'Cuộc gọi thoại nhóm',
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${widget.initiatorName} đã bắt đầu',
                  style: const TextStyle(color: _K.sub, fontSize: 11),
                ),
              ],
            ),
          ),
          // Status dot
          if (_isActive) _buildLiveDot(color),
        ],
      ),
    );
  }

  Widget _buildLiveDot(Color color) {
    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (_, child) =>
          Transform.scale(scale: _pulseAnim.value, child: child),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  boxShadow: [
                    BoxShadow(color: color.withOpacity(0.5), blurRadius: 6)
                  ])),
          const SizedBox(width: 4),
          Text('LIVE',
              style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8)),
        ]),
      ),
    );
  }

  // ── Loading ────────────────────────────────────────────────────────────────
  Widget _buildLoading() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(14, 4, 14, 14),
      child: Center(
          child: SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(color: _K.accent, strokeWidth: 2),
      )),
    );
  }

  // ── Active call body ───────────────────────────────────────────────────────
  Widget _buildActiveBody(Color color) {
    final participants = _call?.participants ?? [];

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Participant mini-avatars
          if (participants.isNotEmpty) ...[
            _buildParticipantAvatars(participants),
            const SizedBox(height: 10),
          ],

          // Join button
          if (!_alreadyIn)
            _buildJoinButton(color)
          else
            _buildAlreadyInChip(color),

          const SizedBox(height: 6),
          _buildTimeInfo(),
        ],
      ),
    );
  }

  Widget _buildParticipantAvatars(List<GroupCallParticipant> list) {
    final shown = list.take(5).toList();
    final extra = list.length > 5 ? list.length - 5 : 0;

    return Row(children: [
      SizedBox(
        height: 26,
        width: shown.length * 18.0 + (extra > 0 ? 22.0 : 0),
        child: Stack(children: [
          ...shown.asMap().entries.map((e) {
            final p = e.value;
            return Positioned(
                left: e.key * 18.0,
                child: Container(
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: _K.surface, width: 1.5)),
                  child: CircleAvatar(
                      radius: 11,
                      backgroundImage: p.userAvatar.isNotEmpty
                          ? NetworkImage(p.userAvatar)
                          : null,
                      backgroundColor: _K.s2,
                      child: p.userAvatar.isEmpty
                          ? Text(
                              p.userName.isNotEmpty
                                  ? p.userName[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.w700))
                          : null),
                ));
          }),
          if (extra > 0)
            Positioned(
                left: shown.length * 18.0,
                child: Container(
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: _K.surface, width: 1.5)),
                    child: CircleAvatar(
                        radius: 11,
                        backgroundColor: _K.accent.withOpacity(0.25),
                        child: Text('+$extra',
                            style: const TextStyle(
                                color: _K.accent,
                                fontSize: 7,
                                fontWeight: FontWeight.w800))))),
        ]),
      ),
      const SizedBox(width: 8),
      Text('${list.length} người đang trong cuộc gọi',
          style: const TextStyle(color: _K.sub, fontSize: 11)),
    ]);
  }

  Widget _buildJoinButton(Color color) {
    return GestureDetector(
      onTap: _join,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: _joining ? color.withOpacity(0.5) : color,
          borderRadius: BorderRadius.circular(12),
          boxShadow: _joining
              ? null
              : [
                  BoxShadow(
                      color: color.withOpacity(0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4)),
                ],
        ),
        child: _joining
            ? const Center(
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2)))
            : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(
                    widget.callType == GroupCallType.video
                        ? Icons.videocam_rounded
                        : Icons.phone_rounded,
                    color: Colors.white,
                    size: 16),
                const SizedBox(width: 7),
                const Text('Tham gia ngay',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ]),
      ),
    );
  }

  Widget _buildAlreadyInChip(Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.check_circle_rounded, color: color, size: 15),
        const SizedBox(width: 7),
        Text('Bạn đang trong cuộc gọi',
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _buildTimeInfo() {
    final elapsed = DateTime.now().difference(widget.createdAt);
    final m = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    final timeStr = elapsed.inHours > 0 ? '${elapsed.inHours}:$m:$s' : '$m:$s';

    return Text('Đã bắt đầu $timeStr trước',
        style: const TextStyle(color: _K.muted, fontSize: 10));
  }

  // ── Ended call body ────────────────────────────────────────────────────────
  Widget _buildEndedBody() {
    final duration = _call?.durationSeconds;
    final count = _call?.participantCount ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Row(children: [
        const Icon(Icons.call_end_rounded, color: _K.muted, size: 14),
        const SizedBox(width: 6),
        Text(
          duration != null && duration > 0
              ? 'Đã kết thúc • ${_formatDur(duration)} • $count người'
              : 'Cuộc gọi đã kết thúc',
          style: const TextStyle(color: _K.muted, fontSize: 11),
        ),
      ]),
    );
  }

  String _formatDur(int s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return s >= 3600 ? '${s ~/ 3600}:$m:$sec' : '$m:$sec';
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// GroupCallStatusBanner
// Compact status strip shown at the top of a group chat page
// when a call is currently ongoing.
// ══════════════════════════════════════════════════════════════════════════════
class GroupCallStatusBanner extends StatefulWidget {
  final String groupId;
  final String currentUserId;
  final String currentUserName;
  final String currentUserAvatar;

  const GroupCallStatusBanner({
    super.key,
    required this.groupId,
    required this.currentUserId,
    required this.currentUserName,
    required this.currentUserAvatar,
  });

  @override
  State<GroupCallStatusBanner> createState() => _GroupCallStatusBannerState();
}

class _GroupCallStatusBannerState extends State<GroupCallStatusBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.7, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _joinCall(GroupCallModel call) async {
    HapticFeedback.mediumImpact();
    final ok = await GroupCallService.instance.joinCall(call.callId);
    if (!ok || !mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GroupCallPage(
        call: call,
        isInitiator: false,
        currentUserId: widget.currentUserId,
        currentUserName: widget.currentUserName,
        currentUserAvatar: widget.currentUserAvatar,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<GroupCallModel?>(
      stream: GroupCallService.instance.activeCallForGroup(widget.groupId),
      builder: (ctx, snap) {
        final call = snap.data;
        if (call == null) return const SizedBox.shrink();

        final isVideo = call.callType == GroupCallType.video;
        final color = isVideo ? _K.accent : _K.green;
        final alreadyIn =
            call.participants.any((p) => p.userId == widget.currentUserId);

        return AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isVideo
                    ? [const Color(0xFF1D4ED8), const Color(0xFF3B82F6)]
                    : [const Color(0xFF15803D), const Color(0xFF22C55E)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                    color: color.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4))
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: alreadyIn ? null : () => _joinCall(call),
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  child: Row(children: [
                    // Live dot
                    AnimatedBuilder(
                      animation: _anim,
                      builder: (_, __) => Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(_anim.value),
                          boxShadow: [
                            BoxShadow(
                                color:
                                    Colors.white.withOpacity(_anim.value * 0.4),
                                blurRadius: 6)
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),

                    // Info
                    Expanded(
                        child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(children: [
                          Icon(
                              isVideo
                                  ? Icons.videocam_rounded
                                  : Icons.phone_rounded,
                              color: Colors.white,
                              size: 13),
                          const SizedBox(width: 5),
                          const Text('Đang có cuộc gọi nhóm',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12)),
                        ]),
                        Text(
                            '${call.participantCount} người • Nhấn để tham gia',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 10)),
                      ],
                    )),

                    // Action
                    if (alreadyIn)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_rounded,
                                  color: Colors.white, size: 11),
                              SizedBox(width: 4),
                              Text('Đang trong cuộc gọi',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700)),
                            ]),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.22),
                          borderRadius: BorderRadius.circular(20),
                          border:
                              Border.all(color: Colors.white.withOpacity(0.4)),
                        ),
                        child: const Text('Tham gia',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 11)),
                      ),
                  ]),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
