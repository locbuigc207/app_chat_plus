// lib/widgets/group_call_button.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/color_constants.dart';
import '../models/group_call_model.dart';
import '../pages/group_call_page.dart';
import '../providers/auth_provider.dart';
import '../services/group_call_service.dart';

/// Video / voice call button for the group chat AppBar.
class GroupVideoCallButton extends StatelessWidget {
  final String groupId;
  final String groupName;
  final List<String> memberIds;

  const GroupVideoCallButton({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.memberIds,
  });

  Future<void> _startCall(BuildContext context, GroupCallType type) async {
    final uid = context.read<AuthProvider>().userFirebaseId;
    if (uid == null) return;

    final service = GroupCallService();

    // Check if there's already an active call in this group
    final existing = await _getActiveCall(service);
    if (existing != null) {
      // Join existing call
      final ok = await service.joinCall(existing.callId);
      if (!ok || !context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => GroupCallPage(
            call: existing,
            isInitiator: existing.initiatorId == uid,
          ),
        ),
      );
      return;
    }

    // Start new call
    final call = await service.initiateCall(
      groupId: groupId,
      groupName: groupName,
      memberIds: memberIds,
      callType: type,
    );

    if (call == null || !context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Could not start group call'),
            backgroundColor: Colors.red),
      );
      return;
    }

    service.scheduleCallTimeout(call.callId, seconds: 30);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroupCallPage(call: call, isInitiator: true),
      ),
    );
  }

  Future<GroupCallModel?> _getActiveCall(GroupCallService service) async {
    try {
      final snap = await service
          .activeCallForGroup(groupId)
          .first
          .timeout(const Duration(seconds: 3));
      return snap;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.videocam, color: ColorConstants.primaryColor),
      tooltip: 'Group Call',
      onSelected: (val) {
        if (val == 'video') _startCall(context, GroupCallType.video);
        if (val == 'voice') _startCall(context, GroupCallType.voice);
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'video',
          child: Row(
            children: [
              Icon(Icons.videocam, color: ColorConstants.primaryColor),
              SizedBox(width: 10),
              Text('Group Video Call'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'voice',
          child: Row(
            children: [
              Icon(Icons.phone, color: ColorConstants.primaryColor),
              SizedBox(width: 10),
              Text('Group Voice Call'),
            ],
          ),
        ),
      ],
    );
  }
}

/// Compact single-icon version that shows call options
class GroupCallIconButton extends StatelessWidget {
  final String groupId;
  final String groupName;
  final List<String> memberIds;
  final GroupCallType callType;

  const GroupCallIconButton({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.memberIds,
    required this.callType,
  });

  Future<void> _tap(BuildContext context) async {
    final uid = context.read<AuthProvider>().userFirebaseId;
    if (uid == null) return;

    final service = GroupCallService();

    // Optimistically try existing call first
    GroupCallModel? existing;
    try {
      existing = await service
          .activeCallForGroup(groupId)
          .first
          .timeout(const Duration(seconds: 2));
    } catch (_) {}

    if (existing != null && context.mounted) {
      final join = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Active Call'),
          content: Text('There is already an active group call. Join it?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Join')),
          ],
        ),
      );
      if (join != true || !context.mounted) return;
      final ok = await service.joinCall(existing.callId);
      if (!ok || !context.mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => GroupCallPage(call: existing!, isInitiator: false)));
      return;
    }

    // New call
    if (!context.mounted) return;
    final call = await service.initiateCall(
      groupId: groupId,
      groupName: groupName,
      memberIds: memberIds,
      callType: callType,
    );
    if (call == null || !context.mounted) return;
    service.scheduleCallTimeout(call.callId, seconds: 30);
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => GroupCallPage(call: call, isInitiator: true)));
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        callType == GroupCallType.video ? Icons.videocam : Icons.phone,
        color: ColorConstants.primaryColor,
      ),
      tooltip: callType == GroupCallType.video
          ? 'Group Video Call'
          : 'Group Voice Call',
      onPressed: () => _tap(context),
    );
  }
}

/// Active-call banner shown inside group chat when a call is ongoing
class ActiveGroupCallBanner extends StatelessWidget {
  final String groupId;
  final String currentUserId;
  final List<String> memberIds;
  final String groupName;

  const ActiveGroupCallBanner({
    super.key,
    required this.groupId,
    required this.currentUserId,
    required this.memberIds,
    required this.groupName,
  });

  @override
  Widget build(BuildContext context) {
    final service = GroupCallService();

    return StreamBuilder<GroupCallModel?>(
      stream: service.activeCallForGroup(groupId),
      builder: (context, snap) {
        final call = snap.data;
        if (call == null) return const SizedBox.shrink();

        // Check if user is already in this call
        final alreadyIn =
            call.participants.any((p) => p.userId == currentUserId);

        return GestureDetector(
          onTap: () async {
            if (alreadyIn) return; // already in – just navigate
            final ok = await service.joinCall(call.callId);
            if (!ok || !context.mounted) return;
            Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => GroupCallPage(call: call, isInitiator: false)));
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF43A047),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(color: Colors.green.withOpacity(0.3), blurRadius: 8)
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.videocam, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Group call in progress',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13),
                      ),
                      Text(
                        '${call.participants.length} participant(s) in call',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                if (!alreadyIn)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8)),
                    child: const Text('Join',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
