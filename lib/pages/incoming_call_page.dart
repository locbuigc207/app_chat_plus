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
const _kAccept = Color(0xFF34C759);
const _kDecline = Color(0xFFFF3B30);
const _kSurface = Color(0x1AFFFFFF);
const _kBorder = Color(0x33FFFFFF);
const _kTimeout = 30;

class IncomingCallPage extends StatefulWidget {
  final CallModel call;

  const IncomingCallPage({super.key, required this.call});

  @override
  State<IncomingCallPage> createState() => _IncomingCallPageState();
}

class _IncomingCallPageState extends State<IncomingCallPage>
    with TickerProviderStateMixin {
  final _callService = CallService.instance;

  // Animations
  late final AnimationController _entryCtrl;
  late final AnimationController _rippleCtrl;
  late final AnimationController _pulseCtrl;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _pulseAnim;

  StreamSubscription<CallModel?>? _statusSub;
  Timer? _countdownTimer;
  int _remaining = _kTimeout;
  bool _dismissed = false;
  bool _showQuickReply = false;
  double _swipeDy = 0;

  static const List<String> _quickReplies = [
    '📵  Không tiện nghe máy lúc này',
    '⏰  Gọi lại cho bạn sau nhé',
    '🏢  Đang họp, nhắn tin đi',
    '🚗  Đang lái xe, gọi lại sau',
  ];

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _entryCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 680));
    _slideAnim = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
        .animate(
            CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));
    _fadeAnim = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);

    _rippleCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2400))
      ..repeat();

    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _entryCtrl.forward();
    _startCountdown();
    _watchStatus();

    Future.delayed(const Duration(milliseconds: 400), () {
      HapticFeedback.heavyImpact();
    });
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _remaining--);
      if (_remaining <= 0) {
        t.cancel();
        _safeDismiss();
      }
    });
  }

  void _watchStatus() {
    _statusSub = _callService.watchCall(widget.call.callId).listen((c) {
      if (c == null || _dismissed) return;
      if (c.status == CallStatus.ended ||
          c.status == CallStatus.missed ||
          c.status == CallStatus.declined ||
          c.status == CallStatus.failed) {
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

  Future<void> _accept() async {
    if (_dismissed) return;
    HapticFeedback.heavyImpact();
    _countdownTimer?.cancel();
    _dismissed = true;
    await _callService.answerCall(widget.call.callId);
    if (!mounted) return;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => CallPage(
        call: widget.call.copyWith(status: CallStatus.connected),
        isOutgoing: false,
      ),
    ));
  }

  Future<void> _decline() async {
    if (_dismissed) return;
    HapticFeedback.mediumImpact();
    _countdownTimer?.cancel();
    await _callService.declineCall(widget.call.callId);
    _safeDismiss();
  }

  Future<void> _sendQuickReply(String msg) async {
    // TODO: Tích hợp với ChatService/ChatProvider để gửi tin nhắn nhanh trước khi từ chối
    await _decline();
  }

  @override
  void dispose() {
    _dismissed = true;
    _entryCtrl.dispose();
    _rippleCtrl.dispose();
    _pulseCtrl.dispose();
    _statusSub?.cancel();
    _countdownTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.call.callerName;
    final avatar = widget.call.callerAvatar;
    final isVid = widget.call.isVideoCall;

    return Scaffold(
      backgroundColor: _kBg,
      body: SlideTransition(
        position: _slideAnim,
        child: FadeTransition(
          opacity: _fadeAnim,
          child: GestureDetector(
            onVerticalDragUpdate: (d) {
              if (_showQuickReply) return;
              setState(() => _swipeDy += d.delta.dy);
            },
            onVerticalDragEnd: (_) {
              if (_swipeDy < -70)
                _accept();
              else if (_swipeDy > 70) _decline();
              setState(() => _swipeDy = 0);
            },
            child: Stack(fit: StackFit.expand, children: [
              _BackgroundLayer(avatarUrl: avatar),
              _ContentLayer(
                name: name,
                avatar: avatar,
                isVideo: isVid,
                rippleCtrl: _rippleCtrl,
                pulseAnim: _pulseAnim,
                remaining: _remaining,
                onAccept: _accept,
                onDecline: _decline,
                onQuickReply: () => setState(() => _showQuickReply = true),
              ),
              if (_showQuickReply)
                _QuickReplySheet(
                  replies: _quickReplies,
                  onSelect: _sendQuickReply,
                  onDismiss: () => setState(() => _showQuickReply = false),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════
// BACKGROUND LAYER
// ══════════════════════════════════════════════════════
class _BackgroundLayer extends StatelessWidget {
  final String avatarUrl;
  const _BackgroundLayer({required this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      if (avatarUrl.isNotEmpty)
        Image.network(avatarUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const ColoredBox(color: _kBg)),
      BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
        child: const SizedBox.expand(),
      ),
      Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xE6080C18),
              Color(0x66080C18),
              Color(0x66080C18),
              Color(0xF0080C18),
            ],
            stops: [0.0, 0.25, 0.65, 1.0],
          ),
        ),
      ),
    ]);
  }
}

// ══════════════════════════════════════════════════════
// MAIN CONTENT
// ══════════════════════════════════════════════════════
class _ContentLayer extends StatelessWidget {
  final String name, avatar;
  final bool isVideo;
  final AnimationController rippleCtrl;
  final Animation<double> pulseAnim;
  final int remaining;
  final VoidCallback onAccept, onDecline, onQuickReply;

  const _ContentLayer({
    required this.name,
    required this.avatar,
    required this.isVideo,
    required this.rippleCtrl,
    required this.pulseAnim,
    required this.remaining,
    required this.onAccept,
    required this.onDecline,
    required this.onQuickReply,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(children: [
        const SizedBox(height: 28),
        _IncomingBadge(isVideo: isVideo),
        const Spacer(flex: 3),
        ScaleTransition(
          scale: pulseAnim,
          child: _RippleAvatar(
            rippleCtrl: rippleCtrl,
            avatarUrl: avatar,
            name: name,
            size: 156,
            ringColor: _kAccept,
          ),
        ),
        const SizedBox(height: 36),
        Text(
          name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 36,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
            height: 1.1,
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 10),
        Text(
          isVideo
              ? '📹  Đang gọi video cho bạn…'
              : '📞  Đang gọi thoại cho bạn…',
          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 16),
        ),
        const SizedBox(height: 20),
        _CountdownRing(remaining: remaining, total: _kTimeout),
        const Spacer(flex: 3),
        _SwipeHint(),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _SideButton(
                icon: Icons.chat_bubble_outline_rounded,
                label: 'Nhắn tin',
                onTap: onQuickReply,
              ),
              _BigActionButton(
                icon: Icons.call_end_rounded,
                label: 'Từ chối',
                color: _kDecline,
                onTap: onDecline,
              ),
              _BigActionButton(
                icon: isVideo ? Icons.videocam_rounded : Icons.phone_rounded,
                label: 'Chấp nhận',
                color: _kAccept,
                onTap: onAccept,
              ),
              _SideButton(
                icon: Icons.alarm_add_rounded,
                label: 'Nhắc sau',
                onTap: onDecline,
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════
// RIPPLE AVATAR
// ══════════════════════════════════════════════════════
class _RippleAvatar extends StatelessWidget {
  final AnimationController rippleCtrl;
  final String avatarUrl, name;
  final double size;
  final Color ringColor;

  const _RippleAvatar({
    required this.rippleCtrl,
    required this.avatarUrl,
    required this.name,
    required this.size,
    required this.ringColor,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(alignment: Alignment.center, children: [
      ...List.generate(4, (i) {
        return AnimatedBuilder(
          animation: rippleCtrl,
          builder: (_, __) {
            final progress = (rippleCtrl.value + i * 0.25) % 1.0;
            final scale = 1.0 + progress * 0.9;
            final opacity = (1 - progress) * 0.45;
            return Transform.scale(
              scale: scale,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: ringColor.withOpacity(opacity),
                    width: 2,
                  ),
                ),
              ),
            );
          },
        );
      }),
      Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: ringColor.withOpacity(0.35),
              blurRadius: 40,
              spreadRadius: 10,
            ),
          ],
        ),
      ),
      Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.85), width: 3),
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

// ══════════════════════════════════════════════════════
// COMPONENTS
// ══════════════════════════════════════════════════════
class _DefaultAvatar extends StatelessWidget {
  final String name;
  final double size;
  const _DefaultAvatar({required this.name, required this.size});

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF3949AB), Color(0xFF1E88E5)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.4,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );
}

class _IncomingBadge extends StatelessWidget {
  final bool isVideo;
  const _IncomingBadge({required this.isVideo});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: _kSurface,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: _kBorder),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(
              isVideo ? Icons.videocam_rounded : Icons.phone_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              isVideo ? 'Cuộc gọi Video đến' : 'Cuộc gọi Thoại đến',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _CountdownRing extends StatelessWidget {
  final int remaining, total;
  const _CountdownRing({required this.remaining, required this.total});

  @override
  Widget build(BuildContext context) {
    final ratio = remaining / total;
    final color = ratio > 0.5
        ? Colors.white54
        : ratio > 0.25
            ? Colors.orangeAccent
            : _kDecline;

    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(alignment: Alignment.center, children: [
        CircularProgressIndicator(
          value: ratio,
          strokeWidth: 3,
          color: color,
          backgroundColor: Colors.white.withOpacity(0.12),
        ),
        Text(
          '$remaining',
          style: TextStyle(
            color: color,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ]),
    );
  }
}

class _SwipeHint extends StatefulWidget {
  @override
  State<_SwipeHint> createState() => _SwipeHintState();
}

class _SwipeHintState extends State<_SwipeHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _anim,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.keyboard_arrow_up_rounded,
              color: Colors.white38, size: 18),
          const SizedBox(width: 4),
          Text(
            'Vuốt lên để nghe  ·  Vuốt xuống để từ chối',
            style:
                TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 12),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.keyboard_arrow_down_rounded,
              color: Colors.white38, size: 18),
        ]),
      );
}

