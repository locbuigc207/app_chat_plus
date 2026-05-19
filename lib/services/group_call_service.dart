
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/group_call_model.dart';

class GroupCallService {
  static const String _collection = 'group_calls';

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _uid => _auth.currentUser?.uid ?? '';

  
  Future<GroupCallModel?> initiateCall({
    required String groupId,
    required String groupName,
    required List<String> memberIds,
    required GroupCallType callType,
  }) async {
    try {
      final initiator = _auth.currentUser;
      if (initiator == null) return null;

      
      final initiatorDoc =
          await _db.collection('users').doc(initiator.uid).get();
      final initiatorData = initiatorDoc.data() ?? {};
      final initiatorName = initiatorData['nickname'] ?? 'Unknown';

      final callId = '${groupId}_${DateTime.now().millisecondsSinceEpoch}';
      final channelName = 'grp_$callId';

      final me = GroupCallParticipant(
        userId: initiator.uid,
        userName: initiatorName,
        userAvatar: initiatorData['photoUrl'] ?? '',
        joinedAt: DateTime.now(),
        isAdmin: true,
      );

      final invitedIds = memberIds.where((id) => id != initiator.uid).toList();

      final model = GroupCallModel(
        callId: callId,
        groupId: groupId,
        groupName: groupName,
        initiatorId: initiator.uid,
        initiatorName: initiatorName,
        callType: callType,
        status: GroupCallStatus.calling,
        channelName: channelName,
        participants: [me],
        invitedUserIds: invitedIds,
        createdAt: DateTime.now(),
      );

      await _db.collection(_collection).doc(callId).set(model.toJson());
      debugPrint('✅ Group call initiated: $callId');
      return model;
    } catch (e) {
      debugPrint('❌ Error initiating group call: $e');
      return null;
    }
  }

  
  Future<bool> joinCall(String callId) async {
    try {
      final userDoc = await _db.collection('users').doc(_uid).get();
      final userData = userDoc.data() ?? {};

      final participant = GroupCallParticipant(
        userId: _uid,
        userName: userData['nickname'] ?? 'User',
        userAvatar: userData['photoUrl'] ?? '',
        joinedAt: DateTime.now(),
      );

      await _db.collection(_collection).doc(callId).update({
        'participants': FieldValue.arrayUnion([participant.toJson()]),
        'status': GroupCallStatus.ongoing.name,
      });

      debugPrint('✅ Joined group call: $callId');
      return true;
    } catch (e) {
      debugPrint('❌ Error joining group call: $e');
      return false;
    }
  }

  
  Future<void> leaveCall(String callId) async {
    try {
      final doc = await _db.collection(_collection).doc(callId).get();
      if (!doc.exists) return;

      final call = GroupCallModel.fromDocument(doc);
      final remaining =
          call.participants.where((p) => p.userId != _uid).toList();

      if (remaining.isEmpty) {
        
        final duration = DateTime.now().difference(call.createdAt).inSeconds;
        await _db.collection(_collection).doc(callId).update({
          'status': GroupCallStatus.ended.name,
          'endedAt': DateTime.now().millisecondsSinceEpoch.toString(),
          'durationSeconds': duration,
          'participants': [],
        });
      } else {
        await _db.collection(_collection).doc(callId).update({
          'participants': remaining.map((p) => p.toJson()).toList(),
        });
      }
      debugPrint('✅ Left group call: $callId');
    } catch (e) {
      debugPrint('❌ Error leaving group call: $e');
    }
  }

  
  Future<void> endCallForAll(String callId, DateTime startTime) async {
    try {
      final duration = DateTime.now().difference(startTime).inSeconds;
      await _db.collection(_collection).doc(callId).update({
        'status': GroupCallStatus.ended.name,
        'endedAt': DateTime.now().millisecondsSinceEpoch.toString(),
        'durationSeconds': duration,
        'participants': [],
      });
      debugPrint('✅ Ended group call for all: $callId');
    } catch (e) {
      debugPrint('❌ Error ending group call: $e');
    }
  }

  
  Future<void> updateParticipantState({
    required String callId,
    required bool isMuted,
    required bool isCameraOff,
  }) async {
    try {
      final doc = await _db.collection(_collection).doc(callId).get();
      if (!doc.exists) return;

      final call = GroupCallModel.fromDocument(doc);
      final updated = call.participants.map((p) {
        if (p.userId == _uid) {
          return p.copyWith(isMuted: isMuted, isCameraOff: isCameraOff);
        }
        return p;
      }).toList();

      await _db.collection(_collection).doc(callId).update({
        'participants': updated.map((p) => p.toJson()).toList(),
      });
    } catch (e) {
      debugPrint('❌ Error updating participant state: $e');
    }
  }

  
  Stream<GroupCallModel?> watchCall(String callId) {
    return _db
        .collection(_collection)
        .doc(callId)
        .snapshots()
        .map((doc) => doc.exists ? GroupCallModel.fromDocument(doc) : null);
  }

  
  Stream<GroupCallModel?> incomingGroupCallStream(String userId) {
    return _db
        .collection(_collection)
        .where('invitedUserIds', arrayContains: userId)
        .where('status', isEqualTo: GroupCallStatus.calling.name)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots()
        .map((snap) {
      if (snap.docs.isEmpty) return null;
      try {
        return GroupCallModel.fromDocument(snap.docs.first);
      } catch (_) {
        return null;
      }
    });
  }

  
  Stream<GroupCallModel?> activeCallForGroup(String groupId) {
    return _db
        .collection(_collection)
        .where('groupId', isEqualTo: groupId)
        .where('status', whereIn: [
          GroupCallStatus.calling.name,
          GroupCallStatus.ongoing.name
        ])
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots()
        .map((snap) {
          if (snap.docs.isEmpty) return null;
          try {
            return GroupCallModel.fromDocument(snap.docs.first);
          } catch (_) {
            return null;
          }
        });
  }

  
  Future<void> declineCall(String callId) async {
    try {
      await _db.collection(_collection).doc(callId).update({
        'invitedUserIds': FieldValue.arrayRemove([_uid]),
      });
    } catch (e) {
      debugPrint('❌ Error declining group call: $e');
    }
  }

  
  void scheduleCallTimeout(String callId, {int seconds = 30}) {
    Timer(Duration(seconds: seconds), () async {
      final doc = await _db.collection(_collection).doc(callId).get();
      if (!doc.exists) return;
      final call = GroupCallModel.fromDocument(doc);
      if (call.status == GroupCallStatus.calling &&
          call.participants.length < 2) {
        await _db.collection(_collection).doc(callId).update({
          'status': GroupCallStatus.ended.name,
          'endedAt': DateTime.now().millisecondsSinceEpoch.toString(),
          'durationSeconds': 0,
        });
      }
    });
  }

  
  Future<List<GroupCallModel>> getGroupCallHistory(String groupId,
      {int limit = 20}) async {
    try {
      final snap = await _db
          .collection(_collection)
          .where('groupId', isEqualTo: groupId)
          .where('status', isEqualTo: GroupCallStatus.ended.name)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();
      return snap.docs.map(GroupCallModel.fromDocument).toList();
    } catch (e) {
      debugPrint('❌ Error fetching call history: $e');
      return [];
    }
  }
}
