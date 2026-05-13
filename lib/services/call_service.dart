// lib/services/call_service.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/call_model.dart';

class CallService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static const String _callsCollection = 'calls';
  static const int _callTimeoutSeconds = 30;

  /// Shorthand reference để tương thích với cách dùng callCollection.doc(...)
  CollectionReference get callCollection =>
      _firestore.collection(_callsCollection);

  // ── Incoming calls stream (theo uid đang đăng nhập) ───────────────────────

  /// Lắng nghe cuộc gọi đến theo uid của user hiện tại (Firestore Auth).
  /// FIX: Bỏ .orderBy('createdAt') để tránh lỗi yêu cầu composite index.
  Stream<CallModel?> get incomingCallStream {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(null);

    return _firestore
        .collection(_callsCollection)
        .where('calleeId', isEqualTo: uid)
        .where('status', whereIn: ['calling', 'ringing', 'dialing'])
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

  // ── Incoming calls stream (theo userId truyền vào) ────────────────────────

  /// Lắng nghe cuộc gọi đến cho một userId cụ thể.
  /// Hỗ trợ cả field 'receiverId' (schema cũ) và 'calleeId' (schema mới).
  Stream<CallModel?> listenToIncomingCall(String userId) {
    // Ưu tiên 'receiverId' để backward-compat với schema cũ
    return callCollection
        .where('receiverId', isEqualTo: userId)
        .where('status', isEqualTo: 'dialing')
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) return null;
      try {
        return CallModel.fromMap(
            snapshot.docs.first.data() as Map<String, dynamic>);
      } catch (e) {
        debugPrint('❌ Error parsing incoming call (listenToIncomingCall): $e');
        return null;
      }
    });
  }

  // ── Watch specific call ───────────────────────────────────────────────────

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
        debugPrint('❌ Error parsing call: $e');
        return null;
      }
    });
  }

  // ── Initiate call (full flow với Firestore Auth) ──────────────────────────

  /// Tạo cuộc gọi mới, tự lấy thông tin caller từ Firestore.
  Future<CallModel?> initiateCall({
    required String calleeId,
    required String calleeName,
    required String calleeAvatar,
    required CallType callType,
  }) async {
    try {
      final caller = _auth.currentUser;
      if (caller == null) throw Exception('Chưa đăng nhập');

      // Lấy thông tin caller từ Firestore
      final callerDoc =
          await _firestore.collection('users').doc(caller.uid).get();
      final callerData = callerDoc.data() ?? {};
      final callerName =
          callerData['nickname'] as String? ?? caller.displayName ?? 'User';
      final callerAvatarUrl = callerData['photoUrl'] as String? ?? '';

      // Kiểm tra callee có đang trong cuộc gọi không
      final existingCall = await _getActiveCallForUser(calleeId);
      if (existingCall != null) {
        debugPrint('⚠️ Callee đang trong cuộc gọi khác');
        return null;
      }

      final callId = _generateCallId();
      final channelName =
          'call_${callId.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')}';

      final call = CallModel(
        callId: callId,
        callerId: caller.uid,
        callerName: callerName,
        callerAvatar: callerAvatarUrl,
        calleeId: calleeId,
        calleeName: calleeName,
        calleeAvatar: calleeAvatar,
        channelName: channelName,
        callType: callType,
        status: CallStatus.calling,
        token: null,
        createdAt: DateTime.now(),
      );

      await _firestore
          .collection(_callsCollection)
          .doc(callId)
          .set(call.toJson());

      debugPrint('✅ Cuộc gọi được tạo: $callId');

      // Auto-timeout nếu không có phản hồi
      _scheduleCallTimeout(callId);

      return call;
    } catch (e) {
      debugPrint('❌ Lỗi tạo cuộc gọi: $e');
      return null;
    }
  }

  // ── Make call (truyền thẳng CallModel — schema cũ) ───────────────────────

  /// Tạo cuộc gọi bằng cách truyền thẳng CallModel.
  /// Tương thích với schema cũ dùng call.id và toMap().
  Future<void> makeCall(CallModel call) async {
    await callCollection.doc(call.callId).set(call.toMap());
  }

  // ── Answer call ───────────────────────────────────────────────────────────

  Future<bool> answerCall(String callId) async {
    try {
      await _firestore.collection(_callsCollection).doc(callId).update({
        'status': CallStatus.connected.name,
        'connectedAt': DateTime.now().millisecondsSinceEpoch.toString(),
      });
      debugPrint('✅ Cuộc gọi được chấp nhận: $callId');
      return true;
    } catch (e) {
      debugPrint('❌ Lỗi chấp nhận cuộc gọi: $e');
      return false;
    }
  }

  // ── Decline call ──────────────────────────────────────────────────────────

  Future<bool> declineCall(String callId) async {
    try {
      await _firestore
          .collection(_callsCollection)
          .doc(callId)
          .update({'status': CallStatus.declined.name});
      debugPrint('✅ Cuộc gọi bị từ chối: $callId');
      return true;
    } catch (e) {
      debugPrint('❌ Lỗi từ chối cuộc gọi: $e');
      return false;
    }
  }

  // ── Update call status (tổng quát) ───────────────────────────────────────

  /// Cập nhật trạng thái cuộc gọi. Dùng được cho cả schema cũ và mới.
  Future<void> updateCallStatus(String callId, String status) async {
    await callCollection.doc(callId).update({'status': status});
  }

  // ── End call ──────────────────────────────────────────────────────────────

  /// Kết thúc cuộc gọi.
  /// [deleteAfter]: xóa document sau 2 giây (hữu ích khi dùng schema đơn giản).
  Future<bool> endCall(
    String callId, {
    int? durationSeconds,
    bool deleteAfter = false,
  }) async {
    try {
      final updates = <String, dynamic>{
        'status': CallStatus.ended.name,
        'endedAt': DateTime.now().millisecondsSinceEpoch.toString(),
      };
      if (durationSeconds != null) {
        updates['durationSeconds'] = durationSeconds;
      }

      await _firestore.collection(_callsCollection).doc(callId).update(updates);
      debugPrint('✅ Cuộc gọi kết thúc: $callId');

      if (deleteAfter) {
        Future.delayed(const Duration(seconds: 2), () {
          callCollection.doc(callId).delete();
        });
      }

      return true;
    } catch (e) {
      debugPrint('❌ Lỗi kết thúc cuộc gọi: $e');
      return false;
    }
  }

  // ── Mark missed ───────────────────────────────────────────────────────────

  Future<void> markCallMissed(String callId) async {
    try {
      final doc =
          await _firestore.collection(_callsCollection).doc(callId).get();
      if (!doc.exists) return;

      final call = CallModel.fromDocument(doc);
      if (call.isActive) {
        await _firestore
            .collection(_callsCollection)
            .doc(callId)
            .update({'status': CallStatus.missed.name});
        debugPrint('✅ Cuộc gọi nhỡ: $callId');
      }
    } catch (e) {
      debugPrint('❌ Lỗi đánh dấu cuộc gọi nhỡ: $e');
    }
  }

  // ── Call history ──────────────────────────────────────────────────────────

  /// FIX: Tách thành 2 query riêng để tránh cần composite index.
  Stream<List<CallModel>> getCallHistory({int limit = 30}) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value([]);

    final asCaller = _firestore
        .collection(_callsCollection)
        .where('callerId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots();

    final asCallee = _firestore
        .collection(_callsCollection)
        .where('calleeId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots();

    return StreamZip([asCaller, asCallee]).map((snapshots) {
      final callerDocs = (snapshots[0] as QuerySnapshot).docs;
      final calleeDocs = (snapshots[1] as QuerySnapshot).docs;

      final seen = <String>{};
      final all = <CallModel>[];

      for (final doc in [...callerDocs, ...calleeDocs]) {
        if (seen.contains(doc.id)) continue;
        seen.add(doc.id);
        try {
          all.add(CallModel.fromDocument(doc));
        } catch (_) {}
      }

      all.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return all.take(limit).toList();
    });
  }

  // ── Get single call ───────────────────────────────────────────────────────

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

  // ── Private helpers ───────────────────────────────────────────────────────

  Future<CallModel?> _getActiveCallForUser(String userId) async {
    try {
      final asCallerSnap = await _firestore
          .collection(_callsCollection)
          .where('callerId', isEqualTo: userId)
          .where('status', whereIn: [
            'dialing',
            'calling',
            'ringing',
            'connected',
            'accepted'
          ])
          .limit(1)
          .get();

      if (asCallerSnap.docs.isNotEmpty) {
        return CallModel.fromDocument(asCallerSnap.docs.first);
      }

      final asCalleeSnap = await _firestore
          .collection(_callsCollection)
          .where('calleeId', isEqualTo: userId)
          .where('status', whereIn: [
            'dialing',
            'calling',
            'ringing',
            'connected',
            'accepted'
          ])
          .limit(1)
          .get();

      if (asCalleeSnap.docs.isNotEmpty) {
        return CallModel.fromDocument(asCalleeSnap.docs.first);
      }

      return null;
    } catch (e) {
      debugPrint('❌ Lỗi kiểm tra cuộc gọi active: $e');
      return null;
    }
  }

  void _scheduleCallTimeout(String callId) {
    Timer(Duration(seconds: _callTimeoutSeconds), () {
      markCallMissed(callId);
    });
  }

  String _generateCallId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final uid = (_auth.currentUser?.uid ?? 'anon').substring(0, 8);
    return '${uid}_$timestamp';
  }
}

// ── StreamZip helper ──────────────────────────────────────────────────────────

/// Merge nhiều streams thành 1 stream phát ra List chứa giá trị mới nhất
/// của từng stream mỗi khi bất kỳ stream nào phát ra giá trị mới.
class StreamZip<T> extends StreamView<List<T>> {
  StreamZip(List<Stream<T>> streams) : super(_buildStream(streams));

  static Stream<List<T>> _buildStream<T>(List<Stream<T>> streams) {
    final controller = StreamController<List<T>>();
    final latest = List<T?>.filled(streams.length, null);
    final initialized = List<bool>.filled(streams.length, false);
    final subs = <StreamSubscription<T>>[];

    void tryEmit() {
      if (initialized.every((v) => v)) {
        controller.add(List<T>.from(latest.map((e) => e as T)));
      }
    }

    for (int i = 0; i < streams.length; i++) {
      final sub = streams[i].listen(
        (value) {
          latest[i] = value;
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
