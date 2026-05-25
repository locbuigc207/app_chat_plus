const functions = require("firebase-functions");
const admin = require("firebase-admin");
const {RtcTokenBuilder, RtcRole} = require("agora-access-token");
const cors = require("cors")({origin: true});
const {GoogleGenerativeAI} = require("@google/generative-ai");

admin.initializeApp();

// =====================================================
// ĐỌC BIẾN MÔI TRƯỜNG TỪ FILE .env (BẢO MẬT KEY)
// =====================================================
const GEMINI_API_KEY = process.env.GEMINI_API_KEY;
const AGORA_APP_ID = process.env.AGORA_APP_ID;
const AGORA_APP_CERTIFICATE = process.env.AGORA_APP_CERTIFICATE;

// Kiểm tra cảnh báo nếu thiếu key
if (!GEMINI_API_KEY) {
  console.error("LỖI: Chưa thiết lập GEMINI_API_KEY trong file functions/.env");
}
if (!AGORA_APP_ID || !AGORA_APP_CERTIFICATE) {
  console.error("LỖI: Chưa thiết lập AGORA_APP_ID hoặc AGORA_APP_CERTIFICATE trong file functions/.env");
}

const genAI = new GoogleGenerativeAI(GEMINI_API_KEY);

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
        AGORA_APP_ID,
        AGORA_APP_CERTIFICATE,
        channelName,
        uid,
        role,
        privilegeExpireTime,
      );
      return res.status(200).json({token});
    } catch (error) {
      console.error("❌ Lỗi khi tạo Token:", error);
      return res.status(500).json({error: "Internal Server Error"});
    }
  });
});

// =====================================================
// 2. AUTO-DELETE EXPIRED MESSAGES
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
// 4. CLEANUP TYPING STATUS
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
      }
      return null;
    } catch (error) {
      console.error("❌ Error updating presence:", error);
      return null;
    }
  });

// =====================================================
// 6. SEND PUSH NOTIFICATION (E2EE BLIND TRANSPORT)
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
        data: {
          conversationId: conversationId,
          senderId: messageData.idFrom,
          senderName: senderName,
          type: "new_message",

          encryptedContent:
            messageData.type === 0 ?
              messageData.content :
              "[Hình ảnh/Tệp đính kèm]",
        },
      };

      await admin.messaging().sendToDevice(pushToken, payload);
      return null;
    } catch (error) {
      console.error("❌ Error sending notification:", error);
      return null;
    }
  });

// =====================================================
// 7. AUTO-DELETE EXPIRED STORIES
// =====================================================
exports.cleanupExpiredStories = functions.pubsub
  .schedule("every 1 hours")
  .onRun(async (context) => {
    try {
      const db = admin.firestore();
      const now = Date.now().toString();

      const expiredStories = await db
        .collection("stories")
        .where("expiresAt", "<=", now)
        .where("isDeleted", "==", false)
        .get();

      if (expiredStories.empty) return null;

      const docs = expiredStories.docs;

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
      }
      return null;
    } catch (error) {
      console.error("❌ Error cleaning expired stories:", error);
      return null;
    }
  });

// =====================================================
// 8. TRANSLATE COMMUNICATION STYLE
// =====================================================
exports.translateCommunication = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Yêu cầu đăng nhập.");

  const {message, targetAudience} = data;
  try {
    const model = genAI.getGenerativeModel({model: "gemini-2.0-flash"});
    let prompt = `Bạn là một AI chuyên dịch phong cách giao tiếp. Hãy viết lại câu sau sao cho phù hợp với đối tượng nhận là: ${targetAudience}. Giữ nguyên ý nghĩa cốt lõi, chỉ thay đổi tone giọng, từ vựng.\n\nTin nhắn gốc: "${message}"\n`;

    if (targetAudience === "elder") prompt += "Yêu cầu: Lễ phép, rõ ràng.";
    else if (targetAudience === "student") prompt += "Yêu cầu: Trẻ trung, gen Z, casual.";
    else if (targetAudience === "work") prompt += "Yêu cầu: Chuyên nghiệp, súc tích.";

    const result = await model.generateContent(prompt);
    const response = await result.response;
    return {translatedText: response.text().trim()};
  } catch (error) {
    console.error("❌ Lỗi AI Translation:", error);
    throw new functions.https.HttpsError("internal", "Lỗi xử lý AI.");
  }
});

