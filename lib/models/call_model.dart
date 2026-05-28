import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────
// Enums
// ─────────────────────────────────────────────────────────────

enum CallType { voice, video }

enum CallStatus {
  dialing,
  calling,
  ringing,
  accepted,
  connected,
  rejected,
  declined,
  ended,
  missed,
  failed,
}

// ─────────────────────────────────────────────────────────────
// Extension helpers
// ─────────────────────────────────────────────────────────────

extension CallStatusX on CallStatus {
  bool get isActive => const {
        CallStatus.dialing,
        CallStatus.calling,
        CallStatus.ringing,
        CallStatus.accepted,
        CallStatus.connected,
      }.contains(this);

  bool get isTerminal => const {
        CallStatus.ended,
        CallStatus.rejected,
        CallStatus.declined,
        CallStatus.missed,
        CallStatus.failed,
      }.contains(this);

  String get label {
    switch (this) {
      case CallStatus.dialing:
        return 'dialing';
      case CallStatus.calling:
        return 'calling';
      case CallStatus.ringing:
        return 'ringing';
      case CallStatus.accepted:
        return 'accepted';
      case CallStatus.connected:
        return 'connected';
      case CallStatus.rejected:
        return 'rejected';
      case CallStatus.declined:
        return 'declined';
      case CallStatus.ended:
        return 'ended';
      case CallStatus.missed:
        return 'missed';
      case CallStatus.failed:
        return 'failed';
    }
  }
}

extension CallTypeX on CallType {
  bool get isVideo => this == CallType.video;
  bool get isVoice => this == CallType.voice;
  String get label => isVideo ? 'video' : 'voice';
}

// ─────────────────────────────────────────────────────────────
// Model
// ─────────────────────────────────────────────────────────────

class CallModel {
  final String callId;
  final String callerId;
  final String callerName;
  final String callerAvatar;
  final String calleeId;
  final String calleeName;
  final String calleeAvatar;
  final String channelName;
  final CallType callType;
  final CallStatus status;
  final String? token;
  final DateTime createdAt;
  final DateTime? connectedAt;
  final DateTime? endedAt;
  final DateTime? expiresAt; // <-- ĐÃ THÊM
  final int? durationSeconds;

  const CallModel({
    required this.callId,
    required this.callerId,
    required this.callerName,
    required this.callerAvatar,
    required this.calleeId,
    required this.calleeName,
    required this.calleeAvatar,
    required this.channelName,
    required this.callType,
    required this.status,
    required this.createdAt,
    this.token,
    this.connectedAt,
    this.endedAt,
    this.expiresAt, // <-- ĐÃ THÊM
    this.durationSeconds,
  });

  // ── Convenience getters ──────────────────────────────────

  bool get isVideoCall => callType.isVideo;
  bool get isVoiceCall => callType.isVoice;
  bool get isActive => status.isActive;
  bool get isTerminal => status.isTerminal;

  String get formattedDuration {
    if (durationSeconds == null || durationSeconds! <= 0) return '';
    final h = durationSeconds! ~/ 3600;
    final m = (durationSeconds! % 3600) ~/ 60;
    final s = durationSeconds! % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  // ── Factory constructors ─────────────────────────────────

  factory CallModel.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return CallModel.fromJson({...data, 'callId': data['callId'] ?? doc.id});
  }

  factory CallModel.fromJson(Map<String, dynamic> d) {
    return CallModel(
      callId: d['callId'] ?? d['id'] ?? '',
      callerId: d['callerId'] ?? '',
      callerName: d['callerName'] ?? '',
      callerAvatar: d['callerAvatar'] ?? d['callerPic'] ?? '',
      calleeId: d['calleeId'] ?? d['receiverId'] ?? '',
      calleeName: d['calleeName'] ?? d['receiverName'] ?? '',
      calleeAvatar: d['calleeAvatar'] ?? d['receiverPic'] ?? '',
      channelName: d['channelName'] ?? d['channelId'] ?? '',
      callType: _parseCallType(d),
      status: _parseStatus(d['status']),
      token: d['token'] as String?,
      createdAt: _parseDate(d['createdAt']) ??
          _parseDateFromMillis(d['timestamp']) ??
          DateTime.now(),
      connectedAt: _parseDateNullable(d['connectedAt']),
      endedAt: _parseDateNullable(d['endedAt']),
      expiresAt: _parseDateNullable(d['expiresAt']), // <-- ĐÃ THÊM
      durationSeconds: d['durationSeconds'] as int?,
    );
  }

