// ignore_for_file: deprecated_member_use
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─── Tokens ───────────────────────────────────────────────────────────────────
class _K {
  static const bg = Color(0xFF080E1C);
  static const surface = Color(0xFF111827);
  static const s2 = Color(0xFF1C2333);
  static const accent = Color(0xFF3B82F6);
  static const green = Color(0xFF22C55E);
  static const red = Color(0xFFEF4444);
  static const amber = Color(0xFFF59E0B);
  static const purple = Color(0xFF8B5CF6);
  static const text = Color(0xFFF8FAFC);
  static const sub = Color(0xFF94A3B8);
  static const muted = Color(0xFF475569);
}

// ══════════════════════════════════════════════════════════════════════════════
// FloatingCallControls
// Translucent pill-shaped control bar that floats above content.
// Used when controls are fading out — user can tap to reveal full controls.
// ══════════════════════════════════════════════════════════════════════════════
class FloatingCallControls extends StatefulWidget {
  final bool isMuted;
  final bool isCamOff;
  final bool isSpeakerOn;
  final bool isVideo;
  final VoidCallback onMicTap;
  final VoidCallback onCamTap;
  final VoidCallback onSpeakerTap;
  final VoidCallback onHangUp;
  final VoidCallback? onExpand;

  const FloatingCallControls({
    super.key,
    required this.isMuted,
    required this.isCamOff,
    required this.isSpeakerOn,
    required this.isVideo,
    required this.onMicTap,
    required this.onCamTap,
    required this.onSpeakerTap,
    required this.onHangUp,
    this.onExpand,
  });

  @override
  State<FloatingCallControls> createState() => _FloatingCallControlsState();
}

