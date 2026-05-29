import 'dart:async';

import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import '../constants/constants.dart';
import '../models/models.dart';
import '../pages/pages.dart';
import '../providers/providers.dart';
import '../services/services.dart';





class GroupVideoCallButton extends StatelessWidget {
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

  Future<void> _startCall(BuildContext context, GroupCallType type) async {
    final auth = context.read<AuthProvider>();
    final uid = auth.userFirebaseId;
    final userName = auth.currentUserName ?? '';
    if (uid == null) return;

    final service = GroupCallService.instance;
    final existing = await _getActiveCall(service);

    if (existing != null && context.mounted) {
      final join = await _showJoinExistingDialog(context, existing);
      if (join != true || !context.mounted) return;
      final ok = await service.joinCall(existing.callId);
      if (!ok || !context.mounted) return;
      _navigateToCall(context, existing, uid, userName, isInitiator: false);
      return;
    }

    final call = await service.initiateCall(
      groupId: groupId,
      groupName: groupName,
      groupAvatarUrl: groupAvatarUrl,
      memberIds: memberIds,
      callType: type,
    );

    if (call == null || !context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không thể bắt đầu cuộc gọi nhóm'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      return;
    }

    if (context.mounted) {
      _navigateToCall(context, call, uid, userName, isInitiator: true);
    }
  }

  Future<GroupCallModel?> _getActiveCall(GroupCallService service) async {
    try {
      return await service.activeCallForGroup(groupId).first.timeout(const Duration(seconds: 3));
    } catch (_) {
      return null;
    }
  }

  Future<bool?> _showJoinExistingDialog(BuildContext context, GroupCallModel call) {
    return showDialog<bool>(
      context: context,
      builder: (_) => _JoinCallDialog(call: call),
    );
  }

  void _navigateToCall(
    BuildContext context,
    GroupCallModel call,
    String uid,
    String userName, {
    required bool isInitiator,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroupCallPage(
          call: call,
          isInitiator: isInitiator,
          currentUserId: uid,
          currentUserName: userName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.videocam_rounded, color: ColorConstants.primaryColor),
      tooltip: 'Gọi nhóm',
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      offset: const Offset(0, 48),
      elevation: 8,
      color: const Color(0xFF1e293b),
      onSelected: (val) {
        if (val == 'video') _startCall(context, GroupCallType.video);
        if (val == 'voice') _startCall(context, GroupCallType.voice);
      },
      itemBuilder: (_) => [
        _menuItem(
          value: 'video',
          icon: Icons.videocam_rounded,
          label: 'Gọi video nhóm',
          iconColor: const Color(0xFF60A5FA),
        ),
        _menuItem(
          value: 'voice',
          icon: Icons.phone_rounded,
          label: 'Gọi thoại nhóm',
          iconColor: const Color(0xFF4ADE80),
        ),
      ],
    );
  }

  PopupMenuItem<String> _menuItem({
    required String value,
    required IconData icon,
    required String label,
    required Color iconColor,
  }) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}





class GroupCallIconButton extends StatefulWidget {
  final String groupId;
  final String groupName;
  final List<String> memberIds;
  final GroupCallType callType;
  final String groupAvatarUrl;

  const GroupCallIconButton({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.memberIds,
    required this.callType,
    this.groupAvatarUrl = '',
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
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _bounceAnim = Tween<double>(begin: 1.0, end: 0.85).animate(
      CurvedAnimation(parent: _bounceCtrl, curve: Curves.easeIn),
    );
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

    final auth = context.read<AuthProvider>();
    final uid = auth.userFirebaseId;
    final userName = auth.currentUserName ?? '';
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
          context: context,
          builder: (_) => _JoinCallDialog(call: existing!),
        );
        if (join != true || !mounted) return;
        final ok = await service.joinCall(existing.callId);
        if (!ok || !mounted) return;
        _navigateTo(existing, uid, userName, isInitiator: false);
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không thể bắt đầu cuộc gọi'),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
        return;
      }
      _navigateTo(call, uid, userName, isInitiator: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _navigateTo(
    GroupCallModel call,
    String uid,
    String userName, {
    required bool isInitiator,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroupCallPage(
          call: call,
          isInitiator: isInitiator,
          currentUserId: uid,
          currentUserName: userName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _bounceAnim,
      builder: (_, child) => Transform.scale(scale: _bounceAnim.value, child: child),
      child: IconButton(
        icon: _loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: ColorConstants.primaryColor,
                ),
              )
            : Icon(
                widget.callType == GroupCallType.video
                    ? Icons.videocam_rounded
                    : Icons.phone_rounded,
                color: ColorConstants.primaryColor,
              ),
        tooltip: widget.callType == GroupCallType.video ? 'Gọi video nhóm' : 'Gọi thoại nhóm',
        onPressed: _loading ? null : _tap,
      ),
    );
  }
}





