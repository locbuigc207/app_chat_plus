// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/group_call_model.dart';

class _K {
  static const bg = Color(0xFF080E1C);
  static const surface = Color(0xFF111827);
  static const s2 = Color(0xFF1C2333);
  static const s3 = Color(0xFF242D3F);
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
// GroupCallEndSummary
// Rich post-call summary: duration, participants, recording, reactions count.
// ══════════════════════════════════════════════════════════════════════════════
class GroupCallEndSummary extends StatefulWidget {
  final GroupCallModel call;
  final DateTime startTime;
  final bool wasHost;
  final String? recordingUrl;
  final Map<CallReactionType, int> reactionCounts;
  final VoidCallback onClose;
  final VoidCallback? onCallAgain;

  const GroupCallEndSummary({
    super.key,
    required this.call,
    required this.startTime,
    required this.wasHost,
    this.recordingUrl,
    this.reactionCounts = const {},
    required this.onClose,
    this.onCallAgain,
  });

  static Future<void> show(
    BuildContext context, {
    required GroupCallModel call,
    required DateTime startTime,
    required bool wasHost,
    String? recordingUrl,
    Map<CallReactionType, int> reactionCounts = const {},
    required VoidCallback onClose,
    VoidCallback? onCallAgain,
  }) {
    return showModalBottomSheet(
      context: context,
      isDismissible: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => GroupCallEndSummary(
        call: call,
        startTime: startTime,
        wasHost: wasHost,
        recordingUrl: recordingUrl,
        reactionCounts: reactionCounts,
        onClose: onClose,
        onCallAgain: onCallAgain,
      ),
    );
  }

