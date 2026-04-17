// lib/pages/incoming_group_call_page.dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../models/group_call_model.dart';
import '../services/group_call_service.dart';
import 'group_call_page.dart';

class IncomingGroupCallPage extends StatefulWidget {
  final GroupCallModel call;
  final String currentUserId;

  const IncomingGroupCallPage({
    super.key,
    required this.call,
    required this.currentUserId,
  });

  @override
  State<IncomingGroupCallPage> createState() => _IncomingGroupCallPageState();
}

class _IncomingGroupCallPageState extends State<IncomingGroupCallPage>
    with TickerProviderStateMixin {
  final _service = GroupCallService();
  late AnimationController _pulseCtrl;
  late AnimationController _rippleCtrl;
  late Animation<double> _pulseAnim;
  late Animation<double> _rippleAnim;

  StreamSubscription? _callSub;
  int _countdown = 30;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _watchCallStatus();
    _startCountdown();
  }

  void _setupAnimations() {
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
    _rippleCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat();
    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05).animate(_pulseCtrl);
    _rippleAnim = Tween<double>(begin: 0.0, end: 1.0).animate(_rippleCtrl);
  }

  void _watchCallStatus() {
    _callSub = _service.watchCall(widget.call.callId).listen((call) {
      if (call == null || !mounted) return;
      if (call.status == GroupCallStatus.ended) _dismiss();
    });
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _countdown--);
      if (_countdown <= 0) {
        _countdownTimer?.cancel();
        _decline();
      }
    });
  }

  void _dismiss() {
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _accept() async {
    _countdownTimer?.cancel();
    final ok = await _service.joinCall(widget.call.callId);
    if (!ok || !mounted) {
      _dismiss();
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => GroupCallPage(
          call: widget.call,
          isInitiator: false,
        ),
      ),
    );
  }

  Future<void> _decline() async {
    _countdownTimer?.cancel();
    await _service.declineCall(widget.call.callId);
    _dismiss();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _rippleCtrl.dispose();
    _callSub?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.call.isVideo;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isVideo
                ? [
                    const Color(0xFF1a1a2e),
                    const Color(0xFF16213e),
                    const Color(0xFF0f3460)
                  ]
                : [
                    const Color(0xFF1b5e20),
                    const Color(0xFF2e7d32),
                    const Color(0xFF1b5e20)
                  ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 24),
              // Call type badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(isVideo ? Icons.videocam : Icons.phone,
                        color: Colors.white, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      isVideo
                          ? 'Incoming Group Video Call'
                          : 'Incoming Group Voice Call',
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Group avatar + ripple
              Stack(
                alignment: Alignment.center,
                children: [
                  ...List.generate(
                    3,
                    (i) => AnimatedBuilder(
                      animation: _rippleAnim,
                      builder: (_, __) {
                        final progress = (_rippleAnim.value + i * 0.33) % 1.0;
                        return Opacity(
                          opacity: (1.0 - progress).clamp(0, 1),
                          child: Container(
                            width: 100 + progress * 100,
                            height: 100 + progress * 100,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.white.withOpacity(0.35),
                                  width: 1.5),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _pulseAnim,
                    builder: (_, child) =>
                        Transform.scale(scale: _pulseAnim.value, child: child),
                    child: Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                      child: ClipOval(
                        child: Container(
                          color: Colors.blueGrey,
                          child: const Icon(Icons.group,
                              size: 60, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              // Group name
              Text(widget.call.groupName,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                '${widget.call.initiatorName} started a group ${isVideo ? 'video' : 'voice'} call',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.75), fontSize: 15),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12)),
                child: Text('Auto-dismiss in ${_countdown}s',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.7), fontSize: 12)),
              ),
              const Spacer(),
              // Buttons
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    // Decline
                    _callBtn(
                      icon: Icons.call_end,
                      label: 'Decline',
                      color: const Color(0xFFE53935),
                      onTap: _decline,
                    ),
                    // Accept
                    _callBtn(
                      icon: isVideo ? Icons.videocam : Icons.call,
                      label: 'Join',
                      color: const Color(0xFF43A047),
                      onTap: _accept,
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

  Widget _callBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: color.withOpacity(0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4))
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 30),
          ),
        ),
        const SizedBox(height: 10),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
      ],
    );
  }
}