class _FloatingCallControlsState extends State<FloatingCallControls>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _scale = Tween<double>(begin: 0.85, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(
        scale: _scale,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(40),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.62),
                borderRadius: BorderRadius.circular(40),
                border:
                    Border.all(color: Colors.white.withOpacity(0.1), width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _pill(
                    icon: widget.isMuted
                        ? Icons.mic_off_rounded
                        : Icons.mic_rounded,
                    active: widget.isMuted,
                    activeColor: _K.red,
                    onTap: widget.onMicTap,
                  ),
                  if (widget.isVideo) ...[
                    const SizedBox(width: 6),
                    _pill(
                      icon: widget.isCamOff
                          ? Icons.videocam_off_rounded
                          : Icons.videocam_rounded,
                      active: widget.isCamOff,
                      activeColor: const Color(0xFFFF9F0A),
                      onTap: widget.onCamTap,
                    ),
                  ],
                  const SizedBox(width: 6),
                  _pill(
                    icon: widget.isSpeakerOn
                        ? Icons.volume_up_rounded
                        : Icons.hearing_rounded,
                    active: widget.isSpeakerOn,
                    activeColor: _K.accent,
                    onTap: widget.onSpeakerTap,
                  ),
                  const SizedBox(width: 10),
                  // End call
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      widget.onHangUp();
                    },
                    child: Container(
                      width: 48,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _K.red,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                              color: _K.red.withOpacity(0.45), blurRadius: 12)
                        ],
                      ),
                      child: const Icon(Icons.call_end_rounded,
                          color: Colors.white, size: 20),
                    ),
                  ),
                  if (widget.onExpand != null) ...[
                    const SizedBox(width: 6),
                    _pill(
                      icon: Icons.expand_less_rounded,
                      active: false,
                      activeColor: _K.sub,
                      onTap: widget.onExpand!,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pill({
    required IconData icon,
    required bool active,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: active
              ? activeColor.withOpacity(0.22)
              : Colors.white.withOpacity(0.09),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active
                ? activeColor.withOpacity(0.5)
                : Colors.white.withOpacity(0.12),
            width: 0.8,
          ),
        ),
        child:
            Icon(icon, color: active ? activeColor : Colors.white70, size: 19),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// CircularVolumeVisualizer
// Radial audio-level ring that pulses around a participant's avatar.
// ══════════════════════════════════════════════════════════════════════════════
class CircularVolumeVisualizer extends StatefulWidget {
  final double level; // 0.0 – 1.0
  final Color color;
  final double size;
  final int barCount;
  final Widget child;

  const CircularVolumeVisualizer({
    super.key,
    required this.level,
    required this.child,
    this.color = const Color(0xFF4ADE80),
    this.size = 90,
    this.barCount = 24,
  });

  @override
  State<CircularVolumeVisualizer> createState() =>
      _CircularVolumeVisualizerState();
}

class _CircularVolumeVisualizerState extends State<CircularVolumeVisualizer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  final _rng = math.Random();
  late List<double> _heights;

  @override
  void initState() {
    super.initState();
    _heights = List.generate(widget.barCount, (_) => 0.3);
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 100))
      ..addListener(_update)
      ..repeat(reverse: true);
  }

  void _update() {
    if (!mounted) return;
    setState(() {
      _heights = List.generate(widget.barCount, (i) {
        if (widget.level < 0.04) return 0.15;
        final base = 0.2 + widget.level * 0.6;
        final noise = (_rng.nextDouble() - 0.5) * 0.3 * widget.level;
        return (base + noise).clamp(0.1, 1.0);
      });
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Radial bars
          CustomPaint(
            size: Size(widget.size, widget.size),
            painter: _RadialBarPainter(
              heights: _heights,
              color: widget.color,
              level: widget.level,
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}

class _RadialBarPainter extends CustomPainter {
  final List<double> heights;
  final Color color;
  final double level;

  _RadialBarPainter({
    required this.heights,
    required this.color,
    required this.level,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (level < 0.03) return;

    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2 - 4;
    final n = heights.length;

    for (int i = 0; i < n; i++) {
      final angle = (i / n) * 2 * math.pi - math.pi / 2;
      final h = heights[i];
      final barLen = h * 10 + 3;

      final x1 = cx + math.cos(angle) * (r - barLen);
      final y1 = cy + math.sin(angle) * (r - barLen);
      final x2 = cx + math.cos(angle) * r;
      final y2 = cy + math.sin(angle) * r;

      final paint = Paint()
        ..color = color.withOpacity((0.3 + h * 0.7).clamp(0.0, 1.0))
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paint);
    }
  }

  @override
  bool shouldRepaint(_RadialBarPainter old) =>
      old.level != level || old.heights != heights;
}

// ══════════════════════════════════════════════════════════════════════════════
// CallCountdownTimer
// Countdown ring shown on the incoming call screen
// ══════════════════════════════════════════════════════════════════════════════
class CallCountdownTimer extends StatefulWidget {
  final int totalSeconds;
  final int remaining;
  final Color color;
  final double size;

  const CallCountdownTimer({
    super.key,
    required this.totalSeconds,
    required this.remaining,
    this.color = const Color(0xFF3B82F6),
    this.size = 58,
  });

  @override
  State<CallCountdownTimer> createState() => _CallCountdownTimerState();
}

class _CallCountdownTimerState extends State<CallCountdownTimer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 1));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(CallCountdownTimer old) {
    super.didUpdateWidget(old);
    if (old.remaining != widget.remaining) {
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fraction = widget.remaining / widget.totalSeconds;
    final isLow = widget.remaining <= 10;
    final color = isLow ? _K.red : widget.color;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 1.0, end: fraction.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOut,
            builder: (_, v, __) => CircularProgressIndicator(
              value: v,
              strokeWidth: 3,
              backgroundColor: Colors.white.withOpacity(0.08),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          ScaleTransition(
            scale: Tween<double>(begin: 1.15, end: 1.0).animate(_anim),
            child: Text(
              '${widget.remaining}',
              style: TextStyle(
                color: isLow ? _K.red : Colors.white.withOpacity(0.85),
                fontSize: widget.size * 0.32,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// CallControlTooltip
// Brief auto-dismiss label that appears when a control is toggled
// ══════════════════════════════════════════════════════════════════════════════
class CallControlTooltip extends StatefulWidget {
  final String message;
  final Color? color;
  final IconData? icon;

  const CallControlTooltip({
    super.key,
    required this.message,
    this.color,
    this.icon,
  });

  @override
  State<CallControlTooltip> createState() => _CallControlTooltipState();
}

class _CallControlTooltipState extends State<CallControlTooltip>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 280));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) _ctrl.reverse();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Colors.white;
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            color: _K.s2.withOpacity(0.95),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.2)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4))
            ],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (widget.icon != null) ...[
              Icon(widget.icon, color: color, size: 13),
              const SizedBox(width: 6),
            ],
            Text(widget.message,
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// CallEndConfirmDialog
// Confirmation bottom sheet when host tries to end call for all
// ══════════════════════════════════════════════════════════════════════════════
class CallEndConfirmDialog extends StatelessWidget {
  final bool isHost;
  final int participantCount;
  final VoidCallback onLeaveOnly;
  final VoidCallback onEndForAll;
  final VoidCallback onCancel;

  const CallEndConfirmDialog({
    super.key,
    required this.isHost,
    required this.participantCount,
    required this.onLeaveOnly,
    required this.onEndForAll,
    required this.onCancel,
  });

  static Future<void> show(
    BuildContext context, {
    required bool isHost,
    required int participantCount,
    required VoidCallback onLeaveOnly,
    required VoidCallback onEndForAll,
    required VoidCallback onCancel,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => CallEndConfirmDialog(
        isHost: isHost,
        participantCount: participantCount,
        onLeaveOnly: onLeaveOnly,
        onEndForAll: onEndForAll,
        onCancel: onCancel,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
      decoration: BoxDecoration(
        color: _K.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 22),

          // Icon
          Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: _K.red.withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(color: _K.red.withOpacity(0.25)),
              ),
              child:
                  const Icon(Icons.call_end_rounded, color: _K.red, size: 28)),
          const SizedBox(height: 14),

          const Text('Rời cuộc gọi?',
              style: TextStyle(
                  color: _K.text, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),

          if (isHost && participantCount > 1)
            Text(
              'Còn $participantCount người trong cuộc gọi.\nBạn có muốn kết thúc cho tất cả không?',
              style: const TextStyle(color: _K.sub, fontSize: 13, height: 1.5),
              textAlign: TextAlign.center,
            )
          else
            const Text(
              'Bạn sẽ rời khỏi cuộc gọi này.',
              style: TextStyle(color: _K.sub, fontSize: 13),
            ),

          const SizedBox(height: 24),

          // Buttons
          if (isHost && participantCount > 1) ...[
            _btn(
              label: 'Kết thúc cho tất cả',
              icon: Icons.call_end_rounded,
              color: _K.red,
              filled: true,
              onTap: onEndForAll,
            ),
            const SizedBox(height: 10),
            _btn(
              label: 'Chỉ rời của tôi',
              icon: Icons.logout_rounded,
              color: _K.amber,
              filled: false,
              onTap: onLeaveOnly,
            ),
          ] else
            _btn(
              label: 'Rời cuộc gọi',
              icon: Icons.call_end_rounded,
              color: _K.red,
              filled: true,
              onTap: onLeaveOnly,
            ),

          const SizedBox(height: 10),
          TextButton(
            onPressed: onCancel,
            child: const Text('Huỷ',
                style: TextStyle(
                    color: _K.muted,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _btn({
    required String label,
    required IconData icon,
    required Color color,
    required bool filled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        onTap();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: filled ? color : color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
          border: filled ? null : Border.all(color: color.withOpacity(0.3)),
          boxShadow: filled
              ? [
                  BoxShadow(
                      color: color.withOpacity(0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4))
                ]
              : null,
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: filled ? Colors.white : color, size: 18),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  color: filled ? Colors.white : color,
                  fontSize: 14,
                  fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// CallQualitySnackbar
// Animated snackbar that appears when quality changes significantly
// ══════════════════════════════════════════════════════════════════════════════
class CallQualitySnackbar extends StatefulWidget {
  final String message;
  final Color color;
  final IconData icon;
  final VoidCallback? onDismiss;

  const CallQualitySnackbar({
    super.key,
    required this.message,
    required this.color,
    required this.icon,
    this.onDismiss,
  });

  static void show(
    BuildContext context, {
    required String message,
    required Color color,
    required IconData icon,
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (_) => Positioned(
        top: MediaQuery.of(context).padding.top + 64,
        left: 16,
        right: 16,
        child: CallQualitySnackbar(
          message: message,
          color: color,
          icon: icon,
          onDismiss: () => entry.remove(),
        ),
      ),
    );

    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 3), () {
      try {
        entry.remove();
      } catch (_) {}
    });
  }

  @override
  State<CallQualitySnackbar> createState() => _CallQualitySnackbarState();
}

class _CallQualitySnackbarState extends State<CallQualitySnackbar>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Material(
          color: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                decoration: BoxDecoration(
                  color: _K.s2.withOpacity(0.96),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: widget.color.withOpacity(0.3), width: 1),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 6))
                  ],
                ),
                child: Row(children: [
                  Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: widget.color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(widget.icon, color: widget.color, size: 17)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(widget.message,
                          style: TextStyle(
                              color: widget.color,
                              fontSize: 13,
                              fontWeight: FontWeight.w600))),
                  GestureDetector(
                    onTap: widget.onDismiss,
                    child: Icon(Icons.close_rounded, color: _K.muted, size: 16),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// GroupCallAvatarGrid
// Compact grid of participant avatars for small UI spaces (notifications, etc.)
// ══════════════════════════════════════════════════════════════════════════════
class GroupCallAvatarGrid extends StatelessWidget {
  final List<String> avatarUrls;
  final List<String> names;
  final double size;
  final int max;

  const GroupCallAvatarGrid({
    super.key,
    required this.avatarUrls,
    required this.names,
    this.size = 48,
    this.max = 4,
  });

  @override
  Widget build(BuildContext context) {
    final shown = avatarUrls.take(max).toList();
    final extra = avatarUrls.length > max ? avatarUrls.length - max : 0;
    final r = size / 2;
    final cols = shown.length <= 1 ? 1 : 2;

    if (shown.isEmpty) {
      return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
              color: _K.s2, borderRadius: BorderRadius.circular(r)),
          child: Icon(Icons.group_rounded, color: _K.muted, size: size * 0.5));
    }

    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(r),
        child: shown.length == 1
            ? _avatar(shown[0], names.isNotEmpty ? names[0] : '?', size: size)
            : GridView.count(
                crossAxisCount: cols,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                mainAxisSpacing: 1,
                crossAxisSpacing: 1,
                children: [
                  ...shown.asMap().entries.map((e) => _avatar(
                      e.value, names.length > e.key ? names[e.key] : '?',
                      size: size / cols)),
                  if (extra > 0)
                    Container(
                      color: _K.accent.withOpacity(0.25),
                      child: Center(
                          child: Text(
                        '+$extra',
                        style: TextStyle(
                            color: _K.accent,
                            fontSize: size * 0.18,
                            fontWeight: FontWeight.w800),
                      )),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _avatar(String url, String name, {required double size}) {
    return url.isNotEmpty
        ? Image.network(url,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _fallback(name, size))
        : _fallback(name, size);
  }

  Widget _fallback(String name, double size) => Container(
      color: _K.s2,
      child: Center(
          child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.35,
            fontWeight: FontWeight.w700),
      )));
}
