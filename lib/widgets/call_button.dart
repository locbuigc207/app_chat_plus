import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/call_model.dart';
import '../pages/outgoing_call_page.dart';
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

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PremiumCallBtn(
          icon: Icons.videocam_rounded,
          color: const Color(0xFF1E88E5),
          tooltip: 'Gọi video',
          onTap: () => _startCall(context, CallType.video),
        ),
        const SizedBox(width: 10),
        _PremiumCallBtn(
          icon: Icons.phone_rounded,
          color: const Color(0xFF43A047),
          tooltip: 'Gọi thoại',
          onTap: () => _startCall(context, CallType.voice),
        ),
      ],
    );
  }

  Future<void> _startCall(BuildContext context, CallType type) async {
    HapticFeedback.lightImpact();
    final service = CallService.instance;

    final messenger = ScaffoldMessenger.of(context);
    final snackBar = SnackBar(
      content: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Text('Đang kết nối ${type == CallType.video ? 'video' : 'thoại'}…'),
        ],
      ),
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF1A1F36),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
    messenger.showSnackBar(snackBar);

    final call = await service.initiateCall(
      calleeId: peerId,
      calleeName: peerName,
      calleeAvatar: peerAvatar,
      callType: type,
    );

    messenger.hideCurrentSnackBar();

    if (!context.mounted) return;

    if (call == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Không thể bắt đầu cuộc gọi lúc này.'),
          backgroundColor: Colors.orange[700],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => OutgoingCallPage(call: call)),
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
    return _PremiumCallBtn(
      icon: Icons.phone_rounded,
      color: const Color(0xFF43A047),
      tooltip: 'Gọi thoại',
      onTap: () => _call(context),
    );
  }

  Future<void> _call(BuildContext context) async {
    HapticFeedback.lightImpact();
    final service = CallService.instance;
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
      _showError(context);
    }
  }

  void _showError(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Không thể thực hiện cuộc gọi lúc này.'),
        backgroundColor: Colors.orange[700],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
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
    return _PremiumCallBtn(
      icon: Icons.videocam_rounded,
      color: const Color(0xFF1E88E5),
      tooltip: 'Gọi video',
      onTap: () => _call(context),
    );
  }

  Future<void> _call(BuildContext context) async {
    HapticFeedback.lightImpact();
    final service = CallService.instance;
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
      _showError(context);
    }
  }

  void _showError(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Không thể thực hiện cuộc gọi lúc này.'),
        backgroundColor: Colors.orange[700],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _PremiumCallBtn extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _PremiumCallBtn({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  State<_PremiumCallBtn> createState() => _PremiumCallBtnState();
}

class _PremiumCallBtnState extends State<_PremiumCallBtn> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 100),
        reverseDuration: const Duration(milliseconds: 200));
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
    return Tooltip(
      message: widget.tooltip,
      child: GestureDetector(
        onTapDown: (_) => _ctrl.forward(),
        onTapUp: (_) {
          _ctrl.reverse();
          widget.onTap();
        },
        onTapCancel: () => _ctrl.reverse(),
        child: ScaleTransition(
          scale: _scale,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: widget.color.withValues(alpha: 0.3), width: 1),
            ),
            child: Icon(widget.icon, color: widget.color, size: 20),
          ),
        ),
      ),
    );
  }
}
