import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/call_model.dart';
import '../services/call_service.dart';
import 'call_page.dart';

// ══════════════════════════════════════════════════════
// DESIGN TOKENS
// ══════════════════════════════════════════════════════
const _kBg = Color(0xFF080C18);
const _kDecline = Color(0xFFFF3B30);
const _kSurface = Color(0x1AFFFFFF);
const _kBorder = Color(0x33FFFFFF);

class OutgoingCallPage extends StatefulWidget {
  final CallModel call;

  const OutgoingCallPage({super.key, required this.call});

  @override
  State<OutgoingCallPage> createState() => _OutgoingCallPageState();
}

class _OutgoingCallPageState extends State<OutgoingCallPage>
    with TickerProviderStateMixin {
  final _callService = CallService.instance;

  late final AnimationController _entryCtrl;
  late final AnimationController _waveCtrl;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _pulseAnim;

  StreamSubscription<CallModel?>? _statusSub;
  bool _dismissed = false;
  String _statusText = 'Đang gọi';

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _entryCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _fadeAnim = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero)
        .animate(
            CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));

    _waveCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2200))
      ..repeat();

    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.97, end: 1.03)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _entryCtrl.forward();
    _watchStatus();
  }

  void _watchStatus() {
    _statusSub = _callService.watchCall(widget.call.callId).listen((call) {
      if (call == null || _dismissed || !mounted) return;

      switch (call.status) {
        case CallStatus.ringing:
          setState(() => _statusText = 'Đang đổ chuông');
          break;
        case CallStatus.accepted:
        case CallStatus.connected:
          _dismissed = true;
          _statusSub?.cancel();
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
          Navigator.of(context).pushReplacement(MaterialPageRoute(
            builder: (_) => CallPage(call: call, isOutgoing: true),
          ));
          break;
        case CallStatus.declined:
          _showEndInfo(
              'Bị từ chối 😔',
              '${widget.call.calleeName} đã từ chối cuộc gọi.',
              Icons.call_end_rounded,
              _kDecline);
          break;
        case CallStatus.missed:
          _showEndInfo(
              'Không có phản hồi',
              '${widget.call.calleeName} không trả lời.',
              Icons.phone_missed_rounded,
              Colors.orangeAccent);
          break;
        case CallStatus.failed:
          _showEndInfo(
              'Cuộc gọi thất bại',
              'Không thể kết nối. Vui lòng thử lại.',
              Icons.error_outline_rounded,
              Colors.grey);
          break;
        default:
          break;
      }
    });
  }

  void _showEndInfo(String title, String msg, IconData icon, Color color) {
    if (!mounted || _dismissed) return;
    _dismissed = true;
    _waveCtrl.stop();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EndCallDialog(
        title: title,
        message: msg,
        icon: icon,
        color: color,
        onClose: () {
          Navigator.of(context).pop(); // Đóng dialog
          if (mounted) {
            SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
            Navigator.of(context).pop(); // Đóng page
          }
        },
      ),
    );
  }

  Future<void> _cancel() async {
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
    _entryCtrl.dispose();
    _waveCtrl.dispose();
    _pulseCtrl.dispose();
    _statusSub?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.call.calleeName;
    final avatar = widget.call.calleeAvatar;
    final isVid = widget.call.isVideoCall;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        backgroundColor: _kBg,
        body: Stack(fit: StackFit.expand, children: [
          // Background Layer
          _OutgoingBackground(avatarUrl: avatar, isVideo: isVid),

          // Content Layer
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: Column(children: [
                  const SizedBox(height: 24),
                  _OutgoingBadge(isVideo: isVid),
                  const Spacer(flex: 2),

                  // Animated Avatar
                  ScaleTransition(
                    scale: _pulseAnim,
                    child: _WaveAvatar(
                      waveCtrl: _waveCtrl,
                      avatarUrl: avatar,
                      name: name,
                      size: 144,
                    ),
                  ),
                  const SizedBox(height: 36),

                  // Caller Name
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.7,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),

                  // Status Text with dots
                  _AnimatedStatusText(status: _statusText),
                  const Spacer(flex: 3),

                  // Cancel Button
                  _CancelButton(onTap: _cancel),
                  const SizedBox(height: 40),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════
// COMPONENTS
// ══════════════════════════════════════════════════════

class _OutgoingBackground extends StatelessWidget {
  final String avatarUrl;
  final bool isVideo;

  const _OutgoingBackground({required this.avatarUrl, required this.isVideo});

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      if (avatarUrl.isNotEmpty)
        Image.network(avatarUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const ColoredBox(color: _kBg)),
      BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 72, sigmaY: 72),
        child: const SizedBox.expand(),
      ),
      Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isVideo
                ? const [
                    Color(0xE0080C18),
                    Color(0x55080C18),
                    Color(0x55080C18),
                    Color(0xF2080C18)
                  ]
                : const [
                    Color(0xCC0A1033),
                    Color(0x44080C18),
                    Color(0x44080C18),
                    Color(0xF0080018)
                  ],
            stops: const [0, 0.3, 0.65, 1],
          ),
        ),
      ),
    ]);
  }
}

