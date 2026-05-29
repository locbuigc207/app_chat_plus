import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/call_model.dart';
import '../services/call_service.dart';
import 'call_page.dart';





class OutgoingCallPage extends StatefulWidget {
  final CallModel call;

  const OutgoingCallPage({super.key, required this.call});

  @override
  State<OutgoingCallPage> createState() => _OutgoingCallPageState();
}

class _OutgoingCallPageState extends State<OutgoingCallPage> with TickerProviderStateMixin {
  final _callService = CallService.instance;
  StreamSubscription? _callStatusSub;
  bool _dismissed = false;

  late final AnimationController _waveController;
  late final AnimationController _entryController;
  late final Animation<double> _fadeIn;
  late final Animation<Offset> _slideUp;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();

    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _fadeIn = CurvedAnimation(parent: _entryController, curve: Curves.easeOut);

    _slideUp = Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entryController, curve: Curves.easeOutCubic));

    _entryController.forward();
    _watchCallStatus();
  }

  void _watchCallStatus() {
    _callStatusSub = _callService.watchCall(widget.call.callId).listen((call) {
      if (call == null || _dismissed || !mounted) return;

      switch (call.status) {
        case CallStatus.accepted:
        case CallStatus.connected:
          _callStatusSub?.cancel();
          _dismissed = true;
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => CallPage(call: call, isOutgoing: true),
            ),
          );
          break;
        case CallStatus.declined:
          _showEndDialog(
            'Bị từ chối',
            '${widget.call.calleeName} đã từ chối cuộc gọi.',
            Icons.call_end_rounded,
            Colors.orangeAccent,
          );
          break;
        case CallStatus.missed:
          _showEndDialog(
            'Không có phản hồi',
            '${widget.call.calleeName} không trả lời.',
            Icons.phone_missed_rounded,
            Colors.redAccent,
          );
          break;
        case CallStatus.failed:
          _showEndDialog(
            'Cuộc gọi thất bại',
            'Không thể kết nối. Vui lòng thử lại.',
            Icons.error_outline_rounded,
            Colors.grey,
          );
          break;
        default:
          break;
      }
    });
  }

  void _showEndDialog(String title, String message, IconData icon, Color color) {
    if (!mounted || _dismissed) return;
    _dismissed = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F36),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 10),
            Text(title,
                style: const TextStyle(
                    color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
          ],
        ),
        content: Text(message, style: const TextStyle(color: Colors.white70, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              if (mounted) {
                SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
                Navigator.of(context).pop();
              }
            },
            child: const Text('OK', style: TextStyle(color: Color(0xFF5C6BC0))),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelCall() async {
    if (_dismissed) return;
    _dismissed = true;
    HapticFeedback.mediumImpact();
    await _callService.endCall(widget.call.callId);
    if (mounted) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _dismissed = true;
    _waveController.dispose();
    _entryController.dispose();
    _callStatusSub?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.call.isVideoCall;
    final name = widget.call.calleeName;
    final avatar = widget.call.calleeAvatar;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancelCall();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            
            if (avatar.isNotEmpty)
              Image.network(avatar,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF0A0E1A))),
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: isVideo
                        ? const [Color(0xBB0D1B4B), Color(0xEE000000)]
                        : const [Color(0xBB0D3A8B), Color(0xEE000B2E)],
                  ),
                ),
              ),
            ),

            SafeArea(
              child: FadeTransition(
                opacity: _fadeIn,
                child: SlideTransition(
                  position: _slideUp,
                  child: Column(
                    children: [
                      const SizedBox(height: 20),

                      
                      _OutgoingBadge(isVideo: isVideo),

                      const Spacer(flex: 2),

                      
                      _AnimatedWaveAvatar(
                        controller: _waveController,
                        avatarUrl: avatar,
                        name: name,
                      ),
                      const SizedBox(height: 36),

                      
                      Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.8,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),

                      
                      _RingingDotsText(label: isVideo ? 'Đang gọi video' : 'Đang đổ chuông'),

                      const Spacer(flex: 2),

                      
                      Padding(
                        padding: const EdgeInsets.only(bottom: 60),
                        child: _CancelButton(onTap: _cancelCall),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}





class _OutgoingBadge extends StatelessWidget {
  final bool isVideo;
  const _OutgoingBadge({required this.isVideo});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isVideo ? Icons.videocam_rounded : Icons.phone_rounded,
            color: Colors.white70,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            isVideo ? 'Đang gọi video…' : 'Đang gọi thoại…',
            style:
                const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _AnimatedWaveAvatar extends StatelessWidget {
  final AnimationController controller;
  final String avatarUrl;
  final String name;

  const _AnimatedWaveAvatar({
    required this.controller,
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
            animation: controller,
            builder: (_, __) {
              final progress = (controller.value + (i * 0.33)) % 1.0;
              return Opacity(
                opacity: ((1.0 - progress) * 0.4).clamp(0, 1),
                child: Container(
                  width: 116 + (progress * 100),
                  height: 116 + (progress * 100),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1.5),
                  ),
                ),
              );
            },
          );
        }),
        Container(
          width: 114,
          height: 114,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 3),
            boxShadow: [
              BoxShadow(
                  color: const Color(0xFF1E88E5).withValues(alpha: 0.3),
                  blurRadius: 40,
                  spreadRadius: 8),
            ],
          ),
          child: ClipOval(
            child: avatarUrl.isNotEmpty
                ? Image.network(avatarUrl,
                    fit: BoxFit.cover, errorBuilder: (_, __, ___) => _defaultAvatar())
                : _defaultAvatar(),
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
          style: const TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class _CancelButton extends StatefulWidget {
  final VoidCallback onTap;
  const _CancelButton({required this.onTap});

  @override
  State<_CancelButton> createState() => _CancelButtonState();
}

class _CancelButtonState extends State<_CancelButton> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _scale = Tween<double>(begin: 1.0, end: 0.88)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaleTransition(
            scale: _scale,
            child: Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                color: const Color(0xFFE53935),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE53935).withValues(alpha: 0.45),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 32),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Huỷ',
            style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _RingingDotsText extends StatefulWidget {
  final String label;
  const _RingingDotsText({required this.label});

  @override
  State<_RingingDotsText> createState() => _RingingDotsTextState();
}

class _RingingDotsTextState extends State<_RingingDotsText> {
  int _dots = 0;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 600), (_) {
      if (mounted) setState(() => _dots = (_dots + 1) % 4);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      '${widget.label}${'.' * _dots}',
      style:
          TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 16, letterSpacing: 0.3),
    );
  }
}
