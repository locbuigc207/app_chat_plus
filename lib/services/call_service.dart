import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/call_model.dart';







class CallService {
  CallService._();
  static final CallService instance = CallService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static const String _col = 'calls';
  static const int _timeoutSeconds = 45;
  static const int _historyLimit = 50;

  
  static const List<String> _activeStatuses = [
    'calling',
    'ringing',
    'dialing',
    'connected',
    'accepted',
  ];

  

  CollectionReference<Map<String, dynamic>> get _calls => _db.collection(_col);

  String? get _uid => _auth.currentUser?.uid;

  
  
  

  
  Stream<CallModel?> get incomingCallStream {
    final uid = _uid;
    if (uid == null) return Stream.value(null);

    return _calls
        .where('calleeId', isEqualTo: uid)
        .where('status', whereIn: ['calling', 'ringing', 'dialing'])
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots()
        .map((snap) => snap.docs.isEmpty ? null : _parseDoc(snap.docs.first));
  }

  
  Stream<CallModel?> watchCall(String callId) => _calls.doc(callId).snapshots().map(
        (doc) => doc.exists ? _parseDoc(doc) : null,
      );

  
  Stream<List<CallModel>> get callHistoryStream {
    final uid = _uid;
    if (uid == null) return Stream.value([]);

    final asCaller = _calls
        .where('callerId', isEqualTo: uid)
        .where('status', whereIn: ['ended', 'missed', 'declined'])
        .orderBy('createdAt', descending: true)
        .limit(_historyLimit)
        .snapshots();

    final asCallee = _calls
        .where('calleeId', isEqualTo: uid)
        .where('status', whereIn: ['ended', 'missed', 'declined'])
        .orderBy('createdAt', descending: true)
        .limit(_historyLimit)
        .snapshots();

    return _mergeQuerySnapshots([asCaller, asCallee]).map((docs) {
      final seen = <String>{};
      final calls = <CallModel>[];
      for (final doc in docs) {
        if (seen.add(doc.id)) {
          final c = _parseDoc(doc);
          if (c != null) calls.add(c);
        }
      }
      calls.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return calls.take(_historyLimit).toList();
    });
  }

  
  
  

  
  Future<CallModel?> initiateCall({
    required String calleeId,
    required String calleeName,
    required String calleeAvatar,
    required CallType callType,
  }) async {
    final uid = _uid;
    if (uid == null) {
      debugPrint('❌ [CallService] initiateCall: user not signed in');
      return null;
    }

    try {
      
      final callerSnap = await _db.collection('users').doc(uid).get();
      final callerData = callerSnap.data() ?? {};
      final callerName =
          callerData['nickname'] as String? ?? _auth.currentUser?.displayName ?? 'User';
      final callerAvatar = callerData['photoUrl'] as String? ?? '';

      
      final busyCall = await _findActiveCallForUser(calleeId);
      if (busyCall != null) {
        debugPrint('⚠️ [CallService] Callee is busy (callId=${busyCall.callId})');
        return null;
      }

      final callId = _buildCallId(uid);
      final channel = 'call_${callId.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')}';
      final now = DateTime.now();
      final expiresAt = now.add(Duration(seconds: _timeoutSeconds));

      final call = CallModel(
        callId: callId,
        callerId: uid,
        callerName: callerName,
        callerAvatar: callerAvatar,
        calleeId: calleeId,
        calleeName: calleeName,
        calleeAvatar: calleeAvatar,
        channelName: channel,
        callType: callType,
        status: CallStatus.calling,
        token: null,
        createdAt: now,
        expiresAt: expiresAt,
      );

      await _calls.doc(callId).set(call.toJson());
      debugPrint('✅ [CallService] Call created: $callId');

