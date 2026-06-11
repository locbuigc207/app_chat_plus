import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/group_call_model.dart';
import '../services/group_call_service.dart';

// ══════════════════════════════════════════════════════════════════════════════
// RaiseHandQueue
// Admin sees who has their hand raised — tap to allow them to speak
// ══════════════════════════════════════════════════════════════════════════════
class RaiseHandQueuePanel extends StatefulWidget {
  final GroupCallModel call;
  final String currentUserId;
  final bool isAdmin;

  const RaiseHandQueuePanel({
    super.key,
    required this.call,
    required this.currentUserId,
    required this.isAdmin,
  });

  @override
  State<RaiseHandQueuePanel> createState() => _RaiseHandQueuePanelState();
}

class _RaiseHandQueuePanelState extends State<RaiseHandQueuePanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  static const _amber = Color(0xFFF59E0B);
  static const _surface = Color(0xFF111827);
  static const _text = Color(0xFFF8FAFC);
  static const _sub = Color(0xFF94A3B8);

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  List<GroupCallParticipant> get _raisedHands => widget.call.participants
      .where((p) => widget.call.hasRaisedHand(p.userId))
      .toList();

  Future<void> _unmuteParticipant(GroupCallParticipant p) async {
    HapticFeedback.lightImpact();
    await GroupCallService.instance.muteParticipant(
      callId: widget.call.callId,
      targetUserId: p.userId,
      mute: false,
    );
    await GroupCallService.instance.toggleRaiseHand(
      callId: widget.call.callId,
      userId: p.userId,
      raised: false,
    );
  }

  Future<void> _lowerHand(GroupCallParticipant p) async {
    await GroupCallService.instance.toggleRaiseHand(
      callId: widget.call.callId,
      userId: p.userId,
      raised: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hands = _raisedHands;
    if (hands.isEmpty) return const SizedBox.shrink();

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 300, maxHeight: 320),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.82),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _amber.withOpacity(0.25), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: _amber.withOpacity(0.1),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildHeader(hands.length),
                  Divider(color: Colors.white.withOpacity(0.06), height: 1),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: hands.length,
                      separatorBuilder: (_, __) => Divider(
                          color: Colors.white.withOpacity(0.04), height: 1),
                      itemBuilder: (_, i) => _buildParticipantRow(hands[i]),
                    ),
                  ),
                  if (widget.isAdmin && hands.length > 1)
                    _buildLowerAllButton(hands),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Row(children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: _amber.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Center(
            child: Text('✋', style: TextStyle(fontSize: 15)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Đang giơ tay ($count)',
                style: TextStyle(
                  color: _amber,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Text(
                'Nhấn để cho phép nói',
                style: TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _buildParticipantRow(GroupCallParticipant p) {
    final isSelf = p.userId == widget.currentUserId;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(children: [
        // Avatar
        CircleAvatar(
          radius: 17,
          backgroundImage:
              p.userAvatar.isNotEmpty ? NetworkImage(p.userAvatar) : null,
          backgroundColor: const Color(0xFF1E2D40),
          child: p.userAvatar.isEmpty
              ? Text(p.userName.isNotEmpty ? p.userName[0].toUpperCase() : '?',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12))
              : null,
        ),
        const SizedBox(width: 10),

        // Name
        Expanded(
          child: Text(
            isSelf ? '${p.userName} (Bạn)' : p.userName,
            style: const TextStyle(
              color: _text,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),

        // Actions
        if (widget.isAdmin && !isSelf) ...[
          // Allow to speak
          _actionChip(
            label: 'Cho nói',
            color: const Color(0xFF22C55E),
            onTap: () => _unmuteParticipant(p),
          ),
          const SizedBox(width: 5),
          // Lower hand
          GestureDetector(
            onTap: () => _lowerHand(p),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.07),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.close_rounded,
                  color: Colors.white38, size: 14),
            ),
          ),
        ] else if (isSelf)
          _actionChip(
            label: 'Hạ tay',
            color: Colors.white24,
            textColor: Colors.white70,
            onTap: () => GroupCallService.instance.toggleRaiseHand(
              callId: widget.call.callId,
              userId: p.userId,
              raised: false,
            ),
          ),
      ]),
    );
  }

  Widget _actionChip({
    required String label,
    required Color color,
    Color textColor = Colors.white,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: textColor,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildLowerAllButton(List<GroupCallParticipant> hands) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      child: GestureDetector(
        onTap: () async {
          for (final p in hands) {
            await GroupCallService.instance.toggleRaiseHand(
              callId: widget.call.callId,
              userId: p.userId,
              raised: false,
            );
          }
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: const Text(
            'Hạ tay tất cả',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// CallReactionFeed
// Compact horizontal feed of recent reactions
// ══════════════════════════════════════════════════════════════════════════════
class CallReactionFeed extends StatefulWidget {
  final List<CallReaction> reactions;
  final int maxVisible;

  const CallReactionFeed({
    super.key,
    required this.reactions,
    this.maxVisible = 5,
  });

  @override
  State<CallReactionFeed> createState() => _CallReactionFeedState();
}

class _CallReactionFeedState extends State<CallReactionFeed> {
  @override
  Widget build(BuildContext context) {
    final recent = widget.reactions
        .where((r) => r.sentAt
            .isAfter(DateTime.now().subtract(const Duration(seconds: 8))))
        .take(widget.maxVisible)
        .toList();

    if (recent.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: recent.asMap().entries.map((e) {
        final i = e.key;
        final r = e.value;
        return _ReactionChip(
          reaction: r,
          delay: Duration(milliseconds: i * 60),
        );
      }).toList(),
    );
  }
}

class _ReactionChip extends StatefulWidget {
  final CallReaction reaction;
  final Duration delay;

  const _ReactionChip({required this.reaction, required this.delay});

  @override
  State<_ReactionChip> createState() => _ReactionChipState();
}

class _ReactionChipState extends State<_ReactionChip>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _scale = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 0.0, end: 1.25)
              .chain(CurveTween(curve: Curves.elasticOut)),
          weight: 60),
      TweenSequenceItem(tween: Tween(begin: 1.25, end: 1.0), weight: 40),
    ]).animate(_ctrl);
    _fade = CurvedAnimation(parent: _ctrl, curve: const Interval(0, 0.3));

    Future.delayed(widget.delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Opacity(
        opacity: _fade.value,
        child: Transform.scale(
          scale: _scale.value,
          child: Container(
            margin: const EdgeInsets.only(right: 4),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.55),
              borderRadius: BorderRadius.circular(20),
              border:
                  Border.all(color: Colors.white.withOpacity(0.1), width: 0.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.reaction.type.emoji,
                    style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 4),
                Text(
                  widget.reaction.userName.split(' ').first,
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 9,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// CallParticipantJoinLeaveToast
// Subtle animated toast when someone joins or leaves
// ══════════════════════════════════════════════════════════════════════════════
class CallParticipantToast extends StatefulWidget {
  final String name;
  final String? avatarUrl;
  final bool isJoining;

  const CallParticipantToast({
    super.key,
    required this.name,
    this.avatarUrl,
    required this.isJoining,
  });

  @override
  State<CallParticipantToast> createState() => _CallParticipantToastState();
}

class _CallParticipantToastState extends State<CallParticipantToast>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(-0.1, 0), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();

    // Auto-dismiss
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) _ctrl.reverse();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color =
        widget.isJoining ? const Color(0xFF22C55E) : const Color(0xFF94A3B8);

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.7),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: color.withOpacity(0.3), width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 12,
                backgroundImage:
                    widget.avatarUrl != null && widget.avatarUrl!.isNotEmpty
                        ? NetworkImage(widget.avatarUrl!)
                        : null,
                backgroundColor: const Color(0xFF1E2D40),
                child: widget.avatarUrl == null || widget.avatarUrl!.isEmpty
                    ? Text(
                        widget.name.isNotEmpty
                            ? widget.name[0].toUpperCase()
                            : '?',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 9))
                    : null,
              ),
              const SizedBox(width: 7),
              Text(
                widget.isJoining
                    ? '${widget.name} đã tham gia'
                    : '${widget.name} đã rời',
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
