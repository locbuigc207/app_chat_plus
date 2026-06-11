import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../constants/constants.dart';
import '../models/group_call_model.dart';
import '../models/models.dart';
import '../pages/group_call_page.dart';
import '../providers/providers.dart';
import '../services/group_call_service.dart';

// ─── Color palette (mirrors GroupCallPage) ────────────────────────────────────
class _C {
  static const bg = Color(0xFF0A0E1A);
  static const surface = Color(0xFF111827);
  static const surface2 = Color(0xFF1C2333);
  static const accent = Color(0xFF3B82F6);
  static const green = Color(0xFF22C55E);
  static const red = Color(0xFFEF4444);
  static const amber = Color(0xFFF59E0B);
  static const text = Color(0xFFF8FAFC);
  static const textSub = Color(0xFF94A3B8);
  static const textMuted = Color(0xFF475569);
}

// ══════════════════════════════════════════════════════════════════════════════
// GroupVideoCallButton — popup menu (video + voice)
// ══════════════════════════════════════════════════════════════════════════════
class GroupVideoCallButton extends StatefulWidget {
  final String groupId;
  final String groupName;
  final List<String> memberIds;
  final String groupAvatarUrl;

  const GroupVideoCallButton({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.memberIds,
    this.groupAvatarUrl = '',
  });

  @override
  State<GroupVideoCallButton> createState() => _GroupVideoCallButtonState();
}

