import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/call_model.dart';

// ══════════════════════════════════════════════════════
// CALL SERVICE
// ══════════════════════════════════════════════════════
class CallService {
  CallService._();
  static final CallService instance = CallService._();

  final _db   = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  static const String _col           = 'calls';
  static const int    _timeoutSec    = 45;
  static const int    _historyLimit  = 60;

  static const List<String> _activeStatuses = [
    'calling', 'ringing', 'dialing', 'connected', 'accepted',
  ];

  CollectionReference<Map<String, dynamic>> get _calls => _db.collection(_col);
  String? get _uid => _auth.currentUser?.uid;

  // ── Streams ────────────────────────────────────────────────────────────────

  /// Listens for incoming calls directed at the current user.
  Stream<CallModel?> get incomingCallStream {
    final uid = _uid;
    if (uid == null) return Stream.value(null);

    return _calls
        .where('calleeId', isEqualTo: uid)
        .where('status', whereIn: ['calling', 'ringing', 'dialing'])
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots()
        .map((snap) => snap.docs.isEmpty ? null : _parse(snap.docs.first));
  }

  /// Watches a specific call document for real-time status changes.
  Stream<CallModel?> watchCall(String callId) =>
      _calls.doc(callId).snapshots().map(
            (doc) => doc.exists ? _parse(doc) : null,
      );

  /// Merged call history stream (as caller + callee).
  Stream<List<CallModel>> get callHistoryStream {
    final uid = _uid;
    if (uid == null) return Stream.value([]);

    final asCaller = _calls
        .where('callerId', isEqualTo: uid)
        .where('status', whereIn: ['ended', 'missed', 'declined', 'rejected', 'failed'])
        .orderBy('createdAt', descending: true)
        .limit(_historyLimit)
        .snapshots();

    final asCallee = _calls
        .where('calleeId', isEqualTo: uid)
        .where('status', whereIn: ['ended', 'missed', 'declined', 'rejected', 'failed'])
        .orderBy('createdAt', descending: true)
        .limit(_historyLimit)
        .snapshots();

    return _mergeSnapshots([asCaller, asCallee]).map((docs) {
      final seen  = <String>{};
      final calls = <CallModel>[];
      for (final doc in docs) {
        if (seen.add(doc.id)) {
          final c = _parse(doc);
          if (c != null) calls.add(c);
        }
      }
      calls.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return calls.take(_historyLimit).toList();
    });
  }

  // ── CRUD ───────────────────────────────────────────────────────────────────

  /// Initiates a new outgoing call. Returns the created [CallModel] or null.
  Future<CallModel?> initiateCall({
    required String calleeId,
    required String calleeName,
    required String calleeAvatar,
    required CallType callType,
  }) async {
    final uid = _uid;
    if (uid == null) {
      debugPrint('❌ [CallService] Not signed in');
      return null;
    }

    try {
      // Fetch caller profile
      final callerSnap = await _db.collection('users').doc(uid).get();
      final callerData = callerSnap.data() ?? {};
      final callerName   = callerData['nickname']  as String? ??
          _auth.currentUser?.displayName ?? 'User';
      final callerAvatar = callerData['photoUrl']  as String? ?? '';

      // Check if callee is already in an active call
      if (await _isUserBusy(calleeId)) {
        debugPrint('⚠️ [CallService] Callee is busy');
        return null;
      }

      final callId  = _buildCallId(uid);
      final channel = 'call_${callId.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')}';
      final now     = DateTime.now();
      final expires = now.add(const Duration(seconds: _timeoutSec));

      final call = CallModel(
        callId:       callId,
        callerId:     uid,
        callerName:   callerName,
        callerAvatar: callerAvatar,
        calleeId:     calleeId,
        calleeName:   calleeName,
        calleeAvatar: calleeAvatar,
        channelName:  channel,
        callType:     callType,
        status:       CallStatus.calling,
        token:        null,
        createdAt:    now,
        expiresAt:    expires,
      );

      await _calls.doc(callId).set(call.toJson());
      debugPrint('✅ [CallService] Call created: $callId');

