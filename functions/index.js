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
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {setGlobalOptions} = require("firebase-functions/v2");
const {defineSecret} = require("firebase-functions/params");
const logger = require("firebase-functions/logger");

const {initializeApp, getApps} = require("firebase-admin/app");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");

// ─── THIRD-PARTY MODULES ──────────────────────────────────────────────────────
const {
  GoogleGenerativeAI,
  HarmCategory,
  HarmBlockThreshold,
} = require("@google/generative-ai");
const {RtcTokenBuilder, RtcRole} = require("agora-access-token");
const cors = require("cors")({origin: true});

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
      type === "personal" ?
        `Đây là cuộc trò chuyện của 2 người bạn trong tuần qua. Viết bản tóm tắt "Bóc Phốt Đôi Bạn" dưới 220 chữ: khoảnh khắc hài tự nhiên, câu nói ấn tượng, những khoảnh khắc đặc biệt. Dùng emoji, tiếng lóng vừa phải, vui nhộn.\n\nChat:\n${chatHistory}` :
        `Đây là lịch sử chat nhóm tuần qua. Đóng vai MC vui nhộn viết bản tin "Bóc Phốt Tuần" dưới 220 chữ: ai nói nhiều nhất, câu nói ấn tượng nhất, trend hài hước nhất, highlight của tuần. Dùng emoji, tiếng lóng Gen Z vừa phải.\n\nChat:\n${chatHistory}`,
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

// ─── ADDED GROUP CALL CONSTANTS ──────────────────────────────────────────────
const GROUP_CALL_TIMEOUT_SEC = 60;
const GROUP_CALL_MAX_PARTICIPANTS = 16;
const GROUP_CALLS_COLLECTION = "group_calls";

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
  _analysisCache.set(key, {value, ts: Date.now()});
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
      {category: HarmCategory.HARM_CATEGORY_HARASSMENT, threshold: HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE},
      {category: HarmCategory.HARM_CATEGORY_HATE_SPEECH, threshold: HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE},
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
  const token = RtcTokenBuilder.buildTokenWithUid(
    appId, appCert, channelName, uid, RtcRole.PUBLISHER, expiresAt,
  );
  return {token, expiresAt};
}

// ─── ADDED GROUP MEMBER TOKENS HELPER ─────────────────────────────────────────
async function getGroupMemberTokens(memberIds) {
  const tokens = [];
  for (const uid of memberIds) {
    try {
      const doc = await db.collection("users").doc(uid).get();
      const token = doc.data()?.pushToken || doc.data()?.fcmToken;
      if (token) tokens.push({ uid, token });
    } catch (_) {}
  }
  return tokens;
}

async function sendPushNotification({pushToken, title, body, data = {}}) {
  if (!pushToken) return;
  try {
    await getMessaging().send({
      token: pushToken,
      notification: {title, body},
      data: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)])),
      android: {priority: "high", notification: {channelId: "chat_messages"}},
      apns: {
        payload: {aps: {contentAvailable: true, sound: "default", badge: 1}},
        headers: {"apns-priority": "10"},
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
    (msg.startsWith("{\"iv\":") || msg.startsWith("eyJ"))
  );
}

function filterMessages(messages) {
  return (messages || []).filter(
    (m) => typeof m === "string" && !isEncrypted(m) && m.trim().length > 2,
  );
}

function periodMs(period) {
  const map = {week7: 7, days30: 30, days90: 90};
  return (map[period] || 7) * 24 * 60 * 60 * 1000;
}