class _BigActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _BigActionButton(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  @override
  State<_BigActionButton> createState() => _BigActionButtonState();
}

class _BigActionButtonState extends State<_BigActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 90),
        reverseDuration: const Duration(milliseconds: 200));
    _scale = Tween<double>(begin: 1.0, end: 0.86)
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
        child: ScaleTransition(
          scale: _scale,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withOpacity(0.5),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(widget.icon, color: Colors.white, size: 34),
            ),
            const SizedBox(height: 12),
            Text(widget.label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
      );
}

class _SideButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SideButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: _kSurface,
                  shape: BoxShape.circle,
                  border: Border.all(color: _kBorder),
                ),
                child: Icon(icon, color: Colors.white70, size: 24),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(label,
              style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                  fontWeight: FontWeight.w500)),
        ]),
      );
}

// ══════════════════════════════════════════════════════
// QUICK REPLY SHEET
// ══════════════════════════════════════════════════════
class _QuickReplySheet extends StatelessWidget {
  final List<String> replies;
  final void Function(String) onSelect;
  final VoidCallback onDismiss;

  const _QuickReplySheet({
    required this.replies,
    required this.onSelect,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onDismiss,
      child: Container(
        color: Colors.black54,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {}, // Ngăn việc đóng modal khi nhấn vào bên trong sheet
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(32)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Color(0xE6080C18),
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(32)),
                    border: Border(
                      top: BorderSide(color: _kBorder),
                      left: BorderSide(color: _kBorder),
                      right: BorderSide(color: _kBorder),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(top: 14, bottom: 18),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const Text('Tin nhắn nhanh',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 16),
                      ...replies.map((r) => ListTile(
                            onTap: () => onSelect(r),
                            leading: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: _kSurface,
                                shape: BoxShape.circle,
                                border: Border.all(color: _kBorder),
                              ),
                              child: const Icon(Icons.send_rounded,
                                  color: Colors.white70, size: 20),
                            ),
                            title: Text(r,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 15)),
                          )),
                      const SizedBox(height: 8),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
