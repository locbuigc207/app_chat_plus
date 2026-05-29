import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_chat_demo/constants/constants.dart';





enum ViewOnceStatus {
  
  unopened,

  
  viewing,

  
  expired,

  
  revoked,
}

class ViewOnceMessage {
  final String id;
  final String groupChatId;
  final String senderId;
  final String recipientId;
  final String content;
  final int type;
  final ViewOnceStatus status;
  final DateTime sentAt;
  final DateTime? viewedAt;
  final String? viewedBy;
  final DateTime? expiresAt;
  final int viewDurationSeconds;

  const ViewOnceMessage({
    required this.id,
    required this.groupChatId,
    required this.senderId,
    required this.recipientId,
    required this.content,
    required this.type,
    required this.status,
    required this.sentAt,
    this.viewedAt,
    this.viewedBy,
    this.expiresAt,
    this.viewDurationSeconds = 10,
  });

  bool get isExpired => status == ViewOnceStatus.expired;
  bool get isViewable => status == ViewOnceStatus.unopened || status == ViewOnceStatus.viewing;

  factory ViewOnceMessage.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) throw Exception('ViewOnce doc data is null');

    DateTime? tsToDate(dynamic v) {
      if (v == null) return null;
      if (v is Timestamp) return v.toDate();
      if (v is String) {
        final ms = int.tryParse(v);
        return ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
      }
      if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
      return null;
    }

    return ViewOnceMessage(
      id: doc.id,
      groupChatId: data['groupChatId'] ?? '',
      senderId: data[FirestoreConstants.idFrom] ?? '',
      recipientId: data[FirestoreConstants.idTo] ?? '',
      content: data[FirestoreConstants.content] ?? '',
      type: (data[FirestoreConstants.type] as num?)?.toInt() ?? 0,
      status: ViewOnceStatus.values.firstWhere(
        (s) => s.name == (data['viewOnceStatus'] ?? 'unopened'),
        orElse: () => ViewOnceStatus.unopened,
      ),
      sentAt: tsToDate(data['sentAt']) ?? DateTime.now(),
      viewedAt: tsToDate(data['viewedAt']),
      viewedBy: data['viewedBy'] as String?,
      expiresAt: tsToDate(data['expiresAt']),
      viewDurationSeconds: (data['viewDurationSeconds'] as num?)?.toInt() ?? 10,
    );
  }
}





class ViewOnceProvider {
  final FirebaseFirestore firebaseFirestore;

  
  final Map<String, Timer> _viewTimers = {};

  ViewOnceProvider({required this.firebaseFirestore});

  
  
  

  
  
  Future<String?> sendViewOnceMessage({
    required String groupChatId,
    required String currentUserId,
    required String peerId,
    required String content,
    required int type,
    int viewDurationSeconds = 10,
  }) async {
    try {
      final messageId = DateTime.now().millisecondsSinceEpoch.toString();

      await firebaseFirestore
          .collection(FirestoreConstants.pathMessageCollection)
          .doc(groupChatId)
          .collection(groupChatId)
          .doc(messageId)
          .set({
        FirestoreConstants.idFrom: currentUserId,
        FirestoreConstants.idTo: peerId,
        FirestoreConstants.timestamp: messageId,
        FirestoreConstants.content: content,
        FirestoreConstants.type: type,
        'groupChatId': groupChatId,
        'isViewOnce': true,
        'viewOnceStatus': ViewOnceStatus.unopened.name,
        'viewDurationSeconds': viewDurationSeconds,
        'sentAt': FieldValue.serverTimestamp(),
        'viewedAt': null,
        'viewedBy': null,
        'expiresAt': null,
        'isDeleted': false,
      });

      debugPrint('✅ View-once message sent: $messageId');
      return messageId;
    } catch (e) {
      debugPrint('❌ sendViewOnceMessage error: $e');
      return null;
    }
  }

  
  
  

  
  
  Future<bool> openViewOnceMessage({
    required String groupChatId,
    required String messageId,
    required String userId,
  }) async {
    try {
      
      final doc = await _getMessageDoc(groupChatId, messageId);
      if (doc == null) {
        debugPrint('⚠️ View-once message not found');
        return false;
      }

      final data = doc.data() as Map<String, dynamic>;
      final recipientId = data[FirestoreConstants.idTo] as String? ?? '';

      if (recipientId != userId) {
        debugPrint('⚠️ Unauthorized: $userId cannot open message for $recipientId');
        return false;
      }

      final status = data['viewOnceStatus'] as String? ?? 'unopened';
      if (status != ViewOnceStatus.unopened.name) {
        debugPrint('⚠️ Message already opened/expired (status: $status)');
        return false;
      }

      final viewDuration = (data['viewDurationSeconds'] as num?)?.toInt() ?? 10;
      final expiresAt = DateTime.now().add(Duration(seconds: viewDuration));

      await _getMessageRef(groupChatId, messageId).update({
        'viewOnceStatus': ViewOnceStatus.viewing.name,
        'viewedAt': FieldValue.serverTimestamp(),
        'viewedBy': userId,
        'expiresAt': expiresAt.millisecondsSinceEpoch.toString(),
      });

      
      _viewTimers[messageId]?.cancel();
      _viewTimers[messageId] = Timer(
        Duration(seconds: viewDuration),
        () => _expireViewOnceMessage(groupChatId, messageId),
      );

      debugPrint('👁 View-once opened: $messageId — expires in ${viewDuration}s');
      return true;
    } catch (e) {
      debugPrint('❌ openViewOnceMessage error: $e');
      return false;
    }
  }

