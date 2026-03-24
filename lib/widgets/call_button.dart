// lib/widgets/call_buttons.dart
//
// Drop these buttons into ChatPage's AppBar actions,
// replacing the placeholder Fluttertoast calls.

import 'package:flutter/material.dart';

import '../models/call_model.dart';
import '../pages/call_page.dart';
import '../services/call_service.dart';

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
    final call = await service.initiateCall(
      calleeId: peerId,
      calleeName: peerName,
      calleeAvatar: peerAvatar,
      callType: type,
    );

    if (call == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not start call. User may be busy.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    if (context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CallPage(call: call, isOutgoing: true),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF1976D2);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.videocam, color: color),
          tooltip: 'Video call',
          onPressed: () => _startCall(context, CallType.video),
        ),
        IconButton(
          icon: const Icon(Icons.phone, color: color),
          tooltip: 'Voice call',
          onPressed: () => _startCall(context, CallType.voice),
        ),
      ],
    );
  }
}

// ── Compact single-icon version ────────────────────────────
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
      tooltip: 'Voice call',
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
            MaterialPageRoute(
              builder: (_) => CallPage(call: call, isOutgoing: true),
            ),
          );
        }
      },
    );
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
    return IconButton(
      icon: const Icon(Icons.videocam, color: Color(0xFF1976D2)),
      tooltip: 'Video call',
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
            MaterialPageRoute(
              builder: (_) => CallPage(call: call, isOutgoing: true),
            ),
          );
        }
      },
    );
  }
}
