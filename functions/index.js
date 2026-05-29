/**
 * ╔══════════════════════════════════════════════════════════════════════════╗
 * ║          Firebase Cloud Functions — AI & Chat Backend v2               ║
 * ║          Runtime: Node.js 20  |  Region: asia-southeast1               ║
 * ╠══════════════════════════════════════════════════════════════════════════╣
 * ║  HTTPS Callable (onCall v2):                                            ║
 * ║   1.  analyzeDecryptedMessage        — Scam detection (E2EE pipeline)   ║
 * ║   2.  analyzeScam                    — Quick scam check                ║
 * ║   3.  analyzeDecryptedClientMessage  — Full AI + reminder extraction    ║
 * ║   4.  translateCommunication         — Audience-aware translation       ║
 * ║   5.  analyzeChatContext             — Summarise / suggest / tasks      ║
 * ║   6.  extractRelationshipMemory      — Relationship memory extraction   ║
 * ║   7.  suggestReplies                 — Smart reply suggestions          ║
 * ║   8.  generateSwipeReplies           — 4 Gen-Z swipe replies            ║
 * ║   9.  generateAutoPilotReply         — Digital-twin auto-reply          ║
 * ║  10.  summarizeConversation          — Conversation summary             ║
 * ║  11.  analyzeSentiment               — Sentiment analysis               ║
 * ║  12.  detectHateSpeech               — Hate-speech / toxicity detection ║
 * ║  13.  analyzeCallSecurity            — Deepfake / scam call analysis    ║
 * ║  14.  requestCallToken               — Callable wrapper for Agora token ║
 * ║  15.  smartReplyWithContext          — Context-aware AI reply composer  ║
 * ║  16.  generateIcebreakers            — Conversation starter suggestions ║
 * ║  17.  analyzeToxicityBatch           — Batch toxicity analysis          ║
 * ║  18.  generateMessageTone            — Tone rewrite (formal/casual/etc) ║
 * ║  19.  extractKeyMoments              — Extract highlights from chat     ║
 * ║  20.  getUserInsights                — Per-user behavioral AI insights  ║
 * ║                                                                          ║
 * ║  HTTPS Request (onRequest):                                             ║
 * ║  21.  generateAgoraToken             — Agora RTC token (REST)           ║
 * ║  22.  healthCheck                    — Service health endpoint          ║
 * ║                                                                          ║
 * ║  Firestore Triggers:                                                    ║
 * ║  23.  scheduleMessageDeletion        — Auto-delete scheduling           ║
 * ║  24.  sendMessageNotification        — Push notification (E2EE blind)   ║
 * ║  25.  updateUserPresence             — lastSeen on go-offline           ║
 * ║  26.  onCallCreated                  — Push ring notification           ║
 * ║  27.  onCallUpdated                  — Push call-status notification    ║
 * ║                                                                          ║
 * ║  Scheduled (pubsub):                                                    ║
 * ║  28.  cleanupExpiredMessages         — Purge expired msgs (5 min)       ║
 * ║  29.  cleanupTypingStatus            — Purge stale typing (1 min)       ║
 * ║  30.  cleanupExpiredStories          — Purge expired stories (1 hr)     ║
 * ║  31.  cleanupStaleCalls              — Purge stale calls (5 min)        ║
 * ║  32.  weeklyAiRecap                  — Weekly AI recap (Sun 20:00 ICT)  ║
 * ║  33.  dailyConversationDigest        — Daily summary (Mon-Fri 08:00)    ║
 * ╚══════════════════════════════════════════════════════════════════════════╝
 */

"use strict";

// ─── Firebase Functions v2 ────────────────────────────────────────────────────
const {
  onCall,
  onRequest,
  HttpsError,
}                           = require("firebase-functions/v2/https");
const {
  onDocumentCreated,
  onDocumentUpdated,
}                           = require("firebase-functions/v2/firestore");
const {onSchedule}          = require("firebase-functions/v2/scheduler");
const {setGlobalOptions}    = require("firebase-functions/v2");
const {defineSecret}        = require("firebase-functions/params");
const logger                = require("firebase-functions/logger");

// ─── Firebase Admin ───────────────────────────────────────────────────────────
const {initializeApp}                  = require("firebase-admin/app");
const {getFirestore, FieldValue}       = require("firebase-admin/firestore");
const {getMessaging}                   = require("firebase-admin/messaging");

// ─── Third-party ──────────────────────────────────────────────────────────────
const {
  GoogleGenerativeAI,
  HarmCategory,
  HarmBlockThreshold,
}                           = require("@google/generative-ai");
const {RtcTokenBuilder, RtcRole} = require("agora-access-token");
const cors                  = require("cors")({origin: true});

// ─── Init ─────────────────────────────────────────────────────────────────────
initializeApp();
const db = getFirestore();

setGlobalOptions({
  region:         "asia-southeast1",
  maxInstances:   30,
  memory:         "256MiB",
  timeoutSeconds: 60,
  concurrency:    80,
});

// ─── Secrets ──────────────────────────────────────────────────────────────────
const geminiApiKey     = defineSecret("GEMINI_API_KEY");
const agoraAppId       = defineSecret("AGORA_APP_ID");
const agoraCertificate = defineSecret("AGORA_APP_CERTIFICATE");

// ═════════════════════════════════════════════════════════════════════════════
// CONSTANTS
// ═════════════════════════════════════════════════════════════════════════════

const MODEL_ID             = "gemini-2.0-flash";
const MODEL_FLASH_LITE     = "gemini-2.0-flash-lite"; // for cheap/fast ops
const MAX_INPUT_LENGTH     = 4000;
const MAX_HISTORY_MSGS     = 20;
const AGORA_TOKEN_TTL_SEC  = 3600;
const CALL_STALE_SEC       = 90;

const ACTIVE_CALL_STATUSES = ["calling", "ringing", "dialing", "connected", "accepted"];

// Rate limiting: max calls per user per minute (tracked in Firestore)
const RATE_LIMIT_AI_CALLS_PER_MIN = 20;

const SCAM_KEYWORDS_VI = [
  "chuyển tiền", "tài khoản ngân hàng", "mã otp", "trúng thưởng",
  "đầu tư sinh lời", "lãi suất cao", "nhận tiền", "phí xử lý",
  "công an", "tòa án", "bắt giữ", "nộp tiền bảo lãnh", "cài app",
  "truy cập link", "xác minh danh tính", "gấp", "khẩn cấp",
  "chuyển khoản ngay", "tài khoản bị khóa", "vi phạm pháp luật",
  "hỗ trợ kỹ thuật", "cập nhật thông tin", "miễn phí hoàn toàn",
  "crypto", "bitcoin", "đầu tư crypto", "ví điện tử lạ",
];

const HATE_KEYWORDS_VI = [
  "chết đi", "mày chết", "tao giết", "đồ ngu", "đồ điên",
  "thằng khùng", "con điên", "đồ khốn", "tao ghét mày",
];

// In-memory cache for short-lived results (cleared on cold start)
const _analysisCache = new Map();
const CACHE_TTL_MS = 30_000; // 30 seconds

// ═════════════════════════════════════════════════════════════════════════════
// SHARED HELPERS
// ═════════════════════════════════════════════════════════════════════════════

function requireAuth(auth) {
  if (!auth) throw new HttpsError("unauthenticated", "Yêu cầu đăng nhập.");
}

function sanitize(text, maxLen = MAX_INPUT_LENGTH) {
  if (typeof text !== "string") return "";
  return text.trim().substring(0, maxLen);
}

function sanitizeMessages(messages) {
  if (!Array.isArray(messages)) return [];
  return messages
    .map((m) => sanitize(String(m ?? "")))
    .filter((m) => m.length > 0)
    .slice(0, MAX_HISTORY_MSGS);
}

function safeParseJson(text) {
  try {
    const clean = text
      .replace(/```json\s*/gi, "")
      .replace(/```\s*/g, "")
      .trim();
    return JSON.parse(clean);
  } catch {
    return null;
  }
}

/** Simple in-memory cache with TTL */
function getCached(key) {
  const entry = _analysisCache.get(key);
  if (!entry) return null;
  if (Date.now() - entry.ts > CACHE_TTL_MS) {
    _analysisCache.delete(key);
    return null;
  }
  return entry.value;
}

function setCached(key, value) {
  _analysisCache.set(key, {value, ts: Date.now()});
  // Evict oldest entries if cache grows too large
  if (_analysisCache.size > 500) {
    const firstKey = _analysisCache.keys().next().value;
    _analysisCache.delete(firstKey);
  }
}