  Future<void> _expireViewOnceMessage(String groupChatId, String messageId) async {
    try {
      await _getMessageRef(groupChatId, messageId).update({
        'viewOnceStatus': ViewOnceStatus.expired.name,
        FirestoreConstants.content: '', 
        'isDeleted': true,
        'deletedAt': DateTime.now().millisecondsSinceEpoch.toString(),
        'deletionReason': 'view_once_expired',
      });
      _viewTimers.remove(messageId);
      debugPrint('✅ View-once expired: $messageId');
    } catch (e) {
      debugPrint('❌ _expireViewOnceMessage error: $e');
    }
  }

  
  
  

  Future<bool> revokeViewOnceMessage({
    required String groupChatId,
    required String messageId,
    required String senderId,
  }) async {
    try {
      final doc = await _getMessageDoc(groupChatId, messageId);
      if (doc == null) return false;

      final data = doc.data() as Map<String, dynamic>;
      final actualSender = data[FirestoreConstants.idFrom] as String? ?? '';

      if (actualSender != senderId) {
        debugPrint('⚠️ Unauthorized revoke: $senderId is not sender');
        return false;
      }

      final status = data['viewOnceStatus'] as String? ?? 'unopened';
      if (status != ViewOnceStatus.unopened.name) {
        debugPrint('⚠️ Cannot revoke: message already opened');
        return false;
      }

      await _getMessageRef(groupChatId, messageId).update({
        'viewOnceStatus': ViewOnceStatus.revoked.name,
        FirestoreConstants.content: '',
        'isDeleted': true,
        'revokedAt': DateTime.now().millisecondsSinceEpoch.toString(),
        'deletionReason': 'revoked_by_sender',
      });

      debugPrint('✅ View-once revoked: $messageId');
      return true;
    } catch (e) {
      debugPrint('❌ revokeViewOnceMessage error: $e');
      return false;
    }
  }

  
  
  

  Future<bool> isMessageViewable({
    required String groupChatId,
    required String messageId,
  }) async {
    try {
      final doc = await _getMessageDoc(groupChatId, messageId);
      if (doc == null) return false;
      final data = doc.data() as Map<String, dynamic>;
      final isViewOnce = data['isViewOnce'] as bool? ?? false;
      if (!isViewOnce) return false;
      final status = data['viewOnceStatus'] as String? ?? 'expired';
      return status == ViewOnceStatus.unopened.name;
    } catch (e) {
      debugPrint('❌ isMessageViewable error: $e');
      return false;
    }
  }

  Future<ViewOnceMessage?> getViewOnceMessage({
    required String groupChatId,
    required String messageId,
  }) async {
    try {
      final doc = await _getMessageDoc(groupChatId, messageId);
      if (doc == null) return null;
      return ViewOnceMessage.fromDocument(doc);
    } catch (e) {
      debugPrint('❌ getViewOnceMessage error: $e');
      return null;
    }
  }

  
  Stream<ViewOnceMessage?> watchViewOnceMessage({
    required String groupChatId,
    required String messageId,
  }) {
    return _getMessageRef(groupChatId, messageId).snapshots().map((doc) {
      if (!doc.exists) return null;
      try {
        return ViewOnceMessage.fromDocument(doc);
      } catch (_) {
        return null;
      }
    });
  }

  
  Future<List<ViewOnceMessage>> getSentViewOnceMessages({
    required String groupChatId,
    required String userId,
  }) async {
    try {
      final snapshot = await firebaseFirestore
          .collection(FirestoreConstants.pathMessageCollection)
          .doc(groupChatId)
          .collection(groupChatId)
          .where(FirestoreConstants.idFrom, isEqualTo: userId)
          .where('isViewOnce', isEqualTo: true)
          .orderBy(FirestoreConstants.timestamp, descending: true)
          .limit(50)
          .get();

      return snapshot.docs.map(ViewOnceMessage.fromDocument).toList();
    } catch (e) {
      debugPrint('❌ getSentViewOnceMessages error: $e');
      return [];
    }
  }

  
  
  

  
  Future<void> processExpiredOnAppResume(String groupChatId) async {
    try {
      final now = DateTime.now();
      final snapshot = await firebaseFirestore
          .collection(FirestoreConstants.pathMessageCollection)
          .doc(groupChatId)
          .collection(groupChatId)
          .where('isViewOnce', isEqualTo: true)
          .where('viewOnceStatus', isEqualTo: ViewOnceStatus.viewing.name)
          .get();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final expiresAtRaw = data['expiresAt'];
        if (expiresAtRaw != null) {
          final ms = int.tryParse(expiresAtRaw.toString()) ?? 0;
          final expiresAt = DateTime.fromMillisecondsSinceEpoch(ms);
          if (expiresAt.isBefore(now)) {
            await _expireViewOnceMessage(groupChatId, doc.id);
          } else {
            
            final remaining = expiresAt.difference(now);
            _viewTimers[doc.id]?.cancel();
            _viewTimers[doc.id] = Timer(
              remaining,
              () => _expireViewOnceMessage(groupChatId, doc.id),
            );
          }
        }
      }
      debugPrint('✅ Processed expired view-once messages on resume');
    } catch (e) {
      debugPrint('❌ processExpiredOnAppResume error: $e');
    }
  }

  
  
  

  DocumentReference _getMessageRef(String groupChatId, String messageId) => firebaseFirestore
      .collection(FirestoreConstants.pathMessageCollection)
      .doc(groupChatId)
      .collection(groupChatId)
      .doc(messageId);

  Future<DocumentSnapshot?> _getMessageDoc(String groupChatId, String messageId) async {
    try {
      final doc = await _getMessageRef(groupChatId, messageId).get();
      return doc.exists ? doc : null;
    } catch (e) {
      return null;
    }
  }

  void dispose() {
    for (final t in _viewTimers.values) {
      t.cancel();
    }
    _viewTimers.clear();
    debugPrint('✅ ViewOnceProvider disposed');
  }
}
