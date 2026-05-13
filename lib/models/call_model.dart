// lib/models/call_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

enum CallType { voice, video }

enum CallStatus {
  dialing, // Caller đang quay số (tương đương 'calling')
  calling, // Caller đang chờ bắt máy
  ringing, // Callee đang nhận cuộc gọi
  accepted, // Callee đã chấp nhận (tương đương 'connected')
  connected, // Cả hai đã kết nối
  rejected, // Callee từ chối (tương đương 'declined')
  declined, // Callee từ chối
  ended, // Cuộc gọi kết thúc bình thường
  missed, // Không được nghe máy
  failed, // Cuộc gọi thất bại do lỗi
}

class CallModel {
  final String callId; // doc ID phía Firestore / id phía Realtime
  final String callerId;
  final String callerName;
  final String callerAvatar; // callerPic
  final String calleeId; // receiverId
  final String calleeName; // receiverName
  final String calleeAvatar; // receiverPic
  final String channelName; // channelId – Agora channel
  final CallType callType; // isVideo → video : voice
  final CallStatus status;
  final String? token; // Agora token (null = no-auth mode)
  final DateTime createdAt; // timestamp
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
    required this.channelName,
    CallType? callType,
    bool isVideo = true,
    CallStatus? status,
    String statusStr = 'dialing',
    this.token,
    DateTime? createdAt,
    int? timestamp,
    this.connectedAt,
    this.endedAt,
    this.durationSeconds,
  })  : callType = callType ?? (isVideo ? CallType.video : CallType.voice),
        status = status ?? _parseStatus(statusStr),
        createdAt = createdAt ??
            (timestamp != null
                ? DateTime.fromMillisecondsSinceEpoch(timestamp)
                : DateTime.now());

  // ─── Serialization ───────────────────────────────────────────────────────────

  /// Dùng cho Firestore (DocumentSnapshot)
  factory CallModel.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CallModel.fromJson(data);
  }

  /// Dùng cho Firestore / JSON
  factory CallModel.fromJson(Map<String, dynamic> data) {
    return CallModel(
      callId: data['callId'] ?? data['id'] ?? '',
      callerId: data['callerId'] ?? '',
      callerName: data['callerName'] ?? '',
      callerAvatar: data['callerAvatar'] ?? data['callerPic'] ?? '',
      calleeId: data['calleeId'] ?? data['receiverId'] ?? '',
      calleeName: data['calleeName'] ?? data['receiverName'] ?? '',
      calleeAvatar: data['calleeAvatar'] ?? data['receiverPic'] ?? '',
      channelName: data['channelName'] ?? data['channelId'] ?? '',
      callType: data['callType'] == 'video'
          ? CallType.video
          : data['callType'] == 'voice'
              ? CallType.voice
              : null,
      isVideo: data['isVideo'] ?? true,
      statusStr: data['status'] ?? 'dialing',
      token: data['token'],
      createdAt: _parseDate(data['createdAt']),
      timestamp: data['timestamp'] is int ? data['timestamp'] as int : null,
      connectedAt: _parseDateNullable(data['connectedAt']),
      endedAt: _parseDateNullable(data['endedAt']),
      durationSeconds: data['durationSeconds'] as int?,
    );
  }

  /// Dùng cho Realtime Database / toMap()
  factory CallModel.fromMap(Map<String, dynamic> map) =>
      CallModel.fromJson(map);

  /// Xuất ra Firestore
  Map<String, dynamic> toJson() => {
        'callId': callId,
        'callerId': callerId,
        'callerName': callerName,
        'callerAvatar': callerAvatar,
        'calleeId': calleeId,
        'calleeName': calleeName,
        'calleeAvatar': calleeAvatar,
        'channelName': channelName,
        'callType': callType.name,
        'isVideo': isVideoCall, // backward-compat
        'status': status.name,
        'token': token,
        'createdAt': createdAt.millisecondsSinceEpoch.toString(),
        'timestamp': createdAt.millisecondsSinceEpoch, // backward-compat
        'connectedAt': connectedAt?.millisecondsSinceEpoch.toString(),
        'endedAt': endedAt?.millisecondsSinceEpoch.toString(),
        'durationSeconds': durationSeconds,
      };

  /// Alias cho Realtime Database
  Map<String, dynamic> toMap() => toJson();

  // ─── CopyWith ────────────────────────────────────────────────────────────────

  CallModel copyWith({
    String? callId,
    CallStatus? status,
    String? channelName,
    String? token,
    DateTime? connectedAt,
    DateTime? endedAt,
    int? durationSeconds,
  }) {
    return CallModel(
      callId: callId ?? this.callId,
      callerId: callerId,
      callerName: callerName,
      callerAvatar: callerAvatar,
      calleeId: calleeId,
      calleeName: calleeName,
      calleeAvatar: calleeAvatar,
      channelName: channelName ?? this.channelName,
      callType: callType,
      status: status ?? this.status,
      token: token ?? this.token,
      createdAt: createdAt,
      connectedAt: connectedAt ?? this.connectedAt,
      endedAt: endedAt ?? this.endedAt,
      durationSeconds: durationSeconds ?? this.durationSeconds,
    );
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────────

  bool get isVideoCall => callType == CallType.video;
  bool get isVoiceCall => callType == CallType.voice;

  bool get isActive =>
      status == CallStatus.dialing ||
      status == CallStatus.calling ||
      status == CallStatus.ringing ||
      status == CallStatus.accepted ||
      status == CallStatus.connected;

  String get formattedDuration {
    if (durationSeconds == null) return '';
    final minutes = durationSeconds! ~/ 60;
    final seconds = durationSeconds! % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  // ─── Private ─────────────────────────────────────────────────────────────────

  static CallStatus _parseStatus(String? s) {
    switch (s) {
      case 'dialing':
        return CallStatus.dialing;
      case 'calling':
        return CallStatus.calling;
      case 'ringing':
        return CallStatus.ringing;
      case 'accepted':
        return CallStatus.accepted;
      case 'connected':
        return CallStatus.connected;
      case 'rejected':
        return CallStatus.rejected;
      case 'declined':
        return CallStatus.declined;
      case 'ended':
        return CallStatus.ended;
      case 'missed':
        return CallStatus.missed;
      case 'failed':
        return CallStatus.failed;
      default:
        return CallStatus.dialing;
    }
  }

  static DateTime _parseDate(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is String) {
      final ms = int.tryParse(value);
      if (ms != null) return DateTime.fromMillisecondsSinceEpoch(ms);
    }
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is Timestamp) return value.toDate();
    return DateTime.now();
  }

  static DateTime? _parseDateNullable(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      final ms = int.tryParse(value);
      if (ms != null) return DateTime.fromMillisecondsSinceEpoch(ms);
    }
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is Timestamp) return value.toDate();
    return null;
  }
}
