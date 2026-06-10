"use strict";

// ═════════════════════════════════════════════════════════════════════════════
// ─── FIREBASE FUNCTIONS & ADMIN INITIALIZATION ───────────────────────────────
// ═════════════════════════════════════════════════════════════════════════════
const {
  onCall,
  onRequest,
  HttpsError,
} = require("firebase-functions/v2/https");
const {
  onDocumentCreated,
  onDocumentUpdated,
} = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { setGlobalOptions } = require("firebase-functions/v2");
const { defineSecret } = require("firebase-functions/params");
const logger = require("firebase-functions/logger");

const { initializeApp, getApps } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

// ─── THIRD-PARTY MODULES ──────────────────────────────────────────────────────
const {
  GoogleGenerativeAI,
  HarmCategory,
  HarmBlockThreshold,
} = require("@google/generative-ai");
const { RtcTokenBuilder, RtcRole } = require("agora-access-token");
const cors = require("cors")({ origin: true });

// ─── GLOBAL CONFIGURATION ─────────────────────────────────────────────────────
if (!getApps().length) {
  initializeApp();
}
const db = getFirestore();

setGlobalOptions({
  region: "asia-southeast1",
  maxInstances: 30,
  memory: "256MiB",
  timeoutSeconds: 60,
  concurrency: 80,
});

// ─── CLOUD SECRET MANAGER PARAMETERS ──────────────────────────────────────────
const geminiApiKey = defineSecret("GEMINI_API_KEY");
const agoraAppId = defineSecret("AGORA_APP_ID");
const agoraCertificate = defineSecret("AGORA_APP_CERTIFICATE");

// ═════════════════════════════════════════════════════════════════════════════
// ─── GLOBAL CONSTANTS ────────────────────────────────────────────────────────
// ═════════════════════════════════════════════════════════════════════════════
const MODEL_ID = "gemini-2.0-flash";
const MODEL_FLASH_LITE = "gemini-2.0-flash-lite";
const MAX_INPUT_LENGTH = 4000;
const MAX_HISTORY_MSGS = 20;
const AGORA_TOKEN_TTL_SEC = 3600;
const CALL_STALE_SEC = 90;

const RECAP_STYLE_CONFIGS = {
  "humorous": {
    systemPrompt: "Bạn là MC vui nhộn, hài hước, am hiểu văn hóa mạng và tiếng lóng Gen Z Việt Nam. Dùng emoji phù hợp.",
    buildPrompt: (chatHistory, type) =>
      type === "personal"
        ? `Đây là cuộc trò chuyện của 2 người bạn trong tuần qua. Viết bản tóm tắt "Bóc Phốt Đôi Bạn" dưới 220 chữ: khoảnh khắc hài tự nhiên, câu nói ấn tượng, những khoảnh khắc đặc biệt. Dùng emoji, tiếng lóng vừa phải, vui nhộn.\n\nChat:\n${chatHistory}`
        : `Đây là lịch sử chat nhóm tuần qua. Đóng vai MC vui nhộn viết bản tin "Bóc Phốt Tuần" dưới 220 chữ: ai nói nhiều nhất, câu nói ấn tượng nhất, trend hài hước nhất, highlight của tuần. Dùng emoji, tiếng lóng Gen Z vừa phải.\n\nChat:\n${chatHistory}`,
    label: "Bóc Phốt Tuần",
    emoji: "😂",
  },
  "professional": {
    systemPrompt: "Bạn là trợ lý AI phân tích giao tiếp chuyên sâu. Văn phong chuyên nghiệp, súc tích, khách quan.",
    buildPrompt: (chatHistory, _type) =>
      `Phân tích lịch sử chat tuần qua theo góc nhìn chuyên nghiệp. Trình bày dưới 220 chữ: (1) Chủ đề chính thảo luận, (2) Quyết định quan trọng được đưa ra, (3) Action items còn chờ xử lý, (4) Hiệu quả giao tiếp tổng thể. Văn phong lịch sự, không rườm rà.\n\nChat:\n${chatHistory}`,
    label: "Báo Cáo Tuần",
    emoji: "📊",
  },
  "romantic": {
    systemPrompt: "Bạn là nhà văn lãng mạn, tinh tế, yêu con người và trân trọng những khoảnh khắc bình dị.",
    buildPrompt: (chatHistory, _type) =>
      `Đây là hành trình giao tiếp tuần qua. Viết đoạn tóm tắt 160-180 chữ tôn vinh: những khoảnh khắc ấm lòng, câu nói đáng nhớ, cảm xúc đặc biệt, sự gắn kết. Văn phong nhẹ nhàng, tình cảm, không sến súa.\n\nChat:\n${chatHistory}`,
    label: "Kỷ Niệm Tuần",
    emoji: "💕",
  },
  "tv_host": {
    systemPrompt: "Bạn là MC chương trình truyền hình Việt Nam nổi tiếng, giọng năng động, hào hứng, hài hước vừa phải.",
    buildPrompt: (chatHistory, _type) =>
      `Chào khán giả yêu quý! Đây là "Bản Tin Chat Tuần"! Viết lại theo phong cách dẫn chương trình truyền hình dưới 220 chữ: điểm tin nóng của tuần, những tình huống đáng chú ý, highlight ấn tượng, câu kết hào hứng. Nhiều emoji, cảm xúc mạnh, cuốn hút.\n\nChat:\n${chatHistory}`,
    label: "Bản Tin Tuần",
    emoji: "🎬",
  },
  "minimal": {
    systemPrompt: "Bạn là AI tóm tắt chính xác, ngắn gọn, súc tích. Không rườm rà, không giải thích thừa.",
    buildPrompt: (chatHistory, _type) =>
      `Tóm tắt cuộc trò chuyện tuần qua trong 4–6 điểm chính. Mỗi điểm 1–2 câu. Ngắn gọn, đi thẳng vào vấn đề, dùng emoji phù hợp cho mỗi điểm.\n\nChat:\n${chatHistory}`,
    label: "Tóm Tắt Tuần",
    emoji: "📝",
  },
};

const TONE_PROMPTS = {
  friendly: "Trả lời theo phong cách THÂN THIỆN: ấm áp, gần gũi, tự nhiên như người bạn thân đang nhắn tin. Có thể dùng emoji nhẹ nhàng. Câu ngắn, không dài dòng.",
  professional: "Trả lời theo phong cách CHUYÊN NGHIỆP: lịch sự, trang trọng, súc tích. Không dùng tiếng lóng hay emoji. Câu đầy đủ, ngữ pháp chuẩn.",
  funny: "Trả lời theo phong cách HÀI HƯỚC Gen Z: vui vẻ, dí dỏm, có thể dùng tiếng lóng và emoji 😂🔥. Ngắn gọn, bắt trend, tự nhiên.",
  brief: "Trả lời CỰC NGẮN: chỉ 1 câu ngắn hoặc vài từ. Thẳng vào vấn đề, không giải thích thêm.",
  likeMe: "Trả lời GIỐNG HỆT PHONG CÁCH của chủ tài khoản: bắt chước đúng cách dùng emoji, độ dài câu, từ ngữ đặc trưng đã học được từ persona.",
};

const ACTIVE_CALL_STATUSES = ["calling", "ringing", "dialing", "connected", "accepted"];
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

const _analysisCache = new Map();
const CACHE_TTL_MS = 30_000;

// ═════════════════════════════════════════════════════════════════════════════
// ─── SHARED HELPER FUNCTIONS ─────────────────────────────────────────────────
// ═════════════════════════════════════════════════════════════════════════════
function requireAuth(auth) {
  if (!auth) throw new HttpsError("unauthenticated", "Yêu cầu đăng nhập.");
}

function sanitize(text, maxLen = MAX_INPUT_LENGTH) {
  if (typeof text !== "string") return "";
  return text.trim().substring(0, maxLen);
}

function sanitizeMessages(messages, limit = MAX_HISTORY_MSGS) {
  if (!Array.isArray(messages)) return [];
  return messages
    .map((m) => sanitize(String(m ?? "")))
    .filter((m) => m.length > 0)
    .slice(0, limit);
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
  _analysisCache.set(key, { value, ts: Date.now() });
  if (_analysisCache.size > 500) {
    const firstKey = _analysisCache.keys().next().value;
    _analysisCache.delete(firstKey);
  }
}

async function checkRateLimit(uid, action) {
  const ref = db.collection("_rate_limits").doc(`${uid}_${action}`);
  const now = Date.now();
  const windowStart = now - 60_000;
  try {
    await db.runTransaction(async (tx) => {
      const doc = await tx.get(ref);
      if (!doc.exists) {
        tx.set(ref, { calls: [{ ts: now }], updatedAt: now });
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
      recent.push({ ts: now });
      tx.update(ref, { calls: recent, updatedAt: now });
    });
  } catch (err) {
    if (err instanceof HttpsError) throw err;
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
  const hits = SCAM_KEYWORDS_VI.filter((kw) => lower.includes(kw));
  return { hasKeywords: hits.length > 0, keywords: hits };
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
      .set({ ...data, analyzedAt: FieldValue.serverTimestamp() }, { merge: true });
  } catch (err) {
    logger.warn("[saveAnalysisResult] Firestore error:", err);
  }
}

function createGeminiModel(apiKey, systemPrompt, genConfig = {}, lite = false) {
  const genAI = new GoogleGenerativeAI(apiKey);
  const modelId = lite ? MODEL_FLASH_LITE : MODEL_ID;
  return genAI.getGenerativeModel({
    model: modelId,
    systemInstruction: systemPrompt,
    generationConfig: {
      maxOutputTokens: 1024,
      temperature: 0.5,
      ...genConfig,
    },
    safetySettings: [
      { category: HarmCategory.HARM_CATEGORY_HARASSMENT, threshold: HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE },
      { category: HarmCategory.HARM_CATEGORY_HATE_SPEECH, threshold: HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE },
      { category: HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT, threshold: HarmBlockThreshold.BLOCK_HIGH_AND_ABOVE },
      { category: HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT, threshold: HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE },
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
  const token = RtcTokenBuilder.buildTokenWithUid(
    appId, appCert, channelName, uid, RtcRole.PUBLISHER, expiresAt,
  );
  return { token, expiresAt };
}

async function sendPushNotification({ pushToken, title, body, data = {} }) {
  if (!pushToken) return;
  try {
    await getMessaging().send({
      token: pushToken,
      notification: { title, body },
      data: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)])),
      android: { priority: "high", notification: { channelId: "chat_messages" } },
      apns: {
        payload: { aps: { contentAvailable: true, sound: "default", badge: 1 } },
        headers: { "apns-priority": "10" },
      },
    });
  } catch (err) {
    logger.warn("[sendPushNotification]", err?.errorInfo?.code ?? err);
  }
}

async function getUserPushToken(userId) {
  if (!userId) return null;
  try {
    const snap = await db.collection("users").doc(userId).get();
    return snap.exists ? (snap.data()?.pushToken ?? null) : null;
  } catch {
    return null;
  }
}

// ─── USER INSIGHTS INSIDE FILE ENGINE HELPERS ────────────────────────────────
function isEncrypted(msg) {
  return (
    typeof msg === "string" &&
    (msg.startsWith('{"iv":') || msg.startsWith("eyJ"))
  );
}

function filterMessages(messages) {
  return (messages || []).filter(
    (m) => typeof m === "string" && !isEncrypted(m) && m.trim().length > 2
  );
}

function periodMs(period) {
  const map = { week7: 7, days30: 30, days90: 90 };
  return (map[period] || 7) * 24 * 60 * 60 * 1000;
}

