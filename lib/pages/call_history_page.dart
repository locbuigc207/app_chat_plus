// lib/pages/call_history_page.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/call_model.dart';
import '../pages/outgoing_call_page.dart';
import '../services/call_service.dart';

class CallHistoryPage extends StatelessWidget {
  final String currentUserId;

  const CallHistoryPage({super.key, required this.currentUserId});

  @override
  Widget build(BuildContext context) {
    final callService = CallService();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Lịch sử cuộc gọi',
          style:
              TextStyle(color: Color(0xFF1976D2), fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Color(0xFF1976D2)),
      ),
      body: StreamBuilder<List<CallModel>>(
        stream: callService.getCallHistory(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF2196F3)),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 56, color: Colors.grey[400]),
                  const SizedBox(height: 12),
                  Text('Không thể tải lịch sử cuộc gọi',
                      style: TextStyle(color: Colors.grey[600])),
                  const SizedBox(height: 8),
                  Text('${snapshot.error}',
                      style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                ],
              ),
            );
          }

          final calls = snapshot.data ?? [];

          if (calls.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.call_missed, size: 72, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text('Chưa có cuộc gọi nào',
                      style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 18,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  Text('Lịch sử cuộc gọi sẽ xuất hiện ở đây',
                      style: TextStyle(color: Colors.grey[400], fontSize: 14)),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: calls.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, indent: 80, color: Colors.grey[200]),
            itemBuilder: (context, i) {
              final call = calls[i];
              final isOutgoing = call.callerId == currentUserId;
              final peerName = isOutgoing ? call.calleeName : call.callerName;
              final peerAvatar =
                  isOutgoing ? call.calleeAvatar : call.callerAvatar;
              final peerId = isOutgoing ? call.calleeId : call.callerId;

              return _CallHistoryTile(
                call: call,
                isOutgoing: isOutgoing,
                peerName: peerName,
                peerAvatar: peerAvatar,
                peerId: peerId,
              );
            },
          );
        },
      ),
    );
  }
}

class _CallHistoryTile extends StatelessWidget {
  final CallModel call;
  final bool isOutgoing;
  final String peerName;
  final String peerAvatar;
  final String peerId;

  const _CallHistoryTile({
    required this.call,
    required this.isOutgoing,
    required this.peerName,
    required this.peerAvatar,
    required this.peerId,
  });

  @override
  Widget build(BuildContext context) {
    final statusInfo = _statusInfo();
    final timeLabel = _timeLabel();

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: _buildAvatar(),
      title: Text(
        peerName,
        style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: Color(0xFF1A1A2E)),
      ),
      subtitle: Row(
        children: [
          Icon(statusInfo.icon, size: 14, color: statusInfo.color),
          const SizedBox(width: 4),
          Text(statusInfo.label,
              style: TextStyle(color: statusInfo.color, fontSize: 13)),
          if (call.durationSeconds != null && call.durationSeconds! > 0) ...[
            Text(' · ${call.formattedDuration}',
                style: TextStyle(color: Colors.grey[500], fontSize: 13)),
          ],
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(timeLabel,
              style: TextStyle(color: Colors.grey[500], fontSize: 12)),
          const SizedBox(height: 4),
          Icon(
            call.isVideoCall ? Icons.videocam : Icons.phone,
            size: 16,
            color: Colors.grey[400],
          ),
        ],
      ),
      onTap: () => _showCallOptions(context),
    );
  }

  Widget _buildAvatar() {
    return Container(
      width: 50,
      height: 50,
      decoration:
          BoxDecoration(shape: BoxShape.circle, color: Colors.grey[200]),
      child: ClipOval(
        child: peerAvatar.isNotEmpty
            ? Image.network(peerAvatar,
                fit: BoxFit.cover, errorBuilder: (_, __, ___) => _initials())
            : _initials(),
      ),
    );
  }

  Widget _initials() {
    return Container(
      color: const Color(0xFF1976D2).withOpacity(0.15),
      child: Center(
        child: Text(
          peerName.isNotEmpty ? peerName[0].toUpperCase() : '?',
          style: const TextStyle(
              color: Color(0xFF1976D2),
              fontWeight: FontWeight.bold,
              fontSize: 20),
        ),
      ),
    );
  }

  _StatusInfo _statusInfo() {
    switch (call.status) {
      case CallStatus.ended:
        return isOutgoing
            ? _StatusInfo(Icons.call_made, Colors.blue[600]!, 'Đã gọi')
            : _StatusInfo(
                Icons.call_received, Colors.green[600]!, 'Cuộc gọi đến');
      case CallStatus.missed:
        return _StatusInfo(Icons.call_missed, Colors.red[600]!, 'Cuộc gọi nhỡ');
      case CallStatus.declined:
        return _StatusInfo(
            Icons.call_missed_outgoing, Colors.orange[700]!, 'Bị từ chối');
      case CallStatus.failed:
        return _StatusInfo(Icons.error_outline, Colors.red[400]!, 'Thất bại');
      default:
        return _StatusInfo(Icons.phone, Colors.grey, 'Không rõ');
    }
  }

  String _timeLabel() {
    final now = DateTime.now();
    final diff = now.difference(call.createdAt);

    if (diff.inSeconds < 60) return 'Vừa xong';
    if (diff.inMinutes < 60) return '${diff.inMinutes}p trước';
    if (diff.inHours < 24) return '${diff.inHours}g trước';
    if (diff.inDays == 1) return 'Hôm qua';
    if (diff.inDays < 7) return DateFormat('EEE').format(call.createdAt);
    return DateFormat('dd/MM').format(call.createdAt);
  }

  void _showCallOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CallbackSheet(
        peerName: peerName,
        peerAvatar: peerAvatar,
        peerId: peerId,
      ),
    );
  }
}

class _StatusInfo {
  final IconData icon;
  final Color color;
  final String label;
  _StatusInfo(this.icon, this.color, this.label);
}

class _CallbackSheet extends StatelessWidget {
  final String peerName;
  final String peerAvatar;
  final String peerId;

  const _CallbackSheet({
    required this.peerName,
    required this.peerAvatar,
    required this.peerId,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 20),

            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundImage:
                      peerAvatar.isNotEmpty ? NetworkImage(peerAvatar) : null,
                  child: peerAvatar.isEmpty
                      ? Text(
                          peerName.isNotEmpty ? peerName[0].toUpperCase() : '?',
                          style: const TextStyle(fontWeight: FontWeight.bold))
                      : null,
                ),
                const SizedBox(width: 12),
                Text(peerName,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),

            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 8),

            // Voice call back
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFF43A047),
                child: Icon(Icons.phone, color: Colors.white),
              ),
              title: const Text('Gọi thoại lại'),
              onTap: () async {
                Navigator.pop(context);
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
                        builder: (_) => OutgoingCallPage(call: call)),
                  );
                }
              },
            ),

            // Video call back
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFF1976D2),
                child: Icon(Icons.videocam, color: Colors.white),
              ),
              title: const Text('Gọi video lại'),
              onTap: () async {
                Navigator.pop(context);
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
                        builder: (_) => OutgoingCallPage(call: call)),
                  );
                }
              },
            ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
