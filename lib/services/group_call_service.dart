import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/group_call_model.dart';

class GroupCallService {
  GroupCallService._();
  static final GroupCallService instance = GroupCallService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static const String _col = 'group_calls';
  static const int _timeoutSeconds = 60;
  static const int _historyLimit = 30;
  static const int _maxParticipants = 16;

  static const List<String> _activeStatuses = ['calling', 'ongoing', 'waiting'];

  final Map<String, Timer> _timeoutTimers = {};
  final Map<String, int> _lastReactionTimes = {};
  static const int _reactionCooldownMs = 400;

  String? get _uid => _auth.currentUser?.uid;
  CollectionReference<Map<String, dynamic>> get _calls => _db.collection(_col);
  String _tsNow() => DateTime.now().millisecondsSinceEpoch.toString();

  GroupCallModel? _parse(DocumentSnapshot<Object?> doc) {
    try {
      return GroupCallModel.fromDocument(doc);
    } catch (e) {
      debugPrint('❌ [GroupCallService] parse error (${doc.id}): $e');
      return null;
    }
  }

  // ── Initiate call ──────────────────────────────────────────────────────────
  Future<GroupCallModel?> initiateCall({
    required String groupId,
    required String groupName,
    required List<String> memberIds,
    required GroupCallType callType,
    String groupAvatarUrl = '',
    bool waitingRoomEnabled = false,
  }) async {
    final uid = _uid;
    if (uid == null) return null;

    try {
      final initiatorSnap = await _db.collection('users').doc(uid).get();
      final initiatorData = initiatorSnap.data() ?? {};
      final initiatorName = initiatorData['nickname'] as String? ?? 'User';
      final initiatorAvatar = initiatorData['photoUrl'] as String? ?? '';

      final existing = await _findActiveCallForGroup(groupId);
      if (existing != null) {
        debugPrint('⚠️ [GroupCallService] Group already has an active call');
        return null;
      }

      final otherIds = memberIds
          .where((id) => id != uid)
          .take(_maxParticipants - 1)
          .toList();
      final callId = '${groupId}_${DateTime.now().millisecondsSinceEpoch}';
      final channel = 'grp_${callId.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')}';
      final now = DateTime.now();

      final initiatorParticipant = GroupCallParticipant(
        userId: uid,
        userName: initiatorName,
        userAvatar: initiatorAvatar,
        joinedAt: now,
        isAdmin: true,
      );

      final model = GroupCallModel(
        callId: callId,
        groupId: groupId,
        groupName: groupName,
        groupAvatarUrl: groupAvatarUrl,
        initiatorId: uid,
        initiatorName: initiatorName,
        callType: callType,
        status: GroupCallStatus.calling,
        channelName: channel,
        participants: [initiatorParticipant],
        invitedUserIds: otherIds,
        createdAt: now,
        waitingRoomEnabled: waitingRoomEnabled,
      );

