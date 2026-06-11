// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/group_call_model.dart';
import '../pages/pages.dart';
import '../services/group_call_service.dart';

class _K {
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
// GroupCallTile
// List tile for group calls — adapts for active vs. ended state.
// ══════════════════════════════════════════════════════════════════════════════
class GroupCallTile extends StatefulWidget {
  final GroupCallModel call;
  final String currentUserId;
  final String currentUserName;
  final String currentUserAvatar;
  final bool showDate;
  final VoidCallback? onTap;

  const GroupCallTile({
    super.key,
    required this.call,
    required this.currentUserId,
    required this.currentUserName,
    required this.currentUserAvatar,
    this.showDate = false,
    this.onTap,
  });

  @override
  State<GroupCallTile> createState() => _GroupCallTileState();
}

class _GroupCallTileState extends State<GroupCallTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _hoverCtrl;
  late Animation<double> _hoverAnim;
  bool _joining = false;

  bool get _isActive => widget.call.isOngoing || widget.call.isCalling;
  bool get _alreadyIn =>
      widget.call.participants.any((p) => p.userId == widget.currentUserId);

  Color get _accentColor => widget.call.isVideo ? _K.accent : _K.green;

  @override
  void initState() {
    super.initState();
    _hoverCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 160));
    _hoverAnim = Tween<double>(begin: 1.0, end: 0.97)
        .animate(CurvedAnimation(parent: _hoverCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _hoverCtrl.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    if (_joining || _alreadyIn) return;
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

  String _formatDuration(int s) {
    if (s <= 0) return '';
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return s >= 3600 ? '${s ~/ 3600}:$m:$sec' : '$m:$sec';
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _statusLabel() {
    if (_isActive) return 'Đang diễn ra';
    if (widget.call.status == GroupCallStatus.missed) return 'Nhỡ';
    final dur = widget.call.durationSeconds;
    if (dur != null && dur > 0) return _formatDuration(dur);
    return 'Đã kết thúc';
  }

  Color _statusColor() {
    if (widget.call.status == GroupCallStatus.missed) return _K.red;
    if (_isActive) return _K.green;
    return _K.muted;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _hoverCtrl.forward(),
      onTapUp: (_) {
        _hoverCtrl.reverse();
        widget.onTap?.call();
      },
      onTapCancel: () => _hoverCtrl.reverse(),
      child: ScaleTransition(
        scale: _hoverAnim,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
          decoration: BoxDecoration(
            color: _K.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _isActive
                  ? _accentColor.withOpacity(0.2)
                  : Colors.white.withOpacity(0.05),
            ),
            boxShadow: _isActive
                ? [
                    BoxShadow(
                        color: _accentColor.withOpacity(0.1), blurRadius: 12),
                  ]
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              _buildAvatar(),
              const SizedBox(width: 12),
              Expanded(child: _buildInfo()),
              const SizedBox(width: 8),
              _buildTrailing(),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    final color = widget.call.isVideo ? _K.accent : _K.green;
    return Stack(clipBehavior: Clip.none, children: [
      // Group avatar or icon
      widget.call.groupAvatarUrl.isNotEmpty
          ? CircleAvatar(
              radius: 24,
              backgroundImage: NetworkImage(widget.call.groupAvatarUrl))
          : Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(color: color.withOpacity(0.2)),
              ),
              child: Icon(
                  widget.call.isVideo
                      ? Icons.videocam_rounded
                      : Icons.phone_rounded,
                  color: color,
                  size: 22)),
      // Active indicator
      if (_isActive)
        Positioned(right: -2, bottom: -2, child: _ActiveDot(color: _K.green)),
      // Recording badge
      if (widget.call.isRecording)
        Positioned(
            right: -4,
            top: -4,
            child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                    color: _K.red,
                    shape: BoxShape.circle,
                    border: Border.all(color: _K.surface, width: 1.5),
                    boxShadow: [
                      BoxShadow(color: _K.red.withOpacity(0.4), blurRadius: 6)
                    ]),
                child: const Icon(Icons.fiber_manual_record_rounded,
                    color: Colors.white, size: 7))),
    ]);
  }

  Widget _buildInfo() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Group name
          Text(widget.call.groupName,
              style: const TextStyle(
                  color: _K.text, fontSize: 14, fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 3),
          // Status row
          Row(children: [
            Icon(_isActive ? Icons.circle : Icons.access_time_rounded,
                size: 9, color: _statusColor()),
            const SizedBox(width: 4),
            Text(_statusLabel(),
                style: TextStyle(
                    color: _statusColor(),
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            Icon(Icons.people_outline_rounded, size: 11, color: _K.muted),
            const SizedBox(width: 3),
            Text('${widget.call.participantCount}',
                style: const TextStyle(color: _K.muted, fontSize: 11)),
          ]),
          // Participant mini avatars
          if (widget.call.participants.isNotEmpty) ...[
            const SizedBox(height: 6),
            _MiniAvatarRow(
                participants: widget.call.participants.take(4).toList()),
          ],
        ],
      );

  Widget _buildTrailing() {
    if (_isActive && !_alreadyIn) {
      return _JoinButton(
        callType: widget.call.callType,
        loading: _joining,
        onTap: _join,
      );
    }
    if (_alreadyIn) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: _K.green.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _K.green.withOpacity(0.2)),
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_rounded, color: _K.green, size: 11),
          SizedBox(width: 4),
          Text('Đang trong\ncuộc gọi',
              style: TextStyle(
                  color: _K.green,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  height: 1.3)),
        ]),
      );
    }
    if (widget.showDate) {
      return Text(_formatTime(widget.call.createdAt),
          style: const TextStyle(color: _K.muted, fontSize: 11));
    }
    return const SizedBox.shrink();
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────
class _ActiveDot extends StatefulWidget {
  final Color color;
  const _ActiveDot({required this.color});
  @override
  State<_ActiveDot> createState() => _ActiveDotState();
}

