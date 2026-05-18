const functions = require("firebase-functions");
const admin = require("firebase-admin");
const {RtcTokenBuilder, RtcRole} = require("agora-access-token");
const cors = require("cors")({origin: true});
const {GoogleGenerativeAI} = require("@google/generative-ai");

admin.initializeApp();

// =====================================================
// CẤU HÌNH AGORA
// =====================================================
const APP_ID = "11d7a5c344694ee5ad835a7e0d388871";
const APP_CERTIFICATE = "aa8c095cf3c248fe876a66b788a37cf4";

// =====================================================
// CẤU HÌNH GEMINI AI (Dùng process.env thay vì functions.config)
// =====================================================
const apiKey = process.env.GEMINI_API_KEY;

if (!apiKey) {
  console.error("LỖI CỰC KỲ QUAN TRỌNG: Chưa thiết lập GEMINI_API_KEY trong file functions/.env");
}

const genAI = new GoogleGenerativeAI(apiKey);
// =====================================================
// 1. GENERATE AGORA TOKEN
// =====================================================
exports.generateAgoraToken = functions.https.onRequest((req, res) => {
  cors(req, res, () => {
    if (req.method !== "GET") {
      return res.status(403).send("Forbidden!");
    }

    const channelName = req.query.channelName;
    if (!channelName) {
      return res.status(400).json({error: "channelName is required"});
    }

    const uid = req.query.uid ? parseInt(req.query.uid, 10) : 0;
    const role = RtcRole.PUBLISHER;
    const expireTime = 3600;
    const currentTimestamp = Math.floor(Date.now() / 1000);
    const privilegeExpireTime = currentTimestamp + expireTime;

    try {
      const token = RtcTokenBuilder.buildTokenWithUid(
        APP_ID,
        APP_CERTIFICATE,
        channelName,
        uid,
        role,
        privilegeExpireTime,
      );
      return res.status(200).json({token});
    } catch (error) {
      console.error("Lỗi khi tạo Token:", error);
      return res.status(500).json({error: "Internal Server Error"});
    }
  });
});
// =====================================================
// 2. AUTO-DELETE EXPIRED MESSAGES (Chạy mỗi 5 phút)
// =====================================================
exports.cleanupExpiredMessages = functions.pubsub
  .schedule("every 5 minutes")
  .onRun(async (context) => {
    console.log("🧹 Starting message cleanup...");

    try {
      const db = admin.firestore();
      const now = Date.now();

      const conversations = await db
        .collection("conversations")
        .where("autoDeleteEnabled", "==", true)
        .get();

      console.log(`Found ${conversations.size} conversations with auto-delete`);

      let totalDeleted = 0;

      for (const conv of conversations.docs) {
        const duration = conv.data().autoDeleteDuration;
        if (!duration) continue;

        const conversationId = conv.id;

        const expiredMessages = await db
          .collection("messages")
          .doc(conversationId)
          .collection(conversationId)
          .where("autoDeleteAt", "<=", now.toString())
          .where("isDeleted", "==", false)
          .get();

        if (expiredMessages.empty) continue;

        const batch = db.batch();
        let batchCount = 0;

        for (const msg of expiredMessages.docs) {
          batch.update(msg.ref, {
            isDeleted: true,
            content: "This message was automatically deleted",
            deletedAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          batchCount++;
          totalDeleted++;

          if (batchCount >= 500) {
            await batch.commit();
            batchCount = 0;
          }
        }

        if (batchCount > 0) {
          await batch.commit();
        }
      }

      console.log(`✅ Cleaned up ${totalDeleted} expired messages`);
      return null;
    } catch (error) {
      console.error("❌ Error in cleanup:", error);
      return null;
    }
  });
// =====================================================
// 3. SCHEDULE MESSAGE DELETION ON CREATE
// =====================================================
exports.scheduleMessageDeletion = functions.firestore
  .document("messages/{conversationId}/{messageId}")
  .onCreate(async (snap, context) => {
    try {
      const {conversationId, messageId} = context.params;

      const convDoc = await admin
        .firestore()
        .collection("conversations")
        .doc(conversationId)
        .get();

      if (!convDoc.exists) return null;

      const convData = convDoc.data();
      if (!convData.autoDeleteEnabled || !convData.autoDeleteDuration) {
        return null;
      }

      const messageData = snap.data();
      const timestamp = parseInt(messageData.timestamp);
      const deleteAt = timestamp + convData.autoDeleteDuration;

      await snap.ref.update({
        autoDeleteAt: deleteAt.toString(),
      });

      console.log(`📅 Scheduled deletion for message ${messageId}`);
      return null;
    } catch (error) {
      console.error("❌ Error scheduling deletion:", error);
      return null;
    }
  });
// =====================================================
// 4. CLEANUP TYPING STATUS (Chạy mỗi phút)
// =====================================================
exports.cleanupTypingStatus = functions.pubsub
  .schedule("every 1 minutes")
  .onRun(async (context) => {
    try {
      const db = admin.firestore();
      const now = Date.now();
      const fiveSecondsAgo = now - 5000;

      const typingDocs = await db.collection("typing_status").get();

      for (const doc of typingDocs.docs) {
        const data = doc.data();
        const updates = {};
        let hasChanges = false;

        for (const [userId, status] of Object.entries(data)) {
          if (
            status.timestamp &&
            status.timestamp.toMillis() < fiveSecondsAgo
          ) {
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
      console.error("❌ Error cleaning typing status:", error);
      return null;
    }
  });
// =====================================================
// 5. UPDATE USER LAST SEEN ON OFFLINE
// =====================================================
exports.updateUserPresence = functions.firestore
  .document("users/{userId}")
  .onUpdate(async (change, context) => {
    try {
      const before = change.before.data();
      const after = change.after.data();

      if (before.isOnline && !after.isOnline) {
        await change.after.ref.update({
          lastSeen: admin.firestore.FieldValue.serverTimestamp(),
        });

        console.log(`✅ Updated last seen for user ${context.params.userId}`);
      }

      return null;
    } catch (error) {
      console.error("❌ Error updating presence:", error);
      return null;
    }
  });
// =====================================================
// 6. SEND PUSH NOTIFICATION ON NEW MESSAGE
// =====================================================
exports.sendMessageNotification = functions.firestore
  .document("messages/{conversationId}/{messageId}")
  .onCreate(async (snap, context) => {
    try {
      const messageData = snap.data();
      const {conversationId} = context.params;

      const receiverDoc = await admin
        .firestore()
        .collection("users")
        .doc(messageData.idTo)
        .get();

      if (!receiverDoc.exists) return null;

      const receiverData = receiverDoc.data();
      const pushToken = receiverData.pushToken;

      if (!pushToken) return null;

      const senderDoc = await admin
        .firestore()
        .collection("users")
        .doc(messageData.idFrom)
        .get();

      const senderName = senderDoc.exists ?
        senderDoc.data().nickname :
        "Someone";

      const payload = {
        notification: {
          title: senderName,
          body:
            messageData.type === 0 ? messageData.content : "📷 Sent an image",
          sound: "default",
        },
        data: {
          conversationId: conversationId,
          senderId: messageData.idFrom,
          type: "new_message",
        },
      };

      await admin.messaging().sendToDevice(pushToken, payload);

      console.log(`✅ Notification sent to ${messageData.idTo}`);
      return null;
    } catch (error) {
      console.error("❌ Error sending notification:", error);
      return null;
    }
  });
// =====================================================
// 6. SEND PUSH NOTIFICATION ON NEW MESSAGE
// =====================================================
exports.sendMessageNotification = functions.firestore
  .document("messages/{conversationId}/{messageId}")
  .onCreate(async (snap, context) => {
    try {
      const messageData = snap.data();
      const {conversationId} = context.params;

      const receiverDoc = await admin
        .firestore()
        .collection("users")
        .doc(messageData.idTo)
        .get();

      if (!receiverDoc.exists) return null;

      const receiverData = receiverDoc.data();
      const pushToken = receiverData.pushToken;

      if (!pushToken) return null;

      const senderDoc = await admin
        .firestore()
        .collection("users")
        .doc(messageData.idFrom)
        .get();

      const senderName = senderDoc.exists ?
        senderDoc.data().nickname :
        "Someone";

      const payload = {
        notification: {
          title: senderName,
          body:
            messageData.type === 0 ? messageData.content : "📷 Sent an image",
          sound: "default",
        },
        data: {
          conversationId: conversationId,
          senderId: messageData.idFrom,
          type: "new_message",
        },
      };

      await admin.messaging().sendToDevice(pushToken, payload);

      console.log(`✅ Notification sent to ${messageData.idTo}`);
      return null;
    } catch (error) {
      console.error("❌ Error sending notification:", error);
      return null;
    }
  });
// =====================================================
// 8. AUTO-DELETE EXPIRED STORIES (Chạy mỗi giờ)
// =====================================================
exports.cleanupExpiredStories = functions.pubsub
  .schedule("every 1 hours")
  .onRun(async (context) => {
    console.log("🧹 Starting story cleanup...");

    try {
      const db = admin.firestore();
      const now = Date.now().toString();

      const expiredStories = await db
        .collection("stories")
        .where("expiresAt", "<=", now)
        .where("isDeleted", "==", false)
        .get();

      if (expiredStories.empty) {
        console.log("No expired stories to clean");
        return null;
      }

      const docs = expiredStories.docs;
      let totalUpdated = 0;

      for (let i = 0; i < docs.length; i += 500) {
        const batch = db.batch();
        const chunk = docs.slice(i, i + 500);

        chunk.forEach((doc) => {
          batch.update(doc.ref, {
            isDeleted: true,
            deletedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        });

        await batch.commit();
        totalUpdated += chunk.length;
      }

      console.log(`✅ Cleaned ${totalUpdated} expired stories`);
      return null;
    } catch (error) {
      console.error("❌ Error cleaning expired stories:", error);
      return null;
    }
  });
// =====================================================
// 9. TRANSLATE COMMUNICATION STYLE (Gemini AI)
// =====================================================
exports.translateCommunication = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Yêu cầu đăng nhập.");
  }

  const {message, targetAudience} = data;

  try {
    const model = genAI.getGenerativeModel({model: "gemini-2.0-flash"});

    let prompt = `Bạn là một AI chuyên dịch phong cách giao tiếp. Hãy viết lại câu sau sao cho phù hợp với đối tượng nhận là: ${targetAudience}. Giữ nguyên ý nghĩa cốt lõi, chỉ thay đổi tone giọng, từ vựng.\n\n`;
    prompt += `Tin nhắn gốc: "${message}"\n`;

    if (targetAudience === "elder") {
      prompt += "Yêu cầu: Văn phong lễ phép, rõ ràng, dễ hiểu, không dùng tiếng lóng hay viết tắt.";
    } else if (targetAudience === "student") {
      prompt += "Yêu cầu: Văn phong trẻ trung, gen Z, casual, có thể dùng từ lóng phổ biến.";
    } else if (targetAudience === "work") {
      prompt += "Yêu cầu: Văn phong chuyên nghiệp, súc tích, lịch sự, tập trung vào công việc.";
    }

    const result = await model.generateContent(prompt);
    const response = await result.response;
    return {translatedText: response.text().trim()};
  } catch (error) {
    console.error("❌ Lỗi khi gọi Gemini AI:", error);
    throw new functions.https.HttpsError("internal", "Lỗi xử lý AI.");
  }
});
// =====================================================
// 10. ANALYZE CHAT CONTEXT (Gemini AI)
// =====================================================
exports.analyzeChatContext = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Yêu cầu đăng nhập.");
  }

  const {messages, contextType, action} = data;

  try {
    const model = genAI.getGenerativeModel({model: "gemini-2.0-flash"});

    let prompt = `Dựa vào đoạn hội thoại sau, hãy thực hiện yêu cầu.\n\nĐoạn hội thoại:\n${messages}\n\n`;

    if (contextType === "work" && action === "extract_tasks") {
      prompt += "Yêu cầu: Liệt kê các công việc (tasks) và deadline được nhắc đến trong hội thoại dưới dạng danh sách ngắn gọn.";
    } else if (contextType === "study" && action === "summarize") {
      prompt += "Yêu cầu: Tóm tắt các kiến thức, bài học chính được trao đổi trong hội thoại.";
    } else {
      prompt += "Yêu cầu: Phân tích và tóm tắt ngắn gọn nội dung chính.";
    }

    const result = await model.generateContent(prompt);
    const response = await result.response;
    return {analysisResult: response.text().trim()};
  } catch (error) {
    console.error("❌ Lỗi khi phân tích Context:", error);
    throw new functions.https.HttpsError("internal", "Lỗi phân tích AI.");
  }
});
// =====================================================
// 11. SCAM DETECTION (Phát hiện lừa đảo bằng AI)
// =====================================================
exports.analyzeScam = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Yêu cầu đăng nhập.");
  }

  const {message} = data;

  try {
    const model = genAI.getGenerativeModel({model: "gemini-2.0-flash"});

    const prompt = `Bạn là một chuyên gia an ninh mạng. Hãy phân tích tin nhắn sau đây xem có dấu hiệu lừa đảo (scam), phishing (link độc hại), mạo danh nhờ chuyển tiền hay tống tiền không.
    Tin nhắn: "${message}"

    Hãy trả về CHỈ MỘT TRONG CÁC TỪ KHÓA SAU (không giải thích thêm):
    - SAFE (nếu tin nhắn hoàn toàn bình thường)
    - WARNING_MONEY (nếu tin nhắn có nhắc đến việc vay mượn, chuyển tiền)
    - WARNING_LINK (nếu tin nhắn chứa đường link không rõ nguồn gốc)
    - DANGER (nếu tin nhắn chắc chắn là lừa đảo, đe dọa)`;

    const result = await model.generateContent(prompt);
    const response = await result.response;
    const text = response.text().trim();

    return {status: text};
  } catch (error) {
    console.error("❌ Lỗi khi phân tích Scam:", error);
    return {status: "ERROR"};
  }
});
