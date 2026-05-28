import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/call_model.dart';
import '../pages/outgoing_call_page.dart';
import '../services/call_service.dart';

// ─────────────────────────────────────────────────────────────
// Call History Page
// ─────────────────────────────────────────────────────────────

class CallHistoryPage extends StatefulWidget {
  final String currentUserId;

  const CallHistoryPage({super.key, required this.currentUserId});

  @override
  State<CallHistoryPage> createState() => _CallHistoryPageState();
}

class _CallHistoryPageState extends State<CallHistoryPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _callService = CallService.instance;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            expandedHeight: 130,
            floating: false,
            pinned: true,
            backgroundColor: Colors.transparent,
            elevation: 0,
            systemOverlayStyle: SystemUiOverlayStyle.light,
            flexibleSpace: FlexibleSpaceBar(
              background: _buildHeader(),
              titlePadding: EdgeInsets.zero,
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: _buildTabBar(),
            ),
          ),
        ],
        body: StreamBuilder<List<CallModel>>(
          stream: _callService.callHistoryStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _LoadingState();
            }
            if (snapshot.hasError) {
              return _ErrorState(error: '${snapshot.error}');
            }

            final all = snapshot.data ?? [];
            final outgoing = all
                .where((c) => c.callerId == widget.currentUserId)
                .toList();
            final incoming = all
                .where((c) => c.calleeId == widget.currentUserId)
                .toList();

            return TabBarView(
              controller: _tabController,
              children: [
                _CallList(
                  calls: all,
                  currentUserId: widget.currentUserId,
                ),
                _CallList(
                  calls: outgoing,
                  currentUserId: widget.currentUserId,
                ),
                _CallList(
                  calls: incoming,
                  currentUserId: widget.currentUserId,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A237E), Color(0xFF0A0E1A)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white70, size: 20),
                padding: EdgeInsets.zero,
              ),
              const SizedBox(width: 8),
              const Text(
                'Lịch sử cuộc gọi',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: const Color(0xFF0A0E1A),
      child: TabBar(
        controller: _tabController,
        indicatorColor: const Color(0xFF5C6BC0),
        indicatorWeight: 3,
        indicatorSize: TabBarIndicatorSize.label,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white38,
        labelStyle: const TextStyle(
            fontWeight: FontWeight.w600, fontSize: 13),
        unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w400, fontSize: 13),
        tabs: const [
          Tab(text: 'Tất cả'),
          Tab(text: 'Đã gọi'),
          Tab(text: 'Nhận'),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Call List
// ─────────────────────────────────────────────────────────────

class _CallList extends StatelessWidget {
  final List<CallModel> calls;
  final String currentUserId;

  const _CallList({required this.calls, required this.currentUserId});

  @override
  Widget build(BuildContext context) {
    if (calls.isEmpty) return const _EmptyState();

    // Group by date
    final grouped = <String, List<CallModel>>{};
    for (final c in calls) {
      final key = _dateKey(c.createdAt);
      grouped.putIfAbsent(key, () => []).add(c);
    }

    final sections = grouped.entries.toList();

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 32),
      itemCount: sections.length,
      itemBuilder: (context, i) {
        final section = sections[i];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
              child: Text(
                section.key,
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            ...section.value.map((call) {
              final isOutgoing = call.callerId == currentUserId;
              return _CallTile(
                call: call,
                isOutgoing: isOutgoing,
                currentUserId: currentUserId,
              );
            }),
          ],
        );
      },
    );
  }

  String _dateKey(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(dt.year, dt.month, dt.day);
    if (d == today) return 'HÔM NAY';
    if (d == today.subtract(const Duration(days: 1))) return 'HÔM QUA';
    if (today.difference(d).inDays < 7) {
      return DateFormat('EEEE', 'vi').format(dt).toUpperCase();
    }
    return DateFormat('dd MMMM yyyy', 'vi').format(dt).toUpperCase();
  }
}

// ─────────────────────────────────────────────────────────────
// Call Tile
// ─────────────────────────────────────────────────────────────

class _CallTile extends StatelessWidget {
  final CallModel call;
  final bool isOutgoing;
  final String currentUserId;

