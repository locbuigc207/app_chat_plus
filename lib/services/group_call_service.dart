import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/group_call_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GroupCallService
//
// Handles all Firestore signalling for group calls:
//   • initiate / join / leave / end
//   • participant media-state sync (muted, camera)
//   • real-time streams (incoming, active, watch)
//   • history fetch
//   • automatic timeout / cleanup
// ─────────────────────────────────────────────────────────────────────────────

class GroupCallService {
  GroupCallService._();
  static final GroupCallService instance = GroupCallService._();

  // ── Firebase ───────────────────────────────────────────────────────────────
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ── Constants ──────────────────────────────────────────────────────────────
  static const String _col = 'group_calls';
  static const int _timeoutSeconds = 45;
  static const int _historyLimit = 30;
  static const int _maxParticipants = 16;

  static const List<String> _activeStatuses = [
    'calling',
    'ongoing',
  ];

  // ── Internal state ─────────────────────────────────────────────────────────
  /// Tracks pending timeout timers keyed by callId so they can be cancelled.
  final Map<String, Timer> _timeoutTimers = {};

  // ── Helpers ────────────────────────────────────────────────────────────────
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

  // ═══════════════════════════════════════════════════════════════════════════
  // INITIATE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Creates a new group call document and returns the [GroupCallModel].
  /// Returns null on any error.
  Future<GroupCallModel?> initiateCall({
    required String groupId,
    required String groupName,
    required List<String> memberIds,
    required GroupCallType callType,
    String groupAvatarUrl = '',
  }) async {
    final uid = _uid;
    if (uid == null) {
      debugPrint('❌ [GroupCallService] initiateCall: not signed in');
      return null;
    }

    try {
      // Fetch initiator profile
      final initiatorSnap = await _db.collection('users').doc(uid).get();
      final initiatorData = initiatorSnap.data() ?? {};
      final initiatorName = initiatorData['nickname'] as String? ?? 'User';
      final initiatorAvatar = initiatorData['photoUrl'] as String? ?? '';

      // Guard: already an active call in this group?
      final existing = await _findActiveCallForGroup(groupId);
      if (existing != null) {
        debugPrint('⚠️ [GroupCallService] Group already has an active call');
        return null;
      }

      // Cap participant list
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
        isMuted: false,
        isCameraOff: false,
      );

      final model = GroupCallModel(
        callId: callId,
        groupId: groupId,
        groupName: groupName,
        initiatorId: uid,
        initiatorName: initiatorName,
        callType: callType,
        status: GroupCallStatus.calling,
        channelName: channel,
        participants: [initiatorParticipant],
        invitedUserIds: otherIds,
        createdAt: now,
      );

      await _calls.doc(callId).set(model.toJson());
      debugPrint('✅ [GroupCallService] Call initiated: $callId');

      _scheduleTimeout(callId);
      return model;
    } catch (e, st) {
      debugPrint('❌ [GroupCallService] initiateCall: $e\n$st');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // JOIN
  // ═══════════════════════════════════════════════════════════════════════════

  /// Adds the current user to [callId]'s participant list.
  /// Returns false if the call is full, already ended, or an error occurs.
  Future<bool> joinCall(String callId) async {
    final uid = _uid;
    if (uid == null) return false;

    try {
      final doc = await _calls.doc(callId).get();
      if (!doc.exists) {
        debugPrint('⚠️ [GroupCallService] joinCall: call not found');
        return false;
      }

      final call = _parse(doc);
      if (call == null) return false;

      // Reject if ended
      if (call.status == GroupCallStatus.ended ||
          call.status == GroupCallStatus.missed) {
        debugPrint('⚠️ [GroupCallService] joinCall: call already ended');
        return false;
      }

      // Reject if full
      if (call.participants.length >= _maxParticipants) {
        debugPrint('⚠️ [GroupCallService] joinCall: call is full');
        return false;
      }

      // Reject if already in the call
      if (call.participants.any((p) => p.userId == uid)) {
        debugPrint('ℹ️ [GroupCallService] joinCall: already a participant');
        return true;
      }

      final userSnap = await _db.collection('users').doc(uid).get();
      final userData = userSnap.data() ?? {};

      final participant = GroupCallParticipant(
        userId: uid,
        userName: userData['nickname'] as String? ?? 'User',
        userAvatar: userData['photoUrl'] as String? ?? '',
        joinedAt: DateTime.now(),
        isAdmin: false,
        isMuted: false,
        isCameraOff: false,
      );

      // Use a transaction to avoid race conditions on participant list
      await _db.runTransaction((tx) async {
        final fresh = await tx.get(_calls.doc(callId));
        if (!fresh.exists) return;
        final freshCall = _parse(fresh);
        if (freshCall == null) return;
        if (freshCall.participants.length >= _maxParticipants) return;

        final updated = List<GroupCallParticipant>.from(freshCall.participants)
          ..removeWhere((p) => p.userId == uid) // idempotent
          ..add(participant);

        tx.update(_calls.doc(callId), {
          'participants': updated.map((p) => p.toJson()).toList(),
          'status': GroupCallStatus.ongoing.name,
          // Remove from invited once joined
          'invitedUserIds': FieldValue.arrayRemove([uid]),
        });
      });

      // Cancel any pending timeout — someone joined
      _cancelTimeout(callId);

      debugPrint('✅ [GroupCallService] Joined call: $callId');
      return true;
    } catch (e, st) {
      debugPrint('❌ [GroupCallService] joinCall: $e\n$st');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LEAVE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Removes the current user from the call.
  /// If they are the last participant, the call is ended automatically.
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
          // Last person left — end the call
          final duration = DateTime.now().difference(call.createdAt).inSeconds;
          tx.update(_calls.doc(callId), {
            'status': GroupCallStatus.ended.name,
            'endedAt': _tsNow(),
            'durationSeconds': duration,
            'participants': <Map<String, dynamic>>[],
          });
        } else {
          // Hand off admin if the leaving user was admin
          final updatedList = remaining.map((p) {
            if (call.initiatorId == uid && p.userId == remaining.first.userId) {
              return p.copyWith(isAdmin: true);
            }
            return p;
          }).toList();

          tx.update(_calls.doc(callId), {
            'participants': updatedList.map((p) => p.toJson()).toList(),
          });
        }
      });