// =====================================================
// 9. ANALYZE CHAT CONTEXT
// =====================================================
exports.analyzeChatContext = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Yêu cầu đăng nhập.");
  const {messages, contextType, action} = data;

  try {
    const model = genAI.getGenerativeModel({model: "gemini-2.0-flash"});
    let prompt = `Dựa vào đoạn hội thoại sau, hãy thực hiện yêu cầu.\n\nĐoạn hội thoại:\n${messages}\n\n`;

    if (contextType === "work" && action === "extract_tasks") prompt += "Yêu cầu: Liệt kê công việc (tasks) và deadline ngắn gọn.";
    else if (contextType === "study" && action === "summarize") prompt += "Yêu cầu: Tóm tắt kiến thức, bài học.";
    else prompt += "Yêu cầu: Phân tích và tóm tắt ngắn gọn.";

    const result = await model.generateContent(prompt);
    const response = await result.response;
    return {analysisResult: response.text().trim()};
  } catch (error) {
    console.error("❌ Lỗi AI Chat Context:", error);
    throw new functions.https.HttpsError("internal", "Lỗi phân tích AI.");
  }
});

// =====================================================
// 10. SCAM DETECTION (Chạy Manual từ Client)
// =====================================================
exports.analyzeScam = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Yêu cầu đăng nhập.");
  const {message} = data;

  try {
    const model = genAI.getGenerativeModel({model: "gemini-2.0-flash"});
    const prompt = `Phân tích tin nhắn sau xem có dấu hiệu lừa đảo, phishing, mạo danh nhờ chuyển tiền không.\nTin nhắn: "${message}"\nTrả về 1 trong các từ khóa: SAFE, WARNING_MONEY, WARNING_LINK, DANGER`;

    const result = await model.generateContent(prompt);
    const response = await result.response;
    return {status: response.text().trim()};
  } catch (error) {
    return {status: "ERROR"};
  }
});

