import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import '../models/call_model.dart';
import '../pages/outgoing_call_page.dart';
import '../services/call_service.dart';

// ══════════════════════════════════════════════════════
// DESIGN TOKENS
// ══════════════════════════════════════════════════════
const _kBg = Color(0xFF080C18);
const _kCard = Color(0xFF0F1428);
const _kBorder = Color(0x22FFFFFF);
const _kBlue = Color(0xFF3D5AFE);
const _kGreen = Color(0xFF34C759);
const _kRed = Color(0xFFFF3B30);
const _kOrange = Color(0xFFFF9F0A);

// ══════════════════════════════════════════════════════
// CALL HISTORY PAGE
// ══════════════════════════════════════════════════════
class CallHistoryPage extends StatefulWidget {
  final String currentUserId;
  const CallHistoryPage({super.key, required this.currentUserId});

  @override
  State<CallHistoryPage> createState() => _CallHistoryPageState();
}

class _CallHistoryPageState extends State<CallHistoryPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  final _callService = CallService.instance;
  final _searchCtrl = TextEditingController();

  bool _searching = false;
  String _query = '';

  static const _tabs = ['Tất cả', 'Nhỡ', 'Video', 'Thoại'];

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('vi');
    _tabCtrl = TabController(length: _tabs.length, vsync: this);
    _tabCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<CallModel> _filter(List<CallModel> all) {
    List<CallModel> out = all;

    // Tab filter
    switch (_tabCtrl.index) {
      case 1:
        out = out.where((c) => c.status == CallStatus.missed).toList();
        break;
      case 2:
        out = out.where((c) => c.isVideoCall).toList();
        break;
      case 3:
        out = out.where((c) => !c.isVideoCall).toList();
        break;
    }

    // Search filter
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      final uid = widget.currentUserId;
      out = out.where((c) {
        final peer = c.callerId == uid ? c.calleeName : c.callerName;
        return peer.toLowerCase().contains(q);
      }).toList();
    }

    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: StreamBuilder<List<CallModel>>(
        stream: _callService.callHistoryStream,
        builder: (context, snap) {
          final all = snap.data ?? [];
          final filtered = _filter(all);
          final stats = _CallStats.from(all, widget.currentUserId);

          return NestedScrollView(
            headerSliverBuilder: (_, inner) => [
              _buildSliverAppBar(context, inner, stats, filtered.length),
            ],
            body: filtered.isEmpty
                ? _EmptyState(
                    isLoading: snap.connectionState == ConnectionState.waiting,
                  )
                : _CallListView(
                    calls: filtered,
                    currentUserId: widget.currentUserId,
                  ),
          );
        },
      ),
    );
  }

  Widget _buildSliverAppBar(
    BuildContext ctx,
    bool inner,
    _CallStats stats,
    int count,
  ) {
    return SliverAppBar(
      expandedHeight: _searching ? 130 : 260,
      floating: false,
      pinned: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      flexibleSpace: FlexibleSpaceBar(
        background: _HeaderContent(
          stats: stats,
          searching: _searching,
          searchCtrl: _searchCtrl,
          onSearchToggle: () {
            setState(() {
              _searching = !_searching;
              if (!_searching) {
                _query = '';
                _searchCtrl.clear();
              }
            });
          },
          onQueryChanged: (q) => setState(() => _query = q),
        ),
        titlePadding: EdgeInsets.zero,
      ),
      leading: IconButton(
        icon: const Icon(
          Icons.arrow_back_ios_new_rounded,
          color: Colors.white70,
          size: 20,
        ),
        onPressed: () => Navigator.pop(ctx),
      ),
      actions: [
        IconButton(
          icon: Icon(
            _searching ? Icons.close_rounded : Icons.search_rounded,
            color: Colors.white70,
          ),
          onPressed: () {
            setState(() {
              _searching = !_searching;
              if (!_searching) {
                _query = '';
                _searchCtrl.clear();
              }
            });
          },
        ),
        const SizedBox(width: 4),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: _buildTabBar(),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: _kBg,
      child: TabBar(
        controller: _tabCtrl,
        indicatorColor: _kBlue,
        indicatorWeight: 3,
        indicatorSize: TabBarIndicatorSize.label,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white38,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w400,
          fontSize: 13,
        ),
        tabs: _tabs.map((t) => Tab(text: t)).toList(),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════
// HEADER CONTENT
// ══════════════════════════════════════════════════════
class _HeaderContent extends StatelessWidget {
  final _CallStats stats;
  final bool searching;
  final TextEditingController searchCtrl;
  final VoidCallback onSearchToggle;
  final ValueChanged<String> onQueryChanged;

  const _HeaderContent({
    required this.stats,
    required this.searching,
    required this.searchCtrl,
    required this.onSearchToggle,
    required this.onQueryChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D1B4B), Color(0xFF080C18)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 56, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!searching) ...[
                const Text(
                  'Lịch sử cuộc gọi',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 20),
                // Stats row
                Row(
                  children: [
                    _StatCard(
                      label: 'Tổng',
                      value: '${stats.total}',
                      icon: Icons.phone_rounded,
                      color: _kBlue,
                    ),
                    const SizedBox(width: 12),
                    _StatCard(
                      label: 'Nhỡ',
                      value: '${stats.missed}',
                      icon: Icons.phone_missed_rounded,
                      color: _kRed,
                    ),
                    const SizedBox(width: 12),
                    _StatCard(
                      label: 'Hôm nay',
                      value: stats.todayDuration,
                      icon: Icons.access_time_rounded,
                      color: _kGreen,
                    ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 8),
                _SearchBar(controller: searchCtrl, onChanged: onQueryChanged),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _SearchBar({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        autofocus: true,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: const InputDecoration(
          hintText: 'Tìm theo tên…',
          hintStyle: TextStyle(color: Colors.white38),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: Colors.white38,
            size: 20,
          ),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 13),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════
// CALL LIST VIEW (grouped by date)
// ══════════════════════════════════════════════════════
class _CallListView extends StatelessWidget {
  final List<CallModel> calls;
  final String currentUserId;

  const _CallListView({required this.calls, required this.currentUserId});

  @override
  Widget build(BuildContext context) {
    // Group by date key
    final groups = <String, List<CallModel>>{};
    for (final c in calls) {
      final key = _dateKey(c.createdAt);
      groups.putIfAbsent(key, () => []).add(c);
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 40),
      itemCount: groups.length,
      itemBuilder: (ctx, i) {
        final entry = groups.entries.elementAt(i);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DateHeader(label: entry.key),
            ...entry.value.map(
              (c) => _CallTile(call: c, currentUserId: currentUserId),
            ),
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
    return DateFormat('dd/MM/yyyy').format(dt);
  }
}

class _DateHeader extends StatelessWidget {
  final String label;
  const _DateHeader({required this.label});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 28, 20, 10),
    child: Text(
      label,
      style: const TextStyle(
        color: Colors.white30,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
      ),
    ),
  );
}

// ══════════════════════════════════════════════════════
// CALL TILE
// ══════════════════════════════════════════════════════
class _CallTile extends StatefulWidget {
  final CallModel call;
  final String currentUserId;

  const _CallTile({required this.call, required this.currentUserId});

  @override
  State<_CallTile> createState() => _CallTileState();
}

class _CallTileState extends State<_CallTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _scale = Tween<double>(
      begin: 1,
      end: 0.97,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _isOutgoing => widget.call.callerId == widget.currentUserId;

  String get _peerName =>
      _isOutgoing ? widget.call.calleeName : widget.call.callerName;
  String get _peerAvatar =>
      _isOutgoing ? widget.call.calleeAvatar : widget.call.callerAvatar;
  String get _peerId =>
      _isOutgoing ? widget.call.calleeId : widget.call.callerId;

  _StatusInfo get _info {
    final c = widget.call;
    switch (c.status) {
      case CallStatus.ended:
        return _isOutgoing
            ? const _StatusInfo(
                Icons.call_made_rounded,
                Color(0xFF4FC3F7),
                'Đã gọi đi',
              )
            : const _StatusInfo(
                Icons.call_received_rounded,
                Color(0xFF81C784),
                'Cuộc gọi đến',
              );
      case CallStatus.missed:
        return const _StatusInfo(
          Icons.call_missed_rounded,
          _kRed,
          'Cuộc gọi nhỡ',
        );
      case CallStatus.declined:
        return const _StatusInfo(
          Icons.call_missed_outgoing_rounded,
          _kOrange,
          'Đã bị từ chối',
        );
      case CallStatus.rejected:
        return const _StatusInfo(
          Icons.do_not_disturb_on_rounded,
          _kOrange,
          'Đã từ chối',
        );
      case CallStatus.failed:
        return const _StatusInfo(
          Icons.error_outline_rounded,
          Colors.white30,
          'Thất bại',
        );
      default:
        return const _StatusInfo(Icons.phone_rounded, Colors.white30, '');
    }
  }

  String _timeLabel() {
    final diff = DateTime.now().difference(widget.call.createdAt);
    if (diff.inSeconds < 60) return 'Vừa xong';
    if (diff.inMinutes < 60) return '${diff.inMinutes}ph';
    if (diff.inHours < 24) return '${diff.inHours}g';
    if (diff.inDays == 1) return 'Hôm qua';
    return DateFormat('dd/MM').format(widget.call.createdAt);
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final isMissed = widget.call.status == CallStatus.missed;

    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        _showOptions(context);
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isMissed ? _kRed.withOpacity(0.05) : _kCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isMissed ? _kRed.withOpacity(0.2) : _kBorder,
            ),
          ),
          child: Row(
            children: [
              // Avatar
              _PeerAvatar(
                url: _peerAvatar,
                name: _peerName,
                size: 52,
                isMissed: isMissed,
              ),
              const SizedBox(width: 14),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _peerName,
                      style: TextStyle(
                        color: isMissed ? _kRed : Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Icon(info.icon, size: 13, color: info.color),
                        const SizedBox(width: 5),
                        Text(
                          info.label,
                          style: TextStyle(
                            color: info.color,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (widget.call.durationSeconds != null &&
                            widget.call.durationSeconds! > 0) ...[
                          const Text(
                            '  ·  ',
                            style: TextStyle(
                              color: Colors.white24,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            widget.call.formattedDuration,
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Right side: time + type
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _timeLabel(),
                    style: const TextStyle(color: Colors.white30, fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Type badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          widget.call.isVideoCall
                              ? Icons.videocam_rounded
                              : Icons.phone_rounded,
                          size: 13,
                          color: Colors.white38,
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Callback button
                      GestureDetector(
                        onTap: () => _callback(context),
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: _kBlue.withOpacity(0.15),
                            shape: BoxShape.circle,
                            border: Border.all(color: _kBlue.withOpacity(0.3)),
                          ),
                          child: const Icon(
                            Icons.phone_rounded,
                            size: 15,
                            color: _kBlue,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showOptions(BuildContext ctx) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _CallbackSheet(
        peerName: _peerName,
        peerAvatar: _peerAvatar,
        peerId: _peerId,
        callType: widget.call.callType,
      ),
    );
  }

  Future<void> _callback(BuildContext ctx) async {
    HapticFeedback.lightImpact();
    final call = await CallService.instance.initiateCall(
      calleeId: _peerId,
      calleeName: _peerName,
      calleeAvatar: _peerAvatar,
      callType: widget.call.callType,
    );
    if (call != null && ctx.mounted) {
      Navigator.of(
        ctx,
      ).push(MaterialPageRoute(builder: (_) => OutgoingCallPage(call: call)));
    }
  }
}

// ══════════════════════════════════════════════════════
// CALLBACK SHEET
// ══════════════════════════════════════════════════════
class _CallbackSheet extends StatelessWidget {
  final String peerName, peerAvatar, peerId;
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
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xF0101728),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border.all(color: const Color(0x33FFFFFF)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Peer info
                  Row(
                    children: [
                      _PeerAvatar(
                        url: peerAvatar,
                        name: peerName,
                        size: 60,
                        isMissed: false,
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            peerName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Gọi lại',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),

                  // Buttons
                  Row(
                    children: [
                      Expanded(
                        child: _SheetCallBtn(
                          icon: Icons.phone_rounded,
                          label: 'Thoại',
                          color: _kGreen,
                          onTap: () => _call(context, CallType.voice),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _SheetCallBtn(
                          icon: Icons.videocam_rounded,
                          label: 'Video',
                          color: _kBlue,
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

  Future<void> _call(BuildContext ctx, CallType type) async {
    Navigator.pop(ctx);
    final call = await CallService.instance.initiateCall(
      calleeId: peerId,
      calleeName: peerName,
      calleeAvatar: peerAvatar,
      callType: type,
    );
    if (call != null && ctx.mounted) {
      Navigator.of(
        ctx,
      ).push(MaterialPageRoute(builder: (_) => OutgoingCallPage(call: call)));
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
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}

// ══════════════════════════════════════════════════════
// PEER AVATAR
// ══════════════════════════════════════════════════════
class _PeerAvatar extends StatelessWidget {
  final String url, name;
  final double size;
  final bool isMissed;

  const _PeerAvatar({
    required this.url,
    required this.name,
    required this.size,
    required this.isMissed,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: isMissed
          ? null
          : const LinearGradient(
              colors: [Color(0xFF3949AB), Color(0xFF1E88E5)],
            ),
      color: isMissed ? _kRed.withOpacity(0.15) : null,
      border: Border.all(
        color: isMissed ? _kRed.withOpacity(0.4) : Colors.white12,
        width: 1.5,
      ),
    ),
    child: ClipOval(
      child: url.isNotEmpty
          ? Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _Initials(name: name, size: size),
            )
          : _Initials(name: name, size: size),
    ),
  );
}

class _Initials extends StatelessWidget {
  final String name;
  final double size;

  const _Initials({required this.name, required this.size});

  @override
  Widget build(BuildContext context) => Center(
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

// ══════════════════════════════════════════════════════
// EMPTY STATE
// ══════════════════════════════════════════════════════
class _EmptyState extends StatelessWidget {
  final bool isLoading;
  const _EmptyState({required this.isLoading});

  @override
  Widget build(BuildContext context) => Center(
    child: isLoading
        ? const CircularProgressIndicator(color: _kBlue, strokeWidth: 2)
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white12),
                ),
                child: const Icon(
                  Icons.phone_missed_rounded,
                  size: 40,
                  color: Colors.white24,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Chưa có cuộc gọi nào',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Lịch sử gọi sẽ hiển thị ở đây',
                style: TextStyle(color: Colors.white24, fontSize: 13),
              ),
            ],
          ),
  );
}

// ══════════════════════════════════════════════════════
// HELPERS
// ══════════════════════════════════════════════════════
class _StatusInfo {
  final IconData icon;
  final Color color;
  final String label;
  const _StatusInfo(this.icon, this.color, this.label);
}

class _CallStats {
  final int total, missed;
  final String todayDuration;

  const _CallStats({
    required this.total,
    required this.missed,
    required this.todayDuration,
  });

  factory _CallStats.from(List<CallModel> calls, String uid) {
    final today = DateTime.now();
    int totalSec = 0;
    int missedCount = 0;

    for (final c in calls) {
      if (c.status == CallStatus.missed) missedCount++;
      final d = c.createdAt;
      if (d.year == today.year &&
          d.month == today.month &&
          d.day == today.day) {
        totalSec += c.durationSeconds ?? 0;
      }
    }

    final h = totalSec ~/ 3600;
    final m = (totalSec % 3600) ~/ 60;
    final todayStr = h > 0
        ? '${h}g ${m}ph'
        : m > 0
        ? '${m}ph'
        : '0ph';

    return _CallStats(
      total: calls.length,
      missed: missedCount,
      todayDuration: todayStr,
    );
  }
}
