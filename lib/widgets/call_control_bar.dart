// lib/widgets/call_control_bar.dart
import 'package:flutter/material.dart';

/// Bottom control bar shown during an active call.
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
  final Future<void> Function() onEndCall;

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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Top row of secondary controls ─────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Mute microphone
              _ControlButton(
                icon: isMuted ? Icons.mic_off : Icons.mic,
                label: isMuted ? 'Unmute' : 'Mute',
                active: isMuted,
                activeColor: Colors.white,
                activeBg: Colors.white.withOpacity(0.2),
                inactiveColor: Colors.white,
                inactiveBg: Colors.white.withOpacity(0.1),
                onTap: onMuteTap,
              ),

              // Speaker / earpiece
              _ControlButton(
                icon: isSpeakerOn ? Icons.volume_up : Icons.hearing,
                label: isSpeakerOn ? 'Speaker' : 'Earpiece',
                active: isSpeakerOn,
                activeColor: Colors.white,
                activeBg: Colors.white.withOpacity(0.2),
                inactiveColor: Colors.white,
                inactiveBg: Colors.white.withOpacity(0.1),
                onTap: onSpeakerTap,
              ),

              // Camera toggle (video only)
              if (isVideoCall && onCameraTap != null)
                _ControlButton(
                  icon: isCameraOff ? Icons.videocam_off : Icons.videocam,
                  label: isCameraOff ? 'Camera off' : 'Camera on',
                  active: isCameraOff,
                  activeColor: Colors.white,
                  activeBg: Colors.white.withOpacity(0.2),
                  inactiveColor: Colors.white,
                  inactiveBg: Colors.white.withOpacity(0.1),
                  onTap: onCameraTap!,
                )
              else
                const SizedBox(width: 64),

              // Switch camera (video only)
              if (isVideoCall && onSwitchCameraTap != null)
                _ControlButton(
                  icon: Icons.flip_camera_android,
                  label: 'Flip',
                  active: false,
                  activeColor: Colors.white,
                  activeBg: Colors.white.withOpacity(0.1),
                  inactiveColor: Colors.white,
                  inactiveBg: Colors.white.withOpacity(0.1),
                  onTap: onSwitchCameraTap!,
                )
              else
                const SizedBox(width: 64),
            ],
          ),

          const SizedBox(height: 28),

          // ── End call button ────────────────────────────
          _EndCallButton(onTap: onEndCall),
        ],
      ),
    );
  }
}

// ── Individual control button ──────────────────────────────────
class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color activeColor;
  final Color activeBg;
  final Color inactiveColor;
  final Color inactiveBg;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.activeColor,
    required this.activeBg,
    required this.inactiveColor,
    required this.inactiveBg,
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
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: active ? activeBg : inactiveBg,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Icon(
              icon,
              color: active ? activeColor : inactiveColor,
              size: 24,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

// ── End call button ─────────────────────────────────────────
class _EndCallButton extends StatefulWidget {
  final Future<void> Function() onTap;
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
      onTapUp: (_) => setState(() => _pressing = false),
      onTapCancel: () => setState(() => _pressing = false),
      onTap: widget.onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: _pressing ? 68 : 72,
            height: _pressing ? 68 : 72,
            decoration: BoxDecoration(
              color: const Color(0xFFE53935),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE53935).withOpacity(0.4),
                  blurRadius: _pressing ? 8 : 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.call_end,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'End',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