function computeLocalStats(messages, periodKey, now = Date.now()) {
  const cutoff = now - periodMs(periodKey);
  const msgs = messages.filter(
    (m) => m.timestamp >= cutoff && !isEncrypted(m.content || "")
  );
  if (msgs.length === 0) return null;
  const contents = msgs.map((m) => m.content || "");
  const totalMessages = msgs.length;
  const totalLen = contents.reduce((s, c) => s + c.length, 0);
  const avgMessageLength = Math.round(totalLen / totalMessages);

  const days = new Set(
    msgs.map((m) => {
      const d = new Date(m.timestamp);
      return `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`;
    })
  );
  const activeDays = days.size;
  const avgMessagesPerDay = Math.round((totalMessages / activeDays) * 10) / 10;

  const emojiRe = /[\u{1F600}-\u{1F64F}\u{1F300}-\u{1F5FF}\u{1F680}-\u{1F6FF}]/gu;
  const emojiCount = contents.reduce(
    (s, c) => s + (c.match(emojiRe) || []).length,
    0
  );
  const emojiLevel =
    emojiCount > totalMessages * 0.5
      ? "heavy"
      : emojiCount > totalMessages * 0.2
        ? "moderate"
        : "minimal";

  const commStyle =
    avgMessageLength < 25
      ? "concise"
      : avgMessageLength > 80
        ? "expressive"
        : "balanced";

  const grid = {};
  let maxCount = 1;
  for (const m of msgs) {
    const d = new Date(m.timestamp);
    const dow = (d.getDay() + 6) % 7;
    const h = d.getHours();
    const k = `${dow}_${h}`;
    grid[k] = (grid[k] || 0) + 1;
    if (grid[k] > maxCount) maxCount = grid[k];
  }

  const activityHeatmap = [];
  for (let d = 0; d < 7; d++) {
    for (let h = 0; h < 24; h++) {
      const count = grid[`${d}_${h}`] || 0;
      activityHeatmap.push({ dow: d, hour: h, count, intensity: count / maxCount });
    }
  }

  const posWords = new Set([
    "vui", "thích", "tuyệt", "hay", "oke", "ok", "được", "yêu",
    "xinh", "đẹp", "ngon", "tốt", "giỏi", "😊", "😂", "❤️", "🥰", "👍",
  ]);
  const negWords = new Set([
    "buồn", "chán", "mệt", "khó", "tệ", "xấu", "không", "sai", "lo",
    "sợ", "ghét", "nhàm", "😢", "😠", "😤",
  ]);
  const byDay = {};
  for (const m of msgs) {
    const d = new Date(m.timestamp);
    const k = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
    if (!byDay[k]) byDay[k] = [];
    byDay[k].push(m.content || "");
  }

  const moodTrend = Object.entries(byDay)
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([dateStr, dayMsgs]) => {
      let pos = 0, neg = 0;
      for (const msg of dayMsgs) {
        const lower = msg.toLowerCase();
        for (const w of posWords) if (lower.includes(w)) pos++;
        for (const w of negWords) if (lower.includes(w)) neg++;
      }
      const total = pos + neg || 1;
      const score = pos / total;
      const emoji =
        score > 0.75 ? "😄" : score > 0.55 ? "😊" : score > 0.45 ? "😐" : score > 0.25 ? "😕" : "😢";
      const [y, mo, day] = dateStr.split("-").map(Number);
      return {
        date: new Date(y, mo - 1, day).getTime(),
        score: Math.round(score * 100) / 100,
        emoji,
        messageCount: dayMsgs.length,
      };
    });

  let posD = 0, negD = 0, neuD = 0;
  for (const pt of moodTrend) {
    if (pt.score > 0.6) posD++;
    else if (pt.score < 0.4) negD++;
    else neuD++;
  }
  const total = moodTrend.length || 1;
  let trend = "stable";
  if (moodTrend.length >= 4) {
    const half = Math.floor(moodTrend.length / 2);
    const first = moodTrend.slice(0, half).reduce((s, p) => s + p.score, 0) / half;
    const second = moodTrend.slice(half).reduce((s, p) => s + p.score, 0) / (moodTrend.length - half);
    if (second - first > 0.12) trend = "improving";
    if (first - second > 0.12) trend = "declining";
  }

  const sentimentBreakdown = {
    positive: Math.round((posD / total) * 100) / 100,
    neutral: Math.round((neuD / total) * 100) / 100,
    negative: Math.round((negD / total) * 100) / 100,
    trend,
  };

  const stopwords = new Set([
    "là", "và", "có", "không", "được", "của", "với", "cho", "trong",
    "mình", "bạn", "thì", "đã", "sẽ", "ở", "tôi", "mày", "tao", "nha",
    "nhé", "ạ", "ra", "vào", "thôi", "rồi", "đây", "đó", "này",
  ]);
  const freq = {};
  for (const c of contents) {
    for (const w of c.toLowerCase().split(/[\s,.\!\?\n]+/)) {
      const clean = w.replace(/[^\w]/g, "").trim();
      if (clean.length >= 2 && !stopwords.has(clean)) {
        freq[clean] = (freq[clean] || 0) + 1;
      }
    }
  }

  const topicEmojis = {
    ăn: "🍜", nhậu: "🍺", "cà phê": "☕", học: "📚", làm: "💼",
    game: "🎮", phim: "🎬", nhạc: "🎵", đi: "🚗", chơi: "🎉",
    mua: "🛍️", tiền: "💰",
  };
  const topTopics = Object.entries(freq)
    .sort(([, a], [, b]) => b - a)
    .slice(0, 8)
    .map(([topic, count], i, arr) => {
      const totalFreq = arr.reduce((s, [, c]) => s + c, 0);
      const emojiEntry = Object.entries(topicEmojis).find(([k]) => topic.includes(k));
      return {
        topic,
        count,
        percentage: Math.round((count / totalFreq) * 100) / 100,
        emoji: emojiEntry ? emojiEntry[1] : "💬",
      };
    });

  let morning = 0, afternoon = 0, evening = 0, night = 0;
  for (const slot of activityHeatmap) {
    if (slot.hour >= 6 && slot.hour < 12) morning += slot.count;
    else if (slot.hour >= 12 && slot.hour < 18) afternoon += slot.count;
    else if (slot.hour >= 18 && slot.hour < 23) evening += slot.count;
    else night += slot.count;
  }
  const totalAct = morning + afternoon + evening + night || 1;
  let activityPattern = "balanced";
  if (night / totalAct > 0.4) activityPattern = "night_owl";
  else if (morning / totalAct > 0.4) activityPattern = "morning_person";
  else if (evening / totalAct > 0.4) activityPattern = "evening_person";

  const traits = [];
  if (emojiLevel === "heavy") traits.push("expressive");
  if (commStyle === "expressive") traits.push("communicative");
  if (commStyle === "concise") traits.push("direct");
  if (sentimentBreakdown.positive > 0.6) traits.push("optimistic");
  if (sentimentBreakdown.negative > 0.4) traits.push("reflective");
  if (traits.length === 0) traits.push("balanced");

  const periodLabel = { week7: "7 ngày", days30: "30 ngày", days90: "90 ngày" }[periodKey] || "7 ngày";
  const styleDesc = commStyle === "concise" ? "ngắn gọn, súc tích" : commStyle === "expressive" ? "chi tiết, cởi mở" : "cân bằng, rõ ràng";
  const emojiDesc = emojiLevel === "heavy" ? "thường xuyên dùng emoji" : emojiLevel === "moderate" ? "đôi khi dùng emoji" : "ít dùng emoji";
  const patternDesc = activityPattern === "night_owl" ? "nhắn tin nhiều về đêm" : activityPattern === "morning_person" ? "hay nhắn tin buổi sáng" : "nhắn tin đều trong ngày";
  const insightSummary = `Trong ${periodLabel} qua, bạn đã gửi ${totalMessages} tin nhắn trên ${activeDays} ngày (trung bình ${avgMessagesPerDay} tin/ngày). Phong cách giao tiếp của bạn ${styleDesc}, ${emojiDesc} và ${patternDesc}.`;

  return {
    period: periodKey,
    totalMessages,
    activeDays,
    avgMessagesPerDay,
    avgMessageLength,
    communicationStyle: commStyle,
    emojiUsageLevel: emojiLevel,
    personalityTraits: traits,
    activityPattern,
    insightSummary,
    moodTrend,
    activityHeatmap,
    topTopics,
    sentimentBreakdown,
    generatedAt: Date.now(),
  };
}

