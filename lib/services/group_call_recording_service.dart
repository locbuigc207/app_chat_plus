import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

// ══════════════════════════════════════════════════════════════════════════════
// GroupCallRecordingService
// Manages Agora Cloud Recording for group calls.
// Records mixed audio/video to cloud storage, saves URL to Firestore.
// ══════════════════════════════════════════════════════════════════════════════
class GroupCallRecordingService {
  GroupCallRecordingService._();
  static final GroupCallRecordingService instance =
      GroupCallRecordingService._();

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _functions = FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  String? _resourceId;
  String? _sid;
  String? _callId;
  bool _isRecording = false;

  bool get isRecording => _isRecording;

  // ── Start recording ────────────────────────────────────────────────────────
  Future<bool> startRecording({
    required String callId,
    required String channelName,
    required String uid,
  }) async {
    if (_isRecording) return false;
    final currentUid = _auth.currentUser?.uid;
    if (currentUid == null) return false;

    try {
      debugPrint('🎙️ Starting cloud recording for: $channelName');

      // Call Cloud Function to start Agora Cloud Recording
      final callable = _functions.httpsCallable(
        'startGroupCallRecording',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );

      final result = await callable.call({
        'callId': callId,
        'channelName': channelName,
        'uid': uid,
      });

      final data = result.data as Map<dynamic, dynamic>;
      _resourceId = data['resourceId'] as String?;
      _sid = data['sid'] as String?;
      _callId = callId;

      if (_resourceId == null || _sid == null) {
        debugPrint('❌ Recording: missing resourceId or sid');
        return false;
      }

      _isRecording = true;

      // Update Firestore
      await _db.collection('group_calls').doc(callId).update({
        'isRecording': true,
        'recordingStartedAt': DateTime.now().millisecondsSinceEpoch.toString(),
        'recordingResourceId': _resourceId,
        'recordingSid': _sid,
      });

      debugPrint('✅ Cloud recording started: sid=$_sid');
      return true;
    } catch (e) {
      debugPrint('❌ Start recording error: $e');
      return false;
    }
  }

  // ── Stop recording ─────────────────────────────────────────────────────────
  Future<String?> stopRecording({required String callId}) async {
    if (!_isRecording || _resourceId == null || _sid == null) return null;

    try {
      debugPrint('⏹️ Stopping cloud recording: $_sid');

      final callable = _functions.httpsCallable(
        'stopGroupCallRecording',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );

      final result = await callable.call({
        'callId': callId,
        'resourceId': _resourceId,
        'sid': _sid,
      });

      final data = result.data as Map<dynamic, dynamic>;
      final url = data['recordingUrl'] as String?;
      final fileList = data['fileList'] as List<dynamic>?;

      _isRecording = false;

      // Update Firestore
      await _db.collection('group_calls').doc(callId).update({
        'isRecording': false,
        'recordingUrl': url ?? '',
        'recordingFiles': fileList ?? [],
        'recordingEndedAt': DateTime.now().millisecondsSinceEpoch.toString(),
      });

      _resourceId = null;
      _sid = null;
      _callId = null;

      debugPrint('✅ Recording stopped, URL: $url');
      return url;
    } catch (e) {
      debugPrint('❌ Stop recording error: $e');
      return null;
    }
  }

  // ── Query recording status ─────────────────────────────────────────────────
  Future<RecordingStatus?> queryStatus() async {
    if (!_isRecording || _resourceId == null || _sid == null) return null;
    try {
      final callable = _functions.httpsCallable('queryGroupCallRecording');
      final result = await callable.call({
        'resourceId': _resourceId,
        'sid': _sid,
      });
      final data = result.data as Map<dynamic, dynamic>;
      return RecordingStatus(
        status: data['status'] as String? ?? 'unknown',
        fileList: (data['fileList'] as List<dynamic>? ?? []).cast<String>(),
        sliceStartTime: data['sliceStartTime'] as int? ?? 0,
      );
    } catch (e) {
      debugPrint('❌ Query recording error: $e');
      return null;
    }
  }

  // ── Get recording URL from Firestore ──────────────────────────────────────
  Future<String?> getRecordingUrl(String callId) async {
    try {
      final doc = await _db.collection('group_calls').doc(callId).get();
      return doc.data()?['recordingUrl'] as String?;
    } catch (_) {
      return null;
    }
  }

  // ── List all recordings for a group ───────────────────────────────────────
  Future<List<CallRecordingEntry>> getGroupRecordings(String groupId) async {
    try {
      final snap = await _db
          .collection('group_calls')
          .where('groupId', isEqualTo: groupId)
          .where('isRecording', isEqualTo: false)
          .where('recordingUrl', isNotEqualTo: '')
          .orderBy('createdAt', descending: true)
          .limit(20)
          .get();

      return snap.docs.map((doc) {
        final d = doc.data();
        return CallRecordingEntry(
          callId: doc.id,
          groupName: d['groupName'] as String? ?? '',
          url: d['recordingUrl'] as String? ?? '',
          duration: d['durationSeconds'] as int? ?? 0,
          createdAt: DateTime.fromMillisecondsSinceEpoch(
              int.tryParse(d['createdAt']?.toString() ?? '0') ?? 0),
          participantCount: (d['participants'] as List?)?.length ?? 0,
        );
      }).toList();
    } catch (e) {
      debugPrint('❌ getGroupRecordings error: $e');
      return [];
    }
  }
}

class RecordingStatus {
  final String status;
  final List<String> fileList;
  final int sliceStartTime;

  const RecordingStatus({
    required this.status,
    required this.fileList,
    required this.sliceStartTime,
  });
}

class CallRecordingEntry {
  final String callId;
  final String groupName;
  final String url;
  final int duration;
  final DateTime createdAt;
  final int participantCount;

  const CallRecordingEntry({
    required this.callId,
    required this.groupName,
    required this.url,
    required this.duration,
    required this.createdAt,
    required this.participantCount,
  });

  String get formattedDuration {
    final d = Duration(seconds: duration);
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }
}