// =====================================================
// 11. EXTRACT RELATIONSHIP MEMORY
// =====================================================
exports.extractRelationshipMemory = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Yêu cầu đăng nhập.");
  const {messages} = data;

  try {
    const model = genAI.getGenerativeModel({model: "gemini-2.0-flash"});
    const prompt = `Trích xuất "Kỷ niệm", "Sở thích", "Lời hứa", và đánh giá "Điểm số quan hệ" (0-100) từ đoạn chat: ${messages}. Trả về JSON chuẩn: {"healthScore": 85, "summary": "...", "memories": [{"category": "preference", "content": "..."}]}`;

    const result = await model.generateContent(prompt);
    let text = result.response.text().trim().replace(/^```json/g, "").replace(/^```/g, "").replace(/```$/g, "").trim();
    return JSON.parse(text);
  } catch (error) {
    throw new functions.https.HttpsError("internal", "Lỗi phân tích AI.");
  }
});

// =====================================================
// 12. CLIENT-DRIVEN SECURE AI ANALYZER (Đảm bảo E2EE)
// =====================================================
exports.analyzeDecryptedClientMessage = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Yêu cầu đăng nhập hợp lệ.");
  }

  const {plainTextContent, conversationId, messageId, idTo} = data;

  try {
    const model = genAI.getGenerativeModel({model: "gemini-2.0-flash"});

    const prompt = `Phân tích tin nhắn sau: "${plainTextContent}".
    Trả về kết quả DƯỚI DẠNG JSON chuẩn (chỉ JSON, không markdown, không giải thích):
    {
      "isScam": boolean,
      "scamReason": "lý do ngắn gọn nếu có dấu hiệu lừa đảo",
      "hasReminder": boolean,
      "reminderTask": "nội dung công việc",
      "reminderTime": "thời gian"
    }`;

    const result = await model.generateContent(prompt);
    let text = result.response.text().trim().replace(/^```json/g, "").replace(/```$/g, "").trim();
    const analysis = JSON.parse(text);
    const db = admin.firestore();

    if (analysis.isScam) {
      await db.collection("messages").doc(conversationId).collection(conversationId).doc(messageId).update({
        scamWarning: true,
        scamReason: analysis.scamReason,
      });
      console.log(`🚨 Phát hiện rủi ro trong E2EE message: ${messageId}`);
    }

    if (analysis.hasReminder) {
      await db.collection("reminders").add({
        userId: idTo,
        conversationId: conversationId,
        messageId: messageId,
        task: analysis.reminderTask,
        timeHint: analysis.reminderTime,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        isCompleted: false,
        isAutoGenerated: true,
      });
    }

    return analysis;
  } catch (error) {
    console.error("❌ Lỗi xử lý AI từ Client:", error);
    return null;
  }
});

// =====================================================
// 13. ADVANCED CALL SECURITY ANALYZER
// =====================================================
exports.analyzeCallSecurity = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Yêu cầu đăng nhập.");
  const {callTranscript, peerId, conversationId} = data;

  try {
    const model = genAI.getGenerativeModel({model: "gemini-2.0-flash"});
    const prompt = `Phân tích hội thoại gọi điện tìm dấu hiệu lừa đảo, tống tiền, Deepfake.\nHội thoại: "${callTranscript}"\nTrả về JSON: {"isSafe": boolean, "riskLevel": "LOW" | "MEDIUM" | "HIGH", "warningMessage": "Cảnh báo", "confidenceScore": 0-100}`;

    const result = await model.generateContent(prompt);
    let text = result.response.text().trim().replace(/^```json/g, "").replace(/^```/g, "").replace(/```$/g, "").trim();
    const analysis = JSON.parse(text);

    if (!analysis.isSafe || analysis.riskLevel === "HIGH") {
      await admin.firestore().collection("security_alerts").add({
        reporterId: context.auth.uid,
        suspectId: peerId,
        conversationId: conversationId || "unknown",
        transcriptSnippet: callTranscript,
        analysisResult: analysis,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    return analysis;
  } catch (error) {
    return {isSafe: true, riskLevel: "LOW", warningMessage: "", confidenceScore: 0};
  }
});

// =====================================================
// 14. AI WEEKLY RECAP (GIAI ĐOẠN 3: BÓC PHỐT TUẦN)
// =====================================================
exports.weeklyAiRecap = functions.pubsub
  .schedule("every sunday 20:00")
  .timeZone("Asia/Ho_Chi_Minh")
  .onRun(async (context) => {
    console.log("🔥 Bắt đầu chạy Recap Tuần...");
    const db = admin.firestore();

    try {
      const groupsSnapshot = await db
        .collection("conversations")
        .where("isGroup", "==", true)
        .get();

      // Lấy thời gian 7 ngày trước (tính bằng milliseconds)
      const sevenDaysAgo = Date.now() - 7 * 24 * 60 * 60 * 1000;

      for (const groupDoc of groupsSnapshot.docs) {
        const groupId = groupDoc.id;

        // Truy vấn tin nhắn trong 7 ngày qua
        const msgsSnapshot = await db
          .collection("messages")
          .doc(groupId)
          .collection(groupId)
          .where("timestamp", ">=", sevenDaysAgo.toString())
          .orderBy("timestamp", "asc")
          .limit(200) // Giới hạn số lượng để tránh quá tải Token
          .get();

        if (msgsSnapshot.empty) continue;

        let chatHistory = "";
        msgsSnapshot.forEach((doc) => {
          const data = doc.data();
          if (data.type === 0) { // Chỉ lấy tin nhắn dạng Text
            chatHistory += `User ${data.idFrom}: ${data.content}\n`;
          }
        });

        if (chatHistory.trim() === "") continue;

        // Gọi Gemini API
        const model = genAI.getGenerativeModel({model: "gemini-2.0-flash"});
        const prompt = `Dưới đây là lịch sử chat nhóm trong tuần qua. Hãy đóng vai một MC vui nhộn, viết một bản tin "Bóc phốt tuần" siêu ngắn (dưới 150 chữ), hài hước, chỉ ra ai nói nhiều nhất, câu nói ấn tượng hoặc trend hài hước nhất. Lịch sử:\n${chatHistory}`;

        const result = await model.generateContent(prompt);
        const recapText = "🔥 BẢN TIN BÓC PHỐT TUẦN 🔥\n\n" + result.response.text();

        // Push tin nhắn Recap vào nhóm với tư cách AI_BOT
        const messageId = Date.now().toString();
        await db
          .collection("messages")
          .doc(groupId)
          .collection(groupId)
          .doc(messageId)
          .set({
            idFrom: "AI_BOT",
            idTo: groupId,
            timestamp: messageId,
            content: recapText,
            type: 0,
            status: "sent",
          });

        // Cập nhật cuộc hội thoại hiển thị Last Message
        await groupDoc.ref.update({
          lastMessage: recapText,
          lastMessageTime: messageId,
          lastMessageType: 0,
        });
      }
      console.log("✅ Hoàn thành Recap Tuần.");
      return null;
    } catch (error) {
      console.error("❌ Lỗi AI Weekly Recap:", error);
      return null;
    }
  });
