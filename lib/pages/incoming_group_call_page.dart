import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/group_call_model.dart';
import '../services/group_call_service.dart';
import 'group_call_page.dart';

class IncomingGroupCallPage extends StatefulWidget {
  final GroupCallModel call;
  final String currentUserId;
  final String currentUserName;
  final String currentUserAvatar;

  const IncomingGroupCallPage({
    super.key,
    required this.call,
    required this.currentUserId,
    this.currentUserName = '',
    this.currentUserAvatar = '',
  });

  @override
  State<IncomingGroupCallPage> createState() => _IncomingGroupCallPageState();
}

class _IncomingGroupCallPageState extends State<IncomingGroupCallPage>
    with TickerProviderStateMixin {
  final _service = GroupCallService.instance;

  StreamSubscription? _callSub;
  Timer? _countdownTimer;
  int _countdown = 30;

  late AnimationController _rippleCtrl;
  late AnimationController _pulseCtrl;
  late AnimationController _slideInCtrl;
  late AnimationController _glowCtrl;

  late Animation<double> _ripple;
  late Animation<double> _pulse;
  late Animation<Offset> _slideIn;
  late Animation<double> _fadeIn;
  late Animation<double> _glow;

  bool _isAccepting = false;
  bool _isDeclining = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );
    _setupAnimations();
    _watchCallStatus();
    _startCountdown();
    _triggerHaptic();
  }

  void _setupAnimations() {
    _rippleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _slideInCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();

    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _ripple = CurvedAnimation(parent: _rippleCtrl, curve: Curves.easeOut);
    _pulse = Tween<double>(begin: 0.96, end: 1.04)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _slideIn = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _slideInCtrl, curve: Curves.elasticOut));
    _fadeIn = CurvedAnimation(parent: _slideInCtrl, curve: Curves.easeIn);
    _glow = Tween<double>(begin: 0.3, end: 0.7)
        .animate(CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut));
  }

  void _triggerHaptic() {
    HapticFeedback.vibrate();
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) HapticFeedback.vibrate();
    });
  }

  void _watchCallStatus() {
    _callSub = _service.watchCall(widget.call.callId).listen((call) {
      if (!mounted || call == null) return;
      if (call.status == GroupCallStatus.ended) _dismissSilently();
    });
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _countdown--);
      if (_countdown <= 0) {
        _countdownTimer?.cancel();
        _decline();
      }
    });
  }

  void _dismissSilently() {
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _accept() async {
    if (_isAccepting) return;
    setState(() => _isAccepting = true);
    _countdownTimer?.cancel();
    HapticFeedback.mediumImpact();

    final ok = await _service.joinCall(widget.call.callId);
    if (!ok || !mounted) {
      _dismissSilently();
      return;
    }
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, __, ___) => GroupCallPage(
          call: widget.call,
          isInitiator: false,
          currentUserId: widget.currentUserId,
          currentUserName: widget.currentUserName,
          currentUserAvatar: widget.currentUserAvatar,
        ),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: anim,
          child: child,
        ),
      ),
    );
  }

  Future<void> _decline() async {
    if (_isDeclining) return;
    setState(() => _isDeclining = true);
    _countdownTimer?.cancel();
    HapticFeedback.lightImpact();
    await _service.declineCall(widget.call.callId);
    _dismissSilently();
  }

  @override
  void dispose() {
    _rippleCtrl.dispose();
    _pulseCtrl.dispose();
    _slideInCtrl.dispose();
    _glowCtrl.dispose();
    _callSub?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SlideTransition(
        position: _slideIn,
        child: FadeTransition(
          opacity: _fadeIn,
          child: _buildBackground(),
        ),
      ),
    );
  }

  Widget _buildBackground() {
    final isVideo = widget.call.isVideo;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isVideo
              ? [
                  const Color(0xFF0d1b3e),
                  const Color(0xFF122463),
                  const Color(0xFF0d1b3e),
                ]
              : [
                  const Color(0xFF0a2e1a),
                  const Color(0xFF124d2a),
                  const Color(0xFF0a2e1a),
                ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildBackgroundBlobs(isVideo),
          SafeArea(child: _buildContent(isVideo)),
        ],
      ),
    );
  }

  Widget _buildBackgroundBlobs(bool isVideo) {
    return AnimatedBuilder(
      animation: _glowCtrl,
      builder: (_, __) {
        return CustomPaint(
          painter: _BlobPainter(
            opacity: _glow.value,
            isVideo: isVideo,
          ),
        );
      },
    );
  }

  Widget _buildContent(bool isVideo) {
    return Column(
      children: [
        const SizedBox(height: 20),
        _buildCallTypeBadge(isVideo),
        const Spacer(flex: 2),
        _buildAvatarSection(isVideo),
        const SizedBox(height: 28),
        _buildGroupInfo(isVideo),
        const Spacer(flex: 1),
        if (_shouldShowParticipants) _buildParticipantsPreview(),
        const Spacer(flex: 2),
        _buildActionButtons(isVideo),
        const SizedBox(height: 32),
      ],
    );
  }

  bool get _shouldShowParticipants =>
      widget.call.participants.isNotEmpty && widget.call.participants.length > 1;

  Widget _buildCallTypeBadge(bool isVideo) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isVideo ? Icons.videocam_rounded : Icons.phone_rounded,
            color: Colors.white,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            isVideo ? 'Cuộc gọi video nhóm' : 'Cuộc gọi thoại nhóm',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarSection(bool isVideo) {
    return SizedBox(
      width: 240,
      height: 240,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ...List.generate(3, (i) {
            return AnimatedBuilder(
              animation: _ripple,
              builder: (_, __) {
                final delay = i / 3.0;
                final progress = (_ripple.value + delay) % 1.0;
                final scale = 0.55 + progress * 0.75;
                final opacity = (1.0 - progress).clamp(0.0, 0.5);

                return Opacity(
                  opacity: opacity,
                  child: Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 240,
                      height: 240,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isVideo
                              ? const Color(0xFF60A5FA).withValues(alpha: 0.6)
                              : const Color(0xFF4ADE80).withValues(alpha: 0.6),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          }),
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, child) => Transform.scale(scale: _pulse.value, child: child),
            child: _buildAvatar(),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    final avatarUrl = widget.call.groupAvatarUrl;
    return Container(
      width: 116,
      height: 116,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipOval(
        child: avatarUrl.isNotEmpty
            ? Image.network(avatarUrl, fit: BoxFit.cover)
            : Container(
                color: const Color(0xFF334155),
                child: const Icon(Icons.group, size: 52, color: Colors.white),
              ),
      ),
    );
  }

  Widget _buildGroupInfo(bool isVideo) {
    return Column(
      children: [
        Text(
          widget.call.groupName,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 30,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          '${widget.call.initiatorName} đang gọi cho nhóm…',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 15,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 14),
        _buildCountdownBadge(),
      ],
    );
  }

  Widget _buildCountdownBadge() {
    final fraction = _countdown / 30.0;
    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: 52,
          height: 52,
          child: CircularProgressIndicator(
            value: fraction,
            strokeWidth: 2.5,
            backgroundColor: Colors.white.withValues(alpha: 0.1),
            valueColor: AlwaysStoppedAnimation(Colors.white.withValues(alpha: 0.6)),
          ),
        ),
        Text(
          '$_countdown',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildParticipantsPreview() {
    final shown = widget.call.participants.take(4).toList();
    final extra = widget.call.participants.length > 4 ? widget.call.participants.length - 4 : 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Text(
            '${widget.call.participants.length} người đang trong cuộc gọi',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ...shown.asMap().entries.map((entry) {
                final i = entry.key;
                final p = entry.value;
                return Transform.translate(
                  offset: Offset(-i * 10.0, 0),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF1e293b), width: 2),
                    ),
                    child: CircleAvatar(
                      radius: 18,
                      backgroundImage: p.userAvatar.isNotEmpty ? NetworkImage(p.userAvatar) : null,
                      backgroundColor: const Color(0xFF475569),
                      child: p.userAvatar.isEmpty
                          ? const Icon(Icons.person, size: 16, color: Colors.white54)
                          : null,
                    ),
                  ),
                );
              }),
              if (extra > 0)
                Transform.translate(
                  offset: Offset(-shown.length * 10.0, 0),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF1e293b), width: 2),
                    ),
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: const Color(0xFF334155),
                      child: Text(
                        '+$extra',
                        style: const TextStyle(color: Colors.white, fontSize: 10),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(bool isVideo) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 56),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _actionButton(
            icon: Icons.call_end_rounded,
            label: 'Từ chối',
            color: const Color(0xFFEF4444),
            loading: _isDeclining,
            onTap: _decline,
          ),
          _actionButton(
            icon: isVideo ? Icons.videocam_rounded : Icons.call_rounded,
            label: 'Tham gia',
            color: const Color(0xFF22C55E),
            loading: _isAccepting,
            onTap: _accept,
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required bool loading,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: loading ? color.withValues(alpha: 0.6) : color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.45),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: loading
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : Icon(icon, color: Colors.white, size: 30),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _BlobPainter extends CustomPainter {
  final double opacity;
  final bool isVideo;

  _BlobPainter({required this.opacity, required this.isVideo});

  @override
  void paint(Canvas canvas, Size size) {
    final baseColor = isVideo ? const Color(0xFF3B82F6) : const Color(0xFF22C55E);

    final paint = Paint()
      ..color = baseColor.withValues(alpha: opacity * 0.08)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 80);

    canvas.drawCircle(
      Offset(size.width * 0.15, size.height * 0.2),
      size.width * 0.45,
      paint,
    );

    canvas.drawCircle(
      Offset(size.width * 0.85, size.height * 0.78),
      size.width * 0.5,
      paint..color = baseColor.withValues(alpha: opacity * 0.06),
    );
  }

  @override
  bool shouldRepaint(_BlobPainter old) => old.opacity != opacity || old.isVideo != isVideo;
}
