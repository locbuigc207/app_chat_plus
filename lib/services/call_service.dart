// lib/services/call_service.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/call_model.dart';

// ─────────────────────────────────────────────
//  NOTE ON AGORA INTEGRATION
//
//  This service uses agora_rtc_engine for real
//  WebRTC voice/video calls.
//
//  Setup steps (see README section below):
//  1. Add agora_rtc_engine: ^6.3.2 to pubspec.yaml
//  2. Add permissions to AndroidManifest.xml
//  3. Get a free Agora App ID from console.agora.io
//  4. Set AGORA_APP_ID in your .env / constants
//
//  The service works in "no-token" mode (safe for
//  dev / testing). For production add token server.
// ─────────────────────────────────────────────

class CallService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static const String _callsCollection = 'calls';
  static const int _callTimeoutSeconds = 30;

  // ──────────────────────────────────────────
  //  STREAM: incoming calls for current user
  // ──────────────────────────────────────────
  Stream<CallModel?> get incomingCallStream {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(null);

    return _firestore
        .collection(_callsCollection)
        .where('calleeId', isEqualTo: uid)
        .where('status', whereIn: ['calling', 'ringing'])
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots()
        .map((snap) {
          if (snap.docs.isEmpty) return null;
          try {
            return CallModel.fromDocument(snap.docs.first);
          } catch (e) {
            debugPrint('❌ Error parsing incoming call: $e');
            return null;
          }
        });
  }

  // ──────────────────────────────────────────
  //  STREAM: watch a specific call doc
  // ──────────────────────────────────────────
  Stream<CallModel?> watchCall(String callId) {
    return _firestore
        .collection(_callsCollection)
        .doc(callId)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return null;
      try {
        return CallModel.fromDocument(doc);
      } catch (e) {
        return null;
      }
    });
  }

  // ──────────────────────────────────────────
  //  INITIATE CALL
  // ──────────────────────────────────────────
  Future<CallModel?> initiateCall({
    required String calleeId,
    required String calleeName,
    required String calleeAvatar,
    required CallType callType,
  }) async {
    try {
      final caller = _auth.currentUser;
      if (caller == null) throw Exception('Not authenticated');

      // Get caller info from Firestore
      final callerDoc =
          await _firestore.collection('users').doc(caller.uid).get();
      final callerData = callerDoc.data() ?? {};
      final callerName = callerData['nickname'] ?? caller.displayName ?? 'User';
      final callerAvatar = callerData['photoUrl'] ?? '';

      // Check if callee is already in a call
      final existingCall = await _getActiveCallForUser(calleeId);
      if (existingCall != null) {
        debugPrint('⚠️ Callee already in a call');
        return null;
      }

      final callId = _generateCallId();
      final channelName = 'call_$callId';

      final call = CallModel(
        callId: callId,
        callerId: caller.uid,
        callerName: callerName,
        callerAvatar: callerAvatar,
        calleeId: calleeId,
        calleeName: calleeName,
        calleeAvatar: calleeAvatar,
        callType: callType,
        status: CallStatus.calling,
        channelName: channelName,
        token: null, // No-token mode for development
        createdAt: DateTime.now(),
      );

      await _firestore
          .collection(_callsCollection)
          .doc(callId)
          .set(call.toJson());

      debugPrint('✅ Call initiated: $callId');

      // Auto-timeout if not answered
      _scheduleCallTimeout(callId);

      return call;
    } catch (e) {
      debugPrint('❌ Error initiating call: $e');
      return null;
    }
  }

  // ──────────────────────────────────────────
  //  ANSWER CALL
  // ──────────────────────────────────────────
  Future<bool> answerCall(String callId) async {
    try {
      await _firestore.collection(_callsCollection).doc(callId).update({
        'status': CallStatus.connected.name,
        'connectedAt': DateTime.now().millisecondsSinceEpoch.toString(),
      });
      debugPrint('✅ Call answered: $callId');
      return true;
    } catch (e) {
      debugPrint('❌ Error answering call: $e');
      return false;
    }
  }

  // ──────────────────────────────────────────
  //  DECLINE CALL
  // ──────────────────────────────────────────
  Future<bool> declineCall(String callId) async {
    try {
      await _firestore
          .collection(_callsCollection)
          .doc(callId)
          .update({'status': CallStatus.declined.name});
      debugPrint('✅ Call declined: $callId');
      return true;
    } catch (e) {
      debugPrint('❌ Error declining call: $e');
      return false;
    }
  }

  // ──────────────────────────────────────────
  //  END CALL
  // ──────────────────────────────────────────
  Future<bool> endCall(String callId, {int? durationSeconds}) async {
    try {
      final updates = <String, dynamic>{
        'status': CallStatus.ended.name,
        'endedAt': DateTime.now().millisecondsSinceEpoch.toString(),
      };
      if (durationSeconds != null) {
        updates['durationSeconds'] = durationSeconds;
      }
      await _firestore.collection(_callsCollection).doc(callId).update(updates);
      debugPrint('✅ Call ended: $callId');
      return true;
    } catch (e) {
      debugPrint('❌ Error ending call: $e');
      return false;
    }
  }

  // ──────────────────────────────────────────
  //  MISS CALL (timeout)
  // ──────────────────────────────────────────
  Future<void> markCallMissed(String callId) async {
    try {
      final doc =
          await _firestore.collection(_callsCollection).doc(callId).get();
      if (!doc.exists) return;
      final call = CallModel.fromDocument(doc);
      if (call.status == CallStatus.calling ||
          call.status == CallStatus.ringing) {
        await _firestore
            .collection(_callsCollection)
            .doc(callId)
            .update({'status': CallStatus.missed.name});
        debugPrint('✅ Call marked missed: $callId');
      }
    } catch (e) {
      debugPrint('❌ Error marking call missed: $e');
    }
  }

  // ──────────────────────────────────────────
  //  CALL HISTORY
  // ──────────────────────────────────────────
  Stream<List<CallModel>> getCallHistory({int limit = 30}) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value([]);

    return _firestore
        .collection(_callsCollection)
        .where(Filter.or(
          Filter('callerId', isEqualTo: uid),
          Filter('calleeId', isEqualTo: uid),
        ))
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) {
              try {
                return CallModel.fromDocument(doc);
              } catch (e) {
                return null;
              }
            })
            .whereType<CallModel>()
            .toList());
  }

  // ──────────────────────────────────────────
  //  HELPERS
  // ──────────────────────────────────────────
  Future<CallModel?> _getActiveCallForUser(String userId) async {
    final snap = await _firestore
        .collection(_callsCollection)
        .where(Filter.or(
          Filter('callerId', isEqualTo: userId),
          Filter('calleeId', isEqualTo: userId),
        ))
        .where('status', whereIn: ['calling', 'ringing', 'connected'])
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return CallModel.fromDocument(snap.docs.first);
  }

  void _scheduleCallTimeout(String callId) {
    Timer(Duration(seconds: _callTimeoutSeconds), () {
      markCallMissed(callId);
    });
  }

  String _generateCallId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final uid = _auth.currentUser?.uid ?? 'unknown';
    return '${uid}_$timestamp';
  }

  Future<CallModel?> getCall(String callId) async {
    try {
      final doc =
          await _firestore.collection(_callsCollection).doc(callId).get();
      if (!doc.exists) return null;
      return CallModel.fromDocument(doc);
    } catch (e) {
      return null;
    }
  }
}