      await _calls.doc(callId).set(model.toJson());
      _scheduleTimeout(callId);
      debugPrint('✅ [GroupCallService] Call initiated: $callId');
      return model;
    } catch (e, st) {
      debugPrint('❌ [GroupCallService] initiateCall: $e\n$st');
      return null;
    }
  }

  // ── Join call ──────────────────────────────────────────────────────────────
  Future<bool> joinCall(String callId) async {
    final uid = _uid;
    if (uid == null) return false;

    try {
      final doc = await _calls.doc(callId).get();
      if (!doc.exists) return false;
      final call = _parse(doc);
      if (call == null) return false;

      if (call.isEnded || call.status == GroupCallStatus.missed) return false;
      if (call.isKicked(uid)) {
        debugPrint('⚠️ [GroupCallService] User was kicked');
        return false;
      }
      if (call.participants.length >= _maxParticipants) return false;
      if (call.participants.any((p) => p.userId == uid)) return true;

      final userSnap = await _db.collection('users').doc(uid).get();
      final userData = userSnap.data() ?? {};

      // Waiting room check
      if (call.waitingRoomEnabled && !call.isParticipant(uid)) {
        await _calls.doc(callId).update({
          'waitingRoomUserIds': FieldValue.arrayUnion([uid]),
        });
        debugPrint('⚠️ [GroupCallService] User added to waiting room: $uid');
        return false;
      }

      final participant = GroupCallParticipant(
        userId: uid,
        userName: userData['nickname'] as String? ?? 'User',
        userAvatar: userData['photoUrl'] as String? ?? '',
        joinedAt: DateTime.now(),
        isAdmin: false,
      );

      await _db.runTransaction((tx) async {
        final fresh = await tx.get(_calls.doc(callId));
        if (!fresh.exists) return;
        final freshCall = _parse(fresh);
        if (freshCall == null) return;
        if (freshCall.participants.length >= _maxParticipants) return;

        final updated = List<GroupCallParticipant>.from(freshCall.participants)
          ..removeWhere((p) => p.userId == uid)
          ..add(participant);

        tx.update(_calls.doc(callId), {
          'participants': updated.map((p) => p.toJson()).toList(),
          'status': GroupCallStatus.ongoing.name,
          'invitedUserIds': FieldValue.arrayRemove([uid]),
          'waitingRoomUserIds': FieldValue.arrayRemove([uid]),
        });
      });

      _cancelTimeout(callId);
      debugPrint('✅ [GroupCallService] Joined call: $callId');
      return true;
    } catch (e, st) {
      debugPrint('❌ [GroupCallService] joinCall: $e\n$st');
      return false;
    }
  }

  // ── Admit from waiting room ────────────────────────────────────────────────
  Future<bool> admitFromWaitingRoom({
    required String callId,
    required String targetUserId,
  }) async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      final doc = await _calls.doc(callId).get();
      final call = _parse(doc);
      if (call == null) return false;

      final self = call.getParticipant(uid);
      if (self == null || (!self.isAdmin && !self.isCoHost)) return false;

      final userSnap = await _db.collection('users').doc(targetUserId).get();
      final userData = userSnap.data() ?? {};
      final participant = GroupCallParticipant(
        userId: targetUserId,
        userName: userData['nickname'] as String? ?? 'User',
        userAvatar: userData['photoUrl'] as String? ?? '',
        joinedAt: DateTime.now(),
        isAdmin: false,
      );

      await _db.runTransaction((tx) async {
        final fresh = await tx.get(_calls.doc(callId));
        if (!fresh.exists) return;
        final freshCall = _parse(fresh);
        if (freshCall == null) return;

        final updated = List<GroupCallParticipant>.from(freshCall.participants)
          ..add(participant);
        tx.update(_calls.doc(callId), {
          'participants': updated.map((p) => p.toJson()).toList(),
          'waitingRoomUserIds': FieldValue.arrayRemove([targetUserId]),
        });
      });
      return true;
    } catch (e) {
      debugPrint('❌ [GroupCallService] admitFromWaitingRoom: $e');
      return false;
    }
  }

  // ── Leave call ─────────────────────────────────────────────────────────────
  Future<void> leaveCall(String callId) async {
    final uid = _uid;
    if (uid == null) return;

    try {
      await _db.runTransaction((tx) async {
        final doc = await tx.get(_calls.doc(callId));
        if (!doc.exists) return;
        final call = _parse(doc);
        if (call == null) return;

        final remaining =
            call.participants.where((p) => p.userId != uid).toList();

        if (remaining.isEmpty) {
          final duration = DateTime.now().difference(call.createdAt).inSeconds;
          tx.update(_calls.doc(callId), {
            'status': GroupCallStatus.ended.name,
            'endedAt': _tsNow(),
            'durationSeconds': duration,
            'participants': <Map<String, dynamic>>[],
          });
        } else {
          // Transfer admin if needed
          final updatedList = remaining.map((p) {
            if (call.initiatorId == uid && p.userId == remaining.first.userId) {
              return p.copyWith(isAdmin: true);
            }
            return p;
          }).toList();

          tx.update(_calls.doc(callId), {
            'participants': updatedList.map((p) => p.toJson()).toList(),
            if (call.screenShareUserId == uid)
              'screenShareUserId': FieldValue.delete(),
            if (call.pinnedUserId == uid) 'pinnedUserId': FieldValue.delete(),
          });
        }
      });

      _cancelTimeout(callId);
      debugPrint('✅ [GroupCallService] Left call: $callId');
    } catch (e, st) {
      debugPrint('❌ [GroupCallService] leaveCall: $e\n$st');
    }
  }

  // ── End call for all ───────────────────────────────────────────────────────
  Future<bool> endCallForAll(String callId, {DateTime? startTime}) async {
    try {
      final doc = await _calls.doc(callId).get();
      if (!doc.exists) return false;
      final call = _parse(doc);
      if (call == null) return false;

      final origin = startTime ?? call.createdAt;
      final duration = DateTime.now().difference(origin).inSeconds;

      await _calls.doc(callId).update({
        'status': GroupCallStatus.ended.name,
        'endedAt': _tsNow(),
        'durationSeconds': duration,
        'participants': <Map<String, dynamic>>[],
      });

      _cancelTimeout(callId);
      debugPrint('✅ [GroupCallService] Ended call for all: $callId');
      return true;
    } catch (e, st) {
      debugPrint('❌ [GroupCallService] endCallForAll: $e\n$st');
      return false;
    }
  }

  // ── Decline ────────────────────────────────────────────────────────────────
  Future<void> declineCall(String callId) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _calls.doc(callId).update({
        'invitedUserIds': FieldValue.arrayRemove([uid]),
        'declinedUserIds': FieldValue.arrayUnion([uid]),
      });
    } catch (e) {
      debugPrint('❌ [GroupCallService] declineCall: $e');
    }
  }

  // ── Update participant state ───────────────────────────────────────────────
  Future<void> updateParticipantState({
    required String callId,
    required bool isMuted,
    required bool isCameraOff,
    int? audioLevel,
  }) async {
    final uid = _uid;
    if (uid == null) return;

    try {
      await _db.runTransaction((tx) async {
        final doc = await tx.get(_calls.doc(callId));
        if (!doc.exists) return;
        final call = _parse(doc);
        if (call == null) return;

        final updated = call.participants.map((p) {
          if (p.userId == uid) {
            return p.copyWith(
              isMuted: isMuted,
              isCameraOff: isCameraOff,
              audioLevel: audioLevel ?? p.audioLevel,
            );
          }
          return p;
        }).toList();

        tx.update(_calls.doc(callId), {
          'participants': updated.map((p) => p.toJson()).toList(),
        });
      });
    } catch (e) {
      debugPrint('❌ [GroupCallService] updateParticipantState: $e');
    }
  }

  // ── Mute participant (admin only) ──────────────────────────────────────────
  Future<void> muteParticipant({
    required String callId,
    required String targetUserId,
    required bool mute,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _db.runTransaction((tx) async {
        final doc = await tx.get(_calls.doc(callId));
        if (!doc.exists) return;
        final call = _parse(doc);
        if (call == null) return;

        final self = call.getParticipant(uid);
        if (self == null || (!self.isAdmin && !self.isCoHost)) return;

        final updated = call.participants
            .map(
                (p) => p.userId == targetUserId ? p.copyWith(isMuted: mute) : p)
            .toList();

        tx.update(_calls.doc(callId), {
          'participants': updated.map((p) => p.toJson()).toList(),
        });
      });
    } catch (e) {
      debugPrint('❌ [GroupCallService] muteParticipant: $e');
    }
  }

  // ── Kick participant ───────────────────────────────────────────────────────
  Future<void> kickParticipant({
    required String callId,
    required String targetUserId,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _db.runTransaction((tx) async {
        final doc = await tx.get(_calls.doc(callId));
        if (!doc.exists) return;
        final call = _parse(doc);
        if (call == null) return;

        final self = call.getParticipant(uid);
        if (self == null || !self.isAdmin) return;

        final updated =
            call.participants.where((p) => p.userId != targetUserId).toList();

        tx.update(_calls.doc(callId), {
          'participants': updated.map((p) => p.toJson()).toList(),
          'kickedUserIds': FieldValue.arrayUnion([targetUserId]),
        });
      });
      debugPrint('✅ [GroupCallService] Kicked $targetUserId from $callId');
    } catch (e) {
      debugPrint('❌ [GroupCallService] kickParticipant: $e');
    }
  }

  // ── Pin participant ────────────────────────────────────────────────────────
  Future<void> pinParticipant(String callId, String? userId) async {
    try {
      await _calls.doc(callId).update({
        'pinnedUserId': userId,
      });
    } catch (e) {
      debugPrint('❌ [GroupCallService] pinParticipant: $e');
    }
  }

  // ── Raise/lower hand ──────────────────────────────────────────────────────
  Future<void> toggleRaiseHand({
    required String callId,
    required String userId,
    required bool raised,
  }) async {
    try {
      if (raised) {
        await _calls.doc(callId).update({
          'raisedHandUserIds': FieldValue.arrayUnion([userId]),
        });
      } else {
        await _calls.doc(callId).update({
          'raisedHandUserIds': FieldValue.arrayRemove([userId]),
        });
      }
    } catch (e) {
      debugPrint('❌ [GroupCallService] toggleRaiseHand: $e');
    }
  }

  // ── Screen share ───────────────────────────────────────────────────────────
  Future<void> updateScreenShare({
    required String callId,
    required String userId,
    required bool isSharing,
  }) async {
    try {
      await _calls.doc(callId).update({
        'screenShareUserId': isSharing ? userId : FieldValue.delete(),
      });
    } catch (e) {
      debugPrint('❌ [GroupCallService] updateScreenShare: $e');
    }
  }

  // ── Update layout ──────────────────────────────────────────────────────────
  Future<void> updateLayout(String callId, VideoLayoutMode mode) async {
    try {
      await _calls.doc(callId).update({'layoutMode': mode.name});
    } catch (e) {
      debugPrint('❌ [GroupCallService] updateLayout: $e');
    }
  }

  // ── Send reaction ──────────────────────────────────────────────────────────
  Future<void> sendReaction({
    required String callId,
    required String userId,
    required String userName,
    required CallReactionType reaction,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final lastTime = _lastReactionTimes[userId] ?? 0;
    if (now - lastTime < _reactionCooldownMs) return;
    _lastReactionTimes[userId] = now;

    try {
      final r = CallReaction(
        userId: userId,
        userName: userName,
        type: reaction,
        sentAt: DateTime.now(),
      );

      await _db.runTransaction((tx) async {
        final snap = await tx.get(_calls.doc(callId));
        if (!snap.exists) return;
        final data = snap.data()!;
        var recentReactions = List<dynamic>.from(data['recentReactions'] ?? []);
        recentReactions.add(r.toJson());
        if (recentReactions.length > 30) {
          recentReactions =
              recentReactions.sublist(recentReactions.length - 30);
        }
        tx.update(_calls.doc(callId), {'recentReactions': recentReactions});
      });
    } catch (e) {
      debugPrint('❌ [GroupCallService] sendReaction: $e');
    }
  }

  // ── Mute all (admin) ───────────────────────────────────────────────────────
  Future<void> muteAll(String callId) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _db.runTransaction((tx) async {
        final doc = await tx.get(_calls.doc(callId));
        if (!doc.exists) return;
        final call = _parse(doc);
        if (call == null) return;
        final self = call.getParticipant(uid);
        if (self == null || !self.isAdmin) return;

        final updated = call.participants
            .map((p) => p.userId == uid ? p : p.copyWith(isMuted: true))
            .toList();
        tx.update(_calls.doc(callId),
            {'participants': updated.map((p) => p.toJson()).toList()});
      });
    } catch (e) {
      debugPrint('❌ [GroupCallService] muteAll: $e');
    }
  }

  // ── Promote to co-host ─────────────────────────────────────────────────────
  Future<void> promoteToCoHost(String callId, String targetUserId) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _db.runTransaction((tx) async {
        final doc = await tx.get(_calls.doc(callId));
        if (!doc.exists) return;
        final call = _parse(doc);
        if (call == null) return;
        final self = call.getParticipant(uid);
        if (self == null || !self.isAdmin) return;

        final updated = call.participants
            .map((p) =>
                p.userId == targetUserId ? p.copyWith(isCoHost: true) : p)
            .toList();
        tx.update(_calls.doc(callId),
            {'participants': updated.map((p) => p.toJson()).toList()});
      });
    } catch (e) {
      debugPrint('❌ [GroupCallService] promoteToCoHost: $e');
    }
  }

  // ── Streams ────────────────────────────────────────────────────────────────
  Stream<GroupCallModel?> watchCall(String callId) => _calls
      .doc(callId)
      .snapshots()
      .map((doc) => doc.exists ? _parse(doc) : null);

  Stream<GroupCallModel?> incomingGroupCallStream(String userId) => _calls
      .where('invitedUserIds', arrayContains: userId)
      .where('status', whereIn: ['calling', 'waiting'])
      .orderBy('createdAt', descending: true)
      .limit(1)
      .snapshots()
      .map((snap) => snap.docs.isNotEmpty ? _parse(snap.docs.first) : null);

  Stream<GroupCallModel?> activeCallForGroup(String groupId) => _calls
      .where('groupId', isEqualTo: groupId)
      .where('status', whereIn: _activeStatuses)
      .orderBy('createdAt', descending: true)
      .limit(1)
      .snapshots()
      .map((snap) => snap.docs.isNotEmpty ? _parse(snap.docs.first) : null);

  Stream<List<GroupCallModel>> myActiveCallsStream() {
    final uid = _uid;
    if (uid == null) return Stream.value([]);

    return _calls
        .where('status', whereIn: _activeStatuses)
        .orderBy('createdAt', descending: true)
        .limit(10)
        .snapshots()
        .map((snap) {
      final calls = <GroupCallModel>[];
      for (final doc in snap.docs) {
        final c = _parse(doc);
        if (c == null) continue;
        final isParticipant = c.participants.any((p) => p.userId == uid);
        final isInvited = c.invitedUserIds.contains(uid);
        if (isParticipant || isInvited) calls.add(c);
      }
      return calls;
    });
  }

  // ── Fetch ──────────────────────────────────────────────────────────────────
  Future<GroupCallModel?> getCall(String callId) async {
    try {
      final doc = await _calls.doc(callId).get();
      return doc.exists ? _parse(doc) : null;
    } catch (_) {
      return null;
    }
  }

  Future<List<GroupCallModel>> getGroupCallHistory(String groupId,
      {int limit = 20}) async {
    try {
      final snap = await _calls
          .where('groupId', isEqualTo: groupId)
          .where('status', isEqualTo: GroupCallStatus.ended.name)
          .orderBy('createdAt', descending: true)
          .limit(limit.clamp(1, _historyLimit))
          .get();
      return snap.docs.map(_parse).whereType<GroupCallModel>().toList();
    } catch (e) {
      debugPrint('❌ [GroupCallService] getGroupCallHistory: $e');
      return [];
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────────
  Future<GroupCallModel?> _findActiveCallForGroup(String groupId) async {
    try {
      final snap = await _calls
          .where('groupId', isEqualTo: groupId)
          .where('status', whereIn: _activeStatuses)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      return _parse(snap.docs.first);
    } catch (e) {
      return null;
    }
  }

  void _scheduleTimeout(String callId) {
    _cancelTimeout(callId);
    _timeoutTimers[callId] = Timer(
      const Duration(seconds: _timeoutSeconds),
      () => _onTimeout(callId),
    );
  }

  void _cancelTimeout(String callId) {
    _timeoutTimers.remove(callId)?.cancel();
  }

  Future<void> _onTimeout(String callId) async {
    _timeoutTimers.remove(callId);
    try {
      final doc = await _calls.doc(callId).get();
      if (!doc.exists) return;
      final call = _parse(doc);
      if (call == null) return;

      if (call.isCalling && call.participants.length <= 1) {
        await _calls.doc(callId).update({
          'status': GroupCallStatus.missed.name,
          'endedAt': _tsNow(),
          'durationSeconds': 0,
          'participants': <Map<String, dynamic>>[],
        });
      }
    } catch (e) {
      debugPrint('❌ [GroupCallService] _onTimeout: $e');
    }
  }

  void dispose() {
    for (final t in _timeoutTimers.values) {
      t.cancel();
    }
    _timeoutTimers.clear();
  }
}