      _scheduleTimeout(callId);
      return call;
    } catch (e, st) {
      debugPrint('❌ [CallService] initiateCall error: $e\n$st');
      return null;
    }
  }

  
  Future<bool> answerCall(String callId) async {
    try {
      await _calls.doc(callId).update({
        'status': CallStatus.connected.name,
        'connectedAt': _tsNow(),
      });
      debugPrint('✅ [CallService] Call answered: $callId');
      return true;
    } catch (e) {
      debugPrint('❌ [CallService] answerCall: $e');
      return false;
    }
  }

  
  Future<bool> declineCall(String callId) async {
    try {
      await _calls.doc(callId).update({'status': CallStatus.declined.name});
      debugPrint('✅ [CallService] Call declined: $callId');
      return true;
    } catch (e) {
      debugPrint('❌ [CallService] declineCall: $e');
      return false;
    }
  }

  
  Future<bool> endCall(String callId, {int? durationSeconds}) async {
    try {
      final updates = <String, dynamic>{
        'status': CallStatus.ended.name,
        'endedAt': _tsNow(),
      };
      if (durationSeconds != null) updates['durationSeconds'] = durationSeconds;
      await _calls.doc(callId).update(updates);
      debugPrint('✅ [CallService] Call ended: $callId (${durationSeconds}s)');
      return true;
    } catch (e) {
      debugPrint('❌ [CallService] endCall: $e');
      return false;
    }
  }

  
  Future<void> markCallMissed(String callId) async {
    try {
      final doc = await _calls.doc(callId).get();
      if (!doc.exists) return;
      final call = _parseDoc(doc);
      if (call != null && call.isActive) {
        await _calls.doc(callId).update({'status': CallStatus.missed.name});
        debugPrint('✅ [CallService] Call missed: $callId');
      }
    } catch (e) {
      debugPrint('❌ [CallService] markCallMissed: $e');
    }
  }

  
  Future<void> updateToken(String callId, String token) async {
    try {
      await _calls.doc(callId).update({'token': token});
    } catch (e) {
      debugPrint('❌ [CallService] updateToken: $e');
    }
  }

  
  Future<void> updateCallStatus(String callId, String status) async {
    try {
      await _calls.doc(callId).update({'status': status});
    } catch (e) {
      debugPrint('❌ [CallService] updateCallStatus: $e');
    }
  }

  
  
  

  Future<CallModel?> getCall(String callId) async {
    try {
      final doc = await _calls.doc(callId).get();
      return doc.exists ? _parseDoc(doc) : null;
    } catch (_) {
      return null;
    }
  }

  Future<List<CallModel>> getCallHistory({int limit = 30}) async {
    final uid = _uid;
    if (uid == null) return [];
    try {
      final callerSnap = await _calls
          .where('callerId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();
      final calleeSnap = await _calls
          .where('calleeId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      final seen = <String>{};
      final calls = <CallModel>[];
      for (final doc in [...callerSnap.docs, ...calleeSnap.docs]) {
        if (seen.add(doc.id)) {
          final c = _parseDoc(doc);
          if (c != null) calls.add(c);
        }
      }
      calls.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return calls.take(limit).toList();
    } catch (e) {
      debugPrint('❌ [CallService] getCallHistory: $e');
      return [];
    }
  }

  
  
  

  CallModel? _parseDoc(DocumentSnapshot<Object?> doc) {
    try {
      return CallModel.fromDocument(doc);
    } catch (e) {
      debugPrint('❌ [CallService] parse error (${doc.id}): $e');
      return null;
    }
  }

  Future<CallModel?> _findActiveCallForUser(String userId) async {
    try {
      for (final field in ['callerId', 'calleeId']) {
        final snap = await _calls
            .where(field, isEqualTo: userId)
            .where('status', whereIn: _activeStatuses)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) return _parseDoc(snap.docs.first);
      }
      return null;
    } catch (e) {
      debugPrint('❌ [CallService] _findActiveCallForUser: $e');
      return null;
    }
  }

  void _scheduleTimeout(String callId) {
    Timer(Duration(seconds: _timeoutSeconds), () => markCallMissed(callId));
  }

  String _buildCallId(String uid) {
    final prefix = uid.length >= 8 ? uid.substring(0, 8) : uid;
    return '${prefix}_${DateTime.now().millisecondsSinceEpoch}';
  }

  String _tsNow() => DateTime.now().millisecondsSinceEpoch.toString();

  
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _mergeQuerySnapshots(
    List<Stream<QuerySnapshot<Map<String, dynamic>>>> streams,
  ) {
    final controller = StreamController<List<QueryDocumentSnapshot<Map<String, dynamic>>>>();
    final latest =
        List<List<QueryDocumentSnapshot<Map<String, dynamic>>>>.filled(streams.length, []);
    final initialized = List<bool>.filled(streams.length, false);
    final subs = <StreamSubscription>[];

    void tryEmit() {
      if (!initialized.contains(false)) {
        controller.add(latest.expand((d) => d).toList());
      }
    }

    for (int i = 0; i < streams.length; i++) {
      final sub = streams[i].listen(
        (snap) {
          latest[i] = snap.docs;
          initialized[i] = true;
          tryEmit();
        },
        onError: controller.addError,
      );
      subs.add(sub);
    }

    controller.onCancel = () {
      for (final s in subs) {
        s.cancel();
      }
    };

    return controller.stream;
  }
}