class _GroupVideoCallButtonState extends State<GroupVideoCallButton>
    with SingleTickerProviderStateMixin {
  bool _loading = false;
  late AnimationController _bounceCtrl;
  late Animation<double> _bounceAnim;

  @override
  void initState() {
    super.initState();
    _bounceCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
    _bounceAnim = Tween<double>(begin: 1.0, end: 0.84)
        .animate(CurvedAnimation(parent: _bounceCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _bounceCtrl.dispose();
    super.dispose();
  }

  Future<void> _startCall(BuildContext context, GroupCallType type) async {
    if (_loading) return;
    setState(() => _loading = true);

    final auth = context.read<AuthProvider>();
    final uid = auth.userFirebaseId;
    final userName = auth.currentUserName ?? '';
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }

    final service = GroupCallService.instance;

    // Check for existing call
    GroupCallModel? existing;
    try {
      existing = await service
          .activeCallForGroup(widget.groupId)
          .first
          .timeout(const Duration(seconds: 3));
    } catch (_) {}

    if (existing != null && mounted) {
      setState(() => _loading = false);
      final join = await _showJoinDialog(context, existing);
      if (join != true || !mounted) return;
      final ok = await service.joinCall(existing.callId);
      if (!ok || !mounted) return;
      _push(context, existing, uid, userName, isInitiator: false);
      return;
    }

    final call = await service.initiateCall(
      groupId: widget.groupId,
      groupName: widget.groupName,
      groupAvatarUrl: widget.groupAvatarUrl,
      memberIds: widget.memberIds,
      callType: type,
    );
    if (mounted) setState(() => _loading = false);

    if (call == null || !mounted) {
      _showError(context, 'Không thể bắt đầu cuộc gọi nhóm');
      return;
    }
    _push(context, call, uid, userName, isInitiator: true);
  }

  Future<bool?> _showJoinDialog(BuildContext ctx, GroupCallModel call) =>
      showDialog<bool>(
          context: ctx, builder: (_) => _JoinCallDialog(call: call));

  void _push(BuildContext ctx, GroupCallModel call, String uid, String name,
      {required bool isInitiator}) {
    Navigator.of(ctx).push(MaterialPageRoute(
      builder: (_) => GroupCallPage(
        call: call,
        isInitiator: isInitiator,
        currentUserId: uid,
        currentUserName: name,
      ),
    ));
  }

  void _showError(BuildContext ctx, String msg) {
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: _C.red,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _bounceAnim,
      builder: (_, child) =>
          Transform.scale(scale: _bounceAnim.value, child: child),
      child: PopupMenuButton<String>(
        icon: _loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: ColorConstants.primaryColor))
            : const Icon(Icons.videocam_rounded,
                color: ColorConstants.primaryColor),
        tooltip: 'Gọi nhóm',
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        offset: const Offset(0, 52),
        elevation: 12,
        color: _C.surface,
        onSelected: (val) {
          _bounceCtrl.forward().then((_) => _bounceCtrl.reverse());
          HapticFeedback.lightImpact();
          if (val == 'video') _startCall(context, GroupCallType.video);
          if (val == 'voice') _startCall(context, GroupCallType.voice);
        },
        itemBuilder: (_) => [
          _menuItem(
            value: 'video',
            icon: Icons.videocam_rounded,
            label: 'Gọi video nhóm',
            subtitle: 'Gọi tất cả thành viên',
            iconColor: _C.accent,
          ),
          const PopupMenuDivider(height: 1),
          _menuItem(
            value: 'voice',
            icon: Icons.phone_rounded,
            label: 'Gọi thoại nhóm',
            subtitle: 'Chỉ âm thanh',
            iconColor: _C.green,
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _menuItem({
    required String value,
    required IconData icon,
    required String label,
    required String subtitle,
    required Color iconColor,
  }) {
    return PopupMenuItem<String>(
      value: value,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: const TextStyle(
                      color: _C.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              Text(subtitle,
                  style: const TextStyle(color: _C.textSub, fontSize: 11)),
            ],
          ),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// GroupCallIconButton — single-type icon button (video OR voice)
// ══════════════════════════════════════════════════════════════════════════════
class GroupCallIconButton extends StatefulWidget {
  final String groupId;
  final String groupName;
  final List<String> memberIds;
  final GroupCallType callType;
  final String groupAvatarUrl;
  final Color? iconColor;

  const GroupCallIconButton({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.memberIds,
    required this.callType,
    this.groupAvatarUrl = '',
    this.iconColor,
  });

  @override
  State<GroupCallIconButton> createState() => _GroupCallIconButtonState();
}

class _GroupCallIconButtonState extends State<GroupCallIconButton>
    with SingleTickerProviderStateMixin {
  bool _loading = false;
  late AnimationController _bounceCtrl;
  late Animation<double> _bounceAnim;

  @override
  void initState() {
    super.initState();
    _bounceCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 100));
    _bounceAnim = Tween<double>(begin: 1.0, end: 0.82)
        .animate(CurvedAnimation(parent: _bounceCtrl, curve: Curves.easeIn));
  }

  @override
  void dispose() {
    _bounceCtrl.dispose();
    super.dispose();
  }

  Future<void> _tap() async {
    if (_loading) return;
    await _bounceCtrl.forward();
    await _bounceCtrl.reverse();
    HapticFeedback.lightImpact();

    final auth = context.read<AuthProvider>();
    final uid = auth.userFirebaseId;
    final name = auth.currentUserName ?? '';
    if (uid == null) return;

    final service = GroupCallService.instance;
    setState(() => _loading = true);

    try {
      GroupCallModel? existing;
      try {
        existing = await service
            .activeCallForGroup(widget.groupId)
            .first
            .timeout(const Duration(seconds: 2));
      } catch (_) {}

      if (existing != null && mounted) {
        setState(() => _loading = false);
        final join = await showDialog<bool>(
            context: context, builder: (_) => _JoinCallDialog(call: existing!));
        if (join != true || !mounted) return;
        final ok = await service.joinCall(existing.callId);
        if (!ok || !mounted) return;
        _navigateTo(existing, uid, name, isInitiator: false);
        return;
      }

      final call = await service.initiateCall(
        groupId: widget.groupId,
        groupName: widget.groupName,
        groupAvatarUrl: widget.groupAvatarUrl,
        memberIds: widget.memberIds,
        callType: widget.callType,
      );
      if (!mounted) return;
      if (call == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Không thể bắt đầu cuộc gọi'),
          backgroundColor: _C.red,
        ));
        return;
      }
      _navigateTo(call, uid, name, isInitiator: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _navigateTo(GroupCallModel call, String uid, String name,
      {required bool isInitiator}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GroupCallPage(
        call: call,
        isInitiator: isInitiator,
        currentUserId: uid,
        currentUserName: name,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.iconColor ?? ColorConstants.primaryColor;
    return AnimatedBuilder(
      animation: _bounceAnim,
      builder: (_, child) =>
          Transform.scale(scale: _bounceAnim.value, child: child),
      child: IconButton(
        icon: _loading
            ? SizedBox(
                width: 20,
                height: 20,
                child:
                    CircularProgressIndicator(strokeWidth: 2.5, color: color))
            : Icon(
                widget.callType == GroupCallType.video
                    ? Icons.videocam_rounded
                    : Icons.phone_rounded,
                color: color,
              ),
        tooltip: widget.callType == GroupCallType.video
            ? 'Gọi video nhóm'
            : 'Gọi thoại nhóm',
        onPressed: _loading ? null : _tap,
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ActiveGroupCallBanner — sticky banner when there's an active call
// ══════════════════════════════════════════════════════════════════════════════
class ActiveGroupCallBanner extends StatelessWidget {
  final String groupId;
  final String currentUserId;
  final String currentUserName;
  final String currentUserAvatar;
  final List<String> memberIds;

  const ActiveGroupCallBanner({
    super.key,
    required this.groupId,
    required this.currentUserId,
    required this.currentUserName,
    this.currentUserAvatar = '',
    this.memberIds = const [],
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<GroupCallModel?>(
      stream: GroupCallService.instance.activeCallForGroup(groupId),
      builder: (ctx, snap) {
        final call = snap.data;
        if (call == null) return const SizedBox.shrink();
        final alreadyIn =
            call.participants.any((p) => p.userId == currentUserId);
        return _ActiveBannerContent(
          call: call,
          alreadyIn: alreadyIn,
          currentUserId: currentUserId,
          currentUserName: currentUserName,
          currentUserAvatar: currentUserAvatar,
        );
      },
    );
  }
}

class _ActiveBannerContent extends StatefulWidget {
  final GroupCallModel call;
  final bool alreadyIn;
  final String currentUserId;
  final String currentUserName;
  final String currentUserAvatar;

  const _ActiveBannerContent({
    required this.call,
    required this.alreadyIn,
    required this.currentUserId,
    required this.currentUserName,
    required this.currentUserAvatar,
  });

  @override
  State<_ActiveBannerContent> createState() => _ActiveBannerContentState();
}

class _ActiveBannerContentState extends State<_ActiveBannerContent>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;
  bool _joining = false;
  int _elapsed = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.96, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _elapsed = DateTime.now().difference(widget.call.createdAt).inSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed++);
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _timer?.cancel();
    super.dispose();
  }

  String get _durationText {
    final m = (_elapsed ~/ 60).toString().padLeft(2, '0');
    final s = (_elapsed % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _join() async {
    if (_joining || widget.alreadyIn) return;
    setState(() => _joining = true);
    HapticFeedback.mediumImpact();
    try {
      final ok = await GroupCallService.instance.joinCall(widget.call.callId);
      if (!ok || !mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => GroupCallPage(
          call: widget.call,
          isInitiator: false,
          currentUserId: widget.currentUserId,
          currentUserName: widget.currentUserName,
          currentUserAvatar: widget.currentUserAvatar,
        ),
      ));
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, child) => Transform.scale(scale: _pulse.value, child: child),
      child: GestureDetector(
        onTap: widget.alreadyIn ? null : _join,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: widget.call.isVideo
                  ? [const Color(0xFF1D4ED8), const Color(0xFF3B82F6)]
                  : [const Color(0xFF15803D), const Color(0xFF22C55E)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: (widget.call.isVideo ? _C.accent : _C.green)
                    .withOpacity(0.35),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    // Live dot
                    _LiveDot(color: Colors.white),
                    const SizedBox(width: 10),

                    // Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(children: [
                            Icon(
                              widget.call.isVideo
                                  ? Icons.videocam_rounded
                                  : Icons.phone_rounded,
                              color: Colors.white,
                              size: 13,
                            ),
                            const SizedBox(width: 5),
                            const Text(
                              'Đang có cuộc gọi nhóm',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ]),
                          const SizedBox(height: 2),
                          Row(children: [
                            Text(
                              '${widget.call.participantCount} người • $_durationText',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 11),
                            ),
                          ]),
                        ],
                      ),
                    ),

                    // Join / In call chip
                    if (widget.alreadyIn)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.check_rounded,
                                color: Colors.white, size: 12),
                            SizedBox(width: 4),
                            Text('Đang trong cuộc gọi',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      )
                    else
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: _joining
                            ? const SizedBox(
                                key: ValueKey('loading'),
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2),
                              )
                            : Container(
                                key: const ValueKey('join'),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 7),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.22),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: Colors.white.withOpacity(0.4),
                                      width: 1),
                                ),
                                child: const Text(
                                  'Tham gia',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
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
}

// ── Live dot ──────────────────────────────────────────────────────────────────
class _LiveDot extends StatefulWidget {
  final Color color;
  const _LiveDot({required this.color});

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.5, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color.withOpacity(_anim.value * 0.3),
            ),
          ),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color,
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _JoinCallDialog
// ══════════════════════════════════════════════════════════════════════════════
class _JoinCallDialog extends StatelessWidget {
  final GroupCallModel call;

  const _JoinCallDialog({required this.call});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: _C.surface.withOpacity(0.96),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: _C.green.withOpacity(0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: _C.green.withOpacity(0.3)),
                  ),
                  child: Icon(
                    call.isVideo ? Icons.videocam_rounded : Icons.phone_rounded,
                    color: _C.green,
                    size: 26,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Cuộc gọi đang diễn ra',
                  style: TextStyle(
                    color: _C.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${call.participantCount} người đang trong cuộc gọi\n"${call.groupName}"',
                  style: const TextStyle(
                      color: _C.textSub, fontSize: 13, height: 1.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Row(children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: TextButton.styleFrom(
                        foregroundColor: _C.textMuted,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side:
                              BorderSide(color: Colors.white.withOpacity(0.08)),
                        ),
                      ),
                      child: const Text('Huỷ',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _C.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Tham gia ngay',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
