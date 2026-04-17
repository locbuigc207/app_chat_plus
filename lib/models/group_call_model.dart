// lib/models/group_call_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

enum GroupCallStatus {
  calling, // Initiator just created call
  ongoing, // At least 2 people connected
  ended, // Call finished
}

enum GroupCallType { video, voice }

class GroupCallParticipant {
  final String userId;
  final String userName;
  final String userAvatar;
  final bool isMuted;
  final bool isCameraOff;
  final DateTime joinedAt;
  final bool isAdmin;

  const GroupCallParticipant({
    required this.userId,
    required this.userName,
    required this.userAvatar,
    this.isMuted = false,
    this.isCameraOff = false,
    required this.joinedAt,
    this.isAdmin = false,
  });

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'userName': userName,
        'userAvatar': userAvatar,
        'isMuted': isMuted,
        'isCameraOff': isCameraOff,
        'joinedAt': joinedAt.millisecondsSinceEpoch.toString(),
        'isAdmin': isAdmin,
      };

  factory GroupCallParticipant.fromJson(Map<String, dynamic> json) =>
      GroupCallParticipant(
        userId: json['userId'] ?? '',
        userName: json['userName'] ?? '',
        userAvatar: json['userAvatar'] ?? '',
        isMuted: json['isMuted'] ?? false,
        isCameraOff: json['isCameraOff'] ?? false,
        joinedAt: DateTime.fromMillisecondsSinceEpoch(
            int.tryParse(json['joinedAt']?.toString() ?? '0') ?? 0),
        isAdmin: json['isAdmin'] ?? false,
      );

  GroupCallParticipant copyWith({
    bool? isMuted,
    bool? isCameraOff,
  }) =>
      GroupCallParticipant(
        userId: userId,
        userName: userName,
        userAvatar: userAvatar,
        isMuted: isMuted ?? this.isMuted,
        isCameraOff: isCameraOff ?? this.isCameraOff,
        joinedAt: joinedAt,
        isAdmin: isAdmin,
      );
}

class GroupCallModel {
  final String callId;
  final String groupId;
  final String groupName;
  final String initiatorId;
  final String initiatorName;
  final GroupCallType callType;
  final GroupCallStatus status;
  final String channelName;
  final List<GroupCallParticipant> participants;
  final List<String> invitedUserIds;
  final DateTime createdAt;
  final DateTime? endedAt;
  final int? durationSeconds;

  const GroupCallModel({
    required this.callId,
    required this.groupId,
    required this.groupName,
    required this.initiatorId,
    required this.initiatorName,
    required this.callType,
    required this.status,
    required this.channelName,
    required this.participants,
    required this.invitedUserIds,
    required this.createdAt,
    this.endedAt,
    this.durationSeconds,
  });

  bool get isVideo => callType == GroupCallType.video;
  bool get isOngoing => status == GroupCallStatus.ongoing;
  int get participantCount => participants.length;

  GroupCallParticipant? getParticipant(String userId) {
    try {
      return participants.firstWhere((p) => p.userId == userId);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
        'callId': callId,
        'groupId': groupId,
        'groupName': groupName,
        'initiatorId': initiatorId,
        'initiatorName': initiatorName,
        'callType': callType.name,
        'status': status.name,
        'channelName': channelName,
        'participants': participants.map((p) => p.toJson()).toList(),
        'invitedUserIds': invitedUserIds,
        'createdAt': createdAt.millisecondsSinceEpoch.toString(),
        'endedAt': endedAt?.millisecondsSinceEpoch.toString(),
        'durationSeconds': durationSeconds,
      };

  factory GroupCallModel.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return GroupCallModel.fromJson(data);
  }

  factory GroupCallModel.fromJson(Map<String, dynamic> data) {
    final participantsRaw = data['participants'] as List<dynamic>? ?? [];
    final participants = participantsRaw
        .map((p) => GroupCallParticipant.fromJson(p as Map<String, dynamic>))
        .toList();

    return GroupCallModel(
      callId: data['callId'] ?? '',
      groupId: data['groupId'] ?? '',
      groupName: data['groupName'] ?? '',
      initiatorId: data['initiatorId'] ?? '',
      initiatorName: data['initiatorName'] ?? '',
      callType: data['callType'] == 'voice'
          ? GroupCallType.voice
          : GroupCallType.video,
      status: _parseStatus(data['status']),
      channelName: data['channelName'] ?? '',
      participants: participants,
      invitedUserIds: List<String>.from(data['invitedUserIds'] ?? []),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
          int.tryParse(data['createdAt']?.toString() ?? '0') ?? 0),
      endedAt: data['endedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              int.tryParse(data['endedAt'].toString()) ?? 0)
          : null,
      durationSeconds: data['durationSeconds'] as int?,
    );
  }

  static GroupCallStatus _parseStatus(String? s) {
    switch (s) {
      case 'ongoing':
        return GroupCallStatus.ongoing;
      case 'ended':
        return GroupCallStatus.ended;
      default:
        return GroupCallStatus.calling;
    }
  }

  GroupCallModel copyWith({
    GroupCallStatus? status,
    List<GroupCallParticipant>? participants,
    DateTime? endedAt,
    int? durationSeconds,
  }) =>
      GroupCallModel(
        callId: callId,
        groupId: groupId,
        groupName: groupName,
        initiatorId: initiatorId,
        initiatorName: initiatorName,
        callType: callType,
        status: status ?? this.status,
        channelName: channelName,
        participants: participants ?? this.participants,
        invitedUserIds: invitedUserIds,
        createdAt: createdAt,
        endedAt: endedAt ?? this.endedAt,
        durationSeconds: durationSeconds ?? this.durationSeconds,
      );
}