  const _CallTile({
    required this.call,
    required this.isOutgoing,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    final peerName = isOutgoing ? call.calleeName : call.callerName;
    final peerAvatar = isOutgoing ? call.calleeAvatar : call.callerAvatar;
    final peerId = isOutgoing ? call.calleeId : call.callerId;
    final info = _statusInfo();

    return InkWell(
      onTap: () => _showOptions(context, peerName, peerAvatar, peerId),
      splashColor: Colors.white.withOpacity(0.04),
      highlightColor: Colors.white.withOpacity(0.02),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            _Avatar(url: peerAvatar, name: peerName, size: 52),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    peerName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(info.icon, size: 13, color: info.color),
                      const SizedBox(width: 5),
                      Text(
                        info.label,
                        style: TextStyle(
                            color: info.color,
                            fontSize: 12,
                            fontWeight: FontWeight.w500),
                      ),
                      if (call.durationSeconds != null &&
                          call.durationSeconds! > 0) ...[
                        Text(
                          '  ·  ${call.formattedDuration}',
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _timeLabel(),
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 11),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    call.isVideoCall
                        ? Icons.videocam_rounded
                        : Icons.phone_rounded,
                    size: 13,
                    color: Colors.white54,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  _StatusInfo _statusInfo() {
    switch (call.status) {
      case CallStatus.ended:
        return isOutgoing
            ? _StatusInfo(
            Icons.call_made_rounded, const Color(0xFF4FC3F7), 'Đã gọi đi')
            : _StatusInfo(Icons.call_received_rounded,
            const Color(0xFF81C784), 'Cuộc gọi đến');
      case CallStatus.missed:
        return _StatusInfo(
            Icons.call_missed_rounded, const Color(0xFFEF5350), 'Cuộc gọi nhỡ');
      case CallStatus.declined:
        return _StatusInfo(Icons.call_missed_outgoing_rounded,
            const Color(0xFFFF8A65), 'Đã bị từ chối');
      case CallStatus.rejected:
        return _StatusInfo(
            Icons.do_not_disturb_on_rounded, const Color(0xFFFF7043), 'Đã từ chối');
      case CallStatus.failed:
        return _StatusInfo(Icons.error_outline_rounded,
            const Color(0xFFBDBDBD), 'Thất bại');
      default:
        return _StatusInfo(Icons.phone_rounded, Colors.white38, 'Không rõ');
    }
  }

  String _timeLabel() {
    final now = DateTime.now();
    final diff = now.difference(call.createdAt);
    if (diff.inSeconds < 60) return 'Vừa xong';
    if (diff.inMinutes < 60) return '${diff.inMinutes}p';
    if (diff.inHours < 24) return '${diff.inHours}g';
    if (diff.inDays == 1) return 'Hôm qua';
    if (diff.inDays < 7) {
      return DateFormat('EEE').format(call.createdAt);
    }
    return DateFormat('dd/MM').format(call.createdAt);
  }

  void _showOptions(
      BuildContext context, String name, String avatar, String peerId) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _CallbackSheet(
        peerName: name,
        peerAvatar: avatar,
        peerId: peerId,
        callType: call.callType,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Callback Bottom Sheet
// ─────────────────────────────────────────────────────────────

class _CallbackSheet extends StatelessWidget {
  final String peerName;
  final String peerAvatar;
  final String peerId;
  final CallType callType;

  const _CallbackSheet({
    required this.peerName,
    required this.peerAvatar,
    required this.peerId,
    required this.callType,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1F36).withOpacity(0.95),
            borderRadius:
            const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      _Avatar(url: peerAvatar, name: peerName, size: 56),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(peerName,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          const Text('Gọi lại',
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 13)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Expanded(
                        child: _SheetCallBtn(
                          icon: Icons.phone_rounded,
                          label: 'Thoại',
                          color: const Color(0xFF43A047),
                          onTap: () => _call(context, CallType.voice),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _SheetCallBtn(
                          icon: Icons.videocam_rounded,
                          label: 'Video',
                          color: const Color(0xFF1E88E5),
                          onTap: () => _call(context, CallType.video),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _call(BuildContext context, CallType type) async {
    Navigator.pop(context);
    final service = CallService.instance;
    final call = await service.initiateCall(
      calleeId: peerId,
      calleeName: peerName,
      calleeAvatar: peerAvatar,
      callType: type,
    );
    if (call != null && context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => OutgoingCallPage(call: call)),
      );
    }
  }
}

class _SheetCallBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _SheetCallBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Shared avatar widget
// ─────────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  final String url;
  final String name;
  final double size;

  const _Avatar(
      {required this.url, required this.name, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFF3949AB), Color(0xFF1E88E5)],
        ),
      ),
      child: ClipOval(
        child: url.isNotEmpty
            ? Image.network(url,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _initials())
            : _initials(),
      ),
    );
  }

  Widget _initials() {
    return Center(
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.38,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// States
// ─────────────────────────────────────────────────────────────

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(
        color: Color(0xFF5C6BC0),
        strokeWidth: 2,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.phone_missed_rounded,
                size: 36, color: Colors.white24),
          ),
          const SizedBox(height: 20),
          const Text('Chưa có cuộc gọi nào',
              style: TextStyle(
                  color: Colors.white54,
                  fontSize: 16,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          const Text('Lịch sử sẽ hiển thị ở đây',
              style: TextStyle(color: Colors.white24, fontSize: 13)),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  const _ErrorState({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 48, color: Colors.white24),
            const SizedBox(height: 16),
            const Text('Không thể tải dữ liệu',
                style: TextStyle(color: Colors.white54, fontSize: 15)),
            const SizedBox(height: 8),
            Text(error,
                style:
                const TextStyle(color: Colors.white24, fontSize: 12),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Data class
// ─────────────────────────────────────────────────────────────

class _StatusInfo {
  final IconData icon;
  final Color color;
  final String label;
  const _StatusInfo(this.icon, this.color, this.label);
}