/** Per-user rate limiter using Firestore counter (sliding 1-minute window) */
async function checkRateLimit(uid, action) {
  const ref = db.collection("_rate_limits").doc(`${uid}_${action}`);
  const now = Date.now();
  const windowStart = now - 60_000;

  try {
    await db.runTransaction(async (tx) => {
      const doc = await tx.get(ref);
      if (!doc.exists) {
        tx.set(ref, {calls: [{ts: now}], updatedAt: now});
        return;
      }
      const data = doc.data();
      const recent = (data.calls || []).filter((c) => c.ts > windowStart);
      if (recent.length >= RATE_LIMIT_AI_CALLS_PER_MIN) {
        throw new HttpsError(
          "resource-exhausted",
          `Quá nhiều yêu cầu. Vui lòng chờ 1 phút. (${action})`,
        );
      }
      recent.push({ts: now});
      tx.update(ref, {calls: recent, updatedAt: now});
    });
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    // If rate limit check itself fails, log but allow through
    logger.warn("[checkRateLimit] Transient error:", err);
  }
}

async function callGeminiWithRetry(model, prompt, maxRetries = 2) {
  let lastError;
  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      const result = await model.generateContent(prompt);
      return result.response.text();
    } catch (err) {
      lastError = err;
      const isRateLimit =
        err.status === 429 ||
        String(err).toLowerCase().includes("quota") ||
        String(err).toLowerCase().includes("rate_limit");
      if (isRateLimit && attempt < maxRetries) {
        const delay = 1000 * Math.pow(2, attempt + 1);
        logger.warn(`Rate limited — retry ${attempt + 1} after ${delay}ms`);
        await new Promise((r) => setTimeout(r, delay));
        continue;
      }
      throw err;
    }
  }
  throw lastError;
}

function quickScamCheck(text) {
  const lower = text.toLowerCase();
  const hits  = SCAM_KEYWORDS_VI.filter((kw) => lower.includes(kw));
  return {hasKeywords: hits.length > 0, keywords: hits};
}

function quickHateCheck(text) {
  const lower = text.toLowerCase();
  return HATE_KEYWORDS_VI.some((kw) => lower.includes(kw));
}

async function saveAnalysisResult(conversationId, messageId, data) {
  if (!conversationId || !messageId) return;
  try {
    await db
      .collection("conversations")
      .doc(conversationId)
      .collection("ai_analysis")
      .doc(messageId)
      .set({...data, analyzedAt: FieldValue.serverTimestamp()}, {merge: true});
  } catch (err) {
    logger.warn("[saveAnalysisResult] Firestore error:", err);
  }
}

function createGeminiModel(apiKey, systemPrompt, genConfig = {}, lite = false) {
  const genAI  = new GoogleGenerativeAI(apiKey);
  const modelId = lite ? MODEL_FLASH_LITE : MODEL_ID;
  return genAI.getGenerativeModel({
    model: modelId,
    systemInstruction: systemPrompt,
    generationConfig: {
      maxOutputTokens: 1024,
      temperature:     0.5,
      ...genConfig,
    },
    safetySettings: [
      {category: HarmCategory.HARM_CATEGORY_HARASSMENT,        threshold: HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE},
      {category: HarmCategory.HARM_CATEGORY_HATE_SPEECH,       threshold: HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE},
      {category: HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT, threshold: HarmBlockThreshold.BLOCK_HIGH_AND_ABOVE},
      {category: HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT, threshold: HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE},
    ],
  });
}

async function batchUpdate(docs, updateFn) {
  for (let i = 0; i < docs.length; i += 500) {
    const batch = db.batch();
    docs.slice(i, i + 500).forEach((doc) => updateFn(batch, doc));
    await batch.commit();
  }
}

function buildAgoraToken(channelName, uid, appId, appCert) {
  const expiresAt = Math.floor(Date.now() / 1000) + AGORA_TOKEN_TTL_SEC;
  const token     = RtcTokenBuilder.buildTokenWithUid(
    appId, appCert, channelName, uid, RtcRole.PUBLISHER, expiresAt,
  );
  return {token, expiresAt};
}

async function sendPushNotification({pushToken, title, body, data = {}}) {
  if (!pushToken) return;
  try {
    await getMessaging().send({
      token:   pushToken,
      notification: {title, body},
      data:    Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)])),
      android: {priority: "high", notification: {channelId: "chat_messages"}},
      apns:    {
        payload: {aps: {contentAvailable: true, sound: "default", badge: 1}},
        headers: {"apns-priority": "10"},
      },
    });
  } catch (err) {
    // Token may be stale — log but don't throw
    logger.warn("[sendPushNotification]", err?.errorInfo?.code ?? err);
  }
}

