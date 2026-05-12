// lib/widgets/call_control_bar.dart
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Bottom control bar hiển thị trong cuộc gọi active.
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
      padding: const EdgeInsets.only(bottom: 32),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(40),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30.0, sigmaY: 30.0),
          child: Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(40),
              border: Border.all(
                  color: Colors.white.withOpacity(0.2), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Micro
                _ControlButton(
                  icon: isMuted
                      ? Icons.mic_off_rounded
                      : Icons.mic_none_rounded,
                  label: isMuted ? 'Bật mic' : 'Tắt mic',
                  isActive: isMuted,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    onMuteTap();
                  },
                ),
                const SizedBox(width: 16),

                // Loa ngoài
                _ControlButton(
                  icon: isSpeakerOn
                      ? Icons.volume_up_rounded
                      : Icons.hearing_rounded,
                  label: isSpeakerOn ? 'Loa ngoài' : 'Tai nghe',
                  isActive: isSpeakerOn,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    onSpeakerTap();
                  },
                ),

                // Camera + Flip (video only)
                if (isVideoCall) ...[
                  const SizedBox(width: 16),
                  _ControlButton(
                    icon: isCameraOff
                        ? Icons.videocam_off_rounded
                        : Icons.videocam_outlined,
                    label: isCameraOff ? 'Bật cam' : 'Tắt cam',
                    isActive: isCameraOff,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      onCameraTap?.call();
                    },
                  ),
                  const SizedBox(width: 16),
                  _ControlButton(
                    icon: Icons.flip_camera_ios_rounded,
                    label: 'Đổi cam',
                    isActive: false,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onSwitchCameraTap?.call();
                    },
                  ),
                ],

                const SizedBox(width: 24),

                // End Call button
                _EndCallButton(onTap: onEndCall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Control Button ─────────────────────────────
class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: isActive
                  ? Colors.white
                  : Colors.black.withOpacity(0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: isActive ? Colors.black : Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
                color: Colors.white.withOpacity(0.8), fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ── End Call Button ────────────────────────────
class _EndCallButton extends StatefulWidget {
  final VoidCallback onTap;
  const _EndCallButton({required this.onTap});

  @override
  State<_EndCallButton> createState() => _EndCallButtonState();
}

class _EndCallButtonState extends State<_EndCallButton> {
  bool _pressing = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressing = true),
      onTapUp: (_) {
        setState(() => _pressing = false);
        HapticFeedback.heavyImpact();
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressing = false),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: _pressing ? 62 : 66,
            height: _pressing ? 52 : 56,
            decoration: BoxDecoration(
              color: const Color(0xFFFF3B30),
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF3B30)
                      .withOpacity(_pressing ? 0.3 : 0.45),
                  blurRadius: _pressing ? 8 : 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(Icons.call_end_rounded,
                color: Colors.white, size: 28),
          ),
          const SizedBox(height: 6),
          const Text(
            'Kết thúc',
            style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}