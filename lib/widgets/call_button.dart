// lib/widgets/call_button.dart
import 'package:flutter/material.dart';

import '../models/call_model.dart';
import '../pages/outgoing_call_page.dart';
import '../services/call_service.dart';

/// Widget chứa 2 nút gọi video + thoại, dùng trong AppBar
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
    final service = CallService();

    // Hiển thị loading
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Text('Đang kết nối ${type == CallType.video ? 'video' : 'thoại'}...'),
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
          content: Text('Không thể bắt đầu cuộc gọi. Người dùng có thể đang bận.'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OutgoingCallPage(call: call),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF1976D2);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.videocam, color: color),
          tooltip: 'Gọi video',
          onPressed: () => _startCall(context, CallType.video),
        ),
        IconButton(
          icon: const Icon(Icons.phone, color: color),
          tooltip: 'Gọi thoại',
          onPressed: () => _startCall(context, CallType.voice),
        ),
      ],
    );
  }
}

/// Nút gọi thoại đơn lẻ
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
    return IconButton(
      icon: const Icon(Icons.phone, color: Color(0xFF1976D2)),
      tooltip: 'Gọi thoại',
      onPressed: () async {
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
      },
    );
  }
}

/// Nút gọi video đơn lẻ
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
    return IconButton(
      icon: const Icon(Icons.videocam, color: Color(0xFF1976D2)),
      tooltip: 'Gọi video',
      onPressed: () async {
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
      },
    );
  }
}