class _ActiveDotState extends State<_ActiveDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color,
                border: Border.all(color: _K.surface, width: 1.5),
                boxShadow: [
                  BoxShadow(
                      color: widget.color.withOpacity(0.4 + _c.value * 0.3),
                      blurRadius: 6)
                ]),
          ));
}

class _MiniAvatarRow extends StatelessWidget {
  final List<GroupCallParticipant> participants;
  const _MiniAvatarRow({required this.participants});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 20,
      child: Stack(
          children: participants.asMap().entries.map((e) {
        final p = e.value;
        return Positioned(
          left: e.key * 14.0,
          child: Container(
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _K.surface, width: 1.2)),
              child: CircleAvatar(
                  radius: 9,
                  backgroundImage: p.userAvatar.isNotEmpty
                      ? NetworkImage(p.userAvatar)
                      : null,
                  backgroundColor: _K.s2,
                  child: p.userAvatar.isEmpty
                      ? Text(
                          p.userName.isNotEmpty
                              ? p.userName[0].toUpperCase()
                              : '?',
                          style:
                              const TextStyle(color: Colors.white, fontSize: 7))
                      : null)),
        );
      }).toList()),
    );
  }
}

class _JoinButton extends StatelessWidget {
  final GroupCallType callType;
  final bool loading;
  final VoidCallback onTap;
  const _JoinButton(
      {required this.callType, required this.loading, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final color = callType == GroupCallType.video ? _K.accent : _K.green;
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: loading ? color.withOpacity(0.5) : color,
          borderRadius: BorderRadius.circular(12),
          boxShadow: loading
              ? null
              : [
                  BoxShadow(
                      color: color.withOpacity(0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3))
                ],
        ),
        child: loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
            : Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(
                    callType == GroupCallType.video
                        ? Icons.videocam_rounded
                        : Icons.phone_rounded,
                    color: Colors.white,
                    size: 13),
                const SizedBox(width: 5),
                const Text('Vào',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// GroupCallTileShimmer  — loading placeholder
// ══════════════════════════════════════════════════════════════════════════════
class GroupCallTileShimmer extends StatefulWidget {
  const GroupCallTileShimmer({super.key});
  @override
  State<GroupCallTileShimmer> createState() => _GroupCallTileShimmerState();
}

class _GroupCallTileShimmerState extends State<GroupCallTileShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final op = 0.04 + _c.value * 0.06;
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: _K.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withOpacity(0.05))),
          child: Row(children: [
            Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(op))),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Container(
                      height: 13,
                      width: 140,
                      decoration: BoxDecoration(
                          color: Colors.white.withOpacity(op),
                          borderRadius: BorderRadius.circular(6))),
                  const SizedBox(height: 7),
                  Container(
                      height: 10,
                      width: 90,
                      decoration: BoxDecoration(
                          color: Colors.white.withOpacity(op * 0.7),
                          borderRadius: BorderRadius.circular(5))),
                ])),
          ]),
        );
      });
}
