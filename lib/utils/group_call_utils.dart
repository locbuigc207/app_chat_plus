import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/group_call_model.dart';
import 'group_call_constants.dart';

// ══════════════════════════════════════════════════════════════════════════════
// GroupCallUtils
// Utility functions for group call feature
// ══════════════════════════════════════════════════════════════════════════════
class GroupCallUtils {
  GroupCallUtils._();

  // ── Duration formatting ────────────────────────────────────────────────────

  /// Format seconds → "mm:ss" or "h:mm:ss"
  static String formatDuration(int totalSeconds) {
    if (totalSeconds <= 0) return '00:00';
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600 ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  /// Format Duration object → "mm:ss"
  static String formatDurationObj(Duration d) => formatDuration(d.inSeconds);

  /// Human-readable: "5 phút 23 giây" or "2 giờ 10 phút"
  static String formatDurationVerbose(int totalSeconds) {
    if (totalSeconds <= 0) return '0 giây';
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) return '$h giờ $m phút';
    if (m > 0) return '$m phút $s giây';
    return '$s giây';
  }

  // ── Channel name ───────────────────────────────────────────────────────────

  /// Build a valid Agora channel name from callId
  static String buildChannelName(String callId) =>
      'grp_${callId.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')}';

  /// Build a unique callId from groupId
  static String buildCallId(String groupId) =>
      '${groupId}_${DateTime.now().millisecondsSinceEpoch}';

  // ── Participant helpers ────────────────────────────────────────────────────

  /// Get sorted participants: admin first, then by join time
  static List<GroupCallParticipant> sortedParticipants(
      List<GroupCallParticipant> participants) {
    final sorted = List<GroupCallParticipant>.from(participants);
    sorted.sort((a, b) {
      if (a.isAdmin && !b.isAdmin) return -1;
      if (!a.isAdmin && b.isAdmin) return 1;
      if (a.isCoHost && !b.isCoHost) return -1;
      if (!a.isCoHost && b.isCoHost) return 1;
      return a.joinedAt.compareTo(b.joinedAt);
    });
    return sorted;
  }

  /// Get display name for participant (self → "Bạn")
  static String displayName(GroupCallParticipant p, String currentUserId) =>
      p.userId == currentUserId ? 'Bạn' : p.userName;

  /// Count how many participants have audio on
  static int audioOnCount(List<GroupCallParticipant> participants) =>
      participants.where((p) => !p.isMuted).length;

  /// Count how many participants have video on
  static int videoOnCount(List<GroupCallParticipant> participants) =>
      participants.where((p) => !p.isCameraOff).length;

  // ── Grid layout ────────────────────────────────────────────────────────────

  /// Calculate optimal grid column count for N remote participants
  static int gridColumns(int remoteCount) {
    if (remoteCount <= 1) return 1;
    if (remoteCount <= 4) return 2;
    return 3;
  }

  /// Calculate optimal aspect ratio for grid cells
  static double gridAspectRatio(int columns) {
    if (columns == 1) return 0.75;
    if (columns == 2) return 0.90;
    return 1.0;
  }

  // ── Avatar initials ────────────────────────────────────────────────────────

  /// Get initials from name (max 2 chars)
  static String initials(String name) {
    if (name.isEmpty) return '?';
    final parts = name.trim().split(' ');
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  // ── Reaction aggregation ───────────────────────────────────────────────────

  /// Aggregate reactions into count map, sorted by count desc
  static Map<CallReactionType, int> aggregateReactions(
      List<CallReaction> reactions) {
    final map = <CallReactionType, int>{};
    for (final r in reactions) {
      map[r.type] = (map[r.type] ?? 0) + 1;
    }
    final sorted = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(sorted);
  }

  /// Get total reaction count
  static int totalReactions(List<CallReaction> reactions) => reactions.length;

  // ── Network quality ────────────────────────────────────────────────────────

  /// Calculate quality level 1-4 from RTT and packet loss
  static int networkQualityLevel({required int rtt, required int packetLoss}) {
    if (rtt == 0 && packetLoss == 0) return 4; // no data yet
    if (rtt < 80 && packetLoss < 2) return 4; // excellent
    if (rtt < 160 && packetLoss < 5) return 3; // good
    if (rtt < 300 && packetLoss < 12) return 2; // poor
    return 1; // bad
  }

  static String networkQualityLabel(int level) {
    switch (level) {
      case 4:
        return 'Xuất sắc';
      case 3:
        return 'Tốt';
      case 2:
        return 'Yếu';
      default:
        return 'Kém';
    }
  }

  static Color networkQualityColor(int level) {
    switch (level) {
      case 4:
        return GroupCallTheme.green;
      case 3:
        return const Color(0xFFAED581);
      case 2:
        return GroupCallTheme.amber;
      default:
        return GroupCallTheme.red;
    }
  }

  // ── Call type helpers ──────────────────────────────────────────────────────

  static String callTypeLabel(GroupCallType type) => type == GroupCallType.video
      ? 'Cuộc gọi video nhóm'
      : 'Cuộc gọi thoại nhóm';

  static String callTypeIcon(GroupCallType type) =>
      type == GroupCallType.video ? '📹' : '📞';

  static Color callTypeColor(GroupCallType type) => type == GroupCallType.video
      ? GroupCallTheme.accent
      : GroupCallTheme.green;

  // ── Time formatting ────────────────────────────────────────────────────────

  static String formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return 'Vừa xong';
    if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
    if (diff.inHours < 24) return '${diff.inHours} giờ trước';
    if (diff.inDays == 1) return 'Hôm qua';
    if (diff.inDays < 7) return '${diff.inDays} ngày trước';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  static String formatTimeHHMM(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  // ── Color from userId (avatar fallback color) ──────────────────────────────

  static Color colorFromId(String id) {
    const colors = [
      Color(0xFF3B82F6),
      Color(0xFF22C55E),
      Color(0xFFF59E0B),
      Color(0xFF8B5CF6),
      Color(0xFFEF4444),
      Color(0xFF06B6D4),
      Color(0xFFEC4899),
      Color(0xFF14B8A6),
    ];
    if (id.isEmpty) return colors[0];
    int hash = 0;
    for (final c in id.codeUnits) hash = (hash * 31 + c) & 0xFFFFFF;
    return colors[hash % colors.length];
  }

  // ── Validation ─────────────────────────────────────────────────────────────

  /// Check if a call can be joined
  static bool canJoinCall(GroupCallModel call, String userId) {
    if (call.isEnded) return false;
    if (call.status == GroupCallStatus.missed) return false;
    if (call.isKicked(userId)) return false;
    if (call.participants.length >= GroupCallConstants.maxParticipants)
      return false;
    return true;
  }

  /// Check if user is already in call
  static bool isAlreadyInCall(GroupCallModel call, String userId) =>
      call.participants.any((p) => p.userId == userId);

  // ── Stats summary ──────────────────────────────────────────────────────────

  /// Build a summary string for ended call
  static String buildSummary(GroupCallModel call) {
    final dur = call.durationSeconds;
    final parts = <String>[];
    if (dur != null && dur > 0) parts.add(formatDurationVerbose(dur));
    parts.add('${call.participantCount} người');
    return parts.join(' • ');
  }

  // ── Random utils ───────────────────────────────────────────────────────────

  static final _rng = math.Random();

  /// Random x position for floating reactions (0.08 – 0.92)
  static double randomReactionX() => 0.08 + _rng.nextDouble() * 0.84;

  /// Random stagger delay for particle animations
  static Duration randomDelay({int maxMs = 300}) =>
      Duration(milliseconds: _rng.nextInt(maxMs));
}
