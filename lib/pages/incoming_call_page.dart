import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/call_model.dart';
import '../services/call_service.dart';
import 'call_page.dart';





class IncomingCallPage extends StatefulWidget {
  final CallModel call;

  const IncomingCallPage({super.key, required this.call});

  @override
  State<IncomingCallPage> createState() => _IncomingCallPageState();
}

class _IncomingCallPageState extends State<IncomingCallPage> with TickerProviderStateMixin {
  final _callService = CallService.instance;

  late final AnimationController _pulseController;
  late final AnimationController _rippleController;
  late final AnimationController _slideController;
  late final Animation<double> _pulseAnimation;
  late final Animation<Offset> _slideAnimation;

  StreamSubscription? _callStatusSub;
  Timer? _countdownTimer;
  int _secondsRemaining = 30;
  bool _dismissed = false;

  
  final double _swipeProgress = 0.0; 
  final bool _swipeStarted = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _pulseAnimation = Tween<double>(begin: 0.94, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _slideAnimation = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic));

    _slideController.forward();
    _watchCallStatus();
    _startCountdown();
  }

  void _watchCallStatus() {
    _callStatusSub = _callService.watchCall(widget.call.callId).listen((call) {
      if (call == null || _dismissed) return;
      if (call.status == CallStatus.ended ||
          call.status == CallStatus.missed ||
          call.status == CallStatus.declined) {
        _safeDismiss();
      }
    });
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _secondsRemaining--);
      if (_secondsRemaining <= 0) {
        t.cancel();
        _safeDismiss();
      }
    });
  }

  void _safeDismiss() {
    if (_dismissed) return;
    _dismissed = true;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _acceptCall() async {
    HapticFeedback.heavyImpact();
    _countdownTimer?.cancel();
    await _callService.answerCall(widget.call.callId);
    if (!mounted) return;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => CallPage(
          call: widget.call.copyWith(status: CallStatus.connected),
          isOutgoing: false,
        ),
      ),
    );
  }

  Future<void> _declineCall() async {
    HapticFeedback.mediumImpact();
    _countdownTimer?.cancel();
    await _callService.declineCall(widget.call.callId);
    _safeDismiss();
  }

  @override
  void dispose() {
    _dismissed = true;
    _pulseController.dispose();
    _rippleController.dispose();
    _slideController.dispose();
    _callStatusSub?.cancel();
    _countdownTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.call.isVideoCall;
    final name = widget.call.callerName;
    final avatar = widget.call.callerAvatar;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SlideTransition(
        position: _slideAnimation,
        child: Stack(
          fit: StackFit.expand,
          children: [
            
            if (avatar.isNotEmpty)
              Image.network(avatar,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF0A0E1A))),
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 56, sigmaY: 56),
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xBB0D1B4B),
                      Color(0xEE000000),
                    ],
                  ),
                ),
              ),
            ),

            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 24),

                  
                  _CallTypeBadge(isVideo: isVideo),

                  const Spacer(),

                  
                  _RippleAvatar(
                    rippleController: _rippleController,
                    pulseAnimation: _pulseAnimation,
                    avatarUrl: avatar,
                    name: name,
                  ),
                  const SizedBox(height: 36),

                  
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),

                  
                  Text(
                    isVideo ? 'Đang gọi video cho bạn' : 'Đang gọi thoại cho bạn',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 15),
                  ),
                  const SizedBox(height: 12),

                  
                  _CountdownRing(seconds: _secondsRemaining, total: 30),

                  const Spacer(),

                  
                  Padding(
                    padding: const EdgeInsets.fromLTRB(40, 0, 40, 56),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _ActionButton(
                          icon: Icons.call_end_rounded,
                          label: 'Từ chối',
                          backgroundColor: const Color(0xFFE53935),
                          onTap: _declineCall,
                        ),
                        _ActionButton(
                          icon: isVideo ? Icons.videocam_rounded : Icons.phone_rounded,
                          label: 'Chấp nhận',
                          backgroundColor: const Color(0xFF43A047),
                          onTap: _acceptCall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}





class _CallTypeBadge extends StatelessWidget {
  final bool isVideo;
  const _CallTypeBadge({required this.isVideo});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isVideo ? Icons.videocam_rounded : Icons.phone_rounded,
                color: Colors.white,
                size: 17,
              ),
              const SizedBox(width: 8),
              Text(
                isVideo ? 'Cuộc gọi Video đến' : 'Cuộc gọi Thoại đến',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
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

class _RippleAvatar extends StatelessWidget {
  final AnimationController rippleController;
  final Animation<double> pulseAnimation;
  final String avatarUrl;
  final String name;

  const _RippleAvatar({
    required this.rippleController,
    required this.pulseAnimation,
    required this.avatarUrl,
    required this.name,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        
        ...List.generate(3, (i) {
          return AnimatedBuilder(
            animation: rippleController,
            builder: (_, __) {
              final progress = (rippleController.value + (i * 0.33)) % 1.0;
              return Opacity(
                opacity: ((1.0 - progress) * 0.5).clamp(0, 1),
                child: Container(
                  width: 130 + (progress * 160),
                  height: 130 + (progress * 160),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1.5),
                  ),
                ),
              );
            },
          );
        }),

        
        AnimatedBuilder(
          animation: pulseAnimation,
          builder: (_, child) => Transform.scale(scale: pulseAnimation.value, child: child),
          child: Container(
            width: 136,
            height: 136,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFF43A047).withValues(alpha: 0.35),
                    blurRadius: 40,
                    spreadRadius: 10),
              ],
              border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 3),
            ),
            child: ClipOval(
              child: avatarUrl.isNotEmpty
                  ? Image.network(avatarUrl,
                      fit: BoxFit.cover, errorBuilder: (_, __, ___) => _defaultAvatar())
                  : _defaultAvatar(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _defaultAvatar() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFF3949AB), Color(0xFF1E88E5)]),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(color: Colors.white, fontSize: 52, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class _CountdownRing extends StatelessWidget {
  final int seconds;
  final int total;

  const _CountdownRing({required this.seconds, required this.total});

  @override
  Widget build(BuildContext context) {
    final progress = seconds / total;
    final color = progress > 0.5
        ? Colors.white54
        : progress > 0.25
            ? Colors.orangeAccent
            : Colors.redAccent;

    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: progress,
            strokeWidth: 2.5,
            color: color,
            backgroundColor: Colors.white12,
          ),
          Text(
            '$seconds',
            style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color backgroundColor;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.onTap,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> with SingleTickerProviderStateMixin {
  late final AnimationController _pressController;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _pressController.forward(),
      onTapUp: (_) {
        _pressController.reverse();
        widget.onTap();
      },
      onTapCancel: () => _pressController.reverse(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaleTransition(
            scale: _scaleAnim,
            child: Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                color: widget.backgroundColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: widget.backgroundColor.withValues(alpha: 0.55),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(widget.icon, color: Colors.white, size: 36),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            widget.label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
