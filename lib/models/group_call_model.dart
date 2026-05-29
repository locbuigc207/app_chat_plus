import 'package:cloud_firestore/cloud_firestore.dart';

enum GroupCallStatus { calling, ongoing, ended, missed }

enum GroupCallType { video, voice }

enum CallReactionType { thumbsUp, heart, clap, laugh, surprised, fire }

extension CallReactionEmoji on CallReactionType {
  String get emoji {
    switch (this) {
      case CallReactionType.thumbsUp:
        return '👍';
      case CallReactionType.heart:
        return '❤️';
      case CallReactionType.clap:
        return '👏';
      case CallReactionType.laugh:
        return '😂';
      case CallReactionType.surprised:
        return '😮';
      case CallReactionType.fire:
        return '🔥';
    }
  }

  static CallReactionType? fromName(String? name) {
    if (name == null) return null;
    return CallReactionType.values.firstWhere(
      (e) => e.name == name,
      orElse: () => CallReactionType.thumbsUp,
    );
  }
}

class CallReaction {
  final String userId;
  final String userName;
  final CallReactionType type;
  final DateTime sentAt;

  const CallReaction({
    required this.userId,
    required this.userName,
    required this.type,
    required this.sentAt,
  });

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'userName': userName,
        'type': type.name,
        'sentAt': sentAt.millisecondsSinceEpoch.toString(),
      };

  factory CallReaction.fromJson(Map<String, dynamic> j) => CallReaction(
        userId: j['userId'] ?? '',
        userName: j['userName'] ?? '',
        type: CallReactionEmoji.fromName(j['type']) ?? CallReactionType.thumbsUp,
        sentAt:
            DateTime.fromMillisecondsSinceEpoch(int.tryParse(j['sentAt']?.toString() ?? '0') ?? 0),
      );
}

class GroupCallParticipant {
  final String userId;
  final String userName;
  final String userAvatar;
  final bool isMuted;
  final bool isCameraOff;
  final bool isScreenSharing;
  final bool hasRaisedHand;
  final bool isAdmin;
  final bool isSpeaking;
  final DateTime joinedAt;
  final int networkQuality;

  const GroupCallParticipant({
    required this.userId,
    required this.userName,
    required this.userAvatar,
    this.isMuted = false,
    this.isCameraOff = false,
    this.isScreenSharing = false,
    this.hasRaisedHand = false,
    required this.isAdmin,
    this.isSpeaking = false,
    required this.joinedAt,
    this.networkQuality = 0,
  });

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'userName': userName,
        'userAvatar': userAvatar,
        'isMuted': isMuted,
        'isCameraOff': isCameraOff,
        'isScreenSharing': isScreenSharing,
        'hasRaisedHand': hasRaisedHand,
        'isAdmin': isAdmin,
        'joinedAt': joinedAt.millisecondsSinceEpoch.toString(),
        'networkQuality': networkQuality,
      };

  factory GroupCallParticipant.fromJson(Map<String, dynamic> j) => GroupCallParticipant(
        userId: j['userId'] ?? '',
        userName: j['userName'] ?? '',
        userAvatar: j['userAvatar'] ?? '',
        isMuted: j['isMuted'] ?? false,
        isCameraOff: j['isCameraOff'] ?? false,
        isScreenSharing: j['isScreenSharing'] ?? false,
        hasRaisedHand: j['hasRaisedHand'] ?? false,
        isAdmin: j['isAdmin'] ?? false,
        joinedAt: DateTime.fromMillisecondsSinceEpoch(
            int.tryParse(j['joinedAt']?.toString() ?? '0') ?? 0),
        networkQuality: (j['networkQuality'] as int?) ?? 0,
      );

  GroupCallParticipant copyWith({
    bool? isMuted,
    bool? isCameraOff,
    bool? isScreenSharing,
    bool? hasRaisedHand,
    bool? isAdmin,
    bool? isSpeaking,
    int? networkQuality,
  }) =>
      GroupCallParticipant(
        userId: userId,
        userName: userName,
        userAvatar: userAvatar,
        isMuted: isMuted ?? this.isMuted,
        isCameraOff: isCameraOff ?? this.isCameraOff,
        isScreenSharing: isScreenSharing ?? this.isScreenSharing,
        hasRaisedHand: hasRaisedHand ?? this.hasRaisedHand,
        isAdmin: isAdmin ?? this.isAdmin,
        isSpeaking: isSpeaking ?? this.isSpeaking,
        joinedAt: joinedAt,
        networkQuality: networkQuality ?? this.networkQuality,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupCallParticipant && runtimeType == other.runtimeType && userId == other.userId;

  @override
  int get hashCode => userId.hashCode;
}

class GroupCallModel {
  final String callId;
  final String groupId;
  final String groupName;
  final String groupAvatarUrl;
  final String initiatorId;
  final String initiatorName;
  final GroupCallType callType;
  final GroupCallStatus status;
  final String channelName;
  final List<GroupCallParticipant> participants;
  final List<String> invitedUserIds;
  final List<String> declinedUserIds;
  final DateTime createdAt;
  final DateTime? endedAt;
  final int? durationSeconds;
  final String? screenShareUserId;
  final List<CallReaction> recentReactions;
  final List<String> raisedHandUserIds;

