import '../models/group_call_model.dart';

// ══════════════════════════════════════════════════════════════════════════════
// GroupCallMessageHelper
// Utilities for creating and parsing group-call-related chat messages.
// These system messages are stored in the messages collection alongside
// normal chat messages so users can see call history inline.
// ══════════════════════════════════════════════════════════════════════════════
class GroupCallMessageHelper {
  GroupCallMessageHelper._();

  // ── Message content builders ───────────────────────────────────────────────

  /// Build the JSON payload stored in message.content for a call-start message.
  static Map<String, dynamic> buildCallStartContent({
    required String callId,
    required GroupCallType callType,
    required String initiatorName,
    required String groupName,
    required String groupAvatarUrl,
  }) {
    return {
      'type': 'group_call_invite',
      'callId': callId,
      'callType': callType.name,
      'initiatorName': initiatorName,
      'groupName': groupName,
      'groupAvatarUrl': groupAvatarUrl,
      'startedAt': DateTime.now().millisecondsSinceEpoch.toString(),
    };
  }

  /// Build the JSON payload for a call-end system message.
  static Map<String, dynamic> buildCallEndContent({
    required String callId,
    required GroupCallType callType,
    required int durationSeconds,
    required int participantCount,
    required String? recordingUrl,
  }) {
    return {
      'type': 'group_call_ended',
      'callId': callId,
      'callType': callType.name,
      'durationSeconds': durationSeconds,
      'participantCount': participantCount,
      if (recordingUrl != null && recordingUrl.isNotEmpty)
        'recordingUrl': recordingUrl,
      'endedAt': DateTime.now().millisecondsSinceEpoch.toString(),
    };
  }

  /// Build the JSON payload for a missed-call system message.
  static Map<String, dynamic> buildCallMissedContent({
    required String callId,
    required GroupCallType callType,
    required String initiatorName,
  }) {
    return {
      'type': 'group_call_missed',
      'callId': callId,
      'callType': callType.name,
      'initiatorName': initiatorName,
      'missedAt': DateTime.now().millisecondsSinceEpoch.toString(),
    };
  }

  // ── Parsing ────────────────────────────────────────────────────────────────

  static bool isGroupCallMessage(Map<String, dynamic>? content) {
    if (content == null) return false;
    final t = content['type'] as String? ?? '';
    return t.startsWith('group_call');
  }

  static GroupCallMessageType parseType(Map<String, dynamic> content) {
    switch (content['type'] as String? ?? '') {
      case 'group_call_invite':
        return GroupCallMessageType.invite;
      case 'group_call_ended':
        return GroupCallMessageType.ended;
      case 'group_call_missed':
        return GroupCallMessageType.missed;
      default:
        return GroupCallMessageType.invite;
    }
  }

  static String getCallId(Map<String, dynamic> content) =>
      content['callId'] as String? ?? '';

  static GroupCallType getCallType(Map<String, dynamic> content) =>
      (content['callType'] as String?) == 'voice'
          ? GroupCallType.voice
          : GroupCallType.video;

  static int getDuration(Map<String, dynamic> content) =>
      (content['durationSeconds'] as int?) ?? 0;

  static String? getRecordingUrl(Map<String, dynamic> content) =>
      content['recordingUrl'] as String?;

  // ── Display helpers ────────────────────────────────────────────────────────

  static String buildSummaryText(Map<String, dynamic> content) {
    final type = parseType(content);
    final callType = getCallType(content);
    final typeLabel = callType == GroupCallType.video ? 'video' : 'thoại';

    switch (type) {
      case GroupCallMessageType.invite:
        return '📞 Cuộc gọi $typeLabel nhóm';
      case GroupCallMessageType.ended:
        final dur = getDuration(content);
        final m = (dur ~/ 60).toString().padLeft(2, '0');
        final s = (dur % 60).toString().padLeft(2, '0');
        return '📞 Cuộc gọi $typeLabel • $m:$s';
      case GroupCallMessageType.missed:
        return '📞 Cuộc gọi $typeLabel nhỡ';
    }
  }
}

enum GroupCallMessageType { invite, ended, missed }

// ══════════════════════════════════════════════════════════════════════════════
// TypeMessage extension
// Adds group-call type constants to the existing TypeMessage enum.
// ══════════════════════════════════════════════════════════════════════════════

/// Message type values for group calls stored in Firestore.
/// These must match the int values used in your TypeMessage enum or class.
class GroupCallMessageTypes {
  GroupCallMessageTypes._();

  /// Stores a call invite / ongoing call card. Value = 20
  static const int groupCallInvite = 20;

  /// Stores a call-ended summary card.  Value = 21
  static const int groupCallEnded = 21;

  /// Stores a missed-call card.         Value = 22
  static const int groupCallMissed = 22;
}