class ActiveGroupCallBanner extends StatelessWidget {
  final String groupId;
  final String currentUserId;
  final List<String> memberIds;
  final String groupName;
  final String currentUserName;

  const ActiveGroupCallBanner({
    super.key,
    required this.groupId,
    required this.currentUserId,
    required this.memberIds,
    required this.groupName,
    this.currentUserName = '',
  });

  @override
  Widget build(BuildContext context) {
    final service = GroupCallService.instance;
    return StreamBuilder<GroupCallModel?>(
      stream: service.activeCallForGroup(groupId),
      builder: (context, snap) {
        final call = snap.data;
        if (call == null) return const SizedBox.shrink();

        final alreadyIn = call.participants.any((p) => p.userId == currentUserId);

        return _BannerContent(
          call: call,
          alreadyIn: alreadyIn,
          currentUserId: currentUserId,
          currentUserName: currentUserName,
          service: service,
        );
      },
    );
  }
}

class _BannerContent extends StatefulWidget {
  final GroupCallModel call;
  final bool alreadyIn;
  final String currentUserId;
  final String currentUserName;
  final GroupCallService service;

  const _BannerContent({
    required this.call,
    required this.alreadyIn,
    required this.currentUserId,
    required this.currentUserName,
    required this.service,
  });

  @override
  State<_BannerContent> createState() => _BannerContentState();
}

class _BannerContentState extends State<_BannerContent> with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;
  bool _joining = false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.97, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    if (_joining || widget.alreadyIn) return;
    setState(() => _joining = true);
    try {
      final ok = await widget.service.joinCall(widget.call.callId);
      if (!ok || !mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => GroupCallPage(
            call: widget.call,
            isInitiator: false,
            currentUserId: widget.currentUserId,
            currentUserName: widget.currentUserName,
          ),
        ),
      );
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
        onTap: _join,
        child: Container(
          margin: const EdgeInsets.fromLTRB(10, 4, 10, 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF16A34A), Color(0xFF22C55E)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF22C55E).withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              
              _buildLiveDot(),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Đang có cuộc gọi nhóm',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      '${widget.call.participants.length} người đang trong cuộc gọi',
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
              if (!widget.alreadyIn)
                _buildJoinChip()
              else
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(Icons.check_circle_rounded, color: Colors.white70, size: 18),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLiveDot() {
    return Stack(
      alignment: Alignment.center,
      children: [
        AnimatedBuilder(
          animation: _pulse,
          builder: (_, __) => Container(
            width: 20 + (_pulse.value - 0.97) * 100,
            height: 20 + (_pulse.value - 0.97) * 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.2),
            ),
          ),
        ),
        Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildJoinChip() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: _joining
          ? const SizedBox(
              key: ValueKey('loading'),
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            )
          : Container(
              key: const ValueKey('join'),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 1),
              ),
              child: const Text(
                'Tham gia',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
    );
  }
}





class _JoinCallDialog extends StatelessWidget {
  final GroupCallModel call;

  const _JoinCallDialog({required this.call});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1e293b),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text(
        'Cuộc gọi đang diễn ra',
        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${call.participants.length} người đang trong cuộc gọi "${call.groupName}".',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 4),
          const Text(
            'Bạn có muốn tham gia không?',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          style: TextButton.styleFrom(
            foregroundColor: Colors.white38,
          ),
          child: const Text('Hủy'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF22C55E),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          ),
          child: const Text('Tham gia', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
