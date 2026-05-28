import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_chat_demo/constants/constants.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────

class UserPresence {
  final String userId;
  final bool isOnline;
  final DateTime? lastSeen;
  final String? currentConversationId;

  const UserPresence({
    required this.userId,
    required this.isOnline,
    this.lastSeen,
    this.currentConversationId,
  });

  /// "Just now" / "X minutes ago" / "X hours ago" etc.
  String get lastSeenText {
    if (isOnline) return 'Online';
    if (lastSeen == null) return 'Last seen: unknown';
    final diff = DateTime.now().difference(lastSeen!);
    if (diff.inSeconds < 60) return 'Last seen just now';
    if (diff.inMinutes < 60) return 'Last seen ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Last seen ${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Last seen yesterday';
    return 'Last seen ${diff.inDays}d ago';
  }
}

class TypingInfo {
  final String userId;
  final bool isTyping;
  final DateTime timestamp;

  const TypingInfo({
    required this.userId,
    required this.isTyping,
    required this.timestamp,
  });

  bool get isStillActive =>
      isTyping &&
          DateTime.now().difference(timestamp).inSeconds < 6;
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

class UserPresenceProvider {
  final FirebaseFirestore firebaseFirestore;

  Timer? _heartbeatTimer;
  String? _currentUserId;

  /// One debounce timer per conversation for typing events.
  final Map<String, Timer> _typingTimers = {};

  /// Track which conversations this user is currently marked as typing in.
  final Set<String> _activeTypingConversations = {};

  static const Duration _heartbeatInterval = Duration(seconds: 30);
  static const Duration _typingTimeout = Duration(seconds: 5);
  static const Duration _onlineGracePeriod = Duration(minutes: 2);
  static const String _typingCollection = 'typing_status';

  UserPresenceProvider({required this.firebaseFirestore});

  // ───────────────────────────────────────────────
  // Online / Offline
  // ───────────────────────────────────────────────

  Future<void> setUserOnline(String userId, {String? currentConversationId}) async {
    _currentUserId = userId;
    try {
      await firebaseFirestore
          .collection(FirestoreConstants.pathUserCollection)
          .doc(userId)
          .update({
        'isOnline': true,
        'lastSeen': FieldValue.serverTimestamp(),
        if (currentConversationId != null)
          'currentConversationId': currentConversationId,
      });
      _startHeartbeat(userId);
      print('✅ User online: $userId');
    } catch (e) {
      print('❌ setUserOnline error: $e');
    }
  }

  Future<void> setUserOffline(String userId) async {
    _currentUserId = null;
    try {
      await firebaseFirestore
          .collection(FirestoreConstants.pathUserCollection)
          .doc(userId)
          .update({
        'isOnline': false,
        'lastSeen': FieldValue.serverTimestamp(),
        'currentConversationId': FieldValue.delete(),
      });

      _heartbeatTimer?.cancel();
      _heartbeatTimer = null;

      // Clear any typing statuses this user left behind
      await _clearAllTypingStatuses(userId);

      print('✅ User offline: $userId');
    } catch (e) {
      print('❌ setUserOffline error: $e');
    }
  }

  /// Update the conversation the user is currently viewing (for read-receipt UX).
  Future<void> setCurrentConversation(
      String userId, String? conversationId) async {
    try {
      await firebaseFirestore
          .collection(FirestoreConstants.pathUserCollection)
          .doc(userId)
          .update({
        'currentConversationId': conversationId != null
            ? conversationId
            : FieldValue.delete(),
      });
    } catch (e) {
      print('❌ setCurrentConversation error: $e');
    }
  }