function computeLocalStats(messages, periodKey, now = Date.now()) {
  const cutoff = now - periodMs(periodKey);
  const msgs = messages.filter(
    (m) => m.timestamp >= cutoff && !isEncrypted(m.content || ""),
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
    }),
  );
  const activeDays = days.size;
  const avgMessagesPerDay = Math.round((totalMessages / activeDays) * 10) / 10;

  const emojiRe = /[\u{1F600}-\u{1F64F}\u{1F300}-\u{1F5FF}\u{1F680}-\u{1F6FF}]/gu;
  const emojiCount = contents.reduce(
    (s, c) => s + (c.match(emojiRe) || []).length,
    0,
  );
  const emojiLevel =
    emojiCount > totalMessages * 0.5 ?
      "heavy" :
      emojiCount > totalMessages * 0.2 ?
        "moderate" :
        "minimal";

  const commStyle =
    avgMessageLength < 25 ?
      "concise" :
      avgMessageLength > 80 ?
        "expressive" :
        "balanced";

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
      activityHeatmap.push({dow: d, hour: h, count, intensity: count / maxCount});
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
    for (const w of c.toLowerCase().split(/[\s,.!?\n]+/)) {
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

  const periodLabel = {week7: "7 ngày", days30: "30 ngày", days90: "90 ngày"}[periodKey] || "7 ngày";
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
      generationConfig: {maxOutputTokens: 150, temperature: 0.6},
    });
    const result = await model.generateContent(prompt);
    const aiSummary = result.response.text().trim();
    return {...localStats, aiGeneratedSummary: aiSummary};
  } catch (err) {
    console.error("[enrichWithAI] error:", err.message);
    return localStats;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// ─── CLOUD FUNCTIONS CALLABLE HANDLERS (v2) ──────────────────────────────────
// ═════════════════════════════════════════════════════════════════════════════

// ... [Toàn bộ các handlers callable từ 1 đến 13 giữ nguyên] ...

// ─── 1. analyzeDecryptedMessage ──────────────────────────────────────────────
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
      const model = createGeminiModel(
        geminiApiKey.value(),
        "Bạn là chuyên gia phát hiện lừa đảo trực tuyến tại Việt Nam. Phân tích chính xác, trả về JSON hợp lệ.",
        {maxOutputTokens: 512, temperature: 0.1},
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

// ─── 2. analyzeScam ──────────────────────────────────────────────────────────
exports.analyzeScam = onCall(
  {secrets: [geminiApiKey], enforceAppCheck: false},
  async (request) => {
    requireAuth(request.auth);
    const {message} = request.data;
    if (!message) throw new HttpsError("invalid-argument", "Thiếu message.");
    const safeMsg = sanitize(message);
    if (!safeMsg) return {status: "SAFE", level: "SAFE"};

    const quick = quickScamCheck(safeMsg);
    if (!quick.hasKeywords && safeMsg.length < 30) {
      return {status: "SAFE", level: "SAFE", warningKeywords: []};
    }

    try {
      const model = createGeminiModel(
        geminiApiKey.value(),
        "Chuyên gia phát hiện lừa đảo. Trả về JSON hợp lệ.",
        {maxOutputTokens: 256, temperature: 0.1},
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
  {secrets: [geminiApiKey], enforceAppCheck: false},
  async (request) => {
    requireAuth(request.auth);
    const {plainTextContent, conversationId, messageId, idTo} = request.data;
    if (!plainTextContent) return null;
    const safeText = sanitize(plainTextContent, 500);

    if (safeText.startsWith("{\"iv\":") || safeText.startsWith("eyJ")) {
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
        {maxOutputTokens: 512, temperature: 0.2},
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
  {secrets: [geminiApiKey]},
  async (request) => {
    requireAuth(request.auth);
    await checkRateLimit(request.auth.uid, "translate");
    const {message, targetAudience, preserveEmoji = true} = request.data;
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
      summarize: "Tóm tắt cuộc trò chuyện trong 3 câu ngắn gọn bằng tiếng Việt:",
      suggest: "Gợi ý 3 hành động tiếp theo phù hợp dựa trên nội dung trò chuyện:",
      extract_tasks: "Liệt kê công việc (tasks) và deadline ngắn gọn từ cuộc trò chuyện theo định dạng JSON: [{\"task\":\"...\",\"deadline\":\"...\",\"priority\":\"high|medium|low\"}]",
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

// ─── 6. extractRelationshipMemory ────────────────────────────────────────────
exports.extractRelationshipMemory = onCall(
  {secrets: [geminiApiKey]},
  async (request) => {
    requireAuth(request.auth);
    const {messages, conversationId} = request.data;
    const clean = sanitizeMessages(messages);
    if (clean.length < 3) {
      return {relationshipType: "unknown", sharedTopics: [], importantDates: []};
    }

    const model = createGeminiModel(
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
      const raw = await callGeminiWithRetry(model, prompt);
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

// ─── 7. suggestReplies ───────────────────────────────────────────────────────
exports.suggestReplies = onCall(
  {secrets: [geminiApiKey]},
  async (request) => {
    requireAuth(request.auth);
    const {messages, tone = "friendly", count = 3, userContext = ""} = request.data;
    const clean = sanitizeMessages(messages);
    if (clean.length === 0) return {suggestions: []};

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

// ─── 8. generateSwipeReplies ─────────────────────────────────────────────────
exports.generateSwipeReplies = onCall(
  {secrets: [geminiApiKey]},
  async (request) => {
    requireAuth(request.auth);
    const {incomingMessage, contextMessages, replyStyle = "genz", includeStickerCards = false} = request.data;

    const FALLBACK_TEXT = ["Ok nha", "Thế à?", "Chịu luôn 😂", "Đỉnh!"];
    if (!incomingMessage) {
      return {replies: FALLBACK_TEXT, stickerCards: []};
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
      {maxOutputTokens: 256, temperature: 0.9},
      true,
    );

    try {
      const stickerHint = includeStickerCards ?
        "\nNgoài ra thêm \"stickers\": mảng 0-2 sticker ID phù hợp từ: [\"mimi1\",\"mimi2\",\"mimi3\",\"mimi4\",\"mimi5\",\"mimi6\",\"mimi7\",\"mimi8\",\"mimi9\"]" :
        "";

      const raw = await callGeminiWithRetry(model,
        `Ngữ cảnh: "${sanitize(contextMessages ?? "", 400)}".\n` +
        `Tin nhắn mới: "${sanitize(incomingMessage, 400)}".\n` +
        `Tạo 4 câu trả lời cực ngắn (dưới 12 chữ), ${styleDesc}, tự nhiên.\n` +
        `Trả về JSON: {"replies":["câu 1","câu 2","câu 3","câu 4"]${stickerHint ? ",\"stickers\":[]" : ""}}${stickerHint}`,
      );

      const parsed    = safeParseJson(raw);
      const replies   = Array.isArray(parsed?.replies) ? parsed.replies.slice(0, 4) : FALLBACK_TEXT;
      const stickerCards = includeStickerCards && Array.isArray(parsed?.stickers) ?
        parsed.stickers.filter((id) => typeof id === "string" && id.startsWith("mimi")).slice(0, 2) :
        [];

      return {replies, stickerCards};
    } catch (err) {
      logger.error("[generateSwipeReplies]", err);
      return {replies: FALLBACK_TEXT, stickerCards: []};
    }
  },
);

// ─── 9. generateAutoPilotReply ───────────────────────────────────────────────
exports.generateAutoPilotReply = onCall(
  {secrets: [geminiApiKey], enforceAppCheck: false},
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
      return {reply: awayMessage ?? "Mình đang bận, sẽ nhắn lại sau nha! 😊"};
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
      {maxOutputTokens: 150, temperature: 0.8},
      true,
    );

    try {
      const raw = await callGeminiWithRetry(model, userPrompt);
      const reply = raw.trim().replace(/^["']|["']$/g, "");
      if (!reply || reply.length < 2) {
        return {reply: awayMessage ?? "Mình đang bận, sẽ nhắn lại sau nha! 😊"};
      }
      logger.info(`[AutoPilot] tone=${tone} → reply="${reply.substring(0, 40)}..."`);
      return {reply, tone, generated: true};
    } catch (err) {
      logger.error("[generateAutoPilotReply]", err);
      return {reply: awayMessage ?? "Mình đang bận, sẽ nhắn lại sau nha! 😊"};
    }
  },
);

// ─── 10. summarizeConversation ───────────────────────────────────────────────
exports.summarizeConversation = onCall(
  {secrets: [geminiApiKey]},
  async (request) => {
    requireAuth(request.auth);
    const {messages, maxSentences = 3, language = "vi", includeKeyPoints = false} = request.data;
    const clean = sanitizeMessages(messages);
    if (clean.length === 0) return {summary: "", keyPoints: []};

    const lang = language === "vi" ? "Trả lời bằng tiếng Việt." : "Respond in English.";
    const model = createGeminiModel(
      geminiApiKey.value(),
      `Chuyên gia tóm tắt nội dung. ${lang}`,
      {maxOutputTokens: 512, temperature: 0.3},
    );

    try {
      let prompt = `Tóm tắt cuộc trò chuyện sau trong ${maxSentences} câu. Không thêm tiêu đề:\n${clean.join("\n")}`;
      if (includeKeyPoints) {
        prompt += `\n\nSau đó trả về JSON: {"summary":"...","keyPoints":["điểm 1","điểm 2","điểm 3"]}`;
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

// ─── 11. analyzeSentiment ────────────────────────────────────────────────────
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

// ─── 12. detectHateSpeech ────────────────────────────────────────────────────
exports.detectHateSpeech = onCall(
  {secrets: [geminiApiKey]},
  async (request) => {
    requireAuth(request.auth);
    const {message} = request.data;
    if (!message) return {isHateful: false, category: "none", confidence: 0};
    const safeMsg = sanitize(message, 1000);

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
      return {isHateful: false, category: "none", confidence: 0};
    }
  },
);

// ─── 13. analyzeCallSecurity ─────────────────────────────────────────────────
exports.analyzeCallSecurity = onCall(
  {secrets: [geminiApiKey]},
  async (request) => {
    requireAuth(request.auth);
    const {
      callTranscript,
      audioFeatures,
      localDeepfakeScore,
      enrollmentStatus,
    } = request.data;

    if ((localDeepfakeScore || 0) < 0.4 && (!callTranscript || callTranscript.trim() === "")) {
      return {isSafe: true, riskLevel: "LOW", warningMessage: "", confidenceScore: 0};
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
      const model = createGeminiModel(geminiApiKey.value(), "Chuyên gia bảo mật cuộc gọi.", {maxOutputTokens: 512, temperature: 0.1});
      const raw = await callGeminiWithRetry(model, prompt);
      const analysis = safeParseJson(raw) || {};
      const cloudDeepfakeScore = (analysis.deepfakeConfidence || 0) / 100;
      const localScore = localDeepfakeScore || 0;

      const combinedScore = (callTranscript && callTranscript.length > 50) ?
        (cloudDeepfakeScore * 0.6 + localScore * 0.4) :
        (localScore * 0.7 + cloudDeepfakeScore * 0.3);

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
  {secrets: [agoraAppId, agoraCertificate], enforceAppCheck: false},
  async (request) => {
    requireAuth(request.auth);
    const {channelName, uid = 0} = request.data;
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
      const {token, expiresAt} = buildAgoraToken(channelName, uid, appId, appCert);
      logger.info(`[requestCallToken] Token issued for channel: ${channelName}`);
      return {token, expiresAt, channelName};
    } catch (err) {
      logger.error("[requestCallToken]", err);
      throw new HttpsError("internal", "Không thể tạo token.");
    }
  },
);

// ─── ADDED START/STOP RECORDING FUNCTIONS ─────────────────────────────────────
exports.startGroupCallRecording = onCall(
  {
    secrets: [agoraAppId, agoraCertificate],
    timeoutSeconds: 60,
    memory: "256MiB",
  },
  async (request) => {
    requireAuth(request.auth);
    const { callId, channelName, uid = "0" } = request.data;
    if (!callId || !channelName) {
      throw new HttpsError("invalid-argument", "Thiếu callId hoặc channelName.");
    }

    const appId  = agoraAppId.value();
    const appCert = agoraCertificate.value();

    const customerKey    = process.env.AGORA_CUSTOMER_KEY    || "";
    const customerSecret = process.env.AGORA_CUSTOMER_SECRET || "";

    if (!customerKey || !customerSecret) {
      throw new HttpsError("failed-precondition", "Agora Recording credentials chưa cấu hình.");
    }

    const authHeader = Buffer.from(`${customerKey}:${customerSecret}`).toString("base64");
    const baseUrl    = `https://api.agora.io/v1/apps/${appId}/cloud_recording`;

    try {
      // 1. Acquire resource
      const acquireRes = await fetch(`${baseUrl}/acquire`, {
        method: "POST",
        headers: {
          Authorization: `Basic ${authHeader}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          cname: channelName,
          uid: String(uid),
          clientRequest: {},
        }),
      });
      const acquireData = await acquireRes.json();
      const resourceId  = acquireData.resourceId;
      if (!resourceId) {
        throw new HttpsError("internal", "Không thể acquire recording resource.");
      }

      // 2. Start recording
      const bucket        = process.env.CLOUD_STORAGE_BUCKET || "";
      const storageKey    = process.env.CLOUD_STORAGE_KEY    || "";
      const storageSecret = process.env.CLOUD_STORAGE_SECRET || "";

      const startRes = await fetch(
        `${baseUrl}/resourceid/${resourceId}/mode/mix/start`,
        {
          method: "POST",
          headers: {
            Authorization: `Basic ${authHeader}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            cname: channelName,
            uid: String(uid),
            clientRequest: {
              token: "",
              recordingConfig: {
                maxIdleTime: 30,
                streamTypes: 2,
                channelType: 0,
                videoStreamType: 0,
                transcodingConfig: {
                  width: 1280, height: 720,
                  fps: 24, bitrate: 1500,
                },
              },
              storageConfig: {
                vendor: 1, region: 7,
                bucket,
                accessKey: storageKey,
                secretKey: storageSecret,
                fileNamePrefix: ["call_recordings", channelName],
              },
            },
          }),
        }
      );
      const startData = await startRes.json();
      if (!startData.sid) {
        throw new HttpsError("internal", "Không thể bắt đầu ghi âm.");
      }

      // 3. Cập nhật Firestore
      await db.collection(GROUP_CALLS_COLLECTION).doc(callId).update({
        isRecording: true,
        recordingResourceId: resourceId,
        recordingSid: startData.sid,
        recordingStartedAt: String(Date.now()),
      });

      logger.info(`[startGroupCallRecording] Recording started for ${callId}`);
      return { resourceId, sid: startData.sid };
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      logger.error("[startGroupCallRecording]", err);
      throw new HttpsError("internal", "Lỗi khi bắt đầu ghi âm.");
    }
  }
);

exports.stopGroupCallRecording = onCall(
  { timeoutSeconds: 60, memory: "256MiB" },
  async (request) => {
    requireAuth(request.auth);
    const { callId, resourceId, sid } = request.data;
    if (!callId || !resourceId || !sid) {
      throw new HttpsError("invalid-argument", "Thiếu callId, resourceId hoặc sid.");
    }

    const appId         = agoraAppId.value();
    const customerKey    = process.env.AGORA_CUSTOMER_KEY    || "";
    const customerSecret = process.env.AGORA_CUSTOMER_SECRET || "";
    const authHeader     = Buffer.from(`${customerKey}:${customerSecret}`).toString("base64");

    try {
      const callDoc = await db
        .collection(GROUP_CALLS_COLLECTION).doc(callId).get();
      const channelName = callDoc.data()?.channelName || callId;

      const stopRes = await fetch(
        `https://api.agora.io/v1/apps/${appId}/cloud_recording/resourceid/${resourceId}/sid/${sid}/mode/mix/stop`,
        {
          method: "POST",
          headers: {
            Authorization: `Basic ${authHeader}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            cname: channelName,
            uid: "0",
            clientRequest: {},
          }),
        }
      );
      const stopData = await stopRes.json();
      const fileList = stopData?.serverResponse?.fileList || [];
      const bucket   = process.env.CLOUD_STORAGE_BUCKET || "";
      const recordingUrl = fileList[0]
        ? `https://${bucket}.s3.amazonaws.com/${fileList[0].fileName}`
        : "";

      // Cập nhật Firestore
      await db.collection(GROUP_CALLS_COLLECTION).doc(callId).update({
        isRecording: false,
        recordingUrl,
        recordingFileList: fileList.map((f) => f.fileName),
        recordingStoppedAt: String(Date.now()),
      });

      logger.info(`[stopGroupCallRecording] Done for ${callId}, url=${recordingUrl}`);
      return {
        recordingUrl,
        fileList: fileList.map((f) => f.fileName),
      };
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      logger.error("[stopGroupCallRecording]", err);
      throw new HttpsError("internal", "Lỗi khi dừng ghi âm.");
    }
  }
);

// ─── 15. smartReplyWithContext ───────────────────────────────────────────────
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
      {maxOutputTokens: 512, temperature: 0.7},
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

// ... [Phần còn lại từ 16 đến 25 giữ nguyên] ...

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

// ─── ADDED ON GROUP CALL CREATED FUNCTION ─────────────────────────────────────
exports.onGroupCallCreated = onDocumentCreated(
  `${GROUP_CALLS_COLLECTION}/{callId}`,
  async (event) => {
    const call = event.data?.data();
    if (!call) return;

    const {
      invitedUserIds = [],
      groupName = "Nhóm",
      initiatorName = "Ai đó",
      callType = "video",
    } = call;

    if (!invitedUserIds.length) return;

    const isVideo = callType === "video";
    const callId  = event.params.callId;

    const memberTokens = await getGroupMemberTokens(invitedUserIds);
    if (!memberTokens.length) return;

    const notifications = memberTokens.map(({ uid, token }) =>
      sendPushNotification({
        pushToken: token,
        title: `${isVideo ? "📹" : "📞"} ${groupName}`,
        body: `${initiatorName} đang gọi cho nhóm`,
        data: {
          type: "group_call_invite",
          callId,
          groupName,
          initiatorName,
          isVideo: String(isVideo),
          callType,
        },
      }).catch((e) =>
        logger.warn(`[onGroupCallCreated] FCM fail uid=${uid}:`, e)
      )
    );

    await Promise.allSettled(notifications);
    logger.info(
      `[onGroupCallCreated] Notified ${memberTokens.length} members for call ${callId}`
    );
  }
);

// ─── 27. onCallUpdated ────────────────────────────────────────────────────────
exports.onCallUpdated = onDocumentUpdated(
  "calls/{callId}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
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
        data: {type: "call_status_update", callId, status: after.status},
      });
    } catch (err) {
      logger.error("[onCallUpdated]", err);
    }
  },
);

// ... [Phần 28 đến 30 giữ nguyên] ...

// ─── 31. cleanupStaleCalls ───────────────────────────────────────────────────
exports.cleanupStaleCalls = onSchedule(
  {schedule: "every 5 minutes", timeZone: "Asia/Ho_Chi_Minh"},
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

// ─── ADDED AUTO MISS EXPIRED GROUP CALLS ─────────────────────────────────────
exports.autoMissExpiredGroupCalls = onSchedule(
  { schedule: "every 1 minutes", timeZone: "Asia/Ho_Chi_Minh" },
  async () => {
    const cutoff = String(Date.now() - GROUP_CALL_TIMEOUT_SEC * 1000);
    try {
      const snap = await db
        .collection(GROUP_CALLS_COLLECTION)
        .where("status", "in", ["calling", "waiting"])
        .where("createdAt", "<", cutoff)
        .limit(20)
        .get();

      if (snap.empty) return;

      await batchUpdate(snap.docs, (batch, doc) => {
        batch.update(doc.ref, {
          status: "missed",
          endedAt: String(Date.now()),
          durationSeconds: 0,
          participants: [],
        });
      });

      logger.info(
        `[autoMissExpiredGroupCalls] Marked ${snap.size} group calls as missed`
      );
    } catch (err) {
      logger.error("[autoMissExpiredGroupCalls]", err);
    }
  }
);

// ... [Phần còn lại từ 32 đến hết file giữ nguyên] ...