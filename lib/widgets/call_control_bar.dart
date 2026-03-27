// lib/widgets/call_control_bar.dart
import 'package:flutter/material.dart';

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
  // FIX: Thay Future<void> Function() thành VoidCallback để tránh lỗi
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Hàng nút phụ ──────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Micro
              _ControlButton(
                icon: isMuted ? Icons.mic_off : Icons.mic,
                label: isMuted ? 'Bật mic' : 'Tắt mic',
                active: isMuted,
                activeBg: Colors.white.withOpacity(0.2),
                inactiveBg: Colors.white.withOpacity(0.1),
                onTap: onMuteTap,
              ),

              // Loa ngoài
              _ControlButton(
                icon: isSpeakerOn ? Icons.volume_up : Icons.hearing,
                label: isSpeakerOn ? 'Loa ngoài' : 'Tai nghe',
                active: isSpeakerOn,
                activeBg: Colors.white.withOpacity(0.2),
                inactiveBg: Colors.white.withOpacity(0.1),
                onTap: onSpeakerTap,
              ),

              // Camera (video only)
              if (isVideoCall && onCameraTap != null)
                _ControlButton(
                  icon: isCameraOff ? Icons.videocam_off : Icons.videocam,
                  label: isCameraOff ? 'Bật cam' : 'Tắt cam',
                  active: isCameraOff,
                  activeBg: Colors.white.withOpacity(0.2),
                  inactiveBg: Colors.white.withOpacity(0.1),
                  onTap: onCameraTap!,
                )
              else
                const SizedBox(width: 64),

              // Đổi camera (video only)
              if (isVideoCall && onSwitchCameraTap != null)
                _ControlButton(
                  icon: Icons.flip_camera_android,
                  label: 'Đổi cam',
                  active: false,
                  activeBg: Colors.white.withOpacity(0.1),
                  inactiveBg: Colors.white.withOpacity(0.1),
                  onTap: onSwitchCameraTap!,
                )
              else
                const SizedBox(width: 64),
            ],
          ),

          const SizedBox(height: 28),

          // ── Nút kết thúc ──────────────────────────────
          _EndCallButton(onTap: onEndCall),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color activeBg;
  final Color inactiveBg;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.activeBg,
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
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style:
                TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 11),
          ),
        ],
      ),
    );
  }
}

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
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressing = false),
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
            child: const Icon(Icons.call_end, color: Colors.white, size: 32),
          ),
          const SizedBox(height: 6),
          const Text('Kết thúc',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