      _cancelTimeout(callId);
      debugPrint('✅ [GroupCallService] Left call: $callId');
    } catch (e, st) {
      debugPrint('❌ [GroupCallService] leaveCall: $e\n$st');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // END FOR ALL (admin action)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Force-ends the call for everyone. Only the initiator / admin should call this.
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

  // ═══════════════════════════════════════════════════════════════════════════
  // DECLINE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Removes the current user from the invited list without joining.
  Future<void> declineCall(String callId) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _calls.doc(callId).update({
        'invitedUserIds': FieldValue.arrayRemove([uid]),
      });
      debugPrint('✅ [GroupCallService] Declined call: $callId');
    } catch (e) {
      debugPrint('❌ [GroupCallService] declineCall: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PARTICIPANT STATE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Syncs local mute / camera state to Firestore so other participants see it.
  Future<void> updateParticipantState({
    required String callId,
    required bool isMuted,
    required bool isCameraOff,
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
            return p.copyWith(isMuted: isMuted, isCameraOff: isCameraOff);
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

  /// Mutes or unmutes a specific participant (admin-only action).
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

        // Only admin can mute others
        final self =
            call.participants.where((p) => p.userId == uid).firstOrNull;
        if (self == null || !self.isAdmin) return;

        final updated = call.participants.map((p) {
          if (p.userId == targetUserId) return p.copyWith(isMuted: mute);
          return p;
        }).toList();

        tx.update(_calls.doc(callId), {
          'participants': updated.map((p) => p.toJson()).toList(),
        });
      });
    } catch (e) {
      debugPrint('❌ [GroupCallService] muteParticipant: $e');
    }
  }

  /// Removes a participant from the call (admin kick).
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

        final self =
            call.participants.where((p) => p.userId == uid).firstOrNull;
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
// ═══════════════════════════════════════════════════════════════════════════
  // TƯƠNG TÁC NÂNG CAO (RAISE HAND QUEUE, SCREEN SHARE APPROVAL, REACTIONS)
  // ═══════════════════════════════════════════════════════════════════════════

  // Bộ đệm (Throttling) để chống spam reaction ở phía Client
  final Map<String, int> _lastReactionTimes = {};
  static const int _reactionCooldownMs =
      500; // Giới hạn 2 reactions/giây mỗi user

  /// 1. RAISE HAND SYSTEM (Queue & Timestamp)
  /// Nâng cấp: Lưu dưới dạng Object {userId, raisedAt} để tạo hàng đợi (Queue)
  /// cho phép Host mời người giơ tay sớm nhất phát biểu.
  Future<void> toggleRaiseHand({
    required String callId,
    required String userId,
    required bool raised,
  }) async {
    try {
      final docRef = _calls.doc(callId);

      if (raised) {
        // Thay vì chỉ lưu String, ta lưu Object chứa thời gian để sắp xếp Queue
        final handData = {
          'userId': userId,
          'raisedAt': FieldValue.serverTimestamp(),
        };
        await docRef.update({
          'raisedHandsQueue': FieldValue.arrayUnion([handData]),
        });
      } else {
        // Khi hạ tay, ta cần lấy doc hiện tại để xóa chính xác Object của user đó
        await _db.runTransaction((tx) async {
          final snap = await tx.get(docRef);
          if (!snap.exists) return;

          final data = snap.data()!;
          final queue =
              List<Map<String, dynamic>>.from(data['raisedHandsQueue'] ?? []);

          queue.removeWhere((item) => item['userId'] == userId);
          tx.update(docRef, {'raisedHandsQueue': queue});
        });
      }
    } catch (e) {
      debugPrint('❌ [GroupCallService] toggleRaiseHand: $e');
    }
  }

  /// 2. SCREEN SHARE SYSTEM (Approval & Multi-share support)
  /// Nâng cấp: Hỗ trợ trạng thái xin phép (pending) và nhiều người share cùng lúc.
  Future<void> updateScreenShare({
    required String callId,
    required String userId,
    required bool isSharing,
    bool requiresApproval = false,
  }) async {
    try {
      final docRef = _calls.doc(callId);

      await _db.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        if (!snap.exists) return;

        final data = snap.data()!;
        final activeShares =
            List<Map<String, dynamic>>.from(data['activeScreenShares'] ?? []);

        if (isSharing) {
          // Trạng thái chia sẻ: active (đang share) hoặc pending (chờ Host duyệt)
          final shareData = {
            'userId': userId,
            'status': requiresApproval ? 'pending' : 'active',
            'startedAt': FieldValue.serverTimestamp(),
          };

          // Tránh duplicate
          activeShares.removeWhere((s) => s['userId'] == userId);
          activeShares.add(shareData);
        } else {
          // Xóa khỏi danh sách share
          activeShares.removeWhere((s) => s['userId'] == userId);
        }

        tx.update(docRef, {'activeScreenShares': activeShares});
      });
    } catch (e) {
      debugPrint('❌ [GroupCallService] updateScreenShare: $e');
    }
  }

  /// 3. REACTION SYSTEM (Anti-Spam & Ephemeral Batching)
  /// Nâng cấp: Chống spam bằng local cooldown và giới hạn số lượng mảng để tối ưu Firestore.
  Future<void> sendReaction({
    required String callId,
    required String userId,
    required String userName,
    required CallReactionType reaction,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    // ANTI-SPAM: Kiểm tra cooldown cục bộ
    final lastTime = _lastReactionTimes[userId] ?? 0;
    if (now - lastTime < _reactionCooldownMs) {
      debugPrint('⚠️ [GroupCallService] Reaction throttled (Anti-spam)');
      return;
    }
    _lastReactionTimes[userId] = now;

    try {
      final r = CallReaction(
        userId: userId,
        userName: userName,
        type: reaction,
        sentAt: DateTime.now(),
      );

      final docRef = _calls.doc(callId);

      // Tối ưu hóa: Dùng Transaction để đảm bảo mảng reactions không bị phình to (Auto cleanup)
      // Giữ tối đa 30 reactions mới nhất để không vượt quá 1MB document size
      await _db.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        if (!snap.exists) return;

        final data = snap.data()!;
        var recentReactions = List<dynamic>.from(data['recentReactions'] ?? []);

        recentReactions.add(r.toJson());

        // Auto-cleanup: Chỉ giữ lại 30 reactions gần nhất
        if (recentReactions.length > 30) {
          recentReactions =
              recentReactions.sublist(recentReactions.length - 30);
        }

        // Analytics Hook: Tăng biến đếm tổng số lượng reaction (cho phần Tracking)
        tx.update(docRef, {
          'recentReactions': recentReactions,
          'totalReactionsCount': FieldValue.increment(1),
        });
      });
    } catch (e) {
      debugPrint('❌ [GroupCallService] sendReaction: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STREAMS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Watches a single group call document in real-time.
  Stream<GroupCallModel?> watchCall(String callId) =>
      _calls.doc(callId).snapshots().map(
            (doc) => doc.exists ? _parse(doc) : null,
          );

  /// Emits the latest incoming group call for [userId], or null.
  Stream<GroupCallModel?> incomingGroupCallStream(String userId) => _calls
      .where('invitedUserIds', arrayContains: userId)
      .where('status', isEqualTo: GroupCallStatus.calling.name)
      .orderBy('createdAt', descending: true)
      .limit(1)
      .snapshots()
      .map((snap) => snap.docs.isNotEmpty ? _parse(snap.docs.first) : null);

  /// Emits the currently active (calling or ongoing) call for a group, or null.
  Stream<GroupCallModel?> activeCallForGroup(String groupId) => _calls
      .where('groupId', isEqualTo: groupId)
      .where('status', whereIn: _activeStatuses)
      .orderBy('createdAt', descending: true)
      .limit(1)
      .snapshots()
      .map((snap) => snap.docs.isNotEmpty ? _parse(snap.docs.first) : null);

  /// Stream of all group calls the current user is a participant in
  /// that are currently active (calling or ongoing).
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

  // ═══════════════════════════════════════════════════════════════════════════
  // HISTORY
  // ═══════════════════════════════════════════════════════════════════════════

  /// Returns the ended call history for [groupId].
  Future<List<GroupCallModel>> getGroupCallHistory(
    String groupId, {
    int limit = 20,
  }) async {
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

  /// Fetches a single call document by ID.
  Future<GroupCallModel?> getCall(String callId) async {
    try {
      final doc = await _calls.doc(callId).get();
      return doc.exists ? _parse(doc) : null;
    } catch (_) {
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PRIVATE HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Finds any active (calling / ongoing) call for [groupId].
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
      debugPrint('❌ [GroupCallService] _findActiveCallForGroup: $e');
      return null;
    }
  }

  /// Schedules a timeout that marks the call as missed if nobody else joined.
  void _scheduleTimeout(String callId) {
    _cancelTimeout(callId); // cancel any previous timer for safety
    _timeoutTimers[callId] = Timer(
      Duration(seconds: _timeoutSeconds),
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

      // Only mark missed if still in 'calling' state with ≤1 participant
      if (call.status == GroupCallStatus.calling &&
          call.participants.length <= 1) {
        await _calls.doc(callId).update({
          'status': GroupCallStatus.missed.name,
          'endedAt': _tsNow(),
          'durationSeconds': 0,
          'participants': <Map<String, dynamic>>[],
        });
        debugPrint('✅ [GroupCallService] Call timed out (missed): $callId');
      }
    } catch (e) {
      debugPrint('❌ [GroupCallService] _onTimeout: $e');
    }
  }

  /// Call this when the service is no longer needed (e.g. app teardown).
  void dispose() {
    for (final t in _timeoutTimers.values) {
      t.cancel();
    }
    _timeoutTimers.clear();
  }
}
