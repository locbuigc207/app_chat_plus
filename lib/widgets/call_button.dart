
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/call_model.dart';
import '../pages/outgoing_call_page.dart';
import '../services/call_service.dart';


Widget _buildPremiumIconBtn(IconData icon, VoidCallback onTap) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF007AFF).withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: const Color(0xFF007AFF), size: 22),
    ),
  );
}


class CallButtons extends StatelessWidget {
  final String peerId;
  final String peerName;
  final String peerAvatar;

  const CallButtons({
    super.key,
    required this.peerId,
    required this.peerName,
    required this.peerAvatar,
  });

  Future<void> _startCall(BuildContext context, CallType type) async {
    HapticFeedback.lightImpact();
    final service = CallService();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Text(
                  'Đang kết nối ${type == CallType.video ? 'video' : 'thoại'}...'),
            ],
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    final call = await service.initiateCall(
      calleeId: peerId,
      calleeName: peerName,
      calleeAvatar: peerAvatar,
      callType: type,
    );

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (call == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Không thể bắt đầu cuộc gọi. Người dùng có thể đang bận.'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => OutgoingCallPage(call: call)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildPremiumIconBtn(
            Icons.videocam_rounded, () => _startCall(context, CallType.video)),
        const SizedBox(width: 8),
        _buildPremiumIconBtn(
            Icons.phone_rounded, () => _startCall(context, CallType.voice)),
        const SizedBox(width: 8),
      ],
    );
  }
}


class VoiceCallIconButton extends StatelessWidget {
  final String peerId;
  final String peerName;
  final String peerAvatar;

  const VoiceCallIconButton({
    super.key,
    required this.peerId,
    required this.peerName,
    required this.peerAvatar,
  });

  @override
  Widget build(BuildContext context) {
    return _buildPremiumIconBtn(Icons.phone_rounded, () async {
      HapticFeedback.lightImpact();
      final service = CallService();
      final call = await service.initiateCall(
        calleeId: peerId,
        calleeName: peerName,
        calleeAvatar: peerAvatar,
        callType: CallType.voice,
      );
      if (call != null && context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => OutgoingCallPage(call: call)),
        );
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không thể thực hiện cuộc gọi lúc này'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    });
  }
}


class VideoCallIconButton extends StatelessWidget {
  final String peerId;
  final String peerName;
  final String peerAvatar;

  const VideoCallIconButton({
    super.key,
    required this.peerId,
    required this.peerName,
    required this.peerAvatar,
  });

  @override
  Widget build(BuildContext context) {
    return _buildPremiumIconBtn(Icons.videocam_rounded, () async {
      HapticFeedback.lightImpact();
      final service = CallService();
      final call = await service.initiateCall(
        calleeId: peerId,
        calleeName: peerName,
        calleeAvatar: peerAvatar,
        callType: CallType.video,
      );
      if (call != null && context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => OutgoingCallPage(call: call)),
        );
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không thể thực hiện cuộc gọi lúc này'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    });
  }
}