  factory CallModel.fromMap(Map<String, dynamic> map) =>
      CallModel.fromJson(map);

  // ── Serialization ────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'callId': callId,
        'callerId': callerId,
        'callerName': callerName,
        'callerAvatar': callerAvatar,
        'calleeId': calleeId,
        'calleeName': calleeName,
        'calleeAvatar': calleeAvatar,
        'channelName': channelName,
        'callType': callType.label,
        'isVideo': isVideoCall,
        'status': status.label,
        'token': token,
        'createdAt': createdAt.millisecondsSinceEpoch.toString(),
        'timestamp': createdAt.millisecondsSinceEpoch,
        'connectedAt': connectedAt?.millisecondsSinceEpoch.toString(),
        'endedAt': endedAt?.millisecondsSinceEpoch.toString(),
        'expiresAt':
            expiresAt?.millisecondsSinceEpoch.toString(), // <-- ĐÃ THÊM
        'durationSeconds': durationSeconds,
      };

  Map<String, dynamic> toMap() => toJson();

  // ── copyWith ─────────────────────────────────────────────

  CallModel copyWith({
    String? callId,
    String? callerId,
    String? callerName,
    String? callerAvatar,
    String? calleeId,
    String? calleeName,
    String? calleeAvatar,
    String? channelName,
    CallType? callType,
    CallStatus? status,
    String? token,
    DateTime? createdAt,
    DateTime? connectedAt,
    DateTime? endedAt,
    DateTime? expiresAt, // <-- ĐÃ THÊM
    int? durationSeconds,
  }) {
    return CallModel(
      callId: callId ?? this.callId,
      callerId: callerId ?? this.callerId,
      callerName: callerName ?? this.callerName,
      callerAvatar: callerAvatar ?? this.callerAvatar,
      calleeId: calleeId ?? this.calleeId,
      calleeName: calleeName ?? this.calleeName,
      calleeAvatar: calleeAvatar ?? this.calleeAvatar,
      channelName: channelName ?? this.channelName,
      callType: callType ?? this.callType,
      status: status ?? this.status,
      token: token ?? this.token,
      createdAt: createdAt ?? this.createdAt,
      connectedAt: connectedAt ?? this.connectedAt,
      endedAt: endedAt ?? this.endedAt,
      expiresAt: expiresAt ?? this.expiresAt, // <-- ĐÃ THÊM
      durationSeconds: durationSeconds ?? this.durationSeconds,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CallModel && other.callId == callId && other.status == status);

  @override
  int get hashCode => Object.hash(callId, status);

  @override
  String toString() =>
      'CallModel(id: $callId, status: ${status.label}, type: ${callType.label})';

  // ── Private helpers ──────────────────────────────────────

  static CallType _parseCallType(Map<String, dynamic> d) {
    final raw = d['callType'];
    if (raw == 'video') return CallType.video;
    if (raw == 'voice') return CallType.voice;
    final isVideo = d['isVideo'];
    if (isVideo is bool) return isVideo ? CallType.video : CallType.voice;
    return CallType.video; // safe default
  }

  static CallStatus _parseStatus(dynamic s) {
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

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) {
      final ms = int.tryParse(value);
      if (ms != null) return DateTime.fromMillisecondsSinceEpoch(ms);
      return DateTime.tryParse(value);
    }
    return null;
  }

  static DateTime? _parseDateFromMillis(dynamic value) {
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }

  static DateTime? _parseDateNullable(dynamic value) => _parseDate(value);
}
