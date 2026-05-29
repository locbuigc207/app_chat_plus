import 'dart:async';

import 'package:flutter/material.dart';

import '../services/realtime_ai_service.dart';

class LiveCaptionOverlay extends StatefulWidget {
  final double bottomOffset;

  final int maxLines;

  const LiveCaptionOverlay({
    super.key,
    this.bottomOffset = 110,
    this.maxLines = 3,
  });

  @override
  State<LiveCaptionOverlay> createState() => _LiveCaptionOverlayState();
}

class _LiveCaptionOverlayState extends State<LiveCaptionOverlay> with TickerProviderStateMixin {
  late AnimationController _entryCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  late AnimationController _securityBorderCtrl;
  late Animation<double> _securityBorderAnim;

  String _text = '';
  bool _visible = false;
  SecurityStatus _securityStatus = SecurityStatus.safe;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();

    _entryCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
    _fadeAnim =
        CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut, reverseCurve: Curves.easeIn);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.25),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.35,
      upperBound: 1.0,
    )..repeat(reverse: true);
    _pulseAnim = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);

    _securityBorderCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _securityBorderAnim = Tween<double>(begin: 0.3, end: 0.9)
        .animate(CurvedAnimation(parent: _securityBorderCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _pulseCtrl.dispose();
    _securityBorderCtrl.dispose();
    _hideTimer?.cancel();
    super.dispose();
  }

  void _onCaptionData(String text) {
    _hideTimer?.cancel();

    if (text.isEmpty) {
      _hideTimer = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        _entryCtrl.reverse().then((_) {
          if (mounted) setState(() => _visible = false);
        });
      });
      return;
    }

    if (!_visible) {
      setState(() {
        _text = text;
        _visible = true;
      });
      _entryCtrl.forward(from: 0);
    } else {
      setState(() => _text = text);
    }
  }

  void _onSecurityEvent(SecurityEvent event) {
    if (!mounted) return;
    setState(() => _securityStatus = event.status);
  }

  Color _accentColor() {
    switch (_securityStatus) {
      case SecurityStatus.warning:
        return const Color(0xFFFBBF24);
      case SecurityStatus.danger:
        return const Color(0xFFF87171);
      case SecurityStatus.scanning:
        return const Color(0xFF60A5FA);
      default:
        return const Color(0xFF34D399);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        StreamBuilder<String>(
          stream: RealtimeAIService().captionStream,
          builder: (context, snap) {
            if (snap.hasData) _onCaptionData(snap.data!);
            return const SizedBox.shrink();
          },
        ),
        StreamBuilder<SecurityEvent>(
          stream: RealtimeAIService().securityStream,
          builder: (context, snap) {
            if (snap.hasData) _onSecurityEvent(snap.data!);
            return const SizedBox.shrink();
          },
        ),
        if (_visible)
          Positioned(
            bottom: widget.bottomOffset,
            left: 16,
            right: 16,
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: _CaptionBubble(
                  text: _text,
                  maxLines: widget.maxLines,
                  pulseAnim: _pulseAnim,
                  securityBorderAnim: _securityBorderAnim,
                  accentColor: _accentColor(),
                  securityStatus: _securityStatus,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CaptionBubble extends StatelessWidget {
  final String text;
  final int maxLines;
  final Animation<double> pulseAnim;
  final Animation<double> securityBorderAnim;
  final Color accentColor;
  final SecurityStatus securityStatus;

  const _CaptionBubble({
    required this.text,
    required this.maxLines,
    required this.pulseAnim,
    required this.securityBorderAnim,
    required this.accentColor,
    required this.securityStatus,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([pulseAnim, securityBorderAnim]),
      builder: (context, child) {
        final borderColor = securityStatus == SecurityStatus.safe
            ? accentColor.withValues(alpha: 0.18)
            : accentColor.withValues(alpha: securityBorderAnim.value * 0.55);

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.76),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
              if (securityStatus != SecurityStatus.safe)
                BoxShadow(
                  color: accentColor.withValues(alpha: securityBorderAnim.value * 0.2),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
            ],
          ),
          child: child,
        );
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5, right: 10),
            child: AnimatedBuilder(
              animation: pulseAnim,
              builder: (_, __) => Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color.lerp(
                    accentColor.withValues(alpha: 0.6),
                    accentColor,
                    pulseAnim.value,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accentColor.withValues(alpha: pulseAnim.value * 0.7),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: child,
              ),
              child: Text(
                text,
                key: ValueKey(text),
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.start,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14.5,
                  height: 1.5,
                  letterSpacing: 0.15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 1),
            child: _StatusBadge(status: securityStatus, accentColor: accentColor),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final SecurityStatus status;
  final Color accentColor;

  const _StatusBadge({required this.status, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    final Widget inner;

    switch (status) {
      case SecurityStatus.warning:
        inner = Icon(Icons.warning_amber_rounded, size: 11, color: accentColor);
        break;
      case SecurityStatus.danger:
        inner = Icon(Icons.gpp_bad_rounded, size: 11, color: accentColor);
        break;
      case SecurityStatus.scanning:
        inner = SizedBox(
          width: 11,
          height: 11,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            valueColor: AlwaysStoppedAnimation<Color>(accentColor),
          ),
        );
        break;
      default:
        inner = Text(
          'CC',
          style: TextStyle(
            color: accentColor.withValues(alpha: 0.65),
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accentColor.withValues(alpha: 0.25), width: 0.8),
      ),
      child: inner,
    );
  }
}
