import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../constants/app_constants.dart';
import '../models/group_call_model.dart';
import '../services/group_call_service.dart';

/// Handles all push/local notifications for group calls.
/// - Sends FCM invites to all group members when a call starts.
/// - Shows a local heads-up notification for incoming calls.
/// - Cancels notification when call ends / user accepts / declines.
class GroupCallNotificationService {
  GroupCallNotificationService._();
  static final GroupCallNotificationService instance =
      GroupCallNotificationService._();

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  late FlutterLocalNotificationsPlugin _localPlugin;

  bool _initialized = false;

  static const int _callNotifId = 88001;

  // ── Initialize ─────────────────────────────────────────────────────────────
  Future<void> initialize(FlutterLocalNotificationsPlugin plugin) async {
    if (_initialized) return;
    _localPlugin = plugin;
    _initialized = true;
    debugPrint('✅ GroupCallNotificationService initialized');
  }

  // ── Show incoming call notification ────────────────────────────────────────
  Future<void> showIncomingCallNotification({
    required GroupCallModel call,
    required String targetUserId,
  }) async {
    if (!_initialized) return;
    try {
      final isVideo = call.callType == GroupCallType.video;
      final title =
          isVideo ? '📹 Cuộc gọi video nhóm' : '📞 Cuộc gọi thoại nhóm';
      final body =
          '${call.initiatorName} đang gọi cho nhóm "${call.groupName}"';

      final androidDetails = AndroidNotificationDetails(
        AppConstants.gameChannelId,
        'Cuộc gọi nhóm',
        channelDescription: 'Thông báo cuộc gọi nhóm đến',
        importance: Importance.max,
        priority: Priority.max,
        fullScreenIntent: true,
        category: AndroidNotificationCategory.call,
        autoCancel: false,
        ongoing: true,
        color: isVideo ? const Color(0xFF3B82F6) : const Color(0xFF22C55E),
        actions: [
          const AndroidNotificationAction(
            'decline_call',
            'Từ chối',
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            'accept_call',
            isVideo ? 'Tham gia video' : 'Tham gia',
            cancelNotification: true,
          ),
        ],
        styleInformation: BigTextStyleInformation(body),
        largeIcon: call.groupAvatarUrl.isNotEmpty
            ? DrawableResourceAndroidBitmap(call.groupAvatarUrl)
            : null,
      );

      final iosDetails = DarwinNotificationDetails(
        categoryIdentifier: 'call_category',
        interruptionLevel: InterruptionLevel.timeSensitive,
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'call_ringtone.aiff',
        subtitle: 'Nhóm: ${call.groupName}',
      );

      final details =
          NotificationDetails(android: androidDetails, iOS: iosDetails);

      await _localPlugin.show(
        _callNotifId,
        title,
        body,
        details,
        payload: jsonEncode({
          'type': 'group_call',
          'callId': call.callId,
          'groupName': call.groupName,
          'isVideo': isVideo,
        }),
      );

      debugPrint('✅ GroupCallNotif shown for: ${call.callId}');
    } catch (e) {
      debugPrint('❌ GroupCallNotif show error: $e');
    }
  }

  // ── Cancel incoming call notification ──────────────────────────────────────
  Future<void> cancelIncomingCallNotification() async {
    if (!_initialized) return;
    try {
      await _localPlugin.cancel(_callNotifId);
    } catch (e) {
      debugPrint('❌ Cancel notif error: $e');
    }
  }

  // ── Show ongoing call notification ─────────────────────────────────────────
  Future<void> showOngoingCallNotification({
    required GroupCallModel call,
    required DateTime startTime,
  }) async {
    if (!_initialized) return;
    try {
      final isVideo = call.callType == GroupCallType.video;

      final androidDetails = AndroidNotificationDetails(
        AppConstants.callChannelId,
        'Cuộc gọi đang diễn ra',
        channelDescription: 'Thông báo cuộc gọi nhóm đang diễn ra',
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        autoCancel: false,
        showWhen: true,
        when: startTime.millisecondsSinceEpoch,
        usesChronometer: true,
        chronometerCountDown: false,
        category: AndroidNotificationCategory.call,
        color: isVideo ? const Color(0xFF3B82F6) : const Color(0xFF22C55E),
        actions: [
          const AndroidNotificationAction(
            'end_call',
            'Kết thúc',
            cancelNotification: true,
          ),
        ],
      );

      await _localPlugin.show(
        _callNotifId + 1,
        '${isVideo ? "📹" : "📞"} ${call.groupName}',
        '${call.participantCount} người đang trong cuộc gọi',
        NotificationDetails(android: androidDetails),
        payload: jsonEncode({
          'type': 'ongoing_group_call',
          'callId': call.callId,
        }),
      );
    } catch (e) {
      debugPrint('❌ Ongoing notif error: $e');
    }
  }

  // ── Cancel ongoing notification ────────────────────────────────────────────
  Future<void> cancelOngoingNotification() async {
    if (!_initialized) return;
    try {
      await _localPlugin.cancel(_callNotifId + 1);
    } catch (_) {}
  }

  // ── Send FCM invite to group members ──────────────────────────────────────
  Future<void> sendCallInvites({
    required GroupCallModel call,
    required List<String> memberIds,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final isVideo = call.callType == GroupCallType.video;

    // Fetch FCM tokens for all invited members
    for (final memberId in memberIds) {
      if (memberId == uid) continue;
      try {
        final snap = await _db.collection('users').doc(memberId).get();
        final token = snap.data()?['fcmToken'] as String?;
        if (token == null || token.isEmpty) continue;

        // Ideally call a Cloud Function that sends FCM.
        // Here we write to a Firestore trigger collection as fallback.
        await _db.collection('_fcm_triggers').add({
          'token': token,
          'title':
              isVideo ? '📹 Cuộc gọi video nhóm' : '📞 Cuộc gọi thoại nhóm',
          'body': '${call.initiatorName} đang gọi nhóm "${call.groupName}"',
          'data': {
            'type': 'group_call_invite',
            'callId': call.callId,
            'groupId': call.groupId,
            'groupName': call.groupName,
            'isVideo': isVideo.toString(),
            'initiatorName': call.initiatorName,
          },
          'createdAt': FieldValue.serverTimestamp(),
          'ttl': 45,
        });
      } catch (e) {
        debugPrint('⚠️ FCM invite to $memberId failed: $e');
      }
    }
    debugPrint('✅ FCM invites sent for call: ${call.callId}');
  }

  // ── Handle FCM foreground message ─────────────────────────────────────────
  /// Call this from AppInitializer._handleFcmForegroundMessages
  Future<void> handleForegroundMessage(RemoteMessage message) async {
    final data = message.data;
    if (data['type'] != 'group_call_invite') return;

    final callId = data['callId'] as String?;
    if (callId == null) return;

    final call = await GroupCallService.instance.getCall(callId);
    if (call == null || call.isEnded) return;

    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    // Don't show if already a participant
    if (call.isParticipant(uid)) return;

    await showIncomingCallNotification(call: call, targetUserId: uid);
  }

  // ── Parse notification tap payload ────────────────────────────────────────
  static Map<String, dynamic>? parsePayload(String? payload) {
    if (payload == null) return null;
    try {
      return jsonDecode(payload) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
