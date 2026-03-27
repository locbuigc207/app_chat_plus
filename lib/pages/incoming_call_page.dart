// lib/pages/incoming_call_page.dart
import 'dart:async';

import 'package:flutter/material.dart';

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
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isVideo
                ? const [Color(0xFF1a1a2e), Color(0xFF16213e), Color(0xFF0f3460)]
                : const [Color(0xFF1b5e20), Color(0xFF2e7d32), Color(0xFF1b5e20)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 20),

              // Call type badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(isVideo ? Icons.videocam : Icons.phone,
                        color: Colors.white, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      isVideo ? 'Cuộc gọi video đến' : 'Cuộc gọi thoại đến',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Avatar với ripple animation
              Stack(
                alignment: Alignment.center,
                children: [
                  // Ripple rings
                  ...List.generate(3, (i) {
                    return AnimatedBuilder(
                      animation: _rippleController,
                      builder: (_, __) {
                        final progress = (_rippleController.value + (i * 0.33)) % 1.0;
                        return Opacity(
                          opacity: (1.0 - progress).clamp(0, 1),
                          child: Container(
                            width: 90 + (progress * 100),
                            height: 90 + (progress * 100),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withOpacity(0.4),
                                width: 2,
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
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withOpacity(0.3),
                            blurRadius: 20,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: callerAvatar.isNotEmpty
                            ? Image.network(callerAvatar, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _defaultAvatar(callerName))
                            : _defaultAvatar(callerName),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // Caller name
              Text(
                callerName,
                style: const TextStyle(
                    color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                isVideo ? 'Cuộc gọi Video' : 'Cuộc gọi Thoại',
                style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 16),
              ),
              const SizedBox(height: 12),

              // Countdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Tự động bỏ qua sau ${_secondsRemaining}s',
                  style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
                ),
              ),

              const Spacer(),

              // Action buttons
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Từ chối
                    _CallActionButton(
                      icon: Icons.call_end,
                      label: 'Từ chối',
                      backgroundColor: const Color(0xFFE53935),
                      onTap: _declineCall,
                    ),

                    // Chấp nhận
                    _CallActionButton(
                      icon: isVideo ? Icons.videocam : Icons.call,
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
      ),
    );
  }

  Widget _defaultAvatar(String name) {
    return Container(
      color: Colors.blueGrey[700],
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(
              color: Colors.white, fontSize: 42, fontWeight: FontWeight.bold),
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
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: backgroundColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: backgroundColor.withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
        ),
        const SizedBox(height: 10),
        Text(label,
            style: const TextStyle(
                color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
      ],
    );
  }
}