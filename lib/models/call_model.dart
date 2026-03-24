// lib/models/call_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

enum CallType { voice, video }

enum CallStatus {
  calling, // Caller is ringing, waiting for answer
  ringing, // Callee is receiving the call
  connected, // Both parties connected
  ended, // Call ended normally
  missed, // Call was not answered
  declined, // Call was declined by callee
  failed, // Call failed due to error
}

class CallModel {
  final String callId;
  final String callerId;
  final String callerName;
  final String callerAvatar;
  final String calleeId;
  final String calleeName;
  final String calleeAvatar;
  final CallType callType;
  final CallStatus status;
  final String? channelName; // Agora channel name
  final String? token; // Agora token (null = no-auth mode)
  final DateTime createdAt;
  final DateTime? connectedAt;
  final DateTime? endedAt;
  final int? durationSeconds;

  CallModel({
    required this.callId,
    required this.callerId,
    required this.callerName,
    required this.callerAvatar,
    required this.calleeId,
    required this.calleeName,
    required this.calleeAvatar,
    required this.callType,
    required this.status,
    this.channelName,
    this.token,
    required this.createdAt,
    this.connectedAt,
    this.endedAt,
    this.durationSeconds,
  });

  Map<String, dynamic> toJson() {
    return {
      'callId': callId,
      'callerId': callerId,
      'callerName': callerName,
      'callerAvatar': callerAvatar,
      'calleeId': calleeId,
      'calleeName': calleeName,
      'calleeAvatar': calleeAvatar,
      'callType': callType.name,
      'status': status.name,
      'channelName': channelName,
      'token': token,
      'createdAt': createdAt.millisecondsSinceEpoch.toString(),
      'connectedAt': connectedAt?.millisecondsSinceEpoch.toString(),
      'endedAt': endedAt?.millisecondsSinceEpoch.toString(),
      'durationSeconds': durationSeconds,
    };
  }

  factory CallModel.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CallModel.fromJson(data);
  }

  factory CallModel.fromJson(Map<String, dynamic> data) {
    DateTime _parseDate(dynamic value) {
      if (value == null) return DateTime.now();
      if (value is String) {
        final ms = int.tryParse(value);
        if (ms != null) return DateTime.fromMillisecondsSinceEpoch(ms);
      }
      if (value is Timestamp) return value.toDate();
      return DateTime.now();
    }

    DateTime? _parseDateNullable(dynamic value) {
      if (value == null) return null;
      if (value is String) {
        final ms = int.tryParse(value);
        if (ms != null) return DateTime.fromMillisecondsSinceEpoch(ms);
      }
      if (value is Timestamp) return value.toDate();
      return null;
    }

    return CallModel(
      callId: data['callId'] ?? '',
      callerId: data['callerId'] ?? '',
      callerName: data['callerName'] ?? '',
      callerAvatar: data['callerAvatar'] ?? '',
      calleeId: data['calleeId'] ?? '',
      calleeName: data['calleeName'] ?? '',
      calleeAvatar: data['calleeAvatar'] ?? '',
      callType: data['callType'] == 'video' ? CallType.video : CallType.voice,
      status: _parseStatus(data['status']),
      channelName: data['channelName'],
      token: data['token'],
      createdAt: _parseDate(data['createdAt']),
      connectedAt: _parseDateNullable(data['connectedAt']),
      endedAt: _parseDateNullable(data['endedAt']),
      durationSeconds: data['durationSeconds'] as int?,
    );
  }

  static CallStatus _parseStatus(String? status) {
    switch (status) {
      case 'calling':
        return CallStatus.calling;
      case 'ringing':
        return CallStatus.ringing;
      case 'connected':
        return CallStatus.connected;
      case 'ended':
        return CallStatus.ended;
      case 'missed':
        return CallStatus.missed;
      case 'declined':
        return CallStatus.declined;
      case 'failed':
        return CallStatus.failed;
      default:
        return CallStatus.calling;
    }
  }

  CallModel copyWith({
    String? callId,
    CallStatus? status,
    DateTime? connectedAt,
    DateTime? endedAt,
    int? durationSeconds,
    String? token,
    String? channelName,
  }) {
    return CallModel(
      callId: callId ?? this.callId,
      callerId: callerId,
      callerName: callerName,
      callerAvatar: callerAvatar,
      calleeId: calleeId,
      calleeName: calleeName,
      calleeAvatar: calleeAvatar,
      callType: callType,
      status: status ?? this.status,
      channelName: channelName ?? this.channelName,
      token: token ?? this.token,
      createdAt: createdAt,
      connectedAt: connectedAt ?? this.connectedAt,
      endedAt: endedAt ?? this.endedAt,
      durationSeconds: durationSeconds ?? this.durationSeconds,
    );
  }

  String get formattedDuration {
    if (durationSeconds == null) return '';
    final minutes = durationSeconds! ~/ 60;
    final seconds = durationSeconds! % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  bool get isVideoCall => callType == CallType.video;
  bool get isVoiceCall => callType == CallType.voice;
  bool get isActive =>
      status == CallStatus.calling ||
      status == CallStatus.ringing ||
      status == CallStatus.connected;
}