  const GroupCallModel({
    required this.callId,
    required this.groupId,
    required this.groupName,
    this.groupAvatarUrl = '',
    required this.initiatorId,
    required this.initiatorName,
    required this.callType,
    required this.status,
    required this.channelName,
    required this.participants,
    required this.invitedUserIds,
    this.declinedUserIds = const [],
    required this.createdAt,
    this.endedAt,
    this.durationSeconds,
    this.screenShareUserId,
    this.recentReactions = const [],
    this.raisedHandUserIds = const [],
  });

  bool get isVideo => callType == GroupCallType.video;
  bool get isVoice => callType == GroupCallType.voice;
  bool get isOngoing => status == GroupCallStatus.ongoing;
  bool get isCalling => status == GroupCallStatus.calling;
  bool get isEnded => status == GroupCallStatus.ended;
  bool get hasScreenShare => screenShareUserId != null;
  int get participantCount => participants.length;

  GroupCallParticipant? getParticipant(String userId) {
    try {
      return participants.firstWhere((p) => p.userId == userId);
    } catch (_) {
      return null;
    }
  }

  bool isParticipant(String userId) => participants.any((p) => p.userId == userId);

  bool hasRaisedHand(String userId) => raisedHandUserIds.contains(userId);

  String get formattedDuration {
    if (durationSeconds == null) return '';
    final d = Duration(seconds: durationSeconds!);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  Map<String, dynamic> toJson() => {
        'callId': callId,
        'groupId': groupId,
        'groupName': groupName,
        'groupAvatarUrl': groupAvatarUrl,
        'initiatorId': initiatorId,
        'initiatorName': initiatorName,
        'callType': callType.name,
        'status': status.name,
        'channelName': channelName,
        'participants': participants.map((p) => p.toJson()).toList(),
        'invitedUserIds': invitedUserIds,
        'declinedUserIds': declinedUserIds,
        'createdAt': createdAt.millisecondsSinceEpoch.toString(),
        'endedAt': endedAt?.millisecondsSinceEpoch.toString(),
        'durationSeconds': durationSeconds,
        'screenShareUserId': screenShareUserId,
        'recentReactions': recentReactions.map((r) => r.toJson()).toList(),
        'raisedHandUserIds': raisedHandUserIds,
      };

  factory GroupCallModel.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return GroupCallModel.fromJson(data);
  }

  factory GroupCallModel.fromJson(Map<String, dynamic> data) {
    final participantsRaw = data['participants'] as List<dynamic>? ?? [];
    final reactionsRaw = data['recentReactions'] as List<dynamic>? ?? [];

    return GroupCallModel(
      callId: data['callId'] ?? '',
      groupId: data['groupId'] ?? '',
      groupName: data['groupName'] ?? '',
      groupAvatarUrl: data['groupAvatarUrl'] ?? '',
      initiatorId: data['initiatorId'] ?? '',
      initiatorName: data['initiatorName'] ?? '',
      callType: data['callType'] == 'voice' ? GroupCallType.voice : GroupCallType.video,
      status: _parseStatus(data['status']),
      channelName: data['channelName'] ?? '',
      participants: participantsRaw
          .map((p) => GroupCallParticipant.fromJson(p as Map<String, dynamic>))
          .toList(),
      invitedUserIds: List<String>.from(data['invitedUserIds'] ?? []),
      declinedUserIds: List<String>.from(data['declinedUserIds'] ?? []),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
          int.tryParse(data['createdAt']?.toString() ?? '0') ?? 0),
      endedAt: data['endedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(int.tryParse(data['endedAt'].toString()) ?? 0)
          : null,
      durationSeconds: data['durationSeconds'] as int?,
      screenShareUserId: data['screenShareUserId'] as String?,
      recentReactions:
          reactionsRaw.map((r) => CallReaction.fromJson(r as Map<String, dynamic>)).toList(),
      raisedHandUserIds: List<String>.from(data['raisedHandUserIds'] ?? []),
    );
  }

  static GroupCallStatus _parseStatus(String? s) {
    switch (s) {
      case 'ongoing':
        return GroupCallStatus.ongoing;
      case 'ended':
        return GroupCallStatus.ended;
      case 'missed':
        return GroupCallStatus.missed;
      default:
        return GroupCallStatus.calling;
    }
  }

  GroupCallModel copyWith({
    GroupCallStatus? status,
    List<GroupCallParticipant>? participants,
    DateTime? endedAt,
    int? durationSeconds,
    String? screenShareUserId,
    bool clearScreenShare = false,
    List<CallReaction>? recentReactions,
    List<String>? raisedHandUserIds,
    List<String>? declinedUserIds,
  }) =>
      GroupCallModel(
        callId: callId,
        groupId: groupId,
        groupName: groupName,
        groupAvatarUrl: groupAvatarUrl,
        initiatorId: initiatorId,
        initiatorName: initiatorName,
        callType: callType,
        status: status ?? this.status,
        channelName: channelName,
        participants: participants ?? this.participants,
        invitedUserIds: invitedUserIds,
        declinedUserIds: declinedUserIds ?? this.declinedUserIds,
        createdAt: createdAt,
        endedAt: endedAt ?? this.endedAt,
        durationSeconds: durationSeconds ?? this.durationSeconds,
        screenShareUserId: clearScreenShare ? null : (screenShareUserId ?? this.screenShareUserId),
        recentReactions: recentReactions ?? this.recentReactions,
        raisedHandUserIds: raisedHandUserIds ?? this.raisedHandUserIds,
      );
}
