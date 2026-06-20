import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/group_call_model.dart';
import '../services/group_call_service.dart';
import 'group_call_page.dart';
import 'group_call_waiting_room.dart';

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
  int _countdown = 45;

  // ── Animation controllers ──────────────────────────────────────────────────
  late AnimationController _rippleCtrl;
  late AnimationController _pulseCtrl;
  late AnimationController _slideCtrl;
  late AnimationController _glowCtrl;
  late AnimationController _acceptCtrl;
  late AnimationController _declineCtrl;
  late AnimationController _particleCtrl;
  late AnimationController _rotateCtrl;

  late Animation<double> _rippleAnim;
  late Animation<double> _pulseAnim;
  late Animation<Offset> _slideAnim;
  late Animation<double> _fadeAnim;
  late Animation<double> _glowAnim;
  late Animation<double> _acceptScaleAnim;
  late Animation<double> _declineScaleAnim;
  late Animation<double> _particleAnim;
  late Animation<double> _rotateAnim;

  bool _isAccepting = false;
  bool _isDeclining = false;

  // Particle positions for background
  final List<_Particle> _particles = [];
  final _random = math.Random();

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
    ));
    _generateParticles();
    _setupAnimations();
    _watchCallStatus();
    _startCountdown();
    _triggerHaptic();
  }

  void _generateParticles() {
    for (int i = 0; i < 18; i++) {
      _particles.add(_Particle(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        size: 2 + _random.nextDouble() * 4,
        opacity: 0.15 + _random.nextDouble() * 0.35,
        speed: 0.3 + _random.nextDouble() * 0.7,
        angle: _random.nextDouble() * 2 * math.pi,
      ));
    }
  }

  void _setupAnimations() {
    _rippleCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2400))
      ..repeat();

    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat(reverse: true);

    _slideCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..forward();

    _glowCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat(reverse: true);

    _acceptCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 100));

    _declineCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 100));

    _particleCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 8))
      ..repeat();

    _rotateCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 20))
      ..repeat();

    _rippleAnim = CurvedAnimation(parent: _rippleCtrl, curve: Curves.easeOut);
    _pulseAnim = Tween<double>(begin: 0.94, end: 1.06)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _slideAnim = Tween<Offset>(begin: const Offset(0, 1.2), end: Offset.zero)
        .animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.elasticOut));
    _fadeAnim = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _slideCtrl, curve: const Interval(0, 0.4)));
    _glowAnim = Tween<double>(begin: 0.2, end: 0.75)
        .animate(CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut));
    _acceptScaleAnim = Tween<double>(begin: 1.0, end: 0.88)
        .animate(CurvedAnimation(parent: _acceptCtrl, curve: Curves.easeOut));
    _declineScaleAnim = Tween<double>(begin: 1.0, end: 0.88)
        .animate(CurvedAnimation(parent: _declineCtrl, curve: Curves.easeOut));
    _particleAnim = CurvedAnimation(parent: _particleCtrl, curve: Curves.linear);
    _rotateAnim = Tween<double>(begin: 0, end: 2 * math.pi)
        .animate(CurvedAnimation(parent: _rotateCtrl, curve: Curves.linear));
  }

  void _triggerHaptic() {
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) HapticFeedback.mediumImpact();
    });
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) HapticFeedback.lightImpact();
    });
  }

  void _watchCallStatus() {
    _callSub = _service.watchCall(widget.call.callId).listen((call) {
      if (!mounted || call == null) return;
      if (call.isEnded || call.status == GroupCallStatus.missed) {
        _dismissSilently();
      }
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
    if (_isAccepting || _isDeclining) return;
    setState(() => _isAccepting = true);
    _countdownTimer?.cancel();

    await _acceptCtrl.forward();
    HapticFeedback.mediumImpact();

    final ok = await _service.joinCall(widget.call.callId);

    // [FIX 5]: Chuyển hướng người dùng bị đẩy vào phòng chờ thay vì silent dismiss
    if (!ok || !mounted) {
      final updatedCall = await _service.getCall(widget.call.callId);
      if (updatedCall?.waitingRoomUserIds.contains(widget.currentUserId) == true && mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 400),
            pageBuilder: (_, __, ___) => GroupCallWaitingRoomPage(
              call: updatedCall!,
              currentUserId: widget.currentUserId,
            ),
            transitionsBuilder: (_, anim, __, child) => FadeTransition(
              opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
              child: child,
            ),
          ),
        );
      } else {
        _dismissSilently();
      }
      return;
    }

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (_, __, ___) => GroupCallPage(
          call: widget.call,
          isInitiator: false,
          currentUserId: widget.currentUserId,
          currentUserName: widget.currentUserName,
          currentUserAvatar: widget.currentUserAvatar,
        ),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween(begin: 0.95, end: 1.0)
                .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
            child: child,
          ),
        ),
      ),
    );
  }

  Future<void> _decline() async {
    if (_isDeclining || _isAccepting) return;
    setState(() => _isDeclining = true);
    _countdownTimer?.cancel();
    await _declineCtrl.forward();
    HapticFeedback.lightImpact();
    await _service.declineCall(widget.call.callId);
    _dismissSilently();
  }

  @override
  void dispose() {
    _rippleCtrl.dispose();
    _pulseCtrl.dispose();
    _slideCtrl.dispose();
    _glowCtrl.dispose();
    _acceptCtrl.dispose();
    _declineCtrl.dispose();
    _particleCtrl.dispose();
    _rotateCtrl.dispose();
    _callSub?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  // ── Colors by call type ──────────────────────────────────────────────────
  Color get _primaryColor => widget.call.isVideo
      ? const Color(0xFF3B82F6)
      : const Color(0xFF22C55E);

  Color get _primaryDark => widget.call.isVideo
      ? const Color(0xFF1D4ED8)
      : const Color(0xFF15803D);

  Color get _bgStart => widget.call.isVideo
      ? const Color(0xFF060D1F)
      : const Color(0xFF041A0D);

  Color get _bgEnd => widget.call.isVideo
      ? const Color(0xFF0F1E3D)
      : const Color(0xFF0A2A14);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgStart,
      body: SlideTransition(
        position: _slideAnim,
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Animated background
              _buildBackground(),

              // Particle field
              _buildParticleField(),

              // Rotating ring decoration
              _buildRotatingRing(),

              // Main content
              SafeArea(child: _buildContent()),
            ],
          ),
        ),
      ),
    );
  }

  // ── Background ─────────────────────────────────────────────────────────────
  Widget _buildBackground() {
    return AnimatedBuilder(
      animation: _glowAnim,
      builder: (_, __) => CustomPaint(
        painter: _BackgroundPainter(
          color: _primaryColor,
          glowOpacity: _glowAnim.value,
        ),
      ),
    );
  }

  Widget _buildParticleField() {
    return AnimatedBuilder(
      animation: _particleAnim,
      builder: (_, __) {
        return CustomPaint(
          painter: _ParticlePainter(
            particles: _particles,
            progress: _particleAnim.value,
            color: _primaryColor,
          ),
        );
      },
    );
  }

  Widget _buildRotatingRing() {
    return Center(
      child: AnimatedBuilder(
        animation: _rotateAnim,
        builder: (_, child) => Transform.rotate(
          angle: _rotateAnim.value,
          child: child,
        ),
        child: Container(
          width: 340,
          height: 340,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: _primaryColor.withValues(alpha: 0.06),
              width: 1,
            ),
          ),
        ),
      ),
    );
  }

  // ── Content ────────────────────────────────────────────────────────────────
  Widget _buildContent() {
    return Column(
      children: [
        const SizedBox(height: 20),
        _buildCallTypeBadge(),
        const Spacer(flex: 2),
        _buildAvatarSection(),
        const SizedBox(height: 28),
        _buildCallInfo(),
        const Spacer(flex: 1),
        if (_shouldShowParticipants) _buildParticipantsRow(),
        const Spacer(flex: 2),
        _buildActionButtons(),
        const SizedBox(height: 40),
      ],
    );
  }

  bool get _shouldShowParticipants =>
      widget.call.participants.isNotEmpty &&
          widget.call.participants.length > 1;

  // ── Call type badge ────────────────────────────────────────────────────────
  Widget _buildCallTypeBadge() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          decoration: BoxDecoration(
            color: _primaryColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: _primaryColor.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _primaryColor,
                  boxShadow: [
                    BoxShadow(
                        color: _primaryColor.withValues(alpha: 0.6),
                        blurRadius: 6,
                        spreadRadius: 1),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                widget.call.isVideo
                    ? Icons.videocam_rounded
                    : Icons.phone_rounded,
                color: _primaryColor,
                size: 16,
              ),
              const SizedBox(width: 7),
              Text(
                widget.call.isVideo
                    ? 'Cuộc gọi video nhóm'
                    : 'Cuộc gọi thoại nhóm',
                style: TextStyle(
                  color: _primaryColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Avatar section with ripple ─────────────────────────────────────────────
  Widget _buildAvatarSection() {
    return SizedBox(
      width: 260,
      height: 260,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Multiple ripple rings
          ...List.generate(4, (i) {
            return AnimatedBuilder(
              animation: _rippleAnim,
              builder: (_, __) {
                final delay = i / 4.0;
                final progress = (_rippleAnim.value + delay) % 1.0;
                final scale = 0.4 + progress * 0.95;
                final opacity = (1.0 - progress).clamp(0.0, 0.45);

                return Opacity(
                  opacity: opacity,
                  child: Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 260,
                      height: 260,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _primaryColor,
                          width: 2 - i * 0.3,
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          }),

          // Glow behind avatar
          AnimatedBuilder(
            animation: _glowAnim,
            builder: (_, child) => Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _primaryColor.withValues(alpha: _glowAnim.value * 0.5),
                    blurRadius: 60,
                    spreadRadius: 20,
                  ),
                ],
              ),
              child: child,
            ),
            child: const SizedBox.shrink(),
          ),

          // Pulsing avatar
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, child) =>
                Transform.scale(scale: _pulseAnim.value, child: child),
            child: _buildAvatar(),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    final avatarUrl = widget.call.groupAvatarUrl;
    return Container(
      width: 124,
      height: 124,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipOval(
        child: avatarUrl.isNotEmpty
            ? Image.network(avatarUrl, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildAvatarFallback())
            : _buildAvatarFallback(),
      ),
    );
  }

  Widget _buildAvatarFallback() {
    return Container(
      color: const Color(0xFF1E2D40),
      child: Icon(Icons.group_rounded, size: 54, color: Colors.white.withValues(alpha: 0.6)),
    );
  }

  // ── Call info ──────────────────────────────────────────────────────────────
  Widget _buildCallInfo() {
    return Column(
      children: [
        Text(
          widget.call.groupName,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            children: [
              TextSpan(
                text: widget.call.initiatorName,
                style: TextStyle(
                  color: _primaryColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const TextSpan(
                text: ' đang gọi cho nhóm',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Countdown
        _buildCountdown(),
      ],
    );
  }

  Widget _buildCountdown() {
    final fraction = _countdown / 45.0;
    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: 58,
          height: 58,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 1.0, end: fraction.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 800),
            builder: (_, v, __) => CircularProgressIndicator(
              value: v,
              strokeWidth: 2.5,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation(
                _countdown > 15
                    ? _primaryColor.withValues(alpha: 0.7)
                    : _CallColors.accentRed.withValues(alpha: 0.8),
              ),
            ),
          ),
        ),
        Text(
          '$_countdown',
          style: TextStyle(
            color: _countdown > 15
                ? Colors.white.withValues(alpha: 0.8)
                : _CallColors.accentRed,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  // ── Participants preview ───────────────────────────────────────────────────
  Widget _buildParticipantsRow() {
    final shown = widget.call.participants.take(5).toList();
    final extra = widget.call.participants.length > 5
        ? widget.call.participants.length - 5
        : 0;

    return Column(
      children: [
        Text(
          '${widget.call.participants.length} người đang trong cuộc gọi',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 44,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              ...shown.asMap().entries.map((entry) {
                final i = entry.key;
                final p = entry.value;
                return Positioned(
                  left: i * 30.0,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _bgStart,
                        width: 2.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 20,
                      backgroundImage: p.userAvatar.isNotEmpty
                          ? NetworkImage(p.userAvatar)
                          : null,
                      backgroundColor: const Color(0xFF334155),
                      child: p.userAvatar.isEmpty
                          ? Text(
                        p.userName.isNotEmpty
                            ? p.userName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700),
                      )
                          : null,
                    ),
                  ),
                );
              }),
              if (extra > 0)
                Positioned(
                  left: shown.length * 30.0,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: _bgStart, width: 2.5),
                    ),
                    child: CircleAvatar(
                      radius: 20,
                      backgroundColor: _primaryColor.withValues(alpha: 0.3),
                      child: Text(
                        '+$extra',
                        style: TextStyle(
                          color: _primaryColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Action buttons ─────────────────────────────────────────────────────────
  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 60),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Decline
          _buildActionBtn(
            icon: Icons.call_end_rounded,
            label: 'Từ chối',
            color: const Color(0xFFEF4444),
            isLoading: _isDeclining,
            scaleAnim: _declineScaleAnim,
            onTap: _decline,
          ),

          // Accept
          _buildActionBtn(
            icon: widget.call.isVideo
                ? Icons.videocam_rounded
                : Icons.phone_rounded,
            label: 'Tham gia',
            color: _primaryColor,
            isLoading: _isAccepting,
            scaleAnim: _acceptScaleAnim,
            onTap: _accept,
          ),
        ],
      ),
    );
  }

  Widget _buildActionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required bool isLoading,
    required Animation<double> scaleAnim,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTapDown: (_) {
        if (!isLoading) {
          if (label == 'Từ chối') _declineCtrl.forward();
          if (label == 'Tham gia') _acceptCtrl.forward();
        }
      },
      onTapUp: (_) {
        _declineCtrl.reverse();
        _acceptCtrl.reverse();
        if (!isLoading) onTap();
      },
      onTapCancel: () {
        _declineCtrl.reverse();
        _acceptCtrl.reverse();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: scaleAnim,
            builder: (_, child) =>
                Transform.scale(scale: scaleAnim.value, child: child),
            child: AnimatedBuilder(
              animation: _glowAnim,
              builder: (_, child) => Container(
                width: 78,
                height: 78,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.4 + _glowAnim.value * 0.2),
                      blurRadius: 28,
                      spreadRadius: 4,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: isLoading
                    ? const Padding(
                  padding: EdgeInsets.all(22),
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                )
                    : Icon(icon, color: Colors.white, size: 32),
              ),
            ),
          ),
          const SizedBox(height: 14),
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

// ─── CallColors alias ──────────────────────────────────────────────────────────
class _CallColors {
  static const accentRed = Color(0xFFEF4444);
}

// ─── Background painter ────────────────────────────────────────────────────────
class _BackgroundPainter extends CustomPainter {
  final Color color;
  final double glowOpacity;

  _BackgroundPainter({required this.color, required this.glowOpacity});

  @override
  void paint(Canvas canvas, Size size) {
    // Base dark gradient
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          color.withValues(alpha: 0.08),
          Colors.black,
          color.withValues(alpha: 0.05),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final blurPaint = Paint()
      ..color = color.withValues(alpha: glowOpacity * 0.1)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 120);

    canvas.drawCircle(
        Offset(size.width * 0.15, size.height * 0.18), size.width * 0.55,
        blurPaint);
    canvas.drawCircle(
        Offset(size.width * 0.85, size.height * 0.82), size.width * 0.6,
        blurPaint..color = color.withValues(alpha: glowOpacity * 0.07));
  }

  @override
  bool shouldRepaint(_BackgroundPainter old) =>
      old.glowOpacity != glowOpacity || old.color != color;
}

// ─── Particle painter ─────────────────────────────────────────────────────────
class _Particle {
  final double x;
  final double y;
  final double size;
  final double opacity;
  final double speed;
  final double angle;

  const _Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.opacity,
    required this.speed,
    required this.angle,
  });
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress;
  final Color color;

  _ParticlePainter({
    required this.particles,
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final t = (progress * p.speed) % 1.0;
      final dx = math.cos(p.angle) * t * size.width * 0.2;
      final dy = math.sin(p.angle) * t * size.height * 0.2;
      final cx = (p.x * size.width + dx) % size.width;
      final cy = (p.y * size.height + dy) % size.height;
      final fadeT = t < 0.5 ? t * 2 : (1 - t) * 2;

      final paint = Paint()
        ..color = color.withValues(alpha: p.opacity * fadeT.clamp(0.0, 1.0))
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(cx, cy), p.size * (0.5 + fadeT * 0.5), paint);
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => old.progress != progress;
}