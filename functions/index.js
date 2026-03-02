// functions/index.js - COMPLETE CLOUD FUNCTIONS

const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

// =====================================================
// 1. AUTO-DELETE EXPIRED MESSAGES (Chạy mỗi 5 phút)
// =====================================================
exports.cleanupExpiredMessages = functions.pubsub
  .schedule('every 5 minutes')
  .onRun(async (context) => {
    console.log('🧹 Starting message cleanup...');

    try {
      const db = admin.firestore();
      const now = Date.now();

      // Get conversations with auto-delete enabled
      const conversations = await db
        .collection('conversations')
        .where('autoDeleteEnabled', '==', true)
        .get();

      console.log(`Found ${conversations.size} conversations with auto-delete`);

      let totalDeleted = 0;

      for (const conv of conversations.docs) {
        const duration = conv.data().autoDeleteDuration;
        if (!duration) continue;

        const conversationId = conv.id;

        // Get expired messages
        const expiredMessages = await db
          .collection('messages')
          .doc(conversationId)
          .collection(conversationId)
          .where('autoDeleteAt', '<=', now.toString())
          .where('isDeleted', '==', false)
          .get();

        if (expiredMessages.empty) continue;

        // Batch delete
        const batch = db.batch();
        let batchCount = 0;

        for (const msg of expiredMessages.docs) {
          batch.update(msg.ref, {
            isDeleted: true,
            content: 'This message was automatically deleted',
            deletedAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          batchCount++;
          totalDeleted++;

          // Commit every 500 operations
          if (batchCount >= 500) {
            await batch.commit();
            batchCount = 0;
          }
        }

        // Commit remaining
        if (batchCount > 0) {
          await batch.commit();
        }
      }

      console.log(`✅ Cleaned up ${totalDeleted} expired messages`);
      return null;

    } catch (error) {
      console.error('❌ Error in cleanup:', error);
      return null;
    }
  });

// =====================================================
// 2. SCHEDULE MESSAGE DELETION ON CREATE
// =====================================================
exports.scheduleMessageDeletion = functions.firestore
  .document('messages/{conversationId}/{messageId}')
  .onCreate(async (snap, context) => {
    try {
      const { conversationId, messageId } = context.params;

      // Get conversation settings
      const convDoc = await admin.firestore()
        .collection('conversations')
        .doc(conversationId)
        .get();

      if (!convDoc.exists) return null;

      const convData = convDoc.data();
      if (!convData.autoDeleteEnabled || !convData.autoDeleteDuration) {
        return null;
      }

      // Calculate deletion time
      const messageData = snap.data();
      const timestamp = parseInt(messageData.timestamp);
      const deleteAt = timestamp + convData.autoDeleteDuration;

      // Store deletion metadata
      await snap.ref.update({
        autoDeleteAt: deleteAt.toString(),
      });

      console.log(`📅 Scheduled deletion for message ${messageId}`);
      return null;

    } catch (error) {
      console.error('❌ Error scheduling deletion:', error);
      return null;
    }
  });

// =====================================================
// 3. CLEANUP TYPING STATUS (Chạy mỗi phút)
// =====================================================
exports.cleanupTypingStatus = functions.pubsub
  .schedule('every 1 minutes')
  .onRun(async (context) => {
    try {
      const db = admin.firestore();
      const now = Date.now();
      const fiveSecondsAgo = now - 5000;

      const typingDocs = await db.collection('typing_status').get();

      for (const doc of typingDocs.docs) {
        const data = doc.data();
        const updates = {};
        let hasChanges = false;

        for (const [userId, status] of Object.entries(data)) {
          if (status.timestamp &&
              status.timestamp.toMillis() < fiveSecondsAgo) {
            updates[userId] = admin.firestore.FieldValue.delete();
            hasChanges = true;
          }
        }

        if (hasChanges) {
          await doc.ref.update(updates);
        }
      }

      return null;
    } catch (error) {
      console.error('❌ Error cleaning typing status:', error);
      return null;
    }
  });

// =====================================================
// 4. UPDATE USER LAST SEEN ON OFFLINE
// =====================================================
exports.updateUserPresence = functions.firestore
  .document('users/{userId}')
  .onUpdate(async (change, context) => {
    try {
      const before = change.before.data();
      const after = change.after.data();

      // User went offline
      if (before.isOnline && !after.isOnline) {
        await change.after.ref.update({
          lastSeen: admin.firestore.FieldValue.serverTimestamp(),
        });

        console.log(`✅ Updated last seen for user ${context.params.userId}`);
      }

      return null;
    } catch (error) {
      console.error('❌ Error updating presence:', error);
      return null;
    }
  });

// =====================================================
// 5. SEND PUSH NOTIFICATION ON NEW MESSAGE
// =====================================================
exports.sendMessageNotification = functions.firestore
  .document('messages/{conversationId}/{messageId}')
  .onCreate(async (snap, context) => {
    try {
      const messageData = snap.data();
      const { conversationId } = context.params;

      // Get receiver info
      const receiverDoc = await admin.firestore()
        .collection('users')
        .doc(messageData.idTo)
        .get();

      if (!receiverDoc.exists) return null;

      const receiverData = receiverDoc.data();
      const pushToken = receiverData.pushToken;

      if (!pushToken) return null;

      // Get sender info
      const senderDoc = await admin.firestore()
        .collection('users')
        .doc(messageData.idFrom)
        .get();

      const senderName = senderDoc.exists
        ? senderDoc.data().nickname
        : 'Someone';

      // Send notification
      const payload = {
        notification: {
          title: senderName,
          body: messageData.type === 0
            ? messageData.content
            : '📷 Sent an image',
          sound: 'default',
        },
        data: {
          conversationId: conversationId,
          senderId: messageData.idFrom,
          type: 'new_message',
        },
      };

      await admin.messaging().sendToDevice(pushToken, payload);

      console.log(`✅ Notification sent to ${messageData.idTo}`);
      return null;

    } catch (error) {
      console.error('❌ Error sending notification:', error);
      return null;
    }
  });

// =====================================================
// 6. CLEANUP OLD DELETED MESSAGES (Chạy hàng ngày)
// =====================================================
exports.cleanupOldDeletedMessages = functions.pubsub
  .schedule('every 24 hours')
  .onRun(async (context) => {
    try {
      const db = admin.firestore();
      const thirtyDaysAgo = Date.now() - (30 * 24 * 60 * 60 * 1000);

      // Get all deleted messages older than 30 days
      const query = db.collectionGroup('messages')
        .where('isDeleted', '==', true)
        .where('deletedAt', '<', new Date(thirtyDaysAgo));

      const snapshot = await query.get();

      if (snapshot.empty) {
        console.log('No old deleted messages to clean');
        return null;
      }

      // Delete in batches
      const batch = db.batch();
      let count = 0;

      for (const doc of snapshot.docs) {
        batch.delete(doc.ref);
        count++;

        if (count >= 500) {
          await batch.commit();
          count = 0;
        }
      }

      if (count > 0) {
        await batch.commit();
      }

      console.log(`✅ Deleted ${snapshot.size} old messages`);
      return null;

    } catch (error) {
      console.error('❌ Error cleaning old messages:', error);
      return null;
    }
  });