  void _startHeartbeat(String userId) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) async {
      try {
        await firebaseFirestore
            .collection(FirestoreConstants.pathUserCollection)
            .doc(userId)
            .update({'lastSeen': FieldValue.serverTimestamp()});
      } catch (e) {
        print('❌ Heartbeat error: $e');
      }
    });
  }

  // ───────────────────────────────────────────────
  // Typing status
  // ───────────────────────────────────────────────

  Future<void> setTypingStatus({
    required String conversationId,
    required String userId,
    required bool isTyping,
  }) async {
    try {
      _typingTimers[conversationId]?.cancel();

      final data = {
        userId: {
          'isTyping': isTyping,
          'timestamp': FieldValue.serverTimestamp(),
        },
      };

      await firebaseFirestore
          .collection(_typingCollection)
          .doc(conversationId)
          .set(data, SetOptions(merge: true));

      if (isTyping) {
        _activeTypingConversations.add(conversationId);
        // Auto-clear after timeout
        _typingTimers[conversationId] = Timer(_typingTimeout, () {
          setTypingStatus(
            conversationId: conversationId,
            userId: userId,
            isTyping: false,
          );
        });
      } else {
        _activeTypingConversations.remove(conversationId);
        _typingTimers.remove(conversationId);
      }
    } catch (e) {
      print('❌ setTypingStatus error: $e');
    }
  }

  Stream<Map<String, TypingInfo>> getTypingStatusStream(
      String conversationId) {
    return firebaseFirestore
        .collection(_typingCollection)
        .doc(conversationId)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return {};
      final data = doc.data() as Map<String, dynamic>;
      final result = <String, TypingInfo>{};

      data.forEach((uid, value) {
        if (value is Map<String, dynamic>) {
          final isTyping = value['isTyping'] as bool? ?? false;
          final ts = value['timestamp'] as Timestamp?;
          if (ts != null) {
            final info = TypingInfo(
              userId: uid,
              isTyping: isTyping,
              timestamp: ts.toDate(),
            );
            if (info.isStillActive) {
              result[uid] = info;
            }
          }
        }
      });

      return result;
    });
  }

  /// Simple stream returning a set of typing user IDs for a conversation.
  Stream<Set<String>> getTypingUsersStream(String conversationId) {
    return getTypingStatusStream(conversationId)
        .map((map) => map.keys.toSet());
  }

  Future<void> _clearAllTypingStatuses(String userId) async {
    try {
      final batch = firebaseFirestore.batch();
      for (final convId in _activeTypingConversations) {
        final ref = firebaseFirestore
            .collection(_typingCollection)
            .doc(convId);
        batch.update(ref, {userId: FieldValue.delete()});
      }
      await batch.commit();
      _activeTypingConversations.clear();
    } catch (e) {
      print('❌ _clearAllTypingStatuses error: $e');
    }
  }

  // ───────────────────────────────────────────────
  // Read receipts
  // ───────────────────────────────────────────────

  Future<void> markMessagesAsRead({
    required String conversationId,
    required String userId,
  }) async {
    try {
      final messages = await firebaseFirestore
          .collection(FirestoreConstants.pathMessageCollection)
          .doc(conversationId)
          .collection(conversationId)
          .where(FirestoreConstants.idTo, isEqualTo: userId)
          .where('isRead', isEqualTo: false)
          .get();

      if (messages.docs.isEmpty) return;

      final batch = firebaseFirestore.batch();
      for (final doc in messages.docs) {
        batch.update(doc.reference, {
          'isRead': true,
          'readAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      print('✅ Marked ${messages.docs.length} messages as read');
    } catch (e) {
      print('❌ markMessagesAsRead error: $e');
    }
  }

  /// Mark a single message as delivered.
  Future<void> markMessageDelivered({
    required String conversationId,
    required String messageId,
  }) async {
    try {
      await firebaseFirestore
          .collection(FirestoreConstants.pathMessageCollection)
          .doc(conversationId)
          .collection(conversationId)
          .doc(messageId)
          .update({
        'isDelivered': true,
        'deliveredAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('❌ markMessageDelivered error: $e');
    }
  }

  Stream<int> getUnreadCountStream(
      String conversationId, String userId) {
    return firebaseFirestore
        .collection(FirestoreConstants.pathMessageCollection)
        .doc(conversationId)
        .collection(conversationId)
        .where(FirestoreConstants.idTo, isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((s) => s.size);
  }

  /// Total unread count across all conversations for a user.
  Future<int> getTotalUnreadCount(String userId) async {
    try {
      // This requires a denormalized 'unread_counts' collection for efficiency.
      // Fallback: sum from user doc if maintained.
      final doc = await firebaseFirestore
          .collection(FirestoreConstants.pathUserCollection)
          .doc(userId)
          .get();
      if (doc.exists) {
        final data = doc.data() ?? {};
        return (data['totalUnread'] as int?) ?? 0;
      }
      return 0;
    } catch (e) {
      print('❌ getTotalUnreadCount error: $e');
      return 0;
    }
  }

  // ───────────────────────────────────────────────
  // User online status
  // ───────────────────────────────────────────────

  Stream<UserPresence> getUserPresenceStream(String userId) {
    return firebaseFirestore
        .collection(FirestoreConstants.pathUserCollection)
        .doc(userId)
        .snapshots()
        .map((doc) {
      if (!doc.exists) {
        return UserPresence(userId: userId, isOnline: false);
      }
      final data = doc.data()!;
      final isOnline = data['isOnline'] as bool? ?? false;
      final lastSeenTs = data['lastSeen'] as Timestamp?;
      final lastSeen = lastSeenTs?.toDate();

      // Grace-period check: if lastSeen > gracePeriod ago, treat as offline
      bool effectiveOnline = isOnline;
      if (isOnline && lastSeen != null) {
        if (DateTime.now().difference(lastSeen) > _onlineGracePeriod) {
          effectiveOnline = false;
        }
      }

      return UserPresence(
        userId: userId,
        isOnline: effectiveOnline,
        lastSeen: lastSeen,
        currentConversationId:
        data['currentConversationId'] as String?,
      );
    });
  }

  Future<UserPresence> getUserPresence(String userId) async {
    try {
      final doc = await firebaseFirestore
          .collection(FirestoreConstants.pathUserCollection)
          .doc(userId)
          .get();
      if (!doc.exists) {
        return UserPresence(userId: userId, isOnline: false);
      }
      final data = doc.data()!;
      final isOnline = data['isOnline'] as bool? ?? false;
      final lastSeenTs = data['lastSeen'] as Timestamp?;
      return UserPresence(
        userId: userId,
        isOnline: isOnline,
        lastSeen: lastSeenTs?.toDate(),
        currentConversationId:
        data['currentConversationId'] as String?,
      );
    } catch (e) {
      print('❌ getUserPresence error: $e');
      return UserPresence(userId: userId, isOnline: false);
    }
  }

  // ───────────────────────────────────────────────
  // Online friends
  // ───────────────────────────────────────────────

  Stream<List<Map<String, dynamic>>> getOnlineFriendsStream(
      String userId) {
    return firebaseFirestore
        .collection(FirestoreConstants.pathUserCollection)
        .where('isOnline', isEqualTo: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
        .where((d) => d.id != userId) // exclude self
        .map((doc) {
      final data = doc.data();
      return {
        'id': doc.id,
        'nickname': data['nickname'] ?? '',
        'photoUrl': data['photoUrl'] ?? '',
        'isOnline': data['isOnline'] ?? false,
        'lastSeen': (data['lastSeen'] as Timestamp?)?.toDate(),
      };
    })
        .toList());
  }

  // ───────────────────────────────────────────────
  // Batch presence fetch (for conversation list)
  // ───────────────────────────────────────────────

  Future<Map<String, UserPresence>> getMultipleUserPresences(
      List<String> userIds) async {
    if (userIds.isEmpty) return {};
    try {
      // Firestore whereIn limit = 30
      final results = <String, UserPresence>{};
      for (int i = 0; i < userIds.length; i += 30) {
        final chunk = userIds.sublist(
            i, (i + 30).clamp(0, userIds.length));
        final snapshot = await firebaseFirestore
            .collection(FirestoreConstants.pathUserCollection)
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final doc in snapshot.docs) {
          final data = doc.data();
          final isOnline = data['isOnline'] as bool? ?? false;
          final lastSeenTs = data['lastSeen'] as Timestamp?;
          results[doc.id] = UserPresence(
            userId: doc.id,
            isOnline: isOnline,
            lastSeen: lastSeenTs?.toDate(),
          );
        }
      }
      return results;
    } catch (e) {
      print('❌ getMultipleUserPresences error: $e');
      return {};
    }
  }

  // ───────────────────────────────────────────────
  // Dispose
  // ───────────────────────────────────────────────

  void dispose() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    for (final t in _typingTimers.values) {
      t.cancel();
    }
    _typingTimers.clear();
    _activeTypingConversations.clear();
    print('✅ UserPresenceProvider disposed');
  }
}