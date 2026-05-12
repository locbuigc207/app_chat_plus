// lib/pages/incoming_call_page.dart
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

class _IncomingCallPageState extends State<IncomingCallPage>
    with TickerProviderStateMixin {
  final _callService = CallService();

  late AnimationController _pulseController;
  late AnimationController _rippleController;
  late Animation<double> _pulseAnimation;

  StreamSubscription? _callStatusSub;
  int _secondsRemaining = 30;
  Timer? _countdownTimer;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

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
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _acceptCall() async {
    HapticFeedback.heavyImpact();
    _countdownTimer?.cancel();
    await _callService.answerCall(widget.call.callId);
    if (!mounted) return;

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
    _callStatusSub?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.call.isVideoCall;
    final callerName = widget.call.callerName;
    final callerAvatar = widget.call.callerAvatar;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Nền: Avatar phóng to blur mờ (Premium Look)
          if (callerAvatar.isNotEmpty)
            Image.network(callerAvatar, fit: BoxFit.cover),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
            child: Container(color: Colors.black.withOpacity(0.5)),
          ),

          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 24),

                // Huy hiệu loại cuộc gọi kiểu kính mờ (Glassmorphism)
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isVideo
                                ? Icons.videocam_rounded
                                : Icons.phone_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isVideo
                                ? 'Cuộc gọi Video đến'
                                : 'Cuộc gọi Thoại đến',
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
                ),

                const Spacer(),

                // Avatar với Ripple + Pulse animation
                Stack(
                  alignment: Alignment.center,
                  children: [
                    // Ripple rings
                    ...List.generate(3, (i) {
                      return AnimatedBuilder(
                        animation: _rippleController,
                        builder: (_, __) {
                          final progress =
                              (_rippleController.value + (i * 0.33)) % 1.0;
                          return Opacity(
                            opacity: (1.0 - progress).clamp(0, 1),
                            child: Container(
                              width: 120 + (progress * 140),
                              height: 120 + (progress * 140),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.5),
                                  width: 1.5,
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    }),

                    // Avatar với pulse
                    AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (_, child) => Transform.scale(
                        scale: _pulseAnimation.value,
                        child: child,
                      ),
                      child: Container(
                        width: 130,
                        height: 130,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withOpacity(0.2),
                              blurRadius: 30,
                              spreadRadius: 10,
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: callerAvatar.isNotEmpty
                              ? Image.network(
                                  callerAvatar,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      _defaultAvatar(callerName),
                                )
                              : _defaultAvatar(callerName),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 40),

                // Tên người gọi
                Text(
                  callerName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),

                // Đếm ngược tự động bỏ qua
                Text(
                  'Tự động bỏ qua sau ${_secondsRemaining}s',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 14,
                  ),
                ),

                const Spacer(),

                // Nút Chấp nhận / Từ chối
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 40, vertical: 48),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _CallActionButton(
                        icon: Icons.call_end_rounded,
                        label: 'Từ chối',
                        backgroundColor: const Color(0xFFFF3B30),
                        onTap: _declineCall,
                      ),
                      const SizedBox(width: 40),
                      _CallActionButton(
                        icon: isVideo
                            ? Icons.videocam_rounded
                            : Icons.phone_rounded,
                        label: 'Chấp nhận',
                        backgroundColor: const Color(0xFF34C759),
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
    );
  }

  Widget _defaultAvatar(String name) {
    return Container(
      color: Colors.blueGrey[800],
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 48,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _CallActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color backgroundColor;
  final VoidCallback onTap;

  const _CallActionButton({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: backgroundColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: backgroundColor.withOpacity(0.5),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 36),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