async function enrichWithAI(localStats, messages, periodKey, apiKey) {
  if (!localStats || messages.length < 5) return localStats;
  const activeKey = apiKey || (typeof geminiApiKey !== "undefined" ? geminiApiKey.value() : null);
  if (!activeKey) return localStats;

  const sample = messages.slice(0, 60).join("\n");
  const prompt = `Phân tích phong cách giao tiếp dựa trên ${messages.length} tin nhắn sau (${periodKey}):
---
${sample}
---
Dựa trên số liệu đã có:
- ${localStats.totalMessages} tin nhắn, ${localStats.activeDays} ngày hoạt động
- Phong cách: ${localStats.communicationStyle}, emoji: ${localStats.emojiUsageLevel}
Hãy viết 2-3 câu tóm tắt THÚ VỊ và CÁ NHÂN HÓA hơn về phong cách giao tiếp này.
Dùng ngôn ngữ gần gũi, tích cực. Không lặp lại số liệu đã có. Tiếng Việt.`;

  try {
    const genAIInstance = new GoogleGenerativeAI(activeKey);
    const model = genAIInstance.getGenerativeModel({
      model: "gemini-1.5-flash",
      generationConfig: { maxOutputTokens: 150, temperature: 0.6 },
    });
    const result = await model.generateContent(prompt);
    const aiSummary = result.response.text().trim();
    return { ...localStats, aiGeneratedSummary: aiSummary };
  } catch (err) {
    console.error("[enrichWithAI] error:", err.message);
    return localStats;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// ─── CLOUD FUNCTIONS CALLABLE HANDLERS (v2) ──────────────────────────────────
// ═════════════════════════════════════════════════════════════════════════════

// ─── 1. analyzeDecryptedMessage ──────────────────────────────────────────────
exports.analyzeDecryptedMessage = onCall(
  { secrets: [geminiApiKey], enforceAppCheck: false },
  async (request) => {
    requireAuth(request.auth);
    const { plainText, conversationId, messageId, idFrom, idTo } = request.data;
    if (!plainText || !conversationId || !messageId) {
      throw new HttpsError("invalid-argument", "Thiếu plainText, conversationId hoặc messageId.");
    }
    const safeText = sanitize(plainText);
    if (!safeText) return { status: "SAFE", level: "SAFE" };

    const cacheKey = `scam_${Buffer.from(safeText).toString("base64").substring(0, 32)}`;
    const cached = getCached(cacheKey);
    if (cached) return cached;

    const quick = quickScamCheck(safeText);
    if (!quick.hasKeywords && safeText.length < 50) {
      const result = { status: "SAFE", level: "SAFE", method: "fast" };
      await saveAnalysisResult(conversationId, messageId, {
        level: "SAFE", method: "keyword_fast", idFrom, idTo,
      });
      setCached(cacheKey, result);
      return result;
    }

    try {
      const model = createGeminiModel(
        geminiApiKey.value(),
        "Bạn là chuyên gia phát hiện lừa đảo trực tuyến tại Việt Nam. Phân tích chính xác, trả về JSON hợp lệ.",
        { maxOutputTokens: 512, temperature: 0.1 },
        true,
      );
      const raw = await callGeminiWithRetry(model,
        `Phân tích tin nhắn sau có dấu hiệu lừa đảo/scam không.\n` +
        `Trả về JSON: {"level":"SAFE"|"WARNING"|"SCAM","reason":"...","confidence":0.0-1.0}\n\n` +
        `Tin nhắn: "${safeText}"`,
      );
      const parsed = safeParseJson(raw);
      const level = parsed?.level ?? (quick.hasKeywords ? "WARNING" : "SAFE");
      const reason = parsed?.reason ?? null;
      const confidence = parsed?.confidence ?? null;

      await saveAnalysisResult(conversationId, messageId, {
        level, reason, confidence, method: "gemini",
        idFrom, idTo, scamKeywords: quick.keywords,
      });

      const result = { status: level, level, reason, confidence };
      setCached(cacheKey, result);
      return result;
    } catch (err) {
      logger.error("[analyzeDecryptedMessage]", err);
      const fallback = quick.hasKeywords ? "WARNING" : "SAFE";
      return { status: fallback, level: fallback, method: "fallback" };
    }
  },
);

// ─── 2. analyzeScam ──────────────────────────────────────────────────────────
exports.analyzeScam = onCall(
  { secrets: [geminiApiKey], enforceAppCheck: false },
  async (request) => {
    requireAuth(request.auth);
    const { message } = request.data;
    if (!message) throw new HttpsError("invalid-argument", "Thiếu message.");
    const safeMsg = sanitize(message);
    if (!safeMsg) return { status: "SAFE", level: "SAFE" };

    const quick = quickScamCheck(safeMsg);
    if (!quick.hasKeywords && safeMsg.length < 30) {
      return { status: "SAFE", level: "SAFE", warningKeywords: [] };
    }

    try {
      const model = createGeminiModel(
        geminiApiKey.value(),
        "Chuyên gia phát hiện lừa đảo. Trả về JSON hợp lệ.",
        { maxOutputTokens: 256, temperature: 0.1 },
        true,
      );
      const raw = await callGeminiWithRetry(model,
        `Tin nhắn: "${safeMsg}"\nTrả về JSON: {"level":"SAFE"|"WARNING"|"SCAM","reason":"...","confidence":0.0-1.0}`,
      );
      const parsed = safeParseJson(raw);
      return {
        status: parsed?.level ?? "SAFE",
        level: parsed?.level ?? "SAFE",
        reason: parsed?.reason ?? null,
        confidence: parsed?.confidence ?? null,
        warningKeywords: quick.keywords,
      };
    } catch (err) {
      logger.error("[analyzeScam]", err);
      return {
        status: quick.hasKeywords ? "WARNING" : "SAFE",
        level: quick.hasKeywords ? "WARNING" : "SAFE",
        warningKeywords: quick.keywords,
        method: "fallback",
      };
    }
  },
);

// ─── 3. analyzeDecryptedClientMessage ────────────────────────────────────────
exports.analyzeDecryptedClientMessage = onCall(
  { secrets: [geminiApiKey], enforceAppCheck: false },
  async (request) => {
    requireAuth(request.auth);
    const { plainTextContent, conversationId, messageId, idTo } = request.data;
    if (!plainTextContent) return null;
    const safeText = sanitize(plainTextContent, 500);

    if (safeText.startsWith('{"iv":') || safeText.startsWith("eyJ")) {
      logger.warn("[analyzeDecryptedClientMessage] Ciphertext received — skip");
      return null;
    }
    if (/^[A-Za-z0-9+/=]+=*:[A-Za-z0-9+/=]+=*$/.test(safeText)) {
      logger.warn("[analyzeDecryptedClientMessage] Legacy ciphertext — skip");
      return null;
    }
    if (safeText.trim().length < 10) return null;

    try {
      const model = createGeminiModel(
        geminiApiKey.value(),
        "Bạn là AI phân tích tin nhắn chat. Trả về JSON hợp lệ, không giải thích.",
        { maxOutputTokens: 512, temperature: 0.2},
      );
      const raw = await callGeminiWithRetry(model,
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
          scamReason: analysis.scamReason ?? "",
          riskLevel: analysis.riskLevel ?? "MEDIUM",
        });
        logger.warn(`[analyzeDecryptedClientMessage] Scam in ${messageId}`);
      }

      if (analysis.hasReminder && idTo) {
        const reminderRef = db.collection("reminders").doc();
        batch.set(reminderRef, {
          userId: idTo,
          conversationId: conversationId ?? null,
          messageId: messageId ?? null,
          task: analysis.reminderTask ?? "",
          timeHint: analysis.reminderTime ?? "",
          createdAt: FieldValue.serverTimestamp(),
          isCompleted: false,
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

// ─── 4. translateCommunication ───────────────────────────────────────────────
exports.translateCommunication = onCall(
  { secrets: [geminiApiKey] },
  async (request) => {
    requireAuth(request.auth);
    await checkRateLimit(request.auth.uid, "translate");
    const { message, targetAudience, preserveEmoji = true } = request.data;
    if (!message || !targetAudience) {
      throw new HttpsError("invalid-argument", "Thiếu message hoặc targetAudience.");
    }

    const audienceDesc = {
      elder: "người cao tuổi (ngôn ngữ đơn giản, kính trọng, không dùng tiếng lóng, câu ngắn rõ ràng)",
      student: "học sinh/sinh viên (trẻ trung, thân thiện, năng động, Gen Z, có thể dùng emoji)",
      work: "môi trường công việc (chuyên nghiệp, lịch sự, súc tích, không emoji quá nhiều)",
      child: "trẻ em (đơn giản, vui vẻ, tích cực, dễ hiểu, dùng từ đơn)",
      formal: "văn bản chính thức (kính ngữ đầy đủ, không viết tắt, trang trọng)",
    }[targetAudience] ?? targetAudience;

    const model = createGeminiModel(
      geminiApiKey.value(),
      "Chuyên gia ngôn ngữ và giao tiếp Việt Nam.",
      { maxOutputTokens: 1024, temperature: 0.5 },
    );

    try {
      const emojiNote = preserveEmoji ? "Giữ nguyên emoji nếu có." : "Bỏ emoji.";
      const translated = await callGeminiWithRetry(model,
        `Diễn giải lại tin nhắn sau phù hợp với ${audienceDesc}. ${emojiNote}\n` +
        `Chỉ trả về nội dung đã diễn giải, không giải thích thêm.\n\n` +
        `Tin nhắn gốc: "${sanitize(message)}"`,
      );
      return {
        translatedText: translated.trim(),
        targetAudience,
        originalLength: message.length,
        translatedLength: translated.trim().length,
      };
    } catch (err) {
      logger.error("[translateCommunication]", err);
      throw new HttpsError("internal", "Không thể dịch tin nhắn.");
    }
  },
);

// ─── 5. analyzeChatContext ───────────────────────────────────────────────────
exports.analyzeChatContext = onCall(
  { secrets: [geminiApiKey] },
  async (request) => {
    requireAuth(request.auth);
    await checkRateLimit(request.auth.uid, "analyze_context");
    const { messages, contextType, action } = request.data;
    if (!messages || !contextType || !action) {
      throw new HttpsError("invalid-argument", "Thiếu messages, contextType hoặc action.");
    }

    const clean = sanitizeMessages(messages);
    if (clean.length === 0) return { analysisResult: "" };

    const actionPrompts = {
      summarize: "Tóm tắt cuộc trò chuyện trong 3 câu ngắn gọn bằng tiếng Việt:",
      suggest: "Gợi ý 3 hành động tiếp theo phù hợp dựa trên nội dung trò chuyện:",
      extract_tasks: 'Liệt kê công việc (tasks) và deadline ngắn gọn từ cuộc trò chuyện theo định dạng JSON: [{"task":"...","deadline":"...","priority":"high|medium|low"}]',
      analyze_mood: "Phân tích tâm trạng/cảm xúc tổng thể và xu hướng của cuộc trò chuyện:",
      key_decisions: "Liệt kê các quyết định quan trọng được đưa ra trong cuộc trò chuyện:",
      action_items: "Liệt kê các việc cần làm sau cuộc trò chuyện này:",
    };

    const contextHints = {
      study: "Đây là cuộc trò chuyện học tập/giáo dục.",
      work: "Đây là cuộc trò chuyện công việc/kinh doanh.",
      elder: "Đây là cuộc trò chuyện với người cao tuổi.",
      family: "Đây là cuộc trò chuyện gia đình.",
      friends: "Đây là cuộc trò chuyện bạn bè.",
    };

    const actionPrompt = actionPrompts[action] ?? `Thực hiện tác vụ "${action}" trên cuộc trò chuyện:`;
    const contextHint = contextHints[contextType] ?? "";

    const model = createGeminiModel(
      geminiApiKey.value(),
      `Bạn là AI phân tích cuộc trò chuyện tiếng Việt. ${contextHint}`,
      { maxOutputTokens: 1024, temperature: 0.4 },
    );

    try {
      const result = await callGeminiWithRetry(model, `${actionPrompt}\n\n${clean.join("\n")}`);
      return { analysisResult: result.trim(), action, contextType };
    } catch (err) {
      logger.error("[analyzeChatContext]", err);
      throw new HttpsError("internal", "Không thể phân tích ngữ cảnh.");
    }
  },
);

// ─── 6. extractRelationshipMemory ────────────────────────────────────────────
exports.extractRelationshipMemory = onCall(
  { secrets: [geminiApiKey] },
  async (request) => {
    requireAuth(request.auth);
    const { messages, conversationId } = request.data;
    const clean = sanitizeMessages(messages);
    if (clean.length < 3) {
      return { relationshipType: "unknown", sharedTopics: [], importantDates: [] };
    }

    const model = createGeminiModel(
      geminiApiKey.value(),
      "Chuyên gia phân tích mối quan hệ và ngữ cảnh xã hội Việt Nam.",
      { maxOutputTokens: 768, temperature: 0.3 },
    );

    const prompt =
      `Phân tích cuộc trò chuyện và trích xuất thông tin quan hệ.\n` +
      `Trả về JSON:\n` +
      `{"relationshipType":"friend"|"family"|"colleague"|"romantic"|"unknown",` +
      `"sharedTopics":[],"importantDates":[],"memories":[{"category":"...","content":"..."}],` +
      `"communicationStyle":"formal"|"casual"|"mixed","closenessLevel":1-5,` +
      `"healthScore":0-100,"summary":"...","redFlags":[],"positiveSignals":[]}\n\nCuộc trò chuyện:\n${clean.join("\n")}`;

    try {
      const raw = await callGeminiWithRetry(model, prompt);
      const parsed = safeParseJson(raw);
      if (conversationId && parsed) {
        await db.collection("conversations").doc(conversationId).set(
          { relationshipMemory: { ...parsed, updatedAt: FieldValue.serverTimestamp() } },
          { merge: true },
        );
      }
      return parsed ?? { relationshipType: "unknown", sharedTopics: [], importantDates: [] };
    } catch (err) {
      logger.error("[extractRelationshipMemory]", err);
      return { relationshipType: "unknown", sharedTopics: [], importantDates: [] };
    }
  },
);

// ─── 7. suggestReplies ───────────────────────────────────────────────────────
exports.suggestReplies = onCall(
  { secrets: [geminiApiKey] },
  async (request) => {
    requireAuth(request.auth);
    const { messages, tone = "friendly", count = 3, userContext = "" } = request.data;
    const clean = sanitizeMessages(messages);
    if (clean.length === 0) return { suggestions: [] };

    const toneDesc = {
      friendly: "thân thiện, tự nhiên, ấm áp",
      formal: "lịch sự, trang trọng, chuyên nghiệp",
      casual: "vui vẻ, hài hước, Gen Z",
      empathetic: "đồng cảm, chia sẻ, ủng hộ",
      professional: "súc tích, rõ ràng, đúng trọng tâm",
    }[tone] ?? "thân thiện";

    const model = createGeminiModel(
      geminiApiKey.value(),
      "Chuyên gia giao tiếp và viết tin nhắn tiếng Việt.",
      { maxOutputTokens: 512, temperature: 0.8 },
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
      return { suggestions, tone, count };
    } catch (err) {
      logger.error("[suggestReplies]", err);
      return { suggestions: [] };
    }
  },
);

// ─── 8. generateSwipeReplies (Cập nhật phiên bản mới) ────────────────────────
exports.generateSwipeReplies = onCall(
  { secrets: [geminiApiKey] },
  async (request) => {
    requireAuth(request.auth);
    const { incomingMessage, contextMessages, replyStyle = "genz", includeStickerCards = false } = request.data;

    const FALLBACK_TEXT = ["Ok nha", "Thế à?", "Chịu luôn 😂", "Đỉnh!"];
    if (!incomingMessage) {
      return { replies: FALLBACK_TEXT, stickerCards: [] };
    }

    const styleDesc = {
      genz:    "Gen Z Việt Nam, dùng tiếng lóng, emoji vừa phải",
      elder:   "thân thiện, lịch sự, dễ hiểu, không tiếng lóng",
      work:    "chuyên nghiệp, ngắn gọn, lịch sự",
      playful: "vui vẻ, hài hước, emoji nhiều",
    }[replyStyle] ?? "Gen Z Việt Nam";

    const model = createGeminiModel(
      geminiApiKey.value(),
      `Chuyên gia viết tin nhắn ngắn phong cách ${styleDesc}.`,
      { maxOutputTokens: 256, temperature: 0.9 },
      true,
    );

    try {
      const stickerHint = includeStickerCards
        ? '\nNgoài ra thêm "stickers": mảng 0-2 sticker ID phù hợp từ: ["mimi1","mimi2","mimi3","mimi4","mimi5","mimi6","mimi7","mimi8","mimi9"]'
        : "";

      const raw = await callGeminiWithRetry(model,
        `Ngữ cảnh: "${sanitize(contextMessages ?? "", 400)}".\n` +
        `Tin nhắn mới: "${sanitize(incomingMessage, 400)}".\n` +
        `Tạo 4 câu trả lời cực ngắn (dưới 12 chữ), ${styleDesc}, tự nhiên.\n` +
        `Trả về JSON: {"replies":["câu 1","câu 2","câu 3","câu 4"]${stickerHint ? ',"stickers":[]' : ""}}${stickerHint}`,
      );

      const parsed    = safeParseJson(raw);
      const replies   = Array.isArray(parsed?.replies) ? parsed.replies.slice(0, 4) : FALLBACK_TEXT;
      const stickerCards = includeStickerCards && Array.isArray(parsed?.stickers)
        ? parsed.stickers.filter((id) => typeof id === "string" && id.startsWith("mimi")).slice(0, 2)
        : [];

      return { replies, stickerCards };
    } catch (err) {
      logger.error("[generateSwipeReplies]", err);
      return { replies: FALLBACK_TEXT, stickerCards: [] };
    }
  },
);

// ─── 9. generateAutoPilotReply ───────────────────────────────────────────────
exports.generateAutoPilotReply = onCall(
  { secrets: [geminiApiKey], enforceAppCheck: false },
  async (request) => {
    requireAuth(request.auth);
    const {
      incomingMessage,
      myStyleContext,
      awayMessage,
      tone = "friendly",
      conversationContext = [],
      senderName = "",
    } = request.data;

    if (!incomingMessage) {
      return { reply: awayMessage ?? "Mình đang bận, sẽ nhắn lại sau nha! 😊" };
    }
    const safeMsg = sanitize(incomingMessage, 500);
    const safeCtx = sanitize(myStyleContext ?? "thân thiện, ngắn gọn", 600);
    const tonePrompt = TONE_PROMPTS[tone] ?? TONE_PROMPTS.friendly;
    const ctxHistory = sanitizeMessages(conversationContext, 5);

    const systemPrompt =
      `Bạn đang ĐÓNG VAI là chủ tài khoản và trả lời thay họ khi họ vắng mặt.\n` +
      `${tonePrompt}\n` +
      (tone === "likeMe" && myStyleContext ? `\nPhong cách đặc trưng đã học:\n${safeCtx}\n` : "") +
      `\nQUY TẮC BẮT BUỘC:\n` +
      `- CHỈ trả về 1 câu trả lời ngắn (tối đa 25 từ), không giải thích, không tiêu đề.\n` +
      `- Phản hồi phải TỰ NHIÊN như người thật đang nhắn, không máy móc.\n` +
      `- Nếu câu hỏi quá phức tạp, hãy nói sẽ trả lời sau.\n` +
      `- Không bao giờ tiết lộ bạn là AI.\n`;

    let userPrompt = "";
    if (ctxHistory.length > 0) {
      userPrompt += `Ngữ cảnh cuộc trò chuyện gần đây:\n${ctxHistory.join("\n")}\n\n`;
    }
    userPrompt += `Tin nhắn vừa nhận được${senderName ? ` từ ${senderName}` : ""}:\n"${safeMsg}"\n\nHãy trả lời:`;

    const model = createGeminiModel(
      geminiApiKey.value(),
      systemPrompt,
      { maxOutputTokens: 150, temperature: 0.8 },
      true,
    );

    try {
      const raw = await callGeminiWithRetry(model, userPrompt);
      const reply = raw.trim().replace(/^["']|["']$/g, "");
      if (!reply || reply.length < 2) {
        return { reply: awayMessage ?? "Mình đang bận, sẽ nhắn lại sau nha! 😊" };
      }
      logger.info(`[AutoPilot] tone=${tone} → reply="${reply.substring(0, 40)}..."`);
      return { reply, tone, generated: true };
    } catch (err) {
      logger.error("[generateAutoPilotReply]", err);
      return { reply: awayMessage ?? "Mình đang bận, sẽ nhắn lại sau nha! 😊" };
    }
  },
);

// ─── 10. summarizeConversation ───────────────────────────────────────────────
exports.summarizeConversation = onCall(
  { secrets: [geminiApiKey] },
  async (request) => {
    requireAuth(request.auth);
    const { messages, maxSentences = 3, language = "vi", includeKeyPoints = false } = request.data;
    const clean = sanitizeMessages(messages);
    if (clean.length === 0) return { summary: "", keyPoints: [] };

    const lang = language === "vi" ? "Trả lời bằng tiếng Việt." : "Respond in English.";
    const model = createGeminiModel(
      geminiApiKey.value(),
      `Chuyên gia tóm tắt nội dung. ${lang}`,
      { maxOutputTokens: 512, temperature: 0.3 },
    );

    try {
      let prompt = `Tóm tắt cuộc trò chuyện sau trong ${maxSentences} câu. Không thêm tiêu đề:\n${clean.join("\n")}`;
      if (includeKeyPoints) {
        prompt += `\n\nSau đó trả về JSON: {"summary":"...","keyPoints":["điểm 1","điểm 2","điểm 3"]}`;
      }
      const raw = await callGeminiWithRetry(model, prompt);
      if (includeKeyPoints) {
        const parsed = safeParseJson(raw);
        if (parsed) return { summary: parsed.summary ?? raw.trim(), keyPoints: parsed.keyPoints ?? [] };
      }
      return { summary: raw.trim(), keyPoints: [] };
    } catch (err) {
      logger.error("[summarizeConversation]", err);
      throw new HttpsError("internal", "Không thể tóm tắt.");
    }
  },
);

// ─── 11. analyzeSentiment ────────────────────────────────────────────────────
exports.analyzeSentiment = onCall(
  { secrets: [geminiApiKey] },
  async (request) => {
    requireAuth(request.auth);
    const { messages } = request.data;
    const clean = sanitizeMessages(messages);
    if (clean.length === 0) return { sentiment: "neutral", score: 0.5, emoji: "😐", mood: "bình thường" };

    const model = createGeminiModel(
      geminiApiKey.value(),
      "Chuyên gia tâm lý và phân tích cảm xúc. Trả về JSON hợp lệ.",
      { maxOutputTokens: 256, temperature: 0.1 },
      true,
    );

    try {
      const raw = await callGeminiWithRetry(model,
        `Phân tích cảm xúc tổng thể cuộc trò chuyện.\n` +
        `Trả về JSON: {"sentiment":"positive"|"neutral"|"negative","score":0.0-1.0,"emoji":"...","mood":"...","trend":"improving"|"stable"|"declining"}\n\n` +
        `${clean.slice(-10).join("\n")}`,
      );
      return safeParseJson(raw) ?? { sentiment: "neutral", score: 0.5, emoji: "😐", mood: "bình thường" };
    } catch (err) {
      logger.error("[analyzeSentiment]", err);
      return { sentiment: "neutral", score: 0.5, emoji: "😐", mood: "bình thường" };
    }
  },
);

// ─── 12. detectHateSpeech ────────────────────────────────────────────────────
exports.detectHateSpeech = onCall(
  { secrets: [geminiApiKey] },
  async (request) => {
    requireAuth(request.auth);
    const { message } = request.data;
    if (!message) return { isHateful: false, category: "none", confidence: 0 };
    const safeMsg = sanitize(message, 1000);

    if (!quickHateCheck(safeMsg) && safeMsg.length < 20) {
      return { isHateful: false, category: "none", confidence: 0 };
    }

    const model = createGeminiModel(
      geminiApiKey.value(),
      "Chuyên gia kiểm duyệt nội dung số tại Việt Nam. Trả về JSON hợp lệ.",
      { maxOutputTokens: 128, temperature: 0.1 },
      true,
    );

    try {
      const raw = await callGeminiWithRetry(model,
        `Kiểm tra tin nhắn có chứa ngôn ngữ thù ghét, quấy rối, xúc phạm không.\n` +
        `Trả về JSON: {"isHateful":bool,"category":"hate"|"harassment"|"offensive"|"none","confidence":0.0-1.0,"reason":"..."}\n\n` +
        `Tin nhắn: "${safeMsg}"`,
      );
      const parsed = safeParseJson(raw);
      return {
        isHateful: parsed?.isHateful ?? false,
        category: parsed?.category ?? "none",
        confidence: parsed?.confidence ?? 0,
        reason: parsed?.reason ?? null,
      };
    } catch (err) {
      logger.error("[detectHateSpeech]", err);
      return { isHateful: false, category: "none", confidence: 0 };
    }
  },
);

// ─── 13. analyzeCallSecurity ─────────────────────────────────────────────────
exports.analyzeCallSecurity = onCall(
  { secrets: [geminiApiKey] },
  async (request) => {
    requireAuth(request.auth);
    const {
      callTranscript,
      peerId,
      conversationId,
      audioFeatures,
      localDeepfakeScore,
      enrollmentStatus,
    } = request.data;

    if ((localDeepfakeScore || 0) < 0.4 && (!callTranscript || callTranscript.trim() === "")) {
      return { isSafe: true, riskLevel: "LOW", warningMessage: "", confidenceScore: 0 };
    }

    const hasAudioEvidence = audioFeatures && localDeepfakeScore > 0;
    let audioContext = "";
    if (hasAudioEvidence) {
      audioContext = `\nPhân tích acoustic từ thiết bị người dùng:\n- Pitch trung bình: ${audioFeatures.pitchMean?.toFixed(1)}Hz\n- Pitch variance: ${audioFeatures.pitchVariance?.toFixed(1)}Hz (người thật: 15-50Hz)\n- Spectral flatness: ${audioFeatures.spectralFlatness?.toFixed(3)} (thực tế <0.5)\n- Điểm đánh giá Deepfake Local: ${(localDeepfakeScore * 100).toFixed(0)}%\n- Trạng thái nhận diện giọng nói: ${enrollmentStatus || "unknown"}\n`;
    }

    const prompt = `Bạn là hệ thống phân tích an ninh cuộc gọi. Hãy phân tích ngữ cảnh sau để tìm dấu hiệu Lừa Đảo và Deepfake AI:
${audioContext}
Transcript cuộc gọi:
"${callTranscript ? callTranscript.substring(0, 2000) : "(Không có transcript)"}"
Trả về định dạng JSON nghiêm ngặt:
{
 "isSafe": boolean,
 "riskLevel": "LOW"|"MEDIUM"|"HIGH",
 "isDeepfakeVoice": boolean,
 "deepfakeConfidence": 0-100,
 "isScam": boolean,
 "warningMessage": "Thông báo ngắn gọn cho user",
 "confidenceScore": 0-100
}`;

    try {
      const model = createGeminiModel(geminiApiKey.value(), "Chuyên gia bảo mật cuộc gọi.", { maxOutputTokens: 512, temperature: 0.1 });
      const raw = await callGeminiWithRetry(model, prompt);
      const analysis = safeParseJson(raw) || {};
      const cloudDeepfakeScore = (analysis.deepfakeConfidence || 0) / 100;
      const localScore = localDeepfakeScore || 0;

      const combinedScore = (callTranscript && callTranscript.length > 50)
        ? (cloudDeepfakeScore * 0.6 + localScore * 0.4)
        : (localScore * 0.7 + cloudDeepfakeScore * 0.3);

      return {
        ...analysis,
        combinedDeepfakeScore: Math.round(combinedScore * 100),
      };
    } catch (err) {
      logger.error("[analyzeCallSecurity] Error", err);
      return {
        isSafe: (localDeepfakeScore || 0) < 0.5,
        riskLevel: localDeepfakeScore > 0.7 ? "HIGH" : "LOW",
        warningMessage: "Không thể kết nối AI Cloud",
        confidenceScore: Math.round((localDeepfakeScore || 0) * 100),
      };
    }
  },
);

// ─── 14. requestCallToken ────────────────────────────────────────────────────
exports.requestCallToken = onCall(
  { secrets: [agoraAppId, agoraCertificate], enforceAppCheck: false },
  async (request) => {
    requireAuth(request.auth);
    const { channelName, uid = 0 } = request.data;
    if (!channelName) {
      throw new HttpsError("invalid-argument", "channelName là bắt buộc.");
    }
    const appId = agoraAppId.value();
    const appCert = agoraCertificate.value();
    if (!appId || !appCert) {
      logger.error("[requestCallToken] Agora credentials not configured.");
      throw new HttpsError("internal", "Agora credentials chưa cấu hình.");
    }
    try {
      const { token, expiresAt } = buildAgoraToken(channelName, uid, appId, appCert);
      logger.info(`[requestCallToken] Token issued for channel: ${channelName}`);
      return { token, expiresAt, channelName };
    } catch (err) {
      logger.error("[requestCallToken]", err);
      throw new HttpsError("internal", "Không thể tạo token.");
    }
  },
);

// ─── 15. smartReplyWithContext ───────────────────────────────────────────────
exports.smartReplyWithContext = onCall(
  { secrets: [geminiApiKey] },
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
      helpful: "hữu ích, giải quyết vấn đề",
      empathetic: "đồng cảm, lắng nghe, ủng hộ",
      playful: "vui vẻ, hài hước nhẹ nhàng",
      concise: "ngắn gọn, thẳng vào vấn đề",
      elaborate: "chi tiết, giải thích đầy đủ",
    }[replyIntent] ?? "hữu ích";

    const langNote = language === "vi" ? "Trả lời bằng tiếng Việt." : "Respond in English.";
    const profileNote = Object.keys(userProfile).length > 0 ? `\nHồ sơ người dùng: ${JSON.stringify(userProfile)}` : "";

    const model = createGeminiModel(
      geminiApiKey.value(),
      `Bạn là AI trợ lý chat thông minh, ${intentDesc}. ${langNote}`,
      { maxOutputTokens: 512, temperature: 0.7 },
    );

    try {
      const raw = await callGeminiWithRetry(model,
        `${profileNote}\nViết 1 câu trả lời (${intentDesc}, tối đa ${maxLength} chữ) cho cuộc trò chuyện sau.\n` +
        `Chỉ trả về nội dung tin nhắn, không giải thích.\n\n` +
        `${clean.slice(-8).join("\n")}`,
      );
      return {
        reply: raw.trim(),
        intent: replyIntent,
        language,
        charCount: raw.trim().length,
      };
    } catch (err) {
      logger.error("[smartReplyWithContext]", err);
      throw new HttpsError("internal", "Không thể tạo câu trả lời.");
    }
  },
);

// ─── 16. generateIcebreakers ─────────────────────────────────────────────────
exports.generateIcebreakers = onCall(
  { secrets: [geminiApiKey] },
  async (request) => {
    requireAuth(request.auth);
    const {
      sharedInterests = [],
      relationshipType = "friend",
      count = 5,
      style = "casual",
    } = request.data;

    const styleDesc = {
      casual: "thân thiện, nhẹ nhàng",
      playful: "vui vẻ, hài hước",
      deep: "sâu sắc, ý nghĩa",
      work: "chuyên nghiệp, lịch sự",
    }[style] ?? "thân thiện";

    const model = createGeminiModel(
      geminiApiKey.value(),
      "Chuyên gia giao tiếp xã hội Việt Nam.",
      { maxOutputTokens: 512, temperature: 0.9 },
      true,
    );

    try {
      const interestNote = sharedInterests.length > 0 ? `Sở thích chung: ${sharedInterests.slice(0, 5).join(", ")}.` : "";
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
      return { icebreakers: [], style, count };
    }
  },
);

// ─── 17. analyzeToxicityBatch ────────────────────────────────────────────────
exports.analyzeToxicityBatch = onCall(
  {
    secrets: [geminiApiKey],
    memory: "512MiB",
    timeoutSeconds: 120,
  },
  async (request) => {
    requireAuth(request.auth);
    const { messages } = request.data;
    if (!Array.isArray(messages) || messages.length === 0) {
      throw new HttpsError("invalid-argument", "Thiếu messages array.");
    }
    const batch = messages.slice(0, 20).map((m) => ({
      id: m.id ?? null,
      text: sanitize(String(m.text ?? ""), 500),
    })).filter((m) => m.text.length > 0);

    const model = createGeminiModel(
      geminiApiKey.value(),
      "Chuyên gia kiểm duyệt nội dung. Trả về JSON hợp lệ.",
      { maxOutputTokens: 2048, temperature: 0.1 },
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
        return { results: batch.map((_, i) => ({ index: i, isToxic: false, category: "safe", confidence: 0 })) };
      }
      return {
        results: results.map((r) => ({
          ...r,
          id: batch[r.index]?.id ?? null,
        })),
        analyzedCount: batch.length,
      };
    } catch (err) {
      logger.error("[analyzeToxicityBatch]", err);
      return { results: [], analyzedCount: 0 };
    }
  },
);

// ─── 18. generateMessageTone ─────────────────────────────────────────────────
exports.generateMessageTone = onCall(
  { secrets: [geminiApiKey] },
  async (request) => {
    requireAuth(request.auth);
    const { message, fromTone = "auto", toTone, keepEmoji = true } = request.data;
    if (!message || !toTone) {
      throw new HttpsError("invalid-argument", "Thiếu message hoặc toTone.");
    }

    const toneMap = {
      formal: "trang trọng, kính ngữ đầy đủ",
      casual: "thân mật, bình thường",
      professional: "chuyên nghiệp, súc tích",
      friendly: "thân thiện, ấm áp",
      assertive: "quyết đoán, rõ ràng, thẳng thắn",
      soft: "nhẹ nhàng, lịch sự, tránh gây xúc phạm",
      enthusiastic: "nhiệt tình, hào hứng, tích cực",
      empathetic: "đồng cảm, thấu hiểu",
    };
    const targetDesc = toneMap[toTone] ?? toTone;
    const emojiNote = keepEmoji ? "Giữ nguyên emoji." : "Bỏ tất cả emoji.";

    const model = createGeminiModel(
      geminiApiKey.value(),
      "Chuyên gia viết lại nội dung với giọng điệu phù hợp.",
      { maxOutputTokens: 512, temperature: 0.6 },
    );

    try {
      const rewritten = await callGeminiWithRetry(model,
        `Viết lại tin nhắn sau theo giọng điệu ${targetDesc}. ${emojiNote}\n` +
        `Giữ nguyên ý nghĩa, chỉ thay đổi cách diễn đạt.\n` +
        `Chỉ trả về nội dung đã viết lại.\n\n` +
        `Tin nhắn gốc: "${sanitize(message)}"`,
      );
      return {
        original: message,
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

// ─── 19. extractKeyMoments ───────────────────────────────────────────────────
exports.extractKeyMoments = onCall(
  { secrets: [geminiApiKey] },
  async (request) => {
    requireAuth(request.auth);
    const { messages, conversationId } = request.data;
    const clean = sanitizeMessages(messages);
    if (clean.length < 5) return { moments: [], highlights: [] };

    const model = createGeminiModel(
      geminiApiKey.value(),
      "Chuyên gia phân tích và tổng hợp nội dung hội thoại.",
      { maxOutputTokens: 1024, temperature: 0.4 },
    );

    try {
      const raw = await callGeminiWithRetry(model,
        `Phân tích cuộc trò chuyện và trích xuất các khoảnhâm thực đáng nhớ, quan trọng.\n` +
        `Trả về JSON:\n` +
        `{"moments":[{"type":"funny"|"touching"|"important"|"decision","content":"...","timestamp":null}],` +
        `"highlights":["highlight1","highlight2"],"overallVibes":"..."}\n\n` +
        `${clean.join("\n")}`,
      );
      const parsed = safeParseJson(raw) ?? { moments: [], highlights: [] };
      if (conversationId && parsed.moments?.length > 0) {
        await db.collection("conversations").doc(conversationId).set(
          { keyMoments: { ...parsed, extractedAt: FieldValue.serverTimestamp() } },
          { merge: true },
        );
      }
      return parsed;
    } catch (err) {
      logger.error("[extractKeyMoments]", err);
      return { moments: [], highlights: [] };
    }
  },
);

// ─── 20. getUserInsights (Phân Tích Bản Thô - File 1) ────────────────────────
exports.getUserInsights = onCall(
  { secrets: [geminiApiKey], memory: "256MiB", timeoutSeconds: 60 },
  async (request) => {
    requireAuth(request.auth);
    const uid = request.auth.uid;
    const { messages } = request.data;
    if (!Array.isArray(messages) || messages.length < 5) {
      return {
        communicationStyle: "unknown",
        topTopics: [],
        activityPattern: "unknown",
        personalityTraits: [],
        insightSummary: "Chưa đủ dữ liệu để phân tích.",
        emojiUsageLevel: "medium",
        avgMessageLength: "medium",
      };
    }
    const validMessages = messages
      .map((m) => sanitize(String(m ?? ""), 200))
      .filter((m) =>
        m.length > 5 &&
        !m.startsWith('{"iv":') &&
        !m.startsWith("eyJ") &&
        !/^[A-Za-z0-9+/=]+=*:[A-Za-z0-9+/=]+=*$/.test(m),
      );

    if (validMessages.length < 5) {
      return { insightSummary: "Không thể phân tích — dữ liệu không hợp lệ." };
    }

    const model = createGeminiModel(
      geminiApiKey.value(),
      "Chuyên gia tâm lý hành vi và phân tích giao tiếp.",
      { maxOutputTokens: 768, temperature: 0.4 },
    );

    try {
      const raw = await callGeminiWithRetry(model,
        `Phân tích phong cách giao tiếp qua ${validMessages.length} tin nhắn.\n` +
        `Trả về JSON:\n{"communicationStyle":"formal"|"casual"|"mixed",` +
        `"topTopics":[],"activityPattern":"...","personalityTraits":[],` +
        `"insightSummary":"...","emojiUsageLevel":"high"|"medium"|"low",` +
        `"avgMessageLength":"short"|"medium"|"long"}\n\n` +
        `Tin nhắn:\n${validMessages.slice(0, 50).join("\n")}`,
      );
      const insights = safeParseJson(raw);
      if (insights) {
        await db.collection("users").doc(uid).set(
          { aiInsights: { ...insights, updatedAt: FieldValue.serverTimestamp() } },
          { merge: true },
        );
      }
      return insights ?? { insightSummary: "Không thể phân tích lúc này." };
    } catch (err) {
      logger.error("[getUserInsights]", err);
      return { insightSummary: "Đã xảy ra lỗi." };
    }
  },
);

// ─── 20b. getUserInsightsV2 (Phân Tích Có Cache/AI Nâng Cao - File 2) ────────
exports.getUserInsightsV2 = onCall(
  { secrets: [geminiApiKey], timeoutSeconds: 30, memory: "512MiB" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Phải đăng nhập.");
    const { conversationId, messages = [], period = "week7", useAI = false } = request.data;
    const cleanMsgs = filterMessages(messages);
    if (cleanMsgs.length === 0) {
      return { success: false, error: "Không có tin nhắn hợp lệ." };
    }
    const msgObjects = cleanMsgs.map((c) => ({
      content: c,
      timestamp: Date.now(),
      idFrom: uid,
    }));
    let stats = computeLocalStats(msgObjects, period);
    if (!stats) return { success: false, error: "Không đủ dữ liệu." };
    if (useAI) {
      stats = await enrichWithAI(stats, cleanMsgs, period, geminiApiKey.value());
    }
    if (conversationId) {
      const docRef = db
        .collection("users").doc(uid)
        .collection("insights_cache").doc(`dashboard_${conversationId}`);
      await docRef.set({ [period]: stats, lastUpdated: Date.now() }, { merge: true });
    }
    return { success: true, insights: stats };
  }
);

// ─── 21. generateAgoraToken — REST endpoint ──────────────────────────────────
exports.generateAgoraToken = onRequest(
  { secrets: [agoraAppId, agoraCertificate] },
  (req, res) => {
    cors(req, res, () => {
      if (req.method !== "GET") {
        return res.status(405).json({ error: "Method Not Allowed" });
      }
      const channelName = req.query.channelName;
      if (!channelName) {
        return res.status(400).json({ error: "channelName is required" });
      }
      const appId = agoraAppId.value();
      const appCert = agoraCertificate.value();
      if (!appId || !appCert) {
        logger.error("[generateAgoraToken] Agora credentials not configured.");
        return res.status(500).json({ error: "Agora credentials not configured" });
      }
      const uid = req.query.uid ? parseInt(req.query.uid, 10) : 0;
      try {
        const { token, expiresAt } = buildAgoraToken(channelName, uid, appId, appCert);
        res.set("Cache-Control", "no-store");
        return res.status(200).json({ token, expiresAt, channelName });
      } catch (err) {
        logger.error("[generateAgoraToken]", err);
        return res.status(500).json({ error: "Token generation failed" });
      }
    });
  },
);

// ─── 22. healthCheck ──────────────────────────────────────────────────────────
exports.healthCheck = onRequest(
  { timeoutSeconds: 10 },
  (req, res) => {
    cors(req, res, () => {
      return res.status(200).json({
        status: "ok",
        timestamp: new Date().toISOString(),
        region: "asia-southeast1",
        version: "2.1.0",
      });
    });
  },
);

// ─── 23. scheduleMessageDeletion ─────────────────────────────────────────────
exports.scheduleMessageDeletion = onDocumentCreated(
  "messages/{conversationId}/{messageId}",
  async (event) => {
    const { conversationId, messageId } = event.params;
    const messageData = event.data?.data();
    if (!messageData) return;
    try {
      const convSnap = await db.collection("conversations").doc(conversationId).get();
      if (!convSnap.exists) return;
      const convData = convSnap.data();
      if (!convData?.autoDeleteEnabled || !convData?.autoDeleteDuration) return;
      const timestamp = parseInt(messageData.timestamp ?? Date.now().toString());
      const deleteAt = (timestamp + convData.autoDeleteDuration).toString();
      await event.data.ref.update({ autoDeleteAt: deleteAt });
      logger.info(`[scheduleMessageDeletion] Scheduled ${messageId} deleteAt=${deleteAt}`);
    } catch (err) {
      logger.error("[scheduleMessageDeletion]", err);
    }
  },
);

// ─── 24. sendMessageNotification ─────────────────────────────────────────────
exports.sendMessageNotification = onDocumentCreated(
  "messages/{conversationId}/{messageId}",
  async (event) => {
    const { conversationId } = event.params;
    const msgData = event.data?.data();
    if (!msgData || msgData.idFrom === "AI_BOT") return;
    try {
      const [receiverSnap, senderSnap] = await Promise.all([
        db.collection("users").doc(msgData.idTo).get(),
        db.collection("users").doc(msgData.idFrom).get(),
      ]);
      if (!receiverSnap.exists) return;
      const receiverData = receiverSnap.data();
      if (receiverData?.isOnline) return;
      const pushToken = receiverData?.pushToken;
      if (!pushToken) return;

      const senderData = senderSnap.exists ? senderSnap.data() : {};
      const senderName = senderData?.nickname ?? "Ai đó";
      const senderAvatar = senderData?.photoUrl ?? "";

      const typeLabels = { 1: "[Hình ảnh]", 2: "[Video]", 3: "[Tệp đính kèm]", 4: "[Âm thanh]" };
      const messagePreview = msgData.type === 0 ? "Bạn có tin nhắn mới" : (typeLabels[msgData.type] ?? "[Tệp đính kèm]");
      const encryptedContent = msgData.type === 0 ? (msgData.content ?? "") : (typeLabels[msgData.type] ?? "");

      await sendPushNotification({
        pushToken,
        title: senderName,
        body: messagePreview,
        data: {
          conversationId,
          senderId: msgData.idFrom,
          senderName,
          senderAvatar,
          type: "new_message",
          messageType: String(msgData.type ?? 0),
          encryptedContent,
          participantIds: JSON.stringify([msgData.idTo, msgData.idFrom]),
        },
      });
    } catch (err) {
      logger.error("[sendMessageNotification]", err);
    }
  },
);

// ─── 25. updateUserPresence ──────────────────────────────────────────────────
exports.updateUserPresence = onDocumentUpdated(
  "users/{userId}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    if (before.isOnline && !after.isOnline) {
      try {
        await event.data.after.ref.update({ lastSeen: FieldValue.serverTimestamp() });
      } catch (err) {
        logger.error("[updateUserPresence]", err);
      }
    }
  },
);

// ─── 26. onCallCreated ────────────────────────────────────────────────────────
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
        body: `${callData.callerName ?? "Ai đó"} đang gọi cho bạn`,
        data: {
          type: "incoming_call",
          callId: event.params.callId,
          callerId: callData.callerId,
          callerName: callData.callerName ?? "",
          callerAvatar: callData.callerAvatar ?? "",
          callType: String(callData.callType ?? 0),
          channelName: callData.channelName ?? "",
        },
      });
      logger.info(`[onCallCreated] Ring notification sent to ${callData.calleeId}`);
    } catch (err) {
      logger.error("[onCallCreated]", err);
    }
  },
);

// ─── 27. onCallUpdated ────────────────────────────────────────────────────────
exports.onCallUpdated = onDocumentUpdated(
  "calls/{callId}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    if (before.status === after.status) return;

    const { callId } = event.params;
    const notifyUserId = after.status === "connected" ? after.callerId : null;
    if (!notifyUserId) return;

    try {
      const pushToken = await getUserPushToken(notifyUserId);
      if (!pushToken) return;
      const msgMap = {
        connected: "Cuộc gọi đã kết nối ✅",
        declined: "Cuộc gọi bị từ chối ❌",
        missed: "Cuộc gọi nhỡ 📵",
        ended: "Cuộc gọi đã kết thúc",
        busy: "Người dùng đang bận 🔔",
      };
      const body = msgMap[after.status];
      if (!body) return;
      await sendPushNotification({
        pushToken,
        title: "Cuộc gọi",
        body,
        data: { type: "call_status_update", callId, status: after.status },
      });
    } catch (err) {
      logger.error("[onCallUpdated]", err);
    }
  },
);

// ─── 28. cleanupExpiredMessages ──────────────────────────────────────────────
exports.cleanupExpiredMessages = onSchedule(
  { schedule: "every 5 minutes", timeZone: "Asia/Ho_Chi_Minh" },
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
            isDeleted: true,
            content: "",
            deletedAt: FieldValue.serverTimestamp(),
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

// ─── 29. cleanupTypingStatus ─────────────────────────────────────────────────
exports.cleanupTypingStatus = onSchedule(
  { schedule: "every 1 minutes", timeZone: "Asia/Ho_Chi_Minh" },
  async () => {
    const staleThreshold = Date.now() - 5000;
    try {
      const typingDocs = await db.collection("typing_status").get();
      const updates = [];
      for (const doc of typingDocs.docs) {
        const updateObj = {};
        let hasChanges = false;
        for (const [userId, status] of Object.entries(doc.data())) {
          const ts = status?.timestamp?.toMillis?.();
          if (ts && ts < staleThreshold) {
            updateObj[userId] = FieldValue.delete();
            hasChanges = true;
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

// ─── 30. cleanupExpiredStories ───────────────────────────────────────────────
exports.cleanupExpiredStories = onSchedule(
  { schedule: "every 1 hours", timeZone: "Asia/Ho_Chi_Minh" },
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

// ─── 31. cleanupStaleCalls ───────────────────────────────────────────────────
exports.cleanupStaleCalls = onSchedule(
  { schedule: "every 5 minutes", timeZone: "Asia/Ho_Chi_Minh" },
  async () => {
    const cutoff = (Date.now() - CALL_STALE_SEC * 1000).toString();
    try {
      const staleCalls = await db
        .collection("calls")
        .where("status", "in", ["calling", "ringing", "dialing"])
        .where("createdAt", "<=", cutoff)
        .get();
      if (staleCalls.empty) return;
      await batchUpdate(staleCalls.docs, (batch, doc) => {
        batch.update(doc.ref, {
          status: "missed",
          endedAt: Date.now().toString(),
        });
      });
      logger.info(`[cleanupStaleCalls] Marked ${staleCalls.size} calls as missed`);
    } catch (err) {
      logger.error("[cleanupStaleCalls]", err);
    }
  },
);

// ─── 32. cleanupExpiredAiContent ─────────────────────────────────────────────
exports.cleanupExpiredAiContent = onSchedule(
  { schedule: "every 24 hours", timeZone: "Asia/Ho_Chi_Minh" },
  async () => {
    logger.info("[cleanupExpiredAiContent] Starting cleanup...");
    const now = new Date();
    let totalDeleted = 0;
    try {
      const convDocs = await db.collection("ai_content").listDocuments();
      for (const convRef of convDocs) {
        try {
          const convId = convRef.id;
          const expiredDocs = await db
            .collection("ai_content")
            .doc(convId)
            .collection(convId)
            .where("expireAt", "<=", now)
            .limit(500)
            .get();
          if (expiredDocs.empty) continue;
          const batch = db.batch();
          expiredDocs.docs.forEach((doc) => batch.delete(doc.ref));
          await batch.commit();
          totalDeleted += expiredDocs.size;
        } catch (convErr) {
          logger.warn(`[cleanupExpiredAiContent] Error for conv ${convRef.id}:`, convErr);
        }
      }
      logger.info(`[cleanupExpiredAiContent] Deleted ${totalDeleted} expired docs`);
    } catch (err) {
      logger.error("[cleanupExpiredAiContent]", err);
    }
  },
);

// ─── 33. weeklyAiRecap ───────────────────────────────────────────────────────
exports.weeklyAiRecap = onSchedule(
  {
    schedule: "0 20 * * 0",
    timeZone: "Asia/Ho_Chi_Minh",
    secrets: [geminiApiKey],
    memory: "512MiB",
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
        const groupId = groupDoc.id;
        const msgsSnap = await db
          .collection("ai_content")
          .doc(groupId)
          .collection(groupId)
          .where("timestamp", ">=", sevenDaysAgo)
          .orderBy("timestamp", "asc")
          .limit(200)
          .get();
        if (msgsSnap.empty) continue;

        const chatHistory = msgsSnap.docs
          .map((d) => {
            const content = d.data().content ?? "";
            if (content.startsWith('{"iv":') || content.startsWith("eyJ")) return null;
            if (content.trim().length < 5) return null;
            return `${d.data().idFrom}: ${sanitize(content, 200)}`;
          })
          .filter(Boolean)
          .join("\n");

        if (!chatHistory.trim()) continue;

        try {
          const model = createGeminiModel(
            geminiApiKey.value(),
            "Bạn là MC vui nhộn, hài hước, am hiểu văn hóa mạng Việt Nam.",
            { maxOutputTokens: 512, temperature: 0.85 },
          );
          const recap = await callGeminiWithRetry(model,
            `Đây là lịch sử chat nhóm tuần qua. Đóng vai MC vui nhộn, viết bản tin "Bóc Phốt Tuần" ` +
            `dưới 150 chữ: ai nói nhiều nhất, câu nói ấn tượng, trend hài hước, highlight của tuần. ` +
            `Dùng emoji, tiếng lóng Gen Z vừa phải, vui vẻ.\n\nLịch sử:\n${chatHistory}`,
          );

          const recapStructured = await (async () => {
            try {
              const modelJson = createGeminiModel(
                geminiApiKey.value(),
                "Phân tích và trả về JSON hợp lệ.",
                { maxOutputTokens: 256, temperature: 0.2 },
              );
              const rawJson = await callGeminiWithRetry(modelJson,
                `Từ bản tin sau, trích xuất JSON:\n` +
                `{"summary":"...","highlights":["..."],"sentiment":"positive"|"neutral"|"negative"}\n\n` +
                `Bản tin: ${recap.trim()}`,
              );
              return safeParseJson(rawJson) ?? {};
            } catch {
              return {};
            }
          })();

          const recapText = `🔥 BẢN TIN BÓC PHỐT TUẦN 🔥\n\n${recap.trim()}`;
          const msgId = Date.now().toString();
          const batch = db.batch();
          const msgRef = db
            .collection("messages").doc(groupId).collection(groupId).doc(msgId);

          batch.set(msgRef, {
            idFrom: "AI_BOT",
            idTo: groupId,
            timestamp: msgId,
            content: recapText,
            type: 0,
            status: "sent",
          });
          batch.update(groupDoc.ref, {
            lastMessage: recapText.substring(0, 100),
            lastMessageTime: msgId,
            lastMessageType: 0,
          });
          await batch.commit();

          await db.collection("users").doc(groupId).set(
            {
              weeklyRecap: {
                summary: recapStructured.summary ?? recapText,
                highlights: recapStructured.highlights ?? [],
                sentiment: recapStructured.sentiment ?? "neutral",
                fullText: recapText,
                generatedAt: FieldValue.serverTimestamp(),
                weekStart: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString(),
                messageCount: msgsSnap.size,
              },
            },
            { merge: true },
          );
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

// ─── 34. generateWeeklyRecap ─────────────────────────────────────────────────
exports.generateWeeklyRecap = onCall(
  {
    secrets: [geminiApiKey],
    memory: "512MiB",
    timeoutSeconds: 120,
  },
  async (request) => {
    requireAuth(request.auth);
    await checkRateLimit(request.auth.uid, "weekly_recap");
    const {
      conversationId,
      recapStyle = "humorous",
      conversationType = "group",
      lookbackDays = 7,
    } = request.data;
    if (!conversationId) {
      throw new HttpsError("invalid-argument", "Thiếu conversationId.");
    }

    const validStyles = ["humorous", "professional", "romantic", "tv_host", "minimal"];
    const safeStyle = validStyles.includes(recapStyle) ? recapStyle : "humorous";
    const safeDays = Math.min(Math.max(parseInt(lookbackDays) || 7, 1), 30);
    const cutoffTs = (Date.now() - safeDays * 24 * 60 * 60 * 1000).toString();

    let msgsSnap;
    try {
      msgsSnap = await db
        .collection("ai_content")
        .doc(conversationId)
        .collection(conversationId)
        .where("timestamp", ">=", cutoffTs)
        .orderBy("timestamp", "asc")
        .limit(200)
        .get();
    } catch (fetchErr) {
      logger.error("[generateWeeklyRecap] Firestore fetch error:", fetchErr);
      throw new HttpsError("internal", "Lỗi đọc dữ liệu hội thoại.");
    }

    if (msgsSnap.empty) {
      return {
        success: false,
        reason: "no_messages",
        summary: "Chưa có tin nhắn trong khoảng thời gian này.",
        messageCount: 0,
        lookbackDays: safeDays,
      };
    }

    const chatHistory = msgsSnap.docs
      .map((d) => {
        const data = d.data();
        const content = data.content ?? "";
        if (content.startsWith('{"iv":') || content.startsWith("eyJ")) return null;
        if (/^[A-Za-z0-9+/=]+=*:[A-Za-z0-9+/=]+=*$/.test(content)) return null;
        if (content.trim().length < 3) return null;
        const sender = data.idFrom ? `[${String(data.idFrom).substring(0, 6)}]` : "[?]";
        return `${sender}: ${sanitize(content, 250)}`;
      })
      .filter(Boolean)
      .join("\n");

    if (chatHistory.trim().length < 50) {
      return {
        success: false,
        reason: "insufficient_content",
        summary: "Nội dung chat chưa đủ để tạo tóm tắt (cần ít nhất 50 ký tự).",
        messageCount: msgsSnap.size,
        lookbackDays: safeDays,
      };
    }

    const styleConfig = RECAP_STYLE_CONFIGS[safeStyle] ?? RECAP_STYLE_CONFIGS["humorous"];
    const stylePrompt = styleConfig.buildPrompt(chatHistory, conversationType);

    try {
      const model = createGeminiModel(
        geminiApiKey.value(),
        styleConfig.systemPrompt,
        { maxOutputTokens: 700, temperature: 0.85 },
      );
      const recapText = await callGeminiWithRetry(model, stylePrompt);

      const modelJson = createGeminiModel(
        geminiApiKey.value(),
        "Trả về JSON hợp lệ duy nhất, không giải thích thêm.",
        { maxOutputTokens: 512, temperature: 0.2 },
        true,
      );
      const rawJson = await callGeminiWithRetry(modelJson,
        `Từ bản tóm tắt sau, trích xuất JSON với đúng cấu trúc:\n` +
        `{"summary":"(1 câu ngắn nhất mô tả nội dung)","highlights":["điểm 1","điểm 2","điểm 3"],"sentiment":"positive|neutral|negative","topKeywords":["từ1","từ2","từ3"]}\n\n` +
        `Bản tóm tắt:\n${recapText.trim()}`,
      );
      const structured = safeParseJson(rawJson) ?? {};
      logger.info(`[generateWeeklyRecap] ${safeStyle} recap OK for ${conversationId}, ${msgsSnap.size} msgs`);

      return {
        success: true,
        style: safeStyle,
        styleLabel: styleConfig.label,
        styleEmoji: styleConfig.emoji,
        fullText: recapText.trim(),
        summary: structured.summary ?? "",
        highlights: structured.highlights ?? [],
        sentiment: structured.sentiment ?? "neutral",
        topKeywords: structured.topKeywords ?? [],
        messageCount: msgsSnap.size,
        generatedAt: Date.now(),
        conversationType: conversationType,
        lookbackDays: safeDays,
      };
    } catch (geminiErr) {
      logger.error("[generateWeeklyRecap] Gemini error:", geminiErr);
      throw new HttpsError("internal", "AI không thể tạo tóm tắt lúc này. Vui lòng thử lại sau ít phút.");
    }
  },
);

// ─── 35. smartReplyEnhanced — Multi-media smart reply với sticker + tone-aware
exports.smartReplyEnhanced = onCall(
  { secrets: [geminiApiKey], enforceAppCheck: false },
  async (request) => {
    requireAuth(request.auth);
    await checkRateLimit(request.auth.uid, "smart_reply_enhanced");

    const {
      messages,
      closenessLevel = 3,        // 1–5: 1=rất trang trọng, 5=rất thân thiết
      relationshipType = "friend",
      language = "vi",
      count = 3,
    } = request.data;

    const clean = sanitizeMessages(messages);
    if (clean.length === 0) {
      return { suggestions: [], suggestStickers: [], detectedEmotion: "neutral" };
    }

    // ── Tone map theo closeness 1-5 ──────────────────────────────────────
    const toneMap = {
      1: "rất trang trọng, dùng kính ngữ đầy đủ, lịch sự",
      2: "lịch sự, tương đối trang trọng, thân thiện nhẹ",
      3: "thân thiện, tự nhiên, cân bằng",
      4: "thân thiết, thoải mái, có thể dùng tiếng lóng nhẹ và emoji",
      5: "rất thân thiết, suồng sã, vui vẻ phong cách Gen Z Việt Nam",
    };
    const relMap = {
      colleague: "đồng nghiệp hoặc cấp trên",
      friend: "bạn bè thân",
      family: "thành viên gia đình",
      romantic: "người yêu / bạn đời",
      unknown: "người quen mới",
    };
    const toneDesc = toneMap[Math.min(5, Math.max(1, closenessLevel))] ?? toneMap[3];
    const relDesc  = relMap[relationshipType] ?? "người quen";

    // ── Sticker catalog ───────────────────────────────────────────────────
    const STICKER_CATALOG = [
      { id: "mimi1", emotions: ["greeting", "happy", "hello", "chào", "hì"] },
      { id: "mimi2", emotions: ["laugh", "funny", "haha", "vui", "cười"] },
      { id: "mimi3", emotions: ["love", "heart", "cute", "yêu", "thích"] },
      { id: "mimi4", emotions: ["sad", "cry", "sorry", "buồn", "tiếc"] },
      { id: "mimi5", emotions: ["angry", "frustrated", "dislike", "tức", "bực"] },
      { id: "mimi6", emotions: ["surprised", "shocked", "wow", "ngạc nhiên", "ôi"] },
      { id: "mimi7", emotions: ["agree", "thumbsup", "great", "ok", "tốt", "đồng ý"] },
      { id: "mimi8", emotions: ["bye", "wave", "farewell", "tạm biệt", "bye bye"] },
      { id: "mimi9", emotions: ["thinking", "confused", "hmm", "nhỉ", "nhớ"] },
    ];

    const model = createGeminiModel(
      geminiApiKey.value(),
      `Bạn là AI gợi ý trả lời chat cho ứng dụng nhắn tin Việt Nam.\nTông giọng: ${toneDesc}.\nMối quan hệ: ${relDesc}.\nNgôn ngữ chính: ${language === "vi" ? "Tiếng Việt" : "English"}.\nLuôn trả về JSON hợp lệ, không markdown, không giải thích thêm.`,
      { maxOutputTokens: 512, temperature: 0.88 },
    );

    try {
      const lastFive = clean.slice(-5).join("\n");
      const catalogJson = JSON.stringify(STICKER_CATALOG.map((s) => ({ id: s.id, emotions: s.emotions.slice(0, 3) })));

      const prompt =
        `Phân tích đoạn chat sau rồi tạo gợi ý trả lời phong phú.\n\n` +
        `Đoạn chat:\n${lastFive}\n\n` +
        `Sticker khả dụng (chọn 0-2 phù hợp nhất):\n${catalogJson}\n\n` +
        `Trả về JSON (chỉ JSON):\n` +
        `{\n` +
        `  "detectedEmotion": "positive"|"neutral"|"negative"|"question"|"greeting"|"farewell"|"funny",\n` +
        `  "suggestions": [\n` +
        `    {"text":"...", "tone":"casual"|"formal"|"playful"|"empathetic", "confidence":0.0-1.0}\n` +
        `  ],\n` +
        `  "suggestStickers": ["mimi1"]\n` +
        `}\n\n` +
        `Quy tắc:\n` +
        `- Tạo đúng ${count} phần tử trong suggestions, mỗi câu tối đa 15 từ\n` +
        `- suggestions[0]: đúng tông giọng closeness đã cho (${toneDesc})\n` +
        `- suggestions[1]: biến thể khác, vẫn đúng tông giọng\n` +
        `- suggestions[2]: ngắn nhất, dùng emoji nếu closeness >= 4\n` +
        `- Nếu detectedEmotion là greeting/farewell/funny: ưu tiên đề xuất sticker liên quan\n` +
        `- Chỉ đề xuất sticker khi cảm xúc phát hiện khớp rõ ràng\n` +
        `- suggestStickers: tối đa 2 phần tử`;

      const raw    = await callGeminiWithRetry(model, prompt);
      const parsed = safeParseJson(raw);

      if (!parsed) {
        return { suggestions: [], suggestStickers: [], detectedEmotion: "neutral" };
      }

      const suggestions = (Array.isArray(parsed.suggestions) ? parsed.suggestions : [])
        .slice(0, count)
        .filter((s) => s && s.text && s.text.trim().length > 0)
        .map((s) => ({
          text:       String(s.text).trim(),
          tone:       ["casual", "formal", "playful", "empathetic"].includes(s.tone) ? s.tone : "casual",
          confidence: typeof s.confidence === "number" ? Math.max(0, Math.min(1, s.confidence)) : 0.8,
        }));

      const validStickerIds = STICKER_CATALOG.map((s) => s.id);
      const suggestStickers = (Array.isArray(parsed.suggestStickers) ? parsed.suggestStickers : [])
        .filter((id) => validStickerIds.includes(id))
        .slice(0, 2);

      return {
        suggestions,
        suggestStickers,
        detectedEmotion: parsed.detectedEmotion ?? "neutral",
      };
    } catch (err) {
      logger.error("[smartReplyEnhanced]", err);
      return { suggestions: [], suggestStickers: [], detectedEmotion: "neutral" };
    }
  },
);

// ─── 36. dailyConversationDigest ─────────────────────────────────────────────
exports.dailyConversationDigest = onSchedule(
  {
    schedule: "0 8 * * 1-5",
    timeZone: "Asia/Ho_Chi_Minh",
    secrets: [geminiApiKey],
    memory: "512MiB",
    timeoutSeconds: 300,
  },
  async () => {
    logger.info("[dailyConversationDigest] Starting...");
    try {
      const usersSnap = await db
        .collection("users")
        .where("lastSeen", ">=", (Date.now() - 7 * 86_400_000).toString())
        .limit(200)
        .get();
      let sent = 0;
      for (const userDoc of usersSnap.docs) {
        const uid = userDoc.id;
        const pushToken = userDoc.data()?.pushToken;
        if (!pushToken) continue;

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
          body: `Bạn có ${unreadCount} tin nhắn chưa đọc trong ${pendingConvs} cuộc trò chuyện`,
          data: { type: "daily_digest", unreadCount: String(unreadCount) },
        });
        sent++;
      }
      logger.info(`[dailyConversationDigest] Sent to ${sent} users`);
    } catch (err) {
      logger.error("[dailyConversationDigest]", err);
    }
  },
);

// ─── 37. learnUserPersona ────────────────────────────────────────────────────
exports.learnUserPersona = onCall(
  {
    secrets: [geminiApiKey],
    memory: "512MiB",
    timeoutSeconds: 90,
  },
  async (request) => {
    requireAuth(request.auth);
    const uid = request.auth.uid;
    const { messages, conversationId } = request.data;
    const cleanMessages = sanitizeMessages(messages ?? [], 100).filter(
      (m) => !m.startsWith('{"iv":') && !m.startsWith("eyJ") && m.length > 5,
    );

    if (cleanMessages.length < 10) {
      return { success: false, reason: "Cần ít nhất 10 tin nhắn để học phong cách." };
    }

    const model = createGeminiModel(
      geminiApiKey.value(),
      "Bạn là chuyên gia phân tích ngôn ngữ và phong cách giao tiếp. Trả về JSON hợp lệ.",
      { maxOutputTokens: 512, temperature: 0.2 },
    );

    try {
      const raw = await callGeminiWithRetry(model,
        `Phân tích ${cleanMessages.length} tin nhắn sau và trích xuất phong cách giao tiếp của người viết.\n` +
        `Trả về JSON:\n` +
        `{\n` +
        `  "greetingStyle": "cách chào thường dùng",\n` +
        `  "emojiUsage": "none|rare|moderate|heavy",\n` +
        `  "sentenceLength": "very_short|short|medium|long",\n` +
        `  "tone": "formal|casual|playful|warm|direct",\n` +
        `  "characteristicWords": ["từ đặc trưng 1", "từ đặc trưng 2"],\n` +
        `  "typicalOpeners": ["cách mở đầu 1", "cách mở đầu 2"],\n` +
        `  "summary": "Mô tả ngắn phong cách (1-2 câu)"\n` +
        `}\n\n` +
        `Tin nhắn:\n${cleanMessages.slice(0, 60).join("\n")}`,
      );

      let persona;
      try {
        const clean = raw.replace(/```json\s*/gi, "").replace(/```\s*/g, "").trim();
        persona = JSON.parse(clean);
      } catch {
        persona = { summary: raw.substring(0, 300) };
      }

      if (conversationId) {
        await db
          .collection("users")
          .doc(uid)
          .collection("autopilot_config")
          .doc(conversationId)
          .set({
            learnedPersona: JSON.stringify(persona),
            personaLearnedAt: Date.now(),
            personaMessageCount: cleanMessages.length,
            updatedAt: FieldValue.serverTimestamp(),
          }, { merge: true });
      }
      return { success: true, persona, messageCount: cleanMessages.length };
    } catch (err) {
      logger.error("[learnUserPersona]", err);
      return { success: false, reason: "Lỗi AI khi phân tích." };
    }
  },
);

// ─── 38. getAutoPilotConfig ──────────────────────────────────────────────────
exports.getAutoPilotConfig = onCall(
  { enforceAppCheck: false },
  async (request) => {
    requireAuth(request.auth);
    const uid = request.auth.uid;
    const { conversationId } = request.data;
    if (!conversationId) {
      throw new HttpsError("invalid-argument", "Thiếu conversationId.");
    }
    try {
      const doc = await db
        .collection("users")
        .doc(uid)
        .collection("autopilot_config")
        .doc(conversationId)
        .get();
      if (!doc.exists) {
        return { exists: false, config: null };
      }
      return { exists: true, config: doc.data() };
    } catch (err) {
      logger.error("[getAutoPilotConfig]", err);
      throw new HttpsError("internal", "Không thể đọc cấu hình.");
    }
  },
);

// ─── 39. saveAutoPilotConfig ──────────────────────────────────────────────────
exports.saveAutoPilotConfig = onCall(
  { enforceAppCheck: false },
  async (request) => {
    requireAuth(request.auth);
    const uid = request.auth.uid;
    const { conversationId, config } = request.data;
    if (!conversationId || !config) {
      throw new HttpsError("invalid-argument", "Thiếu conversationId hoặc config.");
    }

    const allowedTones = ["friendly", "professional", "funny", "brief", "likeMe"];
    const allowedModes = ["always", "sleepHours", "workHours", "custom"];
    const safeConfig = {
      isEnabled: typeof config.isEnabled === "boolean" ? config.isEnabled : false,
      tone: allowedTones.includes(config.tone) ? config.tone : "friendly",
      scheduleMode: allowedModes.includes(config.scheduleMode) ? config.scheduleMode : "always",
      startHour: Math.max(0, Math.min(23, config.startHour ?? 22)),
      endHour: Math.max(0, Math.min(23, config.endHour ?? 7)),
      awayMessage: sanitize(config.awayMessage ?? "", 200),
      updatedAt: FieldValue.serverTimestamp(),
    };

    try {
      await db
        .collection("users")
        .doc(uid)
        .collection("autopilot_config")
        .doc(conversationId)
        .set(safeConfig, { merge: true });
      return { success: true };
    } catch (err) {
      logger.error("[saveAutoPilotConfig]", err);
      throw new HttpsError("internal", "Không thể lưu cấu hình.");
    }
  },
);

// ─── computeUserInsightsCache (Scheduled 02:00) ──────────────────────────────
exports.computeUserInsightsCache = onSchedule(
  {
    schedule: "0 2 * * *",
    timeZone: "Asia/Ho_Chi_Minh",
    region: "asia-southeast1",
    timeoutSeconds: 540,
    memory: "1GiB",
    secrets: [geminiApiKey],
  },
  async (_event) => {
    console.log("[computeUserInsightsCache] Starting scheduled run...");
    const cutoff90 = Date.now() - 90 * 24 * 60 * 60 * 1000;
    const usersSnap = await db.collection("users").limit(500).get();
    let processed = 0;
    const batchSize = 10;

    for (let i = 0; i < usersSnap.docs.length; i += batchSize) {
      const batch = usersSnap.docs.slice(i, i + batchSize);
      await Promise.all(
        batch.map(async (userDoc) => {
          const uid = userDoc.id;
          try {
            await processUserInsights(uid, cutoff90);
            processed++;
          } catch (e) {
            console.error(`[computeUserInsightsCache] uid=${uid} error:`, e.message);
          }
        })
      );
    }
    console.log(`[computeUserInsightsCache] Done. Processed: ${processed} users.`);
  }
);

async function processUserInsights(uid, cutoff90) {
  const aiContentSnap = await db
    .collection("ai_content")
    .where("userId", "==", uid)
    .where("timestamp", ">=", cutoff90)
    .orderBy("timestamp", "desc")
    .limit(500)
    .get();
  if (aiContentSnap.empty) return;

  const convMap = {};
  for (const doc of aiContentSnap.docs) {
    const d = doc.data();
    const convId = d.conversationId || "default";
    if (!convMap[convId]) convMap[convId] = [];
    convMap[convId].push({
      content: d.content || '',
      timestamp: d.timestamp || Date.now(),
      idFrom: d.idFrom || uid,
    });
  }

  for (const [convId, msgs] of Object.entries(convMap)) {
    const myMsgs = msgs.filter((m) => m.idFrom === uid);
    if (myMsgs.length < 5) continue;
    const periods = ["week7", "days30", "days90"];
    const snapshots = {};

    for (const period of periods) {
      const stats = computeLocalStats(myMsgs, period);
      if (stats) {
        if (period === "week7" && myMsgs.length >= 10) {
          snapshots[period] = await enrichWithAI(
            stats,
            myMsgs.map((m) => m.content),
            period,
            geminiApiKey.value()
          );
        } else {
          snapshots[period] = stats;
        }
      }
    }

    if (Object.keys(snapshots).length > 0) {
      await db
        .collection("users").doc(uid)
        .collection("insights_cache").doc(`dashboard_${convId}`)
        .set({ ...snapshots, lastUpdated: Date.now() }, { merge: true });
    }
  }
}

// ─── getInsightsDashboard ────────────────────────────────────────────────────
exports.getInsightsDashboard = onCall(
  { region: "asia-southeast1", timeoutSeconds: 10, memory: "128MiB" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Phải đăng nhập.");
    const { conversationId, userId } = request.data;
    const targetUid = userId || uid;
    try {
      const doc = await db
        .collection("users").doc(targetUid)
        .collection("insights_cache").doc(`dashboard_${conversationId}`)
        .get();
      if (!doc.exists) return { success: true, dashboard: null };
      return { success: true, dashboard: doc.data() };
    } catch (err) {
      console.error("[getInsightsDashboard] error:", err.message);
      throw new HttpsError("internal", err.message);
    }
  }
);

// ─── triggerInsightsRefresh ──────────────────────────────────────────────────
exports.triggerInsightsRefresh = onCall(
  { region: "asia-southeast1", timeoutSeconds: 60, memory: "512MiB", secrets: [geminiApiKey] },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Phải đăng nhập.");
    const { conversationId, userId } = request.data;
    const targetUid = userId || uid;
    const convId = conversationId;

    const rateLimitDoc = db
      .collection("_rate_limits")
      .doc(`insights_${targetUid}_${convId}`);
    const rateSnap = await rateLimitDoc.get();

    if (rateSnap.exists) {
      const lastRefresh = rateSnap.data().lastRefresh || 0;
      const elapsed = Date.now() - lastRefresh;
      if (elapsed < 60 * 60 * 1000) {
        return {
          success: false,
          message: "Vui lòng chờ thêm trước khi làm mới.",
          retryAfterMs: 60 * 60 * 1000 - elapsed,
        };
      }
    }

    const cutoff90 = Date.now() - 90 * 24 * 60 * 60 * 1000;
    const snap = await db
      .collection("ai_content")
      .where("userId", "==", targetUid)
      .where("conversationId", "==", convId)
      .where("timestamp", ">=", cutoff90)
      .orderBy("timestamp", "desc")
      .limit(500)
      .get();

    const myMsgs = snap.docs
      .map((d) => d.data())
      .filter((d) => d.idFrom === targetUid)
      .map((d) => ({
        content: d.content || "",
        timestamp: d.timestamp || Date.now(),
        idFrom: d.idFrom || targetUid,
      }));

    if (myMsgs.length < 5) {
      return { success: false, message: "Chưa đủ dữ liệu để phân tích." };
    }

    const periods = ["week7", "days30", "days90"];
    const snapshots = {};
    for (const period of periods) {
      const stats = computeLocalStats(myMsgs, period);
      if (stats) {
        snapshots[period] = (period === "week7" && myMsgs.length >= 10)
          ? await enrichWithAI(stats, myMsgs.map((m) => m.content), period, geminiApiKey.value())
          : stats;
      }
    }

    await db
      .collection("users").doc(targetUid)
      .collection("insights_cache").doc(`dashboard_${convId}`)
      .set({ ...snapshots, lastUpdated: Date.now() }, { merge: true });

    await rateLimitDoc.set({ lastRefresh: Date.now() });
    return { success: true, periodsUpdated: Object.keys(snapshots) };
  }
);