/** Fetch user push token safely */
async function getUserPushToken(userId) {
  if (!userId) return null;
  try {
    const snap = await db.collection("users").doc(userId).get();
    return snap.exists ? (snap.data()?.pushToken ?? null) : null;
  } catch {
    return null;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 1. analyzeDecryptedMessage
// ═════════════════════════════════════════════════════════════════════════════

exports.analyzeDecryptedMessage = onCall(
  {secrets: [geminiApiKey], enforceAppCheck: false},
  async (request) => {
    requireAuth(request.auth);
    const {plainText, conversationId, messageId, idFrom, idTo} = request.data;
    if (!plainText || !conversationId || !messageId) {
      throw new HttpsError("invalid-argument", "Thiếu plainText, conversationId hoặc messageId.");
    }

    const safeText = sanitize(plainText);
    if (!safeText) return {status: "SAFE", level: "SAFE"};

    // Check in-memory cache
    const cacheKey = `scam_${Buffer.from(safeText).toString("base64").substring(0, 32)}`;
    const cached = getCached(cacheKey);
    if (cached) return cached;

    const quick = quickScamCheck(safeText);
    if (!quick.hasKeywords && safeText.length < 50) {
      const result = {status: "SAFE", level: "SAFE", method: "fast"};
      await saveAnalysisResult(conversationId, messageId, {
        level: "SAFE", method: "keyword_fast", idFrom, idTo,
      });
      setCached(cacheKey, result);
      return result;
    }

    try {
      const model  = createGeminiModel(
        geminiApiKey.value(),
        "Bạn là chuyên gia phát hiện lừa đảo trực tuyến tại Việt Nam. Phân tích chính xác, trả về JSON hợp lệ.",
        {maxOutputTokens: 512, temperature: 0.1},
        true,
      );
      const raw    = await callGeminiWithRetry(model,
        `Phân tích tin nhắn sau có dấu hiệu lừa đảo/scam không.\n` +
        `Trả về JSON: {"level":"SAFE"|"WARNING"|"SCAM","reason":"...","confidence":0.0-1.0}\n\n` +
        `Tin nhắn: "${safeText}"`,
      );
      const parsed     = safeParseJson(raw);
      const level      = parsed?.level      ?? (quick.hasKeywords ? "WARNING" : "SAFE");
      const reason     = parsed?.reason     ?? null;
      const confidence = parsed?.confidence ?? null;

      await saveAnalysisResult(conversationId, messageId, {
        level, reason, confidence, method: "gemini",
        idFrom, idTo, scamKeywords: quick.keywords,
      });
      const result = {status: level, level, reason, confidence};
      setCached(cacheKey, result);
      return result;
    } catch (err) {
      logger.error("[analyzeDecryptedMessage]", err);
      const fallback = quick.hasKeywords ? "WARNING" : "SAFE";
      return {status: fallback, level: fallback, method: "fallback"};
    }
  },
);

// ═════════════════════════════════════════════════════════════════════════════
// 2. analyzeScam
// ═════════════════════════════════════════════════════════════════════════════

exports.analyzeScam = onCall(
  {secrets: [geminiApiKey], enforceAppCheck: false},
  async (request) => {
    requireAuth(request.auth);
    const {message} = request.data;
    if (!message) throw new HttpsError("invalid-argument", "Thiếu message.");

    const safeMsg = sanitize(message);
    if (!safeMsg) return {status: "SAFE", level: "SAFE"};
    const quick = quickScamCheck(safeMsg);

    // Short-circuit if no keywords and short message
    if (!quick.hasKeywords && safeMsg.length < 30) {
      return {status: "SAFE", level: "SAFE", warningKeywords: []};
    }

    try {
      const model  = createGeminiModel(
        geminiApiKey.value(),
        "Chuyên gia phát hiện lừa đảo. Trả về JSON hợp lệ.",
        {maxOutputTokens: 256, temperature: 0.1},
        true,
      );
      const raw    = await callGeminiWithRetry(model,
        `Tin nhắn: "${safeMsg}"\nTrả về JSON: {"level":"SAFE"|"WARNING"|"SCAM","reason":"...","confidence":0.0-1.0}`,
      );
      const parsed = safeParseJson(raw);
      return {
        status:          parsed?.level      ?? "SAFE",
        level:           parsed?.level      ?? "SAFE",
        reason:          parsed?.reason     ?? null,
        confidence:      parsed?.confidence ?? null,
        warningKeywords: quick.keywords,
      };
    } catch (err) {
      logger.error("[analyzeScam]", err);
      return {
        status:          quick.hasKeywords ? "WARNING" : "SAFE",
        level:           quick.hasKeywords ? "WARNING" : "SAFE",
        warningKeywords: quick.keywords,
        method:          "fallback",
      };
    }
  },
);

// ═════════════════════════════════════════════════════════════════════════════
// 3. analyzeDecryptedClientMessage
// ═════════════════════════════════════════════════════════════════════════════

exports.analyzeDecryptedClientMessage = onCall(
  {secrets: [geminiApiKey], enforceAppCheck: false},
  async (request) => {
    requireAuth(request.auth);
    const {plainTextContent, conversationId, messageId, idTo} = request.data;
    if (!plainTextContent) return null;

    const safeText = sanitize(plainTextContent);
    try {
      const model    = createGeminiModel(
        geminiApiKey.value(),
        "Bạn là AI phân tích tin nhắn chat. Trả về JSON hợp lệ, không giải thích.",
        {maxOutputTokens: 512, temperature: 0.2},
      );
      const raw      = await callGeminiWithRetry(model,
        `Phân tích tin nhắn: "${safeText}".\n` +
        `Trả về JSON (chỉ JSON):\n` +
        `{"isScam":bool,"scamReason":"...","hasReminder":bool,"reminderTask":"...","reminderTime":"...","riskLevel":"LOW"|"MEDIUM"|"HIGH","sentiment":"positive"|"neutral"|"negative","intentCategory":"question"|"request"|"statement"|"greeting"|"farewell"|"unknown"}`,
      );
      const analysis = safeParseJson(raw);
      if (!analysis) return null;

      const batch = db.batch();

      if (analysis.isScam && conversationId && messageId) {
        const msgRef = db
          .collection("messages").doc(conversationId)
          .collection(conversationId).doc(messageId);
        batch.update(msgRef, {
          scamWarning: true,
          scamReason:  analysis.scamReason ?? "",
          riskLevel:   analysis.riskLevel  ?? "MEDIUM",
        });
        logger.warn(`[analyzeDecryptedClientMessage] Scam in ${messageId}`);
      }

      if (analysis.hasReminder && idTo) {
        const reminderRef = db.collection("reminders").doc();
        batch.set(reminderRef, {
          userId:          idTo,
          conversationId:  conversationId ?? null,
          messageId:       messageId      ?? null,
          task:            analysis.reminderTask  ?? "",
          timeHint:        analysis.reminderTime  ?? "",
          createdAt:       FieldValue.serverTimestamp(),
          isCompleted:     false,
          isAutoGenerated: true,
        });
      }

      await batch.commit();
      return analysis;
    } catch (err) {
      logger.error("[analyzeDecryptedClientMessage]", err);
      return null;
    }
  },
);

// ═════════════════════════════════════════════════════════════════════════════
// 4. translateCommunication
// ═════════════════════════════════════════════════════════════════════════════

exports.translateCommunication = onCall(
  {secrets: [geminiApiKey]},
  async (request) => {
    requireAuth(request.auth);
    await checkRateLimit(request.auth.uid, "translate");

    const {message, targetAudience, preserveEmoji = true} = request.data;
    if (!message || !targetAudience) {
      throw new HttpsError("invalid-argument", "Thiếu message hoặc targetAudience.");
    }
    const audienceDesc = {
      elder:   "người cao tuổi (ngôn ngữ đơn giản, kính trọng, không dùng tiếng lóng, câu ngắn rõ ràng)",
      student: "học sinh/sinh viên (trẻ trung, thân thiện, năng động, Gen Z, có thể dùng emoji)",
      work:    "môi trường công việc (chuyên nghiệp, lịch sự, súc tích, không emoji quá nhiều)",
      child:   "trẻ em (đơn giản, vui vẻ, tích cực, dễ hiểu, dùng từ đơn)",
      formal:  "văn bản chính thức (kính ngữ đầy đủ, không viết tắt, trang trọng)",
    }[targetAudience] ?? targetAudience;

    const model = createGeminiModel(
      geminiApiKey.value(),
      "Chuyên gia ngôn ngữ và giao tiếp Việt Nam.",
      {maxOutputTokens: 1024, temperature: 0.5},
    );
    try {
      const emojiNote = preserveEmoji ? "Giữ nguyên emoji nếu có." : "Bỏ emoji.";
      const translated = await callGeminiWithRetry(model,
        `Diễn giải lại tin nhắn sau phù hợp với ${audienceDesc}. ${emojiNote}\n` +
        `Chỉ trả về nội dung đã diễn giải, không giải thích thêm.\n\n` +
        `Tin nhắn gốc: "${sanitize(message)}"`,
      );
      return {
        translatedText:  translated.trim(),
        targetAudience,
        originalLength:  message.length,
        translatedLength: translated.trim().length,
      };
    } catch (err) {
      logger.error("[translateCommunication]", err);
      throw new HttpsError("internal", "Không thể dịch tin nhắn.");
    }
  },
);

// ═════════════════════════════════════════════════════════════════════════════
// 5. analyzeChatContext
// ═════════════════════════════════════════════════════════════════════════════

exports.analyzeChatContext = onCall(
  {secrets: [geminiApiKey]},
  async (request) => {
    requireAuth(request.auth);
    await checkRateLimit(request.auth.uid, "analyze_context");

    const {messages, contextType, action} = request.data;
    if (!messages || !contextType || !action) {
      throw new HttpsError("invalid-argument", "Thiếu messages, contextType hoặc action.");
    }
    const clean = sanitizeMessages(messages);
    if (clean.length === 0) return {analysisResult: ""};

    const actionPrompts = {
      summarize:     "Tóm tắt cuộc trò chuyện trong 3 câu ngắn gọn bằng tiếng Việt:",
      suggest:       "Gợi ý 3 hành động tiếp theo phù hợp dựa trên nội dung trò chuyện:",
      extract_tasks: "Liệt kê công việc (tasks) và deadline ngắn gọn từ cuộc trò chuyện theo định dạng JSON: [{\"task\":\"...\",\"deadline\":\"...\",\"priority\":\"high|medium|low\"}]",
      analyze_mood:  "Phân tích tâm trạng/cảm xúc tổng thể và xu hướng của cuộc trò chuyện:",
      key_decisions: "Liệt kê các quyết định quan trọng được đưa ra trong cuộc trò chuyện:",
      action_items:  "Liệt kê các việc cần làm sau cuộc trò chuyện này:",
    };
    const contextHints = {
      study: "Đây là cuộc trò chuyện học tập/giáo dục.",
      work:  "Đây là cuộc trò chuyện công việc/kinh doanh.",
      elder: "Đây là cuộc trò chuyện với người cao tuổi.",
      family: "Đây là cuộc trò chuyện gia đình.",
      friends: "Đây là cuộc trò chuyện bạn bè.",
    };
    const actionPrompt = actionPrompts[action]     ?? `Thực hiện tác vụ "${action}" trên cuộc trò chuyện:`;
    const contextHint  = contextHints[contextType] ?? "";

    const model = createGeminiModel(
      geminiApiKey.value(),
      `Bạn là AI phân tích cuộc trò chuyện tiếng Việt. ${contextHint}`,
      {maxOutputTokens: 1024, temperature: 0.4},
    );
    try {
      const result = await callGeminiWithRetry(model, `${actionPrompt}\n\n${clean.join("\n")}`);
      return {analysisResult: result.trim(), action, contextType};
    } catch (err) {
      logger.error("[analyzeChatContext]", err);
      throw new HttpsError("internal", "Không thể phân tích ngữ cảnh.");
    }
  },
);

// ═════════════════════════════════════════════════════════════════════════════
// 6. extractRelationshipMemory
// ═════════════════════════════════════════════════════════════════════════════

exports.extractRelationshipMemory = onCall(
  {secrets: [geminiApiKey]},
  async (request) => {
    requireAuth(request.auth);
    const {messages, conversationId} = request.data;
    const clean = sanitizeMessages(messages);
    if (clean.length < 3) {
      return {relationshipType: "unknown", sharedTopics: [], importantDates: []};
    }
    const model  = createGeminiModel(
      geminiApiKey.value(),
      "Chuyên gia phân tích mối quan hệ và ngữ cảnh xã hội Việt Nam.",
      {maxOutputTokens: 768, temperature: 0.3},
    );
    const prompt =
      `Phân tích cuộc trò chuyện và trích xuất thông tin quan hệ.\n` +
      `Trả về JSON:\n` +
      `{"relationshipType":"friend"|"family"|"colleague"|"romantic"|"unknown",` +
      `"sharedTopics":[],"importantDates":[],"memories":[{"category":"...","content":"..."}],` +
      `"communicationStyle":"formal"|"casual"|"mixed","closenessLevel":1-5,` +
      `"healthScore":0-100,"summary":"...","redFlags":[],"positiveSignals":[]}\n\nCuộc trò chuyện:\n${clean.join("\n")}`;
    try {
      const raw    = await callGeminiWithRetry(model, prompt);
      const parsed = safeParseJson(raw);
      if (conversationId && parsed) {
        await db.collection("conversations").doc(conversationId).set(
          {relationshipMemory: {...parsed, updatedAt: FieldValue.serverTimestamp()}},
          {merge: true},
        );
      }
      return parsed ?? {relationshipType: "unknown", sharedTopics: [], importantDates: []};
    } catch (err) {
      logger.error("[extractRelationshipMemory]", err);
      return {relationshipType: "unknown", sharedTopics: [], importantDates: []};
    }
  },
);

// ═════════════════════════════════════════════════════════════════════════════
// 7. suggestReplies
// ═════════════════════════════════════════════════════════════════════════════

exports.suggestReplies = onCall(
  {secrets: [geminiApiKey]},
  async (request) => {
    requireAuth(request.auth);
    const {messages, tone = "friendly", count = 3, userContext = ""} = request.data;
    const clean = sanitizeMessages(messages);
    if (clean.length === 0) return {suggestions: []};

    const toneDesc = {
      friendly:     "thân thiện, tự nhiên, ấm áp",
      formal:       "lịch sự, trang trọng, chuyên nghiệp",
      casual:       "vui vẻ, hài hước, Gen Z",
      empathetic:   "đồng cảm, chia sẻ, ủng hộ",
      professional: "súc tích, rõ ràng, đúng trọng tâm",
    }[tone] ?? "thân thiện";

    const model = createGeminiModel(
      geminiApiKey.value(),
      "Chuyên gia giao tiếp và viết tin nhắn tiếng Việt.",
      {maxOutputTokens: 512, temperature: 0.8},
    );
    try {
      const contextNote = userContext ? `\nThông tin thêm về người dùng: ${sanitize(userContext, 200)}` : "";
      const raw = await callGeminiWithRetry(model,
        `Gợi ý ${count} cách trả lời ngắn gọn (${toneDesc}) cho tin nhắn cuối cùng.${contextNote}\n` +
        `Mỗi gợi ý trên một dòng, không đánh số, tối đa 20 từ.\n\n` +
        `Cuộc trò chuyện:\n${clean.slice(-5).join("\n")}`,
      );
      const suggestions = raw
        .split("\n")
        .map((s) => s.replace(/^[-•*\d.]+\s*/, "").trim())
        .filter((s) => s.length > 0)
        .slice(0, count);
      return {suggestions, tone, count};
    } catch (err) {
      logger.error("[suggestReplies]", err);
      return {suggestions: []};
    }
  },
);

// ═════════════════════════════════════════════════════════════════════════════
// 8. generateSwipeReplies
// ═════════════════════════════════════════════════════════════════════════════

exports.generateSwipeReplies = onCall(
  {secrets: [geminiApiKey]},
  async (request) => {
    requireAuth(request.auth);
    const {incomingMessage, contextMessages, replyStyle = "genz"} = request.data;
    if (!incomingMessage) return {replies: ["Ok nha", "Thế à?", "Chịu luôn á 😂", "Đỉnh!"]};

    const styleDesc = {
      genz:     "Gen Z Việt Nam, dùng tiếng lóng, emoji vừa phải",
      elder:    "thân thiện, lịch sự, dễ hiểu, không tiếng lóng",
      work:     "chuyên nghiệp, ngắn gọn, lịch sự",
      playful:  "vui vẻ, hài hước, emoji nhiều",
    }[replyStyle] ?? "Gen Z Việt Nam";

    const model = createGeminiModel(
      geminiApiKey.value(),
      `Chuyên gia viết tin nhắn ngắn phong cách ${styleDesc}.`,
      {maxOutputTokens: 256, temperature: 0.9},
      true,
    );
    try {
      const raw    = await callGeminiWithRetry(model,
        `Ngữ cảnh: "${sanitize(contextMessages ?? "", 400)}".\n` +
        `Tin nhắn mới: "${sanitize(incomingMessage, 400)}".\n` +
        `Tạo 4 câu trả lời cực ngắn (dưới 12 chữ), ${styleDesc}, tự nhiên.\n` +
        `Trả về JSON mảng: ["câu 1","câu 2","câu 3","câu 4"]`,
      );
      const parsed = safeParseJson(raw);
      const replies = Array.isArray(parsed) ? parsed.slice(0, 4) : ["Ok nha", "Thế à?", "Chịu luôn 😂", "Đỉnh!"];
      return {replies};
    } catch (err) {
      logger.error("[generateSwipeReplies]", err);
      return {replies: ["Ok nha", "Thế à?", "Chịu luôn á 😂", "Đỉnh!"]};
    }
  },
);

// ═════════════════════════════════════════════════════════════════════════════
// 9. generateAutoPilotReply
// ═════════════════════════════════════════════════════════════════════════════

exports.generateAutoPilotReply = onCall(
  {secrets: [geminiApiKey]},
  async (request) => {
    requireAuth(request.auth);
    const {incomingMessage, myStyleContext, awayMessage} = request.data;
    if (!incomingMessage) return {reply: awayMessage ?? "Tôi đang bận, sẽ ntin lại sau nha."};

    const model = createGeminiModel(
      geminiApiKey.value(),
      "Bạn sẽ đóng giả làm người dùng và trả lời thay họ dựa trên phong cách được cung cấp.",
      {maxOutputTokens: 256, temperature: 0.75},
    );
    try {
      const raw = await callGeminiWithRetry(model,
        `Phong cách ăn nói của tôi: "${sanitize(myStyleContext ?? "thân thiện, ngắn gọn", 500)}".\n` +
        `Tin nhắn nhận được: "${sanitize(incomingMessage)}".\n` +
        `Viết 1 câu trả lời ngắn, đúng phong cách, tự nhiên như người thật. Không giải thích.`,
      );
      return {reply: raw.trim() || (awayMessage ?? "Tôi đang bận, sẽ ntin lại sau nha.")};
    } catch (err) {
      logger.error("[generateAutoPilotReply]", err);
      return {reply: awayMessage ?? "Tôi đang bận, sẽ ntin lại sau nha."};
    }
  },
);

// ═════════════════════════════════════════════════════════════════════════════
// 10. summarizeConversation
// ═════════════════════════════════════════════════════════════════════════════

exports.summarizeConversation = onCall(
  {secrets: [geminiApiKey]},
  async (request) => {
    requireAuth(request.auth);
    const {messages, maxSentences = 3, language = "vi", includeKeyPoints = false} = request.data;
    const clean = sanitizeMessages(messages);
    if (clean.length === 0) return {summary: "", keyPoints: []};

    const lang  = language === "vi" ? "Trả lời bằng tiếng Việt." : "Respond in English.";
    const model = createGeminiModel(
      geminiApiKey.value(),
      `Chuyên gia tóm tắt nội dung. ${lang}`,
      {maxOutputTokens: 512, temperature: 0.3},
    );
    try {
      let prompt = `Tóm tắt cuộc trò chuyện sau trong ${maxSentences} câu. Không thêm tiêu đề:\n${clean.join("\n")}`;
      if (includeKeyPoints) {
        prompt +=
          `\n\nSau đó trả về JSON: {"summary":"...","keyPoints":["điểm 1","điểm 2","điểm 3"]}`;
      }
      const raw = await callGeminiWithRetry(model, prompt);

      if (includeKeyPoints) {
        const parsed = safeParseJson(raw);
        if (parsed) return {summary: parsed.summary ?? raw.trim(), keyPoints: parsed.keyPoints ?? []};
      }
      return {summary: raw.trim(), keyPoints: []};
    } catch (err) {
      logger.error("[summarizeConversation]", err);
      throw new HttpsError("internal", "Không thể tóm tắt.");
    }
  },
);

// ═════════════════════════════════════════════════════════════════════════════
// 11. analyzeSentiment
// ═════════════════════════════════════════════════════════════════════════════

exports.analyzeSentiment = onCall(
  {secrets: [geminiApiKey]},
  async (request) => {
    requireAuth(request.auth);
    const {messages} = request.data;
    const clean = sanitizeMessages(messages);
    if (clean.length === 0) return {sentiment: "neutral", score: 0.5, emoji: "😐", mood: "bình thường"};

    const model = createGeminiModel(
      geminiApiKey.value(),
      "Chuyên gia tâm lý và phân tích cảm xúc. Trả về JSON hợp lệ.",
      {maxOutputTokens: 256, temperature: 0.1},
      true,
    );
    try {
      const raw = await callGeminiWithRetry(model,
        `Phân tích cảm xúc tổng thể cuộc trò chuyện.\n` +
        `Trả về JSON: {"sentiment":"positive"|"neutral"|"negative","score":0.0-1.0,"emoji":"...","mood":"...","trend":"improving"|"stable"|"declining"}\n\n` +
        `${clean.slice(-10).join("\n")}`,
      );
      return safeParseJson(raw) ?? {sentiment: "neutral", score: 0.5, emoji: "😐", mood: "bình thường"};
    } catch (err) {
      logger.error("[analyzeSentiment]", err);
      return {sentiment: "neutral", score: 0.5, emoji: "😐", mood: "bình thường"};
    }
  },
);

// ═════════════════════════════════════════════════════════════════════════════
// 12. detectHateSpeech
// ═════════════════════════════════════════════════════════════════════════════

exports.detectHateSpeech = onCall(
  {secrets: [geminiApiKey]},
  async (request) => {
    requireAuth(request.auth);
    const {message} = request.data;
    if (!message) return {isHateful: false, category: "none", confidence: 0};

    const safeMsg = sanitize(message, 1000);

    // Quick keyword pre-check
    if (!quickHateCheck(safeMsg) && safeMsg.length < 20) {
      return {isHateful: false, category: "none", confidence: 0};
    }

    const model = createGeminiModel(
      geminiApiKey.value(),
      "Chuyên gia kiểm duyệt nội dung số tại Việt Nam. Trả về JSON hợp lệ.",
      {maxOutputTokens: 128, temperature: 0.1},
      true,
    );
    try {
      const raw    = await callGeminiWithRetry(model,
        `Kiểm tra tin nhắn có chứa ngôn ngữ thù ghét, quấy rối, xúc phạm không.\n` +
        `Trả về JSON: {"isHateful":bool,"category":"hate"|"harassment"|"offensive"|"none","confidence":0.0-1.0,"reason":"..."}\n\n` +
        `Tin nhắn: "${safeMsg}"`,
      );
      const parsed = safeParseJson(raw);
      return {
        isHateful:  parsed?.isHateful  ?? false,
        category:   parsed?.category   ?? "none",
        confidence: parsed?.confidence ?? 0,
        reason:     parsed?.reason     ?? null,
      };
    } catch (err) {
      logger.error("[detectHateSpeech]", err);
      return {isHateful: false, category: "none", confidence: 0};
    }
  },
);

// ═════════════════════════════════════════════════════════════════════════════
// 13. analyzeCallSecurity
// ═════════════════════════════════════════════════════════════════════════════

exports.analyzeCallSecurity = onCall(
  {secrets: [geminiApiKey]},
  async (request) => {
    requireAuth(request.auth);
    const {callTranscript, peerId, conversationId} = request.data;
    if (!callTranscript) {
      return {isSafe: true, riskLevel: "LOW", warningMessage: "", confidenceScore: 0};
    }
    const model = createGeminiModel(
      geminiApiKey.value(),
      "Chuyên gia an ninh mạng và phát hiện lừa đảo qua điện thoại tại Việt Nam.",
      {maxOutputTokens: 512, temperature: 0.1},
    );
    try {
      const raw = await callGeminiWithRetry(model,
        `Phân tích hội thoại cuộc gọi tìm dấu hiệu lừa đảo, tống tiền, Deepfake AI, social engineering.\n` +
        `Hội thoại: "${sanitize(callTranscript, 2000)}"\n` +
        `Trả về JSON: {"isSafe":bool,"riskLevel":"LOW"|"MEDIUM"|"HIGH","warningMessage":"...","confidenceScore":0-100,"redFlags":[]}`,
      );
      const analysis = safeParseJson(raw) ??
        {isSafe: true, riskLevel: "LOW", warningMessage: "", confidenceScore: 0, redFlags: []};

      if (!analysis.isSafe || analysis.riskLevel === "HIGH") {
        await db.collection("security_alerts").add({
          reporterId:        request.auth.uid,
          suspectId:         peerId         ?? null,
          conversationId:    conversationId ?? "unknown",
          transcriptSnippet: sanitize(callTranscript, 300),
          analysisResult:    analysis,
          timestamp:         FieldValue.serverTimestamp(),
          type:              "call_security",
        });
        logger.warn(`[analyzeCallSecurity] High-risk call by ${request.auth.uid}`);
      }
      return analysis;
    } catch (err) {
      logger.error("[analyzeCallSecurity]", err);
      return {isSafe: true, riskLevel: "LOW", warningMessage: "", confidenceScore: 0};
    }
  },
);

// ═════════════════════════════════════════════════════════════════════════════
// 14. requestCallToken
// ═════════════════════════════════════════════════════════════════════════════

exports.requestCallToken = onCall(
  {secrets: [agoraAppId, agoraCertificate], enforceAppCheck: false},
  async (request) => {
    requireAuth(request.auth);
    const {channelName, uid = 0} = request.data;
    if (!channelName) {
      throw new HttpsError("invalid-argument", "channelName là bắt buộc.");
    }

    const appId   = agoraAppId.value();
    const appCert = agoraCertificate.value();
    if (!appId || !appCert) {
      logger.error("[requestCallToken] Agora credentials not configured.");
      throw new HttpsError("internal", "Agora credentials chưa cấu hình.");
    }

    try {
      const {token, expiresAt} = buildAgoraToken(channelName, uid, appId, appCert);
      logger.info(`[requestCallToken] Token issued for channel: ${channelName}`);
      return {token, expiresAt, channelName};
    } catch (err) {
      logger.error("[requestCallToken]", err);
      throw new HttpsError("internal", "Không thể tạo token.");
    }
  },
);

// ═════════════════════════════════════════════════════════════════════════════
// 15. smartReplyWithContext — AI reply composer with full context awareness
// ═════════════════════════════════════════════════════════════════════════════

exports.smartReplyWithContext = onCall(
  {secrets: [geminiApiKey]},
  async (request) => {
    requireAuth(request.auth);
    await checkRateLimit(request.auth.uid, "smart_reply");

    const {
      messages,
      userProfile = {},
      replyIntent = "helpful",
      maxLength = 150,
      language = "vi",
    } = request.data;

    const clean = sanitizeMessages(messages);
    if (clean.length === 0) throw new HttpsError("invalid-argument", "Thiếu messages.");

    const intentDesc = {
      helpful:    "hữu ích, giải quyết vấn đề",
      empathetic: "đồng cảm, lắng nghe, ủng hộ",
      playful:    "vui vẻ, hài hước nhẹ nhàng",
      concise:    "ngắn gọn, thẳng vào vấn đề",
      elaborate:  "chi tiết, giải thích đầy đủ",
    }[replyIntent] ?? "hữu ích";

    const langNote = language === "vi" ? "Trả lời bằng tiếng Việt." : "Respond in English.";
    const profileNote = Object.keys(userProfile).length > 0 ?
      `\nHồ sơ người dùng: ${JSON.stringify(userProfile)}` :
      "";

    const model = createGeminiModel(
      geminiApiKey.value(),
      `Bạn là AI trợ lý chat thông minh, ${intentDesc}. ${langNote}`,
      {maxOutputTokens: 512, temperature: 0.7},
    );

    try {
      const raw = await callGeminiWithRetry(model,
        `${profileNote}\nViết 1 câu trả lời (${intentDesc}, tối đa ${maxLength} chữ) cho cuộc trò chuyện sau.\n` +
        `Chỉ trả về nội dung tin nhắn, không giải thích.\n\n` +
        `${clean.slice(-8).join("\n")}`,
      );
      return {
        reply:      raw.trim(),
        intent:     replyIntent,
        language,
        charCount:  raw.trim().length,
      };
    } catch (err) {
      logger.error("[smartReplyWithContext]", err);
      throw new HttpsError("internal", "Không thể tạo câu trả lời.");
    }
  },
);

// ═════════════════════════════════════════════════════════════════════════════
// 16. generateIcebreakers
// ═════════════════════════════════════════════════════════════════════════════

exports.generateIcebreakers = onCall(
  {secrets: [geminiApiKey]},
  async (request) => {
    requireAuth(request.auth);
    const {
      sharedInterests = [],
      relationshipType = "friend",
      count = 5,
      style = "casual",
    } = request.data;

    const styleDesc = {
      casual:  "thân thiện, nhẹ nhàng",
      playful: "vui vẻ, hài hước",
      deep:    "sâu sắc, ý nghĩa",
      work:    "chuyên nghiệp, lịch sự",
    }[style] ?? "thân thiện";

    const model = createGeminiModel(
      geminiApiKey.value(),
      "Chuyên gia giao tiếp xã hội Việt Nam.",
      {maxOutputTokens: 512, temperature: 0.9},
      true,
    );
    try {
      const interestNote = sharedInterests.length > 0 ?
        `Sở thích chung: ${sharedInterests.slice(0, 5).join(", ")}.` : "";
      const raw = await callGeminiWithRetry(model,
        `Tạo ${count} câu mở đầu cuộc trò chuyện (${styleDesc}) cho mối quan hệ "${relationshipType}". ${interestNote}\n` +
        `Trả về JSON mảng: ["câu 1","câu 2",...]`,
      );
      const parsed = safeParseJson(raw);
      return {
        icebreakers: Array.isArray(parsed) ? parsed.slice(0, count) : [],
        style,
        count,
      };
    } catch (err) {
      logger.error("[generateIcebreakers]", err);
      return {icebreakers: [], style, count};
    }
  },
);

// ═════════════════════════════════════════════════════════════════════════════
// 17. analyzeToxicityBatch — Batch analyze multiple messages at once
// ═════════════════════════════════════════════════════════════════════════════

exports.analyzeToxicityBatch = onCall(
  {
    secrets: [geminiApiKey],
    memory: "512MiB",
    timeoutSeconds: 120,
  },
  async (request) => {
    requireAuth(request.auth);
    const {messages} = request.data;
    if (!Array.isArray(messages) || messages.length === 0) {
      throw new HttpsError("invalid-argument", "Thiếu messages array.");
    }
    // Limit batch size
    const batch = messages.slice(0, 20).map((m) => ({
      id:   m.id ?? null,
      text: sanitize(String(m.text ?? ""), 500),
    })).filter((m) => m.text.length > 0);

    const model = createGeminiModel(
      geminiApiKey.value(),
      "Chuyên gia kiểm duyệt nội dung. Trả về JSON hợp lệ.",
      {maxOutputTokens: 2048, temperature: 0.1},
    );
    try {
      const formattedMsgs = batch.map((m, i) => `[${i}] ${m.text}`).join("\n");
      const raw = await callGeminiWithRetry(model,
        `Phân tích toxicity cho ${batch.length} tin nhắn sau. Trả về JSON mảng:\n` +
        `[{"index":0,"isToxic":bool,"category":"hate"|"harassment"|"offensive"|"safe","confidence":0.0-1.0},...]\n\n` +
        `${formattedMsgs}`,
      );
      const results = safeParseJson(raw);
      if (!Array.isArray(results)) {
        return {results: batch.map((_, i) => ({index: i, isToxic: false, category: "safe", confidence: 0}))};
      }
      // Map results back with IDs
      return {
        results: results.map((r) => ({
          ...r,
          id: batch[r.index]?.id ?? null,
        })),
        analyzedCount: batch.length,
      };
    } catch (err) {
      logger.error("[analyzeToxicityBatch]", err);
      return {results: [], analyzedCount: 0};
    }
  },
);

// ═════════════════════════════════════════════════════════════════════════════
// 18. generateMessageTone — Rewrite message in a different tone
// ═════════════════════════════════════════════════════════════════════════════

exports.generateMessageTone = onCall(
  {secrets: [geminiApiKey]},
  async (request) => {
    requireAuth(request.auth);
    const {message, fromTone = "auto", toTone, keepEmoji = true} = request.data;
    if (!message || !toTone) {
      throw new HttpsError("invalid-argument", "Thiếu message hoặc toTone.");
    }

    const toneMap = {
      formal:      "trang trọng, kính ngữ đầy đủ",
      casual:      "thân mật, bình thường",
      professional:"chuyên nghiệp, súc tích",
      friendly:    "thân thiện, ấm áp",
      assertive:   "quyết đoán, rõ ràng, thẳng thắn",
      soft:        "nhẹ nhàng, lịch sự, tránh gây xúc phạm",
      enthusiastic:"nhiệt tình, hào hứng, tích cực",
      empathetic:  "đồng cảm, thấu hiểu",
    };
    const targetDesc = toneMap[toTone] ?? toTone;
    const emojiNote  = keepEmoji ? "Giữ nguyên emoji." : "Bỏ tất cả emoji.";

    const model = createGeminiModel(
      geminiApiKey.value(),
      "Chuyên gia viết lại nội dung với giọng điệu phù hợp.",
      {maxOutputTokens: 512, temperature: 0.6},
    );
    try {
      const rewritten = await callGeminiWithRetry(model,
        `Viết lại tin nhắn sau theo giọng điệu ${targetDesc}. ${emojiNote}\n` +
        `Giữ nguyên ý nghĩa, chỉ thay đổi cách diễn đạt.\n` +
        `Chỉ trả về nội dung đã viết lại.\n\n` +
        `Tin nhắn gốc: "${sanitize(message)}"`,
      );
      return {
        original:  message,
        rewritten: rewritten.trim(),
        toTone,
        fromTone,
      };
    } catch (err) {
      logger.error("[generateMessageTone]", err);
      throw new HttpsError("internal", "Không thể viết lại tin nhắn.");
    }
  },
);

// ═════════════════════════════════════════════════════════════════════════════
// 19. extractKeyMoments — Extract highlights and memorable moments
// ═════════════════════════════════════════════════════════════════════════════

exports.extractKeyMoments = onCall(
  {secrets: [geminiApiKey]},
  async (request) => {
    requireAuth(request.auth);
    const {messages, conversationId} = request.data;
    const clean = sanitizeMessages(messages);
    if (clean.length < 5) return {moments: [], highlights: []};

    const model = createGeminiModel(
      geminiApiKey.value(),
      "Chuyên gia phân tích và tổng hợp nội dung hội thoại.",
      {maxOutputTokens: 1024, temperature: 0.4},
    );
    try {
      const raw = await callGeminiWithRetry(model,
        `Phân tích cuộc trò chuyện và trích xuất các khoảnh khắc đáng nhớ, quan trọng.\n` +
        `Trả về JSON:\n` +
        `{"moments":[{"type":"funny"|"touching"|"important"|"decision","content":"...","timestamp":null}],` +
        `"highlights":["highlight1","highlight2"],"overallVibes":"..."}\n\n` +
        `${clean.join("\n")}`,
      );
      const parsed = safeParseJson(raw) ?? {moments: [], highlights: []};
      if (conversationId && parsed.moments?.length > 0) {
        await db.collection("conversations").doc(conversationId).set(
          {keyMoments: {...parsed, extractedAt: FieldValue.serverTimestamp()}},
          {merge: true},
        );
      }
      return parsed;
    } catch (err) {
      logger.error("[extractKeyMoments]", err);
      return {moments: [], highlights: []};
    }
  },
);

// ═════════════════════════════════════════════════════════════════════════════
// 20. getUserInsights — Per-user behavioral AI insights from their history
// ═════════════════════════════════════════════════════════════════════════════

exports.getUserInsights = onCall(
  {
    secrets:        [geminiApiKey],
    memory:         "512MiB",
    timeoutSeconds: 120,
  },
  async (request) => {
    requireAuth(request.auth);
    const uid = request.auth.uid;
    const {lookbackDays = 7} = request.data;

    const cutoff = (Date.now() - lookbackDays * 86_400_000).toString();
    try {
      // Sample recent sent messages from all conversations
      const convSnap = await db
        .collection("conversations")
        .where("participants", "array-contains", uid)
        .limit(10)
        .get();

      const allMessages = [];
      await Promise.all(convSnap.docs.map(async (conv) => {
        const msgs = await db
          .collection("messages").doc(conv.id).collection(conv.id)
          .where("idFrom", "==", uid)
          .where("timestamp", ">=", cutoff)
          .orderBy("timestamp", "desc")
          .limit(20)
          .get();
        msgs.docs.forEach((m) => {
          const content = m.data().content;
          if (content && typeof content === "string") {
            allMessages.push(sanitize(content, 200));
          }
        });
      }));

      if (allMessages.length < 5) {
        return {
          communicationStyle: "unknown",
          topTopics:          [],
          activityPattern:    "unknown",
          personalityTraits:  [],
          insightSummary:     "Chưa đủ dữ liệu để phân tích.",
        };
      }

      const model = createGeminiModel(
        geminiApiKey.value(),
        "Chuyên gia tâm lý hành vi và phân tích giao tiếp.",
        {maxOutputTokens: 768, temperature: 0.4},
      );

      const raw = await callGeminiWithRetry(model,
        `Phân tích phong cách giao tiếp của người dùng qua ${allMessages.length} tin nhắn gửi đi.\n` +
        `Trả về JSON:\n` +
        `{"communicationStyle":"formal"|"casual"|"mixed","topTopics":[],"activityPattern":"...","personalityTraits":[],"insightSummary":"...","emojiUsageLevel":"high"|"medium"|"low","avgMessageLength":"short"|"medium"|"long"}\n\n` +
        `Tin nhắn: ${allMessages.slice(0, 50).join(" | ")}`,
      );
      const insights = safeParseJson(raw);
      if (insights) {
        await db.collection("users").doc(uid).set(
          {aiInsights: {...insights, updatedAt: FieldValue.serverTimestamp()}},
          {merge: true},
        );
      }
      return insights ?? {insightSummary: "Không thể phân tích lúc này."};
    } catch (err) {
      logger.error("[getUserInsights]", err);
      return {insightSummary: "Đã xảy ra lỗi."};
    }
  },
);

// ═════════════════════════════════════════════════════════════════════════════
// 21. generateAgoraToken — REST endpoint
// ═════════════════════════════════════════════════════════════════════════════

exports.generateAgoraToken = onRequest(
  {secrets: [agoraAppId, agoraCertificate]},
  (req, res) => {
    cors(req, res, () => {
      if (req.method !== "GET") {
        return res.status(405).json({error: "Method Not Allowed"});
      }
      const channelName = req.query.channelName;
      if (!channelName) {
        return res.status(400).json({error: "channelName is required"});
      }
      const appId  = agoraAppId.value();
      const appCert = agoraCertificate.value();
      if (!appId || !appCert) {
        logger.error("[generateAgoraToken] Agora credentials not configured.");
        return res.status(500).json({error: "Agora credentials not configured"});
      }
      const uid = req.query.uid ? parseInt(req.query.uid, 10) : 0;
      try {
        const {token, expiresAt} = buildAgoraToken(channelName, uid, appId, appCert);
        res.set("Cache-Control", "no-store");
        return res.status(200).json({token, expiresAt, channelName});
      } catch (err) {
        logger.error("[generateAgoraToken]", err);
        return res.status(500).json({error: "Token generation failed"});
      }
    });
  },
);

// ═════════════════════════════════════════════════════════════════════════════
// 22. healthCheck — Service health endpoint
// ═════════════════════════════════════════════════════════════════════════════

exports.healthCheck = onRequest(
  {timeoutSeconds: 10},
  (req, res) => {
    cors(req, res, () => {
      return res.status(200).json({
        status:    "ok",
        timestamp: new Date().toISOString(),
        region:    "asia-southeast1",
        version:   "2.0.0",
      });
    });
  },
);

// ═════════════════════════════════════════════════════════════════════════════
// 23. scheduleMessageDeletion
// ═════════════════════════════════════════════════════════════════════════════

exports.scheduleMessageDeletion = onDocumentCreated(
  "messages/{conversationId}/{messageId}",
  async (event) => {
    const {conversationId, messageId} = event.params;
    const messageData = event.data?.data();
    if (!messageData) return;

    try {
      const convSnap = await db.collection("conversations").doc(conversationId).get();
      if (!convSnap.exists) return;
      const convData = convSnap.data();
      if (!convData?.autoDeleteEnabled || !convData?.autoDeleteDuration) return;

      const timestamp = parseInt(messageData.timestamp ?? Date.now().toString());
      const deleteAt  = (timestamp + convData.autoDeleteDuration).toString();

      await event.data.ref.update({autoDeleteAt: deleteAt});
      logger.info(`[scheduleMessageDeletion] Scheduled ${messageId} deleteAt=${deleteAt}`);
    } catch (err) {
      logger.error("[scheduleMessageDeletion]", err);
    }
  },
);

// ═════════════════════════════════════════════════════════════════════════════
// 24. sendMessageNotification
// ═════════════════════════════════════════════════════════════════════════════

exports.sendMessageNotification = onDocumentCreated(
  "messages/{conversationId}/{messageId}",
  async (event) => {
    const {conversationId} = event.params;
    const msgData = event.data?.data();
    if (!msgData || msgData.idFrom === "AI_BOT") return;

    try {
      const [receiverSnap, senderSnap] = await Promise.all([
        db.collection("users").doc(msgData.idTo).get(),
        db.collection("users").doc(msgData.idFrom).get(),
      ]);
      if (!receiverSnap.exists) return;

      const receiverData = receiverSnap.data();
      // Don't notify if receiver is currently online (they'll see it in real-time)
      if (receiverData?.isOnline) return;

      const pushToken = receiverData?.pushToken;
      if (!pushToken) return;

      const senderData   = senderSnap.exists ? senderSnap.data() : {};
      const senderName   = senderData?.nickname ?? "Ai đó";
      const senderAvatar = senderData?.photoUrl ?? "";

      const typeLabels = {1: "[Hình ảnh]", 2: "[Video]", 3: "[Tệp đính kèm]", 4: "[Âm thanh]"};
      const messagePreview = msgData.type === 0 ?
        "Bạn có tin nhắn mới" :
        (typeLabels[msgData.type] ?? "[Tệp đính kèm]");

      const encryptedContent = msgData.type === 0 ?
        (msgData.content ?? "") :
        (typeLabels[msgData.type] ?? "");

      await sendPushNotification({
        pushToken,
        title: senderName,
        body:  messagePreview,
        data:  {
          conversationId,
          senderId:         msgData.idFrom,
          senderName,
          senderAvatar,
          type:             "new_message",
          messageType:      String(msgData.type ?? 0),
          encryptedContent,
          participantIds:   JSON.stringify([msgData.idTo, msgData.idFrom]),
        },
      });
    } catch (err) {
      logger.error("[sendMessageNotification]", err);
    }
  },
);

// ═════════════════════════════════════════════════════════════════════════════
// 25. updateUserPresence
// ═════════════════════════════════════════════════════════════════════════════

exports.updateUserPresence = onDocumentUpdated(
  "users/{userId}",
  async (event) => {
    const before = event.data?.before.data();
    const after  = event.data?.after.data();
    if (!before || !after) return;
    if (before.isOnline && !after.isOnline) {
      try {
        await event.data.after.ref.update({lastSeen: FieldValue.serverTimestamp()});
      } catch (err) {
        logger.error("[updateUserPresence]", err);
      }
    }
  },
);

// ═════════════════════════════════════════════════════════════════════════════
// 26. onCallCreated
// ═════════════════════════════════════════════════════════════════════════════

exports.onCallCreated = onDocumentCreated(
  "calls/{callId}",
  async (event) => {
    const callData = event.data?.data();
    if (!callData) return;
    if (!ACTIVE_CALL_STATUSES.includes(callData.status)) return;

    try {
      const pushToken = await getUserPushToken(callData.calleeId);
      if (!pushToken) return;

      const callType = callData.callType === 1 ? "Video" : "Âm thanh";
      await sendPushNotification({
        pushToken,
        title: `📞 Cuộc gọi ${callType} đến`,
        body:  `${callData.callerName ?? "Ai đó"} đang gọi cho bạn`,
        data:  {
          type:         "incoming_call",
          callId:       event.params.callId,
          callerId:     callData.callerId,
          callerName:   callData.callerName  ?? "",
          callerAvatar: callData.callerAvatar ?? "",
          callType:     String(callData.callType ?? 0),
          channelName:  callData.channelName  ?? "",
        },
      });
      logger.info(`[onCallCreated] Ring notification sent to ${callData.calleeId}`);
    } catch (err) {
      logger.error("[onCallCreated]", err);
    }
  },
);

// ═════════════════════════════════════════════════════════════════════════════
// 27. onCallUpdated
// ═════════════════════════════════════════════════════════════════════════════

exports.onCallUpdated = onDocumentUpdated(
  "calls/{callId}",
  async (event) => {
    const before = event.data?.before.data();
    const after  = event.data?.after.data();
    if (!before || !after) return;
    if (before.status === after.status) return;

    const {callId} = event.params;
    const notifyUserId = after.status === "connected" ? after.callerId : null;
    if (!notifyUserId) return;

    try {
      const pushToken = await getUserPushToken(notifyUserId);
      if (!pushToken) return;

      const msgMap = {
        connected: "Cuộc gọi đã kết nối ✅",
        declined:  "Cuộc gọi bị từ chối ❌",
        missed:    "Cuộc gọi nhỡ 📵",
        ended:     "Cuộc gọi đã kết thúc",
        busy:      "Người dùng đang bận 🔔",
      };
      const body = msgMap[after.status];
      if (!body) return;

      await sendPushNotification({
        pushToken,
        title: "Cuộc gọi",
        body,
        data:  {type: "call_status_update", callId, status: after.status},
      });
    } catch (err) {
      logger.error("[onCallUpdated]", err);
    }
  },
);

// ═════════════════════════════════════════════════════════════════════════════
// 28. cleanupExpiredMessages
// ═════════════════════════════════════════════════════════════════════════════

exports.cleanupExpiredMessages = onSchedule(
  {schedule: "every 5 minutes", timeZone: "Asia/Ho_Chi_Minh"},
  async () => {
    const now = Date.now().toString();
    try {
      const conversations = await db
        .collection("conversations")
        .where("autoDeleteEnabled", "==", true)
        .get();

      let totalDeleted = 0;
      for (const conv of conversations.docs) {
        if (!conv.data().autoDeleteDuration) continue;
        const expired = await db
          .collection("messages").doc(conv.id).collection(conv.id)
          .where("autoDeleteAt", "<=", now)
          .where("isDeleted", "==", false)
          .limit(500)
          .get();
        if (expired.empty) continue;
        await batchUpdate(expired.docs, (batch, doc) => {
          batch.update(doc.ref, {
            isDeleted:    true,
            content:      "",
            deletedAt:    FieldValue.serverTimestamp(),
            deleteReason: "auto_expire",
          });
        });
        totalDeleted += expired.docs.length;
      }
      logger.info(`[cleanupExpiredMessages] Deleted ${totalDeleted} messages`);
    } catch (err) {
      logger.error("[cleanupExpiredMessages]", err);
    }
  },
);

// ═════════════════════════════════════════════════════════════════════════════
// 29. cleanupTypingStatus
// ═════════════════════════════════════════════════════════════════════════════

exports.cleanupTypingStatus = onSchedule(
  {schedule: "every 1 minutes", timeZone: "Asia/Ho_Chi_Minh"},
  async () => {
    const staleThreshold = Date.now() - 5000;
    try {
      const typingDocs = await db.collection("typing_status").get();
      const updates = [];
      for (const doc of typingDocs.docs) {
        const updateObj = {};
        let hasChanges  = false;
        for (const [userId, status] of Object.entries(doc.data())) {
          const ts = status?.timestamp?.toMillis?.();
          if (ts && ts < staleThreshold) {
            updateObj[userId] = FieldValue.delete();
            hasChanges        = true;
          }
        }
        if (hasChanges) updates.push(doc.ref.update(updateObj));
      }
      await Promise.all(updates);
    } catch (err) {
      logger.error("[cleanupTypingStatus]", err);
    }
  },
);

// ═════════════════════════════════════════════════════════════════════════════
// 30. cleanupExpiredStories
// ═════════════════════════════════════════════════════════════════════════════

exports.cleanupExpiredStories = onSchedule(
  {schedule: "every 1 hours", timeZone: "Asia/Ho_Chi_Minh"},
  async () => {
    const now = Date.now().toString();
    try {
      const expired = await db
        .collection("stories")
        .where("expiresAt", "<=", now)
        .where("isDeleted", "==", false)
        .get();
      if (expired.empty) return;
      await batchUpdate(expired.docs, (batch, doc) => {
        batch.update(doc.ref, {
          isDeleted: true,
          deletedAt: FieldValue.serverTimestamp(),
        });
      });
      logger.info(`[cleanupExpiredStories] Deleted ${expired.size} stories`);
    } catch (err) {
      logger.error("[cleanupExpiredStories]", err);
    }
  },
);

// ═════════════════════════════════════════════════════════════════════════════
// 31. cleanupStaleCalls
// ═════════════════════════════════════════════════════════════════════════════

exports.cleanupStaleCalls = onSchedule(
  {schedule: "every 5 minutes", timeZone: "Asia/Ho_Chi_Minh"},
  async () => {
    const cutoff = (Date.now() - CALL_STALE_SEC * 1000).toString();
    try {
      const staleCalls = await db
        .collection("calls")
        .where("status",    "in",  ["calling", "ringing", "dialing"])
        .where("createdAt", "<=",  cutoff)
        .get();

      if (staleCalls.empty) return;

      await batchUpdate(staleCalls.docs, (batch, doc) => {
        batch.update(doc.ref, {
          status:  "missed",
          endedAt: Date.now().toString(),
        });
      });
      logger.info(`[cleanupStaleCalls] Marked ${staleCalls.size} calls as missed`);
    } catch (err) {
      logger.error("[cleanupStaleCalls]", err);
    }
  },
);

// ═════════════════════════════════════════════════════════════════════════════
// 32. weeklyAiRecap
// ═════════════════════════════════════════════════════════════════════════════

exports.weeklyAiRecap = onSchedule(
  {
    schedule:       "0 20 * * 0",
    timeZone:       "Asia/Ho_Chi_Minh",
    secrets:        [geminiApiKey],
    memory:         "512MiB",
    timeoutSeconds: 300,
  },
  async () => {
    logger.info("[weeklyAiRecap] Starting...");
    const sevenDaysAgo = (Date.now() - 7 * 24 * 60 * 60 * 1000).toString();

    try {
      const groups = await db
        .collection("conversations")
        .where("isGroup", "==", true)
        .get();

      let recapped = 0;
      for (const groupDoc of groups.docs) {
        const groupId  = groupDoc.id;
        const msgsSnap = await db
          .collection("messages").doc(groupId).collection(groupId)
          .where("timestamp", ">=", sevenDaysAgo)
          .where("type",      "==", 0)
          .orderBy("timestamp", "asc")
          .limit(200)
          .get();

        if (msgsSnap.empty) continue;

        const chatHistory = msgsSnap.docs
          .map((d) => `User ${d.data().idFrom}: ${sanitize(d.data().content ?? "", 200)}`)
          .join("\n");
        if (!chatHistory.trim()) continue;

        try {
          const model  = createGeminiModel(
            geminiApiKey.value(),
            "Bạn là MC vui nhộn, hài hước, am hiểu văn hóa mạng Việt Nam.",
            {maxOutputTokens: 512, temperature: 0.85},
          );
          const recap  = await callGeminiWithRetry(model,
            `Đây là lịch sử chat nhóm tuần qua. Đóng vai MC vui nhộn, viết bản tin "Bóc Phốt Tuần" ` +
            `dưới 150 chữ: ai nói nhiều nhất, câu nói ấn tượng, trend hài hước, highlight của tuần. ` +
            `Dùng emoji, tiếng lóng Gen Z vừa phải, vui vẻ.\n\nLịch sử:\n${chatHistory}`,
          );
          const recapText = `🔥 BẢN TIN BÓC PHỐT TUẦN 🔥\n\n${recap.trim()}`;
          const msgId     = Date.now().toString();

          const batch = db.batch();
          const msgRef = db
            .collection("messages").doc(groupId).collection(groupId).doc(msgId);
          batch.set(msgRef, {
            idFrom:    "AI_BOT",
            idTo:      groupId,
            timestamp: msgId,
            content:   recapText,
            type:      0,
            status:    "sent",
          });
          batch.update(groupDoc.ref, {
            lastMessage:     recapText,
            lastMessageTime: msgId,
            lastMessageType: 0,
          });
          await batch.commit();
          recapped++;
        } catch (err) {
          logger.error(`[weeklyAiRecap] Gemini error group ${groupId}:`, err);
        }
      }
      logger.info(`[weeklyAiRecap] Done — ${recapped}/${groups.size} groups`);
    } catch (err) {
      logger.error("[weeklyAiRecap]", err);
    }
  },
);

// ═════════════════════════════════════════════════════════════════════════════
// 33. dailyConversationDigest — Mon–Fri 08:00 ICT personal digest
// ═════════════════════════════════════════════════════════════════════════════

exports.dailyConversationDigest = onSchedule(
  {
    schedule:       "0 8 * * 1-5",
    timeZone:       "Asia/Ho_Chi_Minh",
    secrets:        [geminiApiKey],
    memory:         "512MiB",
    timeoutSeconds: 300,
  },
  async () => {
    logger.info("[dailyConversationDigest] Starting...");

    try {
      // Get active users (online in last 7 days)
      const usersSnap = await db
        .collection("users")
        .where("lastSeen", ">=", (Date.now() - 7 * 86_400_000).toString())
        .limit(200)
        .get();

      let sent = 0;
      for (const userDoc of usersSnap.docs) {
        const uid       = userDoc.id;
        const pushToken = userDoc.data()?.pushToken;
        if (!pushToken) continue;

        // Count unread messages for user
        const convSnap = await db
          .collection("conversations")
          .where("participants", "array-contains", uid)
          .limit(5)
          .get();

        let unreadCount = 0;
        let pendingConvs = 0;
        for (const conv of convSnap.docs) {
          const unreadField = conv.data()[`unread_${uid}`] ?? 0;
          if (unreadField > 0) {
            unreadCount += unreadField;
            pendingConvs++;
          }
        }

        if (unreadCount === 0) continue;

        await sendPushNotification({
          pushToken,
          title: "☀️ Tin nhắn chưa đọc",
          body:  `Bạn có ${unreadCount} tin nhắn chưa đọc trong ${pendingConvs} cuộc trò chuyện`,
          data:  {type: "daily_digest", unreadCount: String(unreadCount)},
        });
        sent++;
      }
      logger.info(`[dailyConversationDigest] Sent to ${sent} users`);
    } catch (err) {
      logger.error("[dailyConversationDigest]", err);
    }
  },
);
