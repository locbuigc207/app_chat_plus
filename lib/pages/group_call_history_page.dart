// ignore_for_file: deprecated_member_use
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../services/group_call_service.dart';
import '../services/services.dart';

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
// GroupCallHistoryPage
// Shows all ended group calls and recorded sessions for a group.
// ══════════════════════════════════════════════════════════════════════════════
class GroupCallHistoryPage extends StatefulWidget {
  final String groupId;
  final String groupName;
  final String currentUserId;

  const GroupCallHistoryPage({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.currentUserId,
  });

  @override
  State<GroupCallHistoryPage> createState() => _GroupCallHistoryPageState();
}

class _GroupCallHistoryPageState extends State<GroupCallHistoryPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  List<GroupCallModel> _history = [];
  List<CallRecordingEntry> _recordings = [];

  bool _loadingHistory = true;
  bool _loadingRecordings = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _loadHistory();
    _loadRecordings();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final data = await GroupCallService.instance
        .getGroupCallHistory(widget.groupId, limit: 30);
    if (mounted)
      setState(() {
        _history = data;
        _loadingHistory = false;
      });
  }

  Future<void> _loadRecordings() async {
    final data = await GroupCallRecordingService.instance
        .getGroupRecordings(widget.groupId);
    if (mounted)
      setState(() {
        _recordings = data;
        _loadingRecordings = false;
      });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _K.bg,
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [_buildAppBar()],
        body: TabBarView(
          controller: _tabCtrl,
          children: [_buildHistoryTab(), _buildRecordingsTab()],
        ),
      ),
    );
  }

  // ── AppBar ─────────────────────────────────────────────────────────────────
  Widget _buildAppBar() {
    return SliverAppBar(
      backgroundColor: _K.bg,
      surfaceTintColor: Colors.transparent,
      pinned: true,
      expandedHeight: 130,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded,
            color: _K.text, size: 20),
        onPressed: () => Navigator.of(context).pop(),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _K.accent.withOpacity(0.12),
                _K.bg,
              ],
            ),
          ),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 56),
              child: Row(children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _K.accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _K.accent.withOpacity(0.2)),
                  ),
                  child: const Icon(Icons.history_rounded,
                      color: _K.accent, size: 22),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Lịch sử cuộc gọi',
                        style: TextStyle(
                            color: _K.text,
                            fontSize: 18,
                            fontWeight: FontWeight.w800)),
                    Text(widget.groupName,
                        style: const TextStyle(color: _K.sub, fontSize: 12)),
                  ],
                ),
              ]),
            ),
          ),
        ),
      ),
      bottom: TabBar(
        controller: _tabCtrl,
        labelColor: _K.accent,
        unselectedLabelColor: _K.muted,
        indicatorColor: _K.accent,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        tabs: const [
          Tab(text: 'Cuộc gọi'),
          Tab(text: 'Bản ghi'),
        ],
      ),
    );
  }

  // ── History tab ────────────────────────────────────────────────────────────
  Widget _buildHistoryTab() {
    if (_loadingHistory) {
      return const Center(
          child: CircularProgressIndicator(color: _K.accent, strokeWidth: 2));
    }
    if (_history.isEmpty)
      return _buildEmpty('Chưa có cuộc gọi nào', Icons.call_outlined,
          'Lịch sử các cuộc gọi nhóm sẽ hiển thị ở đây');

    return RefreshIndicator(
      color: _K.accent,
      backgroundColor: _K.surface,
      onRefresh: _loadHistory,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _history.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _CallHistoryCard(
          call: _history[i],
          currentUserId: widget.currentUserId,
        ),
      ),
    );
  }

  // ── Recordings tab ─────────────────────────────────────────────────────────
  Widget _buildRecordingsTab() {
    if (_loadingRecordings) {
      return const Center(
          child: CircularProgressIndicator(color: _K.accent, strokeWidth: 2));
    }
    if (_recordings.isEmpty)
      return _buildEmpty(
          'Chưa có bản ghi nào',
          Icons.fiber_manual_record_rounded,
          'Các bản ghi cuộc gọi sẽ xuất hiện ở đây sau khi được lưu');

    return RefreshIndicator(
      color: _K.accent,
      backgroundColor: _K.surface,
      onRefresh: _loadRecordings,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _recordings.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _RecordingCard(entry: _recordings[i]),
      ),
    );
  }

  Widget _buildEmpty(String title, IconData icon, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: _K.muted.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: _K.muted, size: 36),
            ),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(
                    color: _K.text, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(subtitle,
                style:
                    const TextStyle(color: _K.sub, fontSize: 13, height: 1.5),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

// ─── Call history card ────────────────────────────────────────────────────────
class _CallHistoryCard extends StatelessWidget {
  final GroupCallModel call;
  final String currentUserId;

  const _CallHistoryCard({required this.call, required this.currentUserId});

  bool get _wasParticipant =>
      call.participants.any((p) => p.userId == currentUserId) ||
      call.initiatorId == currentUserId;

  Color get _statusColor {
    switch (call.status) {
      case GroupCallStatus.missed:
        return _K.red;
      case GroupCallStatus.ongoing:
      case GroupCallStatus.calling:
        return _K.green;
      default:
        return _K.muted;
    }
  }

  String get _statusText {
    switch (call.status) {
      case GroupCallStatus.missed:
        return 'Nhỡ';
      case GroupCallStatus.ongoing:
        return 'Đang diễn ra';
      case GroupCallStatus.calling:
        return 'Đang gọi';
      default:
        return call.durationSeconds != null && call.durationSeconds! > 0
            ? call.formattedDuration
            : 'Đã kết thúc';
    }
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0)
      return 'Hôm nay ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (diff.inDays == 1) return 'Hôm qua';
    if (diff.inDays < 7) return '${diff.inDays} ngày trước';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = call.callType == GroupCallType.video;
    final iconColor = isVideo ? _K.accent : _K.green;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _K.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          // Icon
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              isVideo ? Icons.videocam_rounded : Icons.phone_rounded,
              color: iconColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(
                    isVideo ? 'Cuộc gọi video' : 'Cuộc gọi thoại',
                    style: const TextStyle(
                        color: _K.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700),
                  ),
                  if (call.isRecording)
                    Container(
                      margin: const EdgeInsets.only(left: 7),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _K.red.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _K.red.withOpacity(0.3)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.fiber_manual_record_rounded,
                              color: _K.red, size: 8),
                          SizedBox(width: 3),
                          Text('REC',
                              style: TextStyle(
                                  color: _K.red,
                                  fontSize: 8,
                                  fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  Icon(Icons.access_time_rounded,
                      size: 11, color: _statusColor),
                  const SizedBox(width: 4),
                  Text(_statusText,
                      style: TextStyle(
                          color: _statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(width: 10),
                  Icon(Icons.people_rounded, size: 11, color: _K.muted),
                  const SizedBox(width: 3),
                  Text('${call.participantCount} người',
                      style: const TextStyle(color: _K.muted, fontSize: 11)),
                  const SizedBox(width: 10),
                  Text(_formatDate(call.createdAt),
                      style: const TextStyle(color: _K.muted, fontSize: 11)),
                ]),
              ],
            ),
          ),

          // Initiator tag
          if (call.initiatorId == currentUserId)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('Bạn gọi',
                  style: TextStyle(
                      color: iconColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }
}

// ─── Recording card ───────────────────────────────────────────────────────────
class _RecordingCard extends StatelessWidget {
  final CallRecordingEntry entry;
  const _RecordingCard({required this.entry});

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _K.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          // Play icon
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: _K.purple.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.play_circle_outline_rounded,
                color: _K.purple, size: 24),
          ),
          const SizedBox(width: 12),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Bản ghi cuộc gọi',
                    style: const TextStyle(
                        color: _K.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Row(children: [
                  Icon(Icons.access_time_rounded, size: 11, color: _K.sub),
                  const SizedBox(width: 3),
                  Text(entry.formattedDuration,
                      style: const TextStyle(color: _K.sub, fontSize: 11)),
                  const SizedBox(width: 10),
                  Icon(Icons.people_rounded, size: 11, color: _K.muted),
                  const SizedBox(width: 3),
                  Text('${entry.participantCount} người',
                      style: const TextStyle(color: _K.muted, fontSize: 11)),
                ]),
                const SizedBox(height: 2),
                Text(_formatDate(entry.createdAt),
                    style: const TextStyle(color: _K.muted, fontSize: 10)),
              ],
            ),
          ),

          // Open button
          GestureDetector(
            onTap: () async {
              if (entry.url.isEmpty) return;
              final uri = Uri.tryParse(entry.url);
              if (uri != null && await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: _K.purple.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _K.purple.withOpacity(0.3)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.open_in_new_rounded, color: _K.purple, size: 13),
                  SizedBox(width: 5),
                  Text('Mở',
                      style: TextStyle(
                          color: _K.purple,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// GroupCallStatsSummaryCard
// Quick stats card to embed in group chat's info panel.
// ══════════════════════════════════════════════════════════════════════════════
class GroupCallStatsSummaryCard extends StatefulWidget {
  final String groupId;
  final String groupName;
  final String currentUserId;

  const GroupCallStatsSummaryCard({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.currentUserId,
  });

  @override
  State<GroupCallStatsSummaryCard> createState() =>
      _GroupCallStatsSummaryCardState();
}

class _GroupCallStatsSummaryCardState extends State<GroupCallStatsSummaryCard> {
  int _totalCalls = 0;
  int _totalMinutes = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final calls = await GroupCallService.instance
        .getGroupCallHistory(widget.groupId, limit: 50);
    int mins = 0;
    for (final c in calls) {
      mins += (c.durationSeconds ?? 0) ~/ 60;
    }
    if (mounted)
      setState(() {
        _totalCalls = calls.length;
        _totalMinutes = mins;
        _loading = false;
      });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => GroupCallHistoryPage(
          groupId: widget.groupId,
          groupName: widget.groupName,
          currentUserId: widget.currentUserId,
        ),
      )),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _K.accent.withOpacity(0.07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _K.accent.withOpacity(0.15)),
        ),
        child: Row(children: [
          const Icon(Icons.history_rounded, color: _K.accent, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Lịch sử cuộc gọi',
                    style: TextStyle(
                        color: _K.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
                Text('$_totalCalls cuộc gọi • $_totalMinutes phút',
                    style: const TextStyle(color: _K.sub, fontSize: 11)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: _K.muted, size: 18),
        ]),
      ),
    );
  }
}