      // Auto-mark missed after timeout
      _scheduleTimeout(callId);
      return call;

    } catch (e, st) {
      debugPrint('❌ [CallService] initiateCall: $e\n$st');
      return null;
    }
  }

  /// Callee accepts the call.
  Future<bool> answerCall(String callId) async {
    try {
      await _calls.doc(callId).update({
        'status':      CallStatus.connected.name,
        'connectedAt': _tsNow(),
      });
      debugPrint('✅ [CallService] Answered: $callId');
      return true;
    } catch (e) {
      debugPrint('❌ [CallService] answerCall: $e');
      return false;
    }
  }

  /// Callee declines the call.
  Future<bool> declineCall(String callId) async {
    try {
      await _calls.doc(callId).update({'status': CallStatus.declined.name});
      debugPrint('✅ [CallService] Declined: $callId');
      return true;
    } catch (e) {
      debugPrint('❌ [CallService] declineCall: $e');
      return false;
    }
  }

  /// Ends an active call with optional duration.
  Future<bool> endCall(String callId, {int? durationSeconds}) async {
    try {
      final updates = <String, dynamic>{
        'status':  CallStatus.ended.name,
        'endedAt': _tsNow(),
      };
      if (durationSeconds != null) updates['durationSeconds'] = durationSeconds;
      await _calls.doc(callId).update(updates);
      debugPrint('✅ [CallService] Ended: $callId (${durationSeconds ?? 0}s)');
      return true;
    } catch (e) {
      debugPrint('❌ [CallService] endCall: $e');
      return false;
    }
  }

  /// Marks a call as missed (called by timeout or Cloud Function).
  Future<void> markCallMissed(String callId) async {
    try {
      final doc  = await _calls.doc(callId).get();
      if (!doc.exists) return;
      final call = _parse(doc);
      if (call != null && call.isActive) {
        await _calls.doc(callId).update({
          'status':  CallStatus.missed.name,
          'endedAt': _tsNow(),
        });
        debugPrint('✅ [CallService] Missed: $callId');
      }
    } catch (e) {
      debugPrint('❌ [CallService] markCallMissed: $e');
    }
  }

  /// Updates the Agora token for a call.
  Future<void> updateToken(String callId, String token) async {
    try {
      await _calls.doc(callId).update({'token': token});
    } catch (e) {
      debugPrint('❌ [CallService] updateToken: $e');
    }
  }

  /// Updates call status directly.
  Future<void> updateStatus(String callId, CallStatus status) async {
    try {
      await _calls.doc(callId).update({'status': status.name});
    } catch (e) {
      debugPrint('❌ [CallService] updateStatus: $e');
    }
  }

  /// Fetch a single call by ID.
  Future<CallModel?> getCall(String callId) async {
    try {
      final doc = await _calls.doc(callId).get();
      return doc.exists ? _parse(doc) : null;
    } catch (_) {
      return null;
    }
  }

  /// One-shot call history fetch.
  Future<List<CallModel>> getCallHistory({int limit = 40}) async {
    final uid = _uid;
    if (uid == null) return [];
    try {
      final r1 = await _calls
          .where('callerId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();
      final r2 = await _calls
          .where('calleeId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      final seen  = <String>{};
      final calls = <CallModel>[];
      for (final doc in [...r1.docs, ...r2.docs]) {
        if (seen.add(doc.id)) {
          final c = _parse(doc);
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

  // ── Helpers ────────────────────────────────────────────────────────────────

  CallModel? _parse(DocumentSnapshot doc) {
    try {
      return CallModel.fromDocument(doc);
    } catch (e) {
      debugPrint('❌ [CallService] parse (${doc.id}): $e');
      return null;
    }
  }

  Future<bool> _isUserBusy(String userId) async {
    try {
      for (final field in ['callerId', 'calleeId']) {
        final snap = await _calls
            .where(field, isEqualTo: userId)
            .where('status', whereIn: _activeStatuses)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) return true;
      }
      return false;
    } catch (e) {
      debugPrint('❌ [CallService] _isUserBusy: $e');
      return false;
    }
  }

  void _scheduleTimeout(String callId) {
    Timer(const Duration(seconds: _timeoutSec), () => markCallMissed(callId));
  }

  String _buildCallId(String uid) {
    final prefix = uid.length >= 8 ? uid.substring(0, 8) : uid;
    return '${prefix}_${DateTime.now().millisecondsSinceEpoch}';
  }

  String _tsNow() => DateTime.now().millisecondsSinceEpoch.toString();

  // Merges multiple query snapshot streams
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _mergeSnapshots(
      List<Stream<QuerySnapshot<Map<String, dynamic>>>> streams,
      ) {
    final ctrl    = StreamController<List<QueryDocumentSnapshot<Map<String, dynamic>>>>();
    final latest  = List<List<QueryDocumentSnapshot<Map<String, dynamic>>>>.filled(
        streams.length, []);
    final ready   = List<bool>.filled(streams.length, false);
    final subs    = <StreamSubscription>[];

    void tryEmit() {
      if (!ready.contains(false)) ctrl.add(latest.expand((d) => d).toList());
    }

    for (int i = 0; i < streams.length; i++) {
      final sub = streams[i].listen(
            (snap) { latest[i] = snap.docs; ready[i] = true; tryEmit(); },
        onError: ctrl.addError,
      );
      subs.add(sub);
    }

    ctrl.onCancel = () { for (final s in subs) { s.cancel(); } };
    return ctrl.stream;
  }
}