  @override
  State<GroupCallEndSummary> createState() => _GroupCallEndSummaryState();
}

class _GroupCallEndSummaryState extends State<GroupCallEndSummary>
    with TickerProviderStateMixin {
  late AnimationController _entryCtrl;
  late AnimationController _statsCtrl;
  late Animation<double> _entryFade;
  late Animation<Offset> _entrySlide;
  late Animation<double> _statsAnim;

  int get _durationSec =>
      widget.call.durationSeconds ??
      DateTime.now().difference(widget.startTime).inSeconds;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 450));
    _statsCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));

    _entryFade = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _entrySlide = Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
        .animate(
            CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));
    _statsAnim = CurvedAnimation(parent: _statsCtrl, curve: Curves.easeOut);

    _entryCtrl.forward().then((_) => _statsCtrl.forward());
    HapticFeedback.mediumImpact();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _statsCtrl.dispose();
    super.dispose();
  }

  String _formatDuration(int s) {
    if (s <= 0) return '00:00';
    final h = s ~/ 3600;
    final m = (s % 3600 ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$sec' : '$m:$sec';
  }

  String _formatDate(DateTime dt) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}, '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _entryFade,
      child: SlideTransition(
        position: _entrySlide,
        child: Container(
          decoration: BoxDecoration(
            color: _K.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border.all(color: Colors.white.withOpacity(0.07)),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildHandle(),
                  const SizedBox(height: 20),
                  _buildHeader(),
                  const SizedBox(height: 24),
                  _buildMainStats(),
                  const SizedBox(height: 16),
                  _buildParticipantGrid(),
                  if (widget.reactionCounts.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildReactionSummary(),
                  ],
                  if (widget.recordingUrl != null) ...[
                    const SizedBox(height: 16),
                    _buildRecordingCard(),
                  ],
                  const SizedBox(height: 24),
                  _buildActions(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHandle() => Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  Widget _buildHeader() => Column(children: [
        // Icon
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_K.red.withOpacity(0.2), _K.red.withOpacity(0.08)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            border: Border.all(color: _K.red.withOpacity(0.3), width: 1.5),
          ),
          child: const Icon(Icons.call_end_rounded, color: _K.red, size: 32),
        ),
        const SizedBox(height: 14),
        const Text('Cuộc gọi đã kết thúc',
            style: TextStyle(
                color: _K.text,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4)),
        const SizedBox(height: 4),
        Text(
          widget.call.groupName,
          style: const TextStyle(color: _K.sub, fontSize: 14),
        ),
        const SizedBox(height: 4),
        Text(_formatDate(widget.startTime),
            style: const TextStyle(color: _K.muted, fontSize: 11)),
      ]);

  Widget _buildMainStats() {
    return AnimatedBuilder(
      animation: _statsAnim,
      builder: (_, __) {
        return Row(children: [
          Expanded(
              child: _statCard(
            icon: Icons.access_time_rounded,
            label: 'Thời gian',
            value: _formatDuration(_durationSec),
            color: _K.accent,
            animValue: _statsAnim.value,
          )),
          const SizedBox(width: 10),
          Expanded(
              child: _statCard(
            icon: Icons.people_rounded,
            label: 'Thành viên',
            value: '${widget.call.participantCount}',
            color: _K.green,
            animValue: _statsAnim.value,
          )),
          const SizedBox(width: 10),
          Expanded(
              child: _statCard(
            icon: widget.call.isVideo
                ? Icons.videocam_rounded
                : Icons.phone_rounded,
            label: 'Loại',
            value: widget.call.isVideo ? 'Video' : 'Thoại',
            color: _K.purple,
            animValue: _statsAnim.value,
          )),
        ]);
      },
    );
  }

  Widget _statCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required double animValue,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07 + animValue * 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Column(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 6),
        Text(value,
            style: TextStyle(
                color: color, fontSize: 17, fontWeight: FontWeight.w800)),
        Text(label,
            style: const TextStyle(color: _K.muted, fontSize: 10, height: 1.3)),
      ]),
    );
  }

  Widget _buildParticipantGrid() {
    if (widget.call.participants.isEmpty) return const SizedBox.shrink();
    final parts = widget.call.participants.take(8).toList();
    final extra =
        widget.call.participantCount > 8 ? widget.call.participantCount - 8 : 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _K.s2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.people_outline_rounded, color: _K.sub, size: 14),
          const SizedBox(width: 6),
          Text('${widget.call.participantCount} người tham gia',
              style: const TextStyle(
                  color: _K.sub, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, children: [
          ...parts.map((p) => _ParticipantChip(participant: p)),
          if (extra > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _K.accent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _K.accent.withOpacity(0.2)),
              ),
              child: Text('+$extra người',
                  style: const TextStyle(
                      color: _K.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
        ]),
      ]),
    );
  }

  Widget _buildReactionSummary() {
    final sorted = widget.reactionCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = widget.reactionCounts.values.fold(0, (s, v) => s + v);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _K.s2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('😊', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text('$total cảm xúc được gửi',
              style: const TextStyle(
                  color: _K.sub, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 10),
        Wrap(
            spacing: 8,
            runSpacing: 8,
            children: sorted
                .map(
                  (e) => Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(e.key.emoji, style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 5),
                      Text('${e.value}',
                          style: const TextStyle(
                              color: _K.sub,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                    ]),
                  ),
                )
                .toList()),
      ]),
    );
  }

  Widget _buildRecordingCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _K.purple.withOpacity(0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _K.purple.withOpacity(0.2)),
      ),
      child: Row(children: [
        Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _K.purple.withOpacity(0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(Icons.fiber_manual_record_rounded,
                color: _K.purple, size: 18)),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Bản ghi cuộc gọi',
              style: TextStyle(
                  color: _K.text, fontSize: 13, fontWeight: FontWeight.w700)),
          const Text('Đã lưu và sẵn sàng xem',
              style: TextStyle(color: _K.sub, fontSize: 11)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _K.purple.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _K.purple.withOpacity(0.3)),
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.play_arrow_rounded, color: _K.purple, size: 15),
            SizedBox(width: 4),
            Text('Xem',
                style: TextStyle(
                    color: _K.purple,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ]),
        ),
      ]),
    );
  }

  Widget _buildActions() => Column(children: [
        if (widget.onCallAgain != null) ...[
          _actionBtn(
            icon: widget.call.isVideo
                ? Icons.videocam_rounded
                : Icons.phone_rounded,
            label: 'Gọi lại',
            color: _K.accent,
            filled: true,
            onTap: () {
              Navigator.pop(context);
              widget.onCallAgain!();
            },
          ),
          const SizedBox(height: 10),
        ],
        _actionBtn(
          icon: Icons.close_rounded,
          label: 'Đóng',
          color: _K.muted,
          filled: false,
          onTap: widget.onClose,
        ),
      ]);

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required bool filled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: filled ? color : color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: filled ? null : Border.all(color: color.withOpacity(0.25)),
          boxShadow: filled
              ? [
                  BoxShadow(
                      color: color.withOpacity(0.3),
                      blurRadius: 14,
                      offset: const Offset(0, 4))
                ]
              : null,
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: filled ? Colors.white : color, size: 18),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  color: filled ? Colors.white : color,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

class _ParticipantChip extends StatelessWidget {
  final GroupCallParticipant participant;
  const _ParticipantChip({required this.participant});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      CircleAvatar(
        radius: 13,
        backgroundImage: participant.userAvatar.isNotEmpty
            ? NetworkImage(participant.userAvatar)
            : null,
        backgroundColor: _K.s3,
        child: participant.userAvatar.isEmpty
            ? Text(
                participant.userName.isNotEmpty
                    ? participant.userName[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700))
            : null,
      ),
      const SizedBox(width: 6),
      Text(
        participant.isAdmin
            ? '${participant.userName} ★'
            : participant.userName,
        style: TextStyle(
          color: participant.isAdmin ? _K.amber : _K.sub,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    ]);
  }
}
