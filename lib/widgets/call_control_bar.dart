import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CallControlBar extends StatelessWidget {
  final bool isVideoCall;
  final bool isMuted;
  final bool isCameraOff;
  final bool isSpeakerOn;
  final bool isFrontCamera;
  final VoidCallback onMuteTap;
  final VoidCallback? onCameraTap;
  final VoidCallback onSpeakerTap;
  final VoidCallback? onSwitchCameraTap;
  final VoidCallback onEndCall;

  const CallControlBar({
    super.key,
    required this.isVideoCall,
    required this.isMuted,
    required this.isCameraOff,
    required this.isSpeakerOn,
    required this.isFrontCamera,
    required this.onMuteTap,
    this.onCameraTap,
    required this.onSpeakerTap,
    this.onSwitchCameraTap,
    required this.onEndCall,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 36, left: 16, right: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(48),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(48),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 1),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 32,
                    offset: const Offset(0, 8)),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ControlBtn(
                  icon: isMuted ? Icons.mic_off_rounded : Icons.mic_none_rounded,
                  label: isMuted ? 'Bật mic' : 'Tắt mic',
                  isActive: isMuted,
                  activeColor: Colors.redAccent,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    onMuteTap();
                  },
                ),
                const SizedBox(width: 12),
                _ControlBtn(
                  icon: isSpeakerOn ? Icons.volume_up_rounded : Icons.hearing_rounded,
                  label: isSpeakerOn ? 'Loa ngoài' : 'Tai nghe',
                  isActive: isSpeakerOn,
                  activeColor: const Color(0xFF42A5F5),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    onSpeakerTap();
                  },
                ),
                if (isVideoCall) ...[
                  const SizedBox(width: 12),
                  _ControlBtn(
                    icon: isCameraOff ? Icons.videocam_off_rounded : Icons.videocam_rounded,
                    label: isCameraOff ? 'Bật cam' : 'Tắt cam',
                    isActive: isCameraOff,
                    activeColor: Colors.orangeAccent,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      onCameraTap?.call();
                    },
                  ),
                  const SizedBox(width: 12),
                  _ControlBtn(
                    icon: Icons.flip_camera_ios_rounded,
                    label: isFrontCamera ? 'Cam sau' : 'Cam trước',
                    isActive: false,
                    activeColor: Colors.white,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onSwitchCameraTap?.call();
                    },
                  ),
                ],
                const SizedBox(width: 16),
                _EndCallBtn(onTap: onEndCall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ControlBtn extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final Color activeColor;
  final VoidCallback onTap;

  const _ControlBtn({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.activeColor,
    required this.onTap,
  });

  @override
  State<_ControlBtn> createState() => _ControlBtnState();
}

class _ControlBtnState extends State<_ControlBtn> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 80),
        reverseDuration: const Duration(milliseconds: 160));
    _scale = Tween<double>(begin: 1.0, end: 0.85)
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
      child: ScaleTransition(
        scale: _scale,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: widget.isActive
                    ? widget.activeColor.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: widget.isActive
                      ? widget.activeColor.withValues(alpha: 0.5)
                      : Colors.white.withValues(alpha: 0.15),
                  width: 1,
                ),
              ),
              child: Icon(
                widget.icon,
                color: widget.isActive ? widget.activeColor : Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.label,
              style: TextStyle(
                color: widget.isActive
                    ? widget.activeColor.withValues(alpha: 0.9)
                    : Colors.white.withValues(alpha: 0.75),
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EndCallBtn extends StatefulWidget {
  final VoidCallback onTap;
  const _EndCallBtn({required this.onTap});

  @override
  State<_EndCallBtn> createState() => _EndCallBtnState();
}

class _EndCallBtnState extends State<_EndCallBtn> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 100),
        reverseDuration: const Duration(milliseconds: 250));
    _scale = Tween<double>(begin: 1.0, end: 0.84)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _glow = Tween<double>(begin: 0.45, end: 0.15).animate(_ctrl);
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
        HapticFeedback.heavyImpact();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, child) => Transform.scale(
              scale: _scale.value,
              child: Container(
                width: 68,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFE53935),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE53935).withValues(alpha: _glow.value),
                      blurRadius: 20,
                      spreadRadius: 2,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 28),
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Kết thúc',
            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