class _OutgoingBadge extends StatelessWidget {
  final bool isVideo;
  const _OutgoingBadge({required this.isVideo});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          decoration: BoxDecoration(
            color: _kSurface,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: _kBorder),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(isVideo ? Icons.videocam_rounded : Icons.phone_rounded,
                color: Colors.white70, size: 17),
            const SizedBox(width: 8),
            Text(isVideo ? 'Đang gọi video…' : 'Đang gọi thoại…',
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
          ]),
        ),
      ),
    );
  }
}

class _WaveAvatar extends StatelessWidget {
  final AnimationController waveCtrl;
  final String avatarUrl, name;
  final double size;

  const _WaveAvatar(
      {required this.waveCtrl,
      required this.avatarUrl,
      required this.name,
      required this.size});

  @override
  Widget build(BuildContext context) {
    return Stack(alignment: Alignment.center, children: [
      // Wave Effect
      ...List.generate(4, (i) {
        return AnimatedBuilder(
          animation: waveCtrl,
          builder: (_, __) {
            final p = (waveCtrl.value + i * 0.25) % 1.0;
            return Opacity(
              opacity: ((1 - p) * 0.42).clamp(0, 1),
              child: Container(
                width: size + p * 90,
                height: size + p * 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF5C6BC0).withOpacity(0.7),
                    width: 1.8,
                  ),
                ),
              ),
            );
          },
        );
      }),

      // Glow Ring
      Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
                color: Color(0x553949AB), blurRadius: 36, spreadRadius: 8),
          ],
        ),
      ),

      // Avatar Content
      Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.8), width: 3),
        ),
        child: ClipOval(
          child: avatarUrl.isNotEmpty
              ? Image.network(avatarUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      _DefaultAvatar(name: name, size: size))
              : _DefaultAvatar(name: name, size: size),
        ),
      ),
    ]);
  }
}

class _DefaultAvatar extends StatelessWidget {
  final String name;
  final double size;
  const _DefaultAvatar({required this.name, required this.size});

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          gradient:
              LinearGradient(colors: [Color(0xFF3949AB), Color(0xFF1E88E5)]),
        ),
        child: Center(
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.38,
                fontWeight: FontWeight.w800),
          ),
        ),
      );
}

class _AnimatedStatusText extends StatefulWidget {
  final String status;
  const _AnimatedStatusText({required this.status});

  @override
  State<_AnimatedStatusText> createState() => _AnimatedStatusTextState();
}

class _AnimatedStatusTextState extends State<_AnimatedStatusText> {
  int _dots = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 550), (_) {
      if (mounted) setState(() => _dots = (_dots + 1) % 4);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
        '${widget.status}${'.' * _dots}',
        style: TextStyle(
          color: Colors.white.withOpacity(0.62),
          fontSize: 17,
          letterSpacing: 0.3,
          fontWeight: FontWeight.w400,
        ),
      );
}

class _CancelButton extends StatefulWidget {
  final VoidCallback onTap;
  const _CancelButton({required this.onTap});

  @override
  State<_CancelButton> createState() => _CancelButtonState();
}

class _CancelButtonState extends State<_CancelButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 100),
        reverseDuration: const Duration(milliseconds: 250));
    _scale = Tween<double>(begin: 1, end: 0.86)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTapDown: (_) => _ctrl.forward(),
        onTapUp: (_) {
          _ctrl.reverse();
          widget.onTap();
        },
        onTapCancel: () => _ctrl.reverse(),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ScaleTransition(
            scale: _scale,
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: _kDecline,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _kDecline.withOpacity(0.45),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(Icons.call_end_rounded,
                  color: Colors.white, size: 34),
            ),
          ),
          const SizedBox(height: 12),
          const Text('Huỷ cuộc gọi',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
        ]),
      );
}

class _EndCallDialog extends StatelessWidget {
  final String title, message;
  final IconData icon;
  final Color color;
  final VoidCallback onClose;

  const _EndCallDialog({
    required this.title,
    required this.message,
    required this.icon,
    required this.color,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: const Color(0xF0111827),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: _kBorder),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withOpacity(0.3), width: 2),
                ),
                child: Icon(icon, color: color, size: 34),
              ),
              const SizedBox(height: 20),
              Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Text(message,
                  style: const TextStyle(color: Colors.white60, fontSize: 15),
                  textAlign: TextAlign.center),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: onClose,
                  style: TextButton.styleFrom(
                    backgroundColor: _kSurface,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Đóng',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
