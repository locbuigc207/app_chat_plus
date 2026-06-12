import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../models/group_call_model.dart';
import '../pages/group_call_waiting_room.dart';
import '../providers/providers.dart';
import '../services/group_call_service.dart';
import '../widgets/group_call_audio_visualizer.dart';
import '../widgets/group_call_permission_gate.dart';
import 'group_call_page.dart';

// ══════════════════════════════════════════════════════════════════════════════
// GroupCallSetupPage
// Pre-call screen: choose mic/camera state, preview, then join.
// ══════════════════════════════════════════════════════════════════════════════
class GroupCallSetupPage extends StatefulWidget {
  final String groupId;
  final String groupName;
  final String groupAvatarUrl;
  final List<String> memberIds;
  final GroupCallType callType;

  const GroupCallSetupPage({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.groupAvatarUrl,
    required this.memberIds,
    required this.callType,
  });

  @override
  State<GroupCallSetupPage> createState() => _GroupCallSetupPageState();
}

class _GroupCallSetupPageState extends State<GroupCallSetupPage>
    with TickerProviderStateMixin {
  bool _micEnabled = true;
  bool _cameraEnabled = true;
  bool _speakerEnabled = true;
  bool _isStarting = false;

  double _micLevel = 0.0; // 0.0–1.0 mic test level
  bool _waitingRoom = false; // đang vào waiting room
  bool _hasPermissions = false; // permissions granted

  late AnimationController _enterCtrl;
  late AnimationController _pulseCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  late Animation<double> _pulseAnim;

  static const _bg = Color(0xFF080E1C);
  static const _surface = Color(0xFF111827);
  static const _surface2 = Color(0xFF1C2333);
  static const _accent = Color(0xFF3B82F6);
  static const _green = Color(0xFF22C55E);

  Color get _primaryColor =>
      widget.callType == GroupCallType.video ? _accent : _green;

  @override
  void initState() {
    super.initState();
    _checkPermissions();

    _enterCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..forward();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);

    _fadeAnim = CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(
            CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOutCubic));
    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _enterCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkPermissions() async {
    final mic = await Permission.microphone.status;
    final cam = await Permission.camera.status;
    setState(() {
      _micEnabled = mic.isGranted;
      _cameraEnabled = cam.isGranted && widget.callType == GroupCallType.video;
      _hasPermissions = mic.isGranted;
    });
  }

  Future<void> _startCall() async {
    if (_isStarting) return;
    setState(() => _isStarting = true);
    HapticFeedback.mediumImpact();

    // Request permissions
    final perms = [Permission.microphone];
    if (widget.callType == GroupCallType.video && _cameraEnabled) {
      perms.add(Permission.camera);
    }
    await perms.request();

    final auth = context.read<AuthProvider>();
    final uid = auth.userFirebaseId;
    final name = auth.currentUserName ?? '';
    if (uid == null) {
      setState(() => _isStarting = false);
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

    final provider = context.read<GroupCallProvider>();

    // Cập nhật userId nếu chưa có
    provider.updateUserId(uid);

    if (existing != null && mounted) {
      final join = await _showJoinExistingDialog(existing);
      if (join != true) {
        setState(() => _isStarting = false);
        return;
      }

      final ok = await provider.joinCall(existing.callId);

      if (!ok || !mounted) {
        // Kiểm tra waiting room
        if (provider.isWaitingRoom && mounted) {
          setState(() => _isStarting = false);
          _navigateToWaitingRoom(existing, uid, name);
          return;
        }
        setState(() => _isStarting = false);
        return;
      }
      _navigateTo(existing, uid, name, isInitiator: false);
      return;
    }

    final call = await provider.startCall(
      groupId: widget.groupId,
      groupName: widget.groupName,
      groupAvatarUrl: widget.groupAvatarUrl,
      memberIds: widget.memberIds,
      callType: widget.callType,
      waitingRoomEnabled: _waitingRoom,
    );

    if (call == null || !mounted) {
      setState(() => _isStarting = false);
      // Hiển thị error từ provider
      final err = provider.error ?? 'Không thể bắt đầu cuộc gọi.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(err),
        backgroundColor: const Color(0xFFEF4444),
      ));
      return;
    }

    _navigateTo(call, uid, name, isInitiator: true);
  }

  Future<bool?> _showJoinExistingDialog(GroupCallModel call) {
    return showDialog<bool>(
      context: context,
      builder: (_) => _JoinExistingDialog(call: call),
    );
  }

  void _navigateTo(GroupCallModel call, String uid, String name,
      {required bool isInitiator}) {
    final auth = context.read<AuthProvider>();

    final avatar = auth.currentUserAvatar ?? '';

    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (_, __, ___) => GroupCallPage(
        call: call,
        isInitiator: isInitiator,
        currentUserId: uid,
        currentUserName: name,
        currentUserAvatar: avatar,
      ),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: child,
      ),
    ));
  }

  void _navigateToWaitingRoom(GroupCallModel call, String uid, String name) {
    final auth = context.read<AuthProvider>();

    final avatar = auth.currentUserAvatar ?? '';

    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => WaitingRoomPage(
        call: call,
        currentUserId: uid,
        currentUserName: name,
        currentUserAvatar: avatar,
      ),
    ));
    // WaitingRoomPage tự navigate vào GroupCallPage khi được admit
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(child: _buildBody()),
                _buildBottomSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white60),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Text(
              widget.groupName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  // ── Body ───────────────────────────────────────────────────────────────────
  Widget _buildBody() {
    // SỬA LẠI WIDGET NÀY:
    return GroupCallPermissionGate(
      callType: widget.callType,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          children: [
            const SizedBox(height: 16),

            // Call type label
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: _primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _primaryColor.withOpacity(0.25)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.callType == GroupCallType.video
                        ? Icons.videocam_rounded
                        : Icons.phone_rounded,
                    color: _primaryColor,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.callType == GroupCallType.video
                        ? 'Gọi video nhóm'
                        : 'Gọi thoại nhóm',
                    style: TextStyle(
                      color: _primaryColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Avatar preview
            AnimatedBuilder(
              animation: _pulseAnim,
              builder: (_, child) =>
                  Transform.scale(scale: _pulseAnim.value, child: child),
              child: _buildAvatarPreview(),
            ),

            const SizedBox(height: 32),

            // Members count
            _buildMembersChip(),

            const SizedBox(height: 28),

            // Settings card
            _buildSettingsCard(),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarPreview() {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Glow
        Container(
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: _primaryColor.withOpacity(0.25),
                blurRadius: 48,
                spreadRadius: 8,
              ),
            ],
          ),
        ),
        // Avatar
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: _primaryColor.withOpacity(0.4),
              width: 2.5,
            ),
          ),
          child: CircleAvatar(
            radius: 56,
            backgroundImage: widget.groupAvatarUrl.isNotEmpty
                ? NetworkImage(widget.groupAvatarUrl)
                : null,
            backgroundColor: _surface2,
            child: widget.groupAvatarUrl.isEmpty
                ? Icon(Icons.group_rounded,
                    size: 48, color: Colors.white.withOpacity(0.4))
                : null,
          ),
        ),
      ],
    );
  }

  Widget _buildMembersChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.people_rounded, color: Colors.white54, size: 15),
          const SizedBox(width: 7),
          Text(
            '${widget.memberIds.length} thành viên sẽ nhận được lời mời',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsCard() {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          _buildToggleTile(
            icon: _micEnabled ? Icons.mic_rounded : Icons.mic_off_rounded,
            label: 'Micro',
            subtitle: _micEnabled ? 'Đang bật' : 'Đang tắt',
            value: _micEnabled,
            iconColor: _micEnabled ? _green : const Color(0xFFEF4444),
            onChanged: (v) => setState(() => _micEnabled = v),
          ),
          Divider(color: Colors.white.withOpacity(0.05), height: 1),
          if (widget.callType == GroupCallType.video) ...[
            _buildToggleTile(
              icon: _cameraEnabled
                  ? Icons.videocam_rounded
                  : Icons.videocam_off_rounded,
              label: 'Camera',
              subtitle: _cameraEnabled ? 'Đang bật' : 'Đang tắt',
              value: _cameraEnabled,
              iconColor: _cameraEnabled ? _accent : const Color(0xFFFF9F0A),
              onChanged: (v) => setState(() => _cameraEnabled = v),
            ),
            Divider(color: Colors.white.withOpacity(0.05), height: 1),
          ],
          _buildToggleTile(
            icon: _speakerEnabled
                ? Icons.volume_up_rounded
                : Icons.hearing_rounded,
            label: 'Loa ngoài',
            subtitle: _speakerEnabled ? 'Đang bật' : 'Tai nghe',
            value: _speakerEnabled,
            iconColor: _speakerEnabled ? _accent : Colors.white38,
            onChanged: (v) => setState(() => _speakerEnabled = v),
          ),
          Divider(color: Colors.white.withOpacity(0.05), height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Kiểm tra micro',
                    style: TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                MicTestWidget(
                  micLevel: _micLevel,
                  isMuted: !_micEnabled,
                  onToggle: () => setState(() => _micEnabled = !_micEnabled),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleTile({
    required IconData icon,
    required String label,
    required String subtitle,
    required bool value,
    required Color iconColor,
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
      leading: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(
        label,
        style: const TextStyle(
            color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Colors.white38, fontSize: 12),
      ),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: _primaryColor,
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return _primaryColor.withOpacity(0.3);
          }
          return Colors.white.withOpacity(0.1);
        }),
      ),
    );
  }

  // ── Bottom section ─────────────────────────────────────────────────────────
  Widget _buildBottomSection() {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        bottom: MediaQuery.of(context).padding.bottom + 20,
        top: 12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.memberIds.length > 2) ...[
            Row(children: [
              Checkbox(
                value: _waitingRoom,
                onChanged: (v) => setState(() => _waitingRoom = v ?? false),
                activeColor: _primaryColor,
                side: BorderSide(color: Colors.white.withOpacity(0.2)),
              ),
              Expanded(
                child: Text(
                  'Bật phòng chờ (admin phê duyệt từng người)',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.55), fontSize: 12),
                ),
              ),
            ]),
            const SizedBox(height: 8),
          ],
          // Info text
          Text(
            'Mọi thành viên trong nhóm sẽ nhận thông báo',
            style: TextStyle(
              color: Colors.white.withOpacity(0.35),
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),

          // Start button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _isStarting
                      ? [
                          _primaryColor.withOpacity(0.5),
                          _primaryColor.withOpacity(0.5)
                        ]
                      : [_primaryColor, _primaryColor.withOpacity(0.85)],
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: _isStarting
                    ? null
                    : [
                        BoxShadow(
                          color: _primaryColor.withOpacity(0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
              ),
              child: ElevatedButton(
                onPressed: _isStarting ? null : _startCall,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                ),
                child: _isStarting
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            widget.callType == GroupCallType.video
                                ? Icons.videocam_rounded
                                : Icons.phone_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            widget.callType == GroupCallType.video
                                ? 'Bắt đầu cuộc gọi video'
                                : 'Bắt đầu cuộc gọi thoại',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Join existing dialog ──────────────────────────────────────────────────────
class _JoinExistingDialog extends StatelessWidget {
  final GroupCallModel call;
  const _JoinExistingDialog({required this.call});

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
              color: const Color(0xFF111827).withOpacity(0.96),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E).withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.groups_rounded,
                      color: Color(0xFF22C55E), size: 28),
                ),
                const SizedBox(height: 16),
                const Text('Cuộc gọi đang diễn ra',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(
                  '${call.participantCount} người đang trong nhóm "${call.groupName}".\nBạn có muốn tham gia không?',
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 13, height: 1.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Row(children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white38,
                        padding: const EdgeInsets.symmetric(vertical: 12),
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
                        backgroundColor: const Color(0xFF22C55E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: const Text('Vào ngay',
                          style: TextStyle(fontWeight: FontWeight.w700)),
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
