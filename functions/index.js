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
const {GoogleGenAI} = require("@google/genai");
const {RtcTokenBuilder, RtcRole} = require("agora-access-token");
const crypto = require("crypto");
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
const agoraCustomerKey = defineSecret("AGORA_CUSTOMER_KEY");
const agoraCustomerSecret = defineSecret("AGORA_CUSTOMER_SECRET");
const cloudStorageBucket = defineSecret("CLOUD_STORAGE_BUCKET");
const cloudStorageKey = defineSecret("CLOUD_STORAGE_KEY");
const cloudStorageSecret = defineSecret("CLOUD_STORAGE_SECRET");

// ═════════════════════════════════════════════════════════════════════════════
// ─── GLOBAL CONSTANTS ────────────────────────────────────────────────────────
// ═════════════════════════════════════════════════════════════════════════════
const MODEL_ID = "gemini-2.5-flash";
const MODEL_FLASH_LITE = "gemini-2.5-flash-lite";
const AI_ASSISTANT_ID = "ai_assistant_gemini_001";

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
const RATE_LIMIT_AI_CALLS_PER_MIN = 20;

const GAME_MATCH_TIMEOUT_SEC = 300;
const GAME_MATCHES_COLLECTION = "game_matches";

const GROUP_CALL_TIMEOUT_SEC = 60;
const GROUP_CALLS_COLLECTION = "group_calls";

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

const maskPII = (text) => {
  if (!text) return "";
  return text
    .replace(/(\+84|0)(3[2-9]|5[6-9]|7[06-9]|8[0-9]|9[0-9])\d{7}/g, "[SĐT]")
    .replace(/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/g, "[EMAIL]");
};

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
        tx.set(ref, {
          calls: [{ts: now}],
          updatedAt: now,
          expireAt: new Date(now + 10 * 60 * 1000),
        });
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
      tx.update(ref, {
        calls: recent,
        updatedAt: now,
        expireAt: new Date(now + 10 * 60 * 1000),
      });
    });
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    logger.warn("[checkRateLimit] Transient error:", err);
  }
}

function createGeminiModel(apiKey, systemPrompt, genConfig = {}, lite = false) {
  const ai = new GoogleGenAI({apiKey});
  const modelId = lite ? MODEL_FLASH_LITE : MODEL_ID;

  return {
    generateContent: async (prompt) => {
      const response = await ai.models.generateContent({
        model: modelId,
        contents: prompt,
        config: {
          systemInstruction: systemPrompt,
          temperature: genConfig.temperature ?? 0.5,
          maxOutputTokens: genConfig.maxOutputTokens ?? 1024,
          responseMimeType: genConfig.responseMimeType,
        },
      });
      return {response: {text: () => response.text || ""}};
    },
  };
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
    if (!snap.exists) return null;
    const data = snap.data();
    return data?.pushToken ?? data?.fcmToken ?? null;
  } catch {
    return null;
  }
}

async function getGroupMemberTokens(memberIds) {
  const tokens = [];
  for (const uid of memberIds) {
    try {
      const doc = await db.collection("users").doc(uid).get();
      const token = doc.data()?.pushToken || doc.data()?.fcmToken;
      if (token) tokens.push({uid, token});
    } catch {
      // intentionally ignored
    }
  }
  return tokens;
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

async function enrichWithAI(stats, messages, period, apiKey) {
  if (!messages || messages.length === 0) return stats;
  const model = createGeminiModel(
    apiKey,
    "Chuyên gia phân tích hành vi người dùng. Chỉ trả về JSON hợp lệ, không giải thích.",
    {maxOutputTokens: 256, temperature: 0.3},
  );
  try {
    const raw = await callGeminiWithRetry(model,
      `Dựa trên các chỉ số giao tiếp: ${JSON.stringify(stats)}\n` +
      `Trích xuất 2 điểm nhấn (highlights) về phong cách người dùng.\n` +
      `Trả về định dạng JSON: {"highlights": ["..."]}`,
    );
    const parsed = safeParseJson(raw);
    return {...stats, aiHighlights: parsed?.highlights || []};
  } catch (err) {
    logger.error("[enrichWithAI] Lỗi:", err);
    return stats;
  }
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

// ═════════════════════════════════════════════════════════════════════════════
// ─── CLOUD FUNCTIONS CALLABLE HANDLERS (v2) ──────────────────────────────────
// ═════════════════════════════════════════════════════════════════════════════

// ─── 1. analyzeDecryptedMessage ──────────────────────────────────────────────
exports.analyzeDecryptedMessage = onCall(
  {secrets: [geminiApiKey], enforceAppCheck: true},
  async (request) => {
    requireAuth(request.auth);
    const {plainText, conversationId, messageId, idFrom, idTo} = request.data;
    if (!plainText || !conversationId || !messageId) {
      throw new HttpsError("invalid-argument", "Thiếu plainText, conversationId hoặc messageId.");
    }
    const safeText = sanitize(plainText);
    if (!safeText) return {status: "SAFE", level: "SAFE"};

    const cacheKey = `scam_${crypto.createHash("sha256").update(safeText).digest("hex").substring(0, 16)}`;
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
  {secrets: [geminiApiKey], enforceAppCheck: true},
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
  {secrets: [geminiApiKey], enforceAppCheck: true},
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
        batch.set(msgRef, {
          scamWarning: true,
          scamReason: analysis.scamReason ?? "",
          riskLevel: analysis.riskLevel ?? "MEDIUM",
        }, {merge: true});
        logger.warn(`[analyzeDecryptedClientMessage] Scam in ${messageId}`);
      }

      if (analysis.hasReminder && idTo) {
        const recentWindow = Date.now() - 600000;
        const existingSnap = await db.collection("reminders")
          .where("userId", "==", idTo)
          .where("conversationId", "==", conversationId)
          .where("isAutoGenerated", "==", true)
          .where("createdAt", ">=", new Date(recentWindow))
          .limit(1)
          .get();

        if (existingSnap.empty) {
          let targetReminderTime = Date.now() + 3600000;
          if (analysis.reminderTime) {
            const parsedDate = new Date(analysis.reminderTime);
            if (!isNaN(parsedDate.getTime()) && parsedDate.getTime() > Date.now()) {
              targetReminderTime = parsedDate.getTime();
            }
          }

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
            notificationSent: false,
            reminderTime: targetReminderTime,
            priority: "medium",
            category: "other",
            snoozeCount: 0,
          });
        }
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

    const ALLOWED_ACTIONS = ["summarize", "suggest", "extract_tasks", "analyze_mood", "key_decisions", "action_items"];
    if (!ALLOWED_ACTIONS.includes(action)) {
      throw new HttpsError("invalid-argument", `Hành động phân tích không hợp lệ: ${action}`);
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

    const actionPrompt = actionPrompts[action];
    const contextHint = contextHints[contextType] ?? "";

    const model = createGeminiModel(
      geminiApiKey.value(),
      `Bạn là AI phân tích cuộc trò chuyện tiếng Việt. ${contextHint}`,
      {maxOutputTokens: 1024, temperature: 0.4},
    );

    try {
      const result = await callGeminiWithRetry(model, `${actionPrompt}\n\n${clean.join("\n")}`);

      if (action === "extract_tasks") {
        const parsed = safeParseJson(result);
        return {
          analysisResult: result.trim(),
          parsedTasks: Array.isArray(parsed) ? parsed : [],
          action,
          contextType,
        };
      }

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
        parsed.healthScore = Math.max(0, Math.min(100, parsed.healthScore ?? 50));
        parsed.closenessLevel = Math.max(1, Math.min(5, parsed.closenessLevel ?? 3));

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
    await checkRateLimit(request.auth.uid, "suggest_replies");
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
      const safeContext = userContext ? maskPII(sanitize(userContext, 200)) : "";
      const contextNote = safeContext ? `\nNgữ cảnh người dùng: ${safeContext}` : "";

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
      const schemaStr = includeStickerCards ?
        `{"replies":["câu 1","câu 2","câu 3","câu 4"],"stickers":["mimi1"]}` :
        `{"replies":["câu 1","câu 2","câu 3","câu 4"]}`;

      const stickerInstruction = includeStickerCards ?
        `\nNgoài ra thêm "stickers": mảng 0-2 sticker ID từ danh sách cố định: ["mimi1","mimi2","mimi3","mimi4","mimi5","mimi6","mimi7","mimi8","mimi9"]` :
        "";

      const prompt =
        `Ngữ cảnh: "${sanitize(contextMessages ?? "", 400)}".\n` +
        `Tin nhắn mới: "${sanitize(incomingMessage, 400)}".\n` +
        `Tạo 4 câu trả lời cực ngắn (dưới 12 chữ), ${styleDesc}, tự nhiên.${stickerInstruction}\n` +
        `Trả về JSON: ${schemaStr}`;

      const raw = await callGeminiWithRetry(model, prompt);
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
  {secrets: [geminiApiKey], enforceAppCheck: true},
  async (request) => {
    requireAuth(request.auth);
    const {
      incomingMessage,
      myStyleContext,
      awayMessage,
      tone = "friendly",
      conversationContext = [],
      senderName = "",
      learnedPersona,
    } = request.data;

    if (!incomingMessage) {
      return {reply: awayMessage ?? "Mình đang bận, sẽ nhắn lại sau nha! 😊"};
    }
    const safeMsg = sanitize(incomingMessage, 500);
    const safeCtx = sanitize(learnedPersona ?? myStyleContext ?? "thân thiện, ngắn gọn", 600);
    const tonePrompt = TONE_PROMPTS[tone] ?? TONE_PROMPTS.friendly;
    const ctxHistory = sanitizeMessages(conversationContext, 5);

    const systemPrompt =
      `Bạn đang ĐÓNG VAI là chủ tài khoản và trả lời thay họ khi họ vắng mặt.\n` +
      `${tonePrompt}\n` +
      (tone === "likeMe" && safeCtx ? `\nPhong cách đặc trưng đã học:\n${safeCtx}\n` : "") +
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
      {maxOutputTokens: 512, temperature: 0.3, ...(includeKeyPoints ? {responseMimeType: "application/json"} : {})},
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
    const {callTranscript, audioFeatures, localDeepfakeScore, enrollmentStatus} = request.data;

    if (!callTranscript || callTranscript.trim() === "") {
      const localScore = localDeepfakeScore || 0;
      return {
        isSafe: localScore < 0.5,
        riskLevel: localScore > 0.7 ? "HIGH" : localScore > 0.4 ? "MEDIUM" : "LOW",
        isDeepfakeVoice: localScore > 0.55,
        deepfakeConfidence: Math.round(localScore * 100),
        isScam: false,
        warningMessage: localScore > 0.55 ? "Phát hiện giọng nói bất thường" : "",
        confidenceScore: Math.round(localScore * 100),
        combinedDeepfakeScore: Math.round(localScore * 100),
        source: "local_only",
      };
    }

    const hasAudioEvidence = audioFeatures && localDeepfakeScore > 0;
    let audioContext = "";
    if (hasAudioEvidence) {
      audioContext = `\nPhân tích acoustic từ thiết bị người dùng:\n- Pitch trung bình: ${audioFeatures.pitchMean?.toFixed(1)}Hz\n- Pitch variance: ${audioFeatures.pitchVariance?.toFixed(1)}Hz\n- Điểm đánh giá Deepfake Local: ${(localDeepfakeScore * 100).toFixed(0)}%\n- Trạng thái nhận diện: ${enrollmentStatus || "unknown"}\n`;
    }

    const prompt = `Bạn là hệ thống phân tích an ninh cuộc gọi. Hãy phân tích ngữ cảnh sau để tìm dấu hiệu Lừa Đảo và Deepfake AI:
${audioContext}
Transcript cuộc gọi:
"${callTranscript.substring(0, 2000)}"
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

      const combinedScore = (cloudDeepfakeScore * 0.6 + localScore * 0.4);

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
      throw new HttpsError("failed-precondition", "Agora credentials chưa cấu hình.");
    }
    try {
      const {token, expiresAt} = buildAgoraToken(channelName, uid, appId, appCert);
      return {token, expiresAt, channelName};
    } catch (err) {
      logger.error("[requestCallToken]", err);
      throw new HttpsError("internal", "Không thể tạo token.");
    }
  },
);

// ─── 15. startGroupCallRecording ────────────────────────────────────────────
exports.startGroupCallRecording = onCall(
  {
    secrets: [agoraAppId, agoraCustomerKey, agoraCustomerSecret, cloudStorageBucket, cloudStorageKey, cloudStorageSecret],
    timeoutSeconds: 60,
    memory: "256MiB",
  },
  async (request) => {
    requireAuth(request.auth);
    const {callId, channelName, uid = "0"} = request.data;
    if (!callId || !channelName) {
      throw new HttpsError("invalid-argument", "Thiếu callId hoặc channelName.");
    }

    const appId  = agoraAppId.value();
    const customerKey    = agoraCustomerKey.value();
    const customerSecret = agoraCustomerSecret.value();

    if (!customerKey || !customerSecret) {
      throw new HttpsError("failed-precondition", "Agora Recording credentials chưa cấu hình.");
    }

    const authHeader = Buffer.from(`${customerKey}:${customerSecret}`).toString("base64");
    const baseUrl    = `https://api.agora.io/v1/apps/${appId}/cloud_recording`;

    try {
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

      const bucket        = cloudStorageBucket.value();
      const storageKey    = cloudStorageKey.value();
      const storageSecret = cloudStorageSecret.value();

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
                vendor: 6, region: 0,
                bucket,
                accessKey: storageKey,
                secretKey: storageSecret,
                fileNamePrefix: ["call_recordings", channelName],
              },
            },
          }),
        },
      );
      const startData = await startRes.json();
      if (!startData.sid) {
        throw new HttpsError("internal", "Không thể bắt đầu ghi âm.");
      }

      await db.collection(GROUP_CALLS_COLLECTION).doc(callId).update({
        isRecording: true,
        recordingResourceId: resourceId,
        recordingSid: startData.sid,
        recordingStartedAt: String(Date.now()),
      });

      return {resourceId, sid: startData.sid};
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      logger.error("[startGroupCallRecording]", err);
      throw new HttpsError("internal", "Lỗi khi bắt đầu ghi âm.");
    }
  },
);

// ─── 16. stopGroupCallRecording ─────────────────────────────────────────────
exports.stopGroupCallRecording = onCall(
  {
    timeoutSeconds: 60,
    memory: "256MiB",
    secrets: [agoraAppId, agoraCustomerKey, agoraCustomerSecret, cloudStorageBucket],
  },
  async (request) => {
    requireAuth(request.auth);
    const {callId, resourceId, sid} = request.data;
    if (!callId || !resourceId || !sid) {
      throw new HttpsError("invalid-argument", "Thiếu callId, resourceId hoặc sid.");
    }

    const appId          = agoraAppId.value();
    const customerKey    = agoraCustomerKey.value();
    const customerSecret = agoraCustomerSecret.value();
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
        },
      );
      const stopData = await stopRes.json();
      const fileList = stopData?.serverResponse?.fileList || [];
      const bucket   = cloudStorageBucket.value();
      const recordingUrl = fileList[0] ?
        `https://firebasestorage.googleapis.com/v0/b/${bucket}/o/${encodeURIComponent(fileList[0].fileName)}?alt=media` :
        "";

      await db.collection(GROUP_CALLS_COLLECTION).doc(callId).update({
        isRecording: false,
        recordingUrl,
        recordingFileList: fileList.map((f) => f.fileName),
        recordingStoppedAt: String(Date.now()),
      });

      return {
        recordingUrl,
        fileList: fileList.map((f) => f.fileName),
      };
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      logger.error("[stopGroupCallRecording]", err);
      throw new HttpsError("internal", "Lỗi khi dừng ghi âm.");
    }
  },
);

// ─── 17. smartReplyWithContext ───────────────────────────────────────────────
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

// ─── 18. generateIcebreakers ─────────────────────────────────────────────────
exports.generateIcebreakers = onCall(
  {secrets: [geminiApiKey]},
  async (request) => {
    requireAuth(request.auth);
    const {sharedInterests = [], relationshipType = "friend", count = 5, style = "casual"} = request.data;

    const styleDesc = {
      casual: "thân thiện, nhẹ nhàng",
      playful: "vui vẻ, hài hước",
      deep: "sâu sắc, ý nghĩa",
      work: "chuyên nghiệp, lịch sự",
    }[style] ?? "thân thiện";

    const model = createGeminiModel(
      geminiApiKey.value(),
      "Chuyên gia giao tiếp xã hội Việt Nam.",
      {maxOutputTokens: 512, temperature: 0.9},
      true,
    );

    try {
      const interestNote = sharedInterests.length > 0 ? `Sở thích chung: ${sharedInterests.slice(0, 5).join(", ")}.` : "";
      const raw = await callGeminiWithRetry(model,
        `Tạo ${count} câu mở đầu cuộc trò chuyện (${styleDesc}) cho mối quan hệ "${relationshipType}". ${interestNote}\n` +
        `Trả về JSON mảng: ["câu 1","câu 2",...]`,
      );

      const parsed = safeParseJson(raw);
      let icebreakers = [];
      if (Array.isArray(parsed)) {
        icebreakers = parsed;
      } else if (parsed && Array.isArray(parsed.icebreakers)) {
        icebreakers = parsed.icebreakers;
      } else if (parsed && Array.isArray(parsed.suggestions)) {
        icebreakers = parsed.suggestions;
      }

      return {
        icebreakers: icebreakers.slice(0, count).map(String),
        style,
        count,
      };
    } catch (err) {
      logger.error("[generateIcebreakers]", err);
      return {icebreakers: [], style, count};
    }
  },
);

// ─── 19. analyzeToxicityBatch ────────────────────────────────────────────────
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
    const batch = messages.slice(0, 20).map((m) => ({
      id: m.id ?? null,
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

// ─── 20. generateMessageTone ─────────────────────────────────────────────────
exports.generateMessageTone = onCall(
  {secrets: [geminiApiKey]},
  async (request) => {
    requireAuth(request.auth);
    const {message, fromTone = "auto", toTone, keepEmoji = true} = request.data;
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
      enthusiasm: "nhiệt tình, hào hứng, tích cực",
      empathetic: "đồng cảm, thấu hiểu",
    };
    const targetDesc = toneMap[toTone] ?? toTone;
    const emojiNote = keepEmoji ? "Giữ nguyên emoji." : "Bỏ tất cả emoji.";

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

// ─── 21. extractKeyMoments ───────────────────────────────────────────────────
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
        `Phân tích cuộc trò chuyện và trích xuất các khoảnh khắc đáng nhớ.\n` +
        `Trả về JSON:\n` +
        `{"moments":[{"type":"funny"|"touching"|"important"|"decision","content":"...","messageSnippet":"tin nhắn gốc dưới 50 chữ","approximatePosition":"early"|"middle"|"late"}],` +
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

// ─── 22. getUserInsights (Tương thích ngược V1) ──────────────────────────────
exports.getUserInsights = onCall(
  {secrets: [geminiApiKey], memory: "256MiB", timeoutSeconds: 60},
  async (request) => {
    requireAuth(request.auth);
    const uid = request.auth.uid;
    const {messages} = request.data;
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
        !m.startsWith("{\"iv\":") &&
        !m.startsWith("eyJ") &&
        !/^[A-Za-z0-9+/=]+=*:[A-Za-z0-9+/=]+=*$/.test(m),
      );

    if (validMessages.length < 5) {
      return {insightSummary: "Không thể phân tích — dữ liệu không hợp lệ."};
    }

    const model = createGeminiModel(
      geminiApiKey.value(),
      "Chuyên gia tâm lý hành vi và phân tích giao tiếp.",
      {maxOutputTokens: 768, temperature: 0.4},
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

// ─── 23. getUserInsightsV2 ──────────────────────────────────────────────────
exports.getUserInsightsV2 = onCall(
  {secrets: [geminiApiKey], timeoutSeconds: 30, memory: "512MiB"},
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Phải đăng nhập.");
    const {conversationId, messages = [], period = "week7", useAI = false} = request.data;
    const cleanMsgs = filterMessages(messages);
    if (cleanMsgs.length === 0) {
      return {success: false, error: "Không có tin nhắn hợp lệ."};
    }
    const msgObjects = cleanMsgs.map((c, i) => ({
      content: c,
      timestamp: Date.now() - (cleanMsgs.length - i) * 5 * 60 * 1000,
      idFrom: uid,
    }));
    let stats = computeLocalStats(msgObjects, period);
    if (!stats) return {success: false, error: "Không đủ dữ liệu."};
    if (useAI) {
      stats = await enrichWithAI(stats, cleanMsgs, period, geminiApiKey.value());
    }
    if (conversationId) {
      const docRef = db
        .collection("users").doc(uid)
        .collection("insights_cache").doc(`dashboard_${conversationId}`);
      await docRef.set({[period]: stats, lastUpdated: Date.now()}, {merge: true});
    }
    return {success: true, insights: stats};
  },
);

// ─── 24. getInsightsDashboard ────────────────────────────────────────────────
exports.getInsightsDashboard = onCall(
  {region: "asia-southeast1", timeoutSeconds: 10, memory: "128MiB"},
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Phải đăng nhập.");
    const {conversationId, userId} = request.data;
    const targetUid = userId || uid;
    try {
      const doc = await db
        .collection("users").doc(targetUid)
        .collection("insights_cache").doc(`dashboard_${conversationId}`)
        .get();
      if (!doc.exists) return {success: true, dashboard: null};
      return {success: true, dashboard: doc.data()};
    } catch (err) {
      console.error("[getInsightsDashboard] error:", err.message);
      throw new HttpsError("internal", err.message);
    }
  },
);

// ─── 25. triggerInsightsRefresh ──────────────────────────────────────────────
exports.triggerInsightsRefresh = onCall(
  {region: "asia-southeast1", timeoutSeconds: 60, memory: "512MiB", secrets: [geminiApiKey]},
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Phải đăng nhập.");
    const {conversationId, userId} = request.data;
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
      .doc(convId)
      .collection(convId)
      .where("timestamp", ">=", cutoff90)
      .orderBy("timestamp", "desc")
      .limit(500)
      .get();

    // Lọc bỏ tin nhắn của AI Assistant để không làm nhiễu dữ liệu insights của người dùng
    const myMsgs = snap.docs
      .map((d) => d.data())
      .filter((d) => d.idFrom === targetUid && d.idTo !== AI_ASSISTANT_ID)
      .map((d) => ({
        content:   d.content || "",
        timestamp: parseInt(d.timestamp) || Date.now(),
        idFrom:    d.idFrom || targetUid,
      }));

    if (myMsgs.length < 5) {
      return {success: false, message: "Chưa đủ dữ liệu để phân tích."};
    }

    const periods = ["week7", "days30", "days90"];
    const snapshots = {};
    for (const period of periods) {
      const stats = computeLocalStats(myMsgs, period);
      if (stats) {
        snapshots[period] = (period === "week7" && myMsgs.length >= 10) ?
          await enrichWithAI(stats, myMsgs.map((m) => m.content), period, geminiApiKey.value()) :
          stats;
      }
    }

    await db
      .collection("users").doc(targetUid)
      .collection("insights_cache").doc(`dashboard_${convId}`)
      .set({...snapshots, lastUpdated: Date.now()}, {merge: true});

    await rateLimitDoc.set({lastRefresh: Date.now()});
    return {success: true, periodsUpdated: Object.keys(snapshots)};
  },
);

// ─── 26. learnUserPersona ────────────────────────────────────────────────────
exports.learnUserPersona = onCall(
  {
    secrets: [geminiApiKey],
    memory: "512MiB",
    timeoutSeconds: 90,
  },
  async (request) => {
    requireAuth(request.auth);
    const uid = request.auth.uid;
    const {messages, conversationId} = request.data;
    const cleanMessages = sanitizeMessages(messages ?? [], 100).filter(
      (m) => !m.startsWith("{\"iv\":") && !m.startsWith("eyJ") && m.length > 5,
    );

    if (cleanMessages.length < 10) {
      return {success: false, reason: "Cần ít nhất 10 tin nhắn để học phong cách."};
    }

    const model = createGeminiModel(
      geminiApiKey.value(),
      "Bạn là chuyên gia phân tích ngôn ngữ và phong cách giao tiếp. Trả về JSON hợp lệ.",
      {maxOutputTokens: 512, temperature: 0.2},
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

      let persona = safeParseJson(raw) ?? {summary: raw.substring(0, 300)};

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
          }, {merge: true});
      }
      return {success: true, persona, messageCount: cleanMessages.length};
    } catch (err) {
      logger.error("[learnUserPersona]", err);
      return {success: false, reason: "Lỗi AI khi phân tích."};
    }
  },
);

// ─── 27. getAutoPilotConfig ──────────────────────────────────────────────────
exports.getAutoPilotConfig = onCall(
  {enforceAppCheck: true},
  async (request) => {
    requireAuth(request.auth);
    const uid = request.auth.uid;
    const {conversationId} = request.data;
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
        return {exists: false, config: null};
      }
      return {exists: true, config: doc.data()};
    } catch (err) {
      logger.error("[getAutoPilotConfig]", err);
      throw new HttpsError("internal", "Không thể đọc cấu hình.");
    }
  },
);

// ─── 28. saveAutoPilotConfig ──────────────────────────────────────────────────
exports.saveAutoPilotConfig = onCall(
  {enforceAppCheck: true},
  async (request) => {
    requireAuth(request.auth);
    const uid = request.auth.uid;
    const {conversationId, config} = request.data;
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
        .set(safeConfig, {merge: true});
      return {success: true};
    } catch (err) {
      logger.error("[saveAutoPilotConfig]", err);
      throw new HttpsError("internal", "Không thể lưu cấu hình.");
    }
  },
);

// ─── 29. generateAgoraToken — REST endpoint ──────────────────────────────────
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
      const appId = agoraAppId.value();
      const appCert = agoraCertificate.value();
      if (!appId || !appCert) {
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

// ─── 30. healthCheck ──────────────────────────────────────────────────────────
exports.healthCheck = onRequest(
  {timeoutSeconds: 10},
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

// ═════════════════════════════════════════════════════════════════════════════
// ─── FIRESTORE DB TRIGGERS (v2) ──────────────────────────────────────────────
// ═════════════════════════════════════════════════════════════════════════════

// ─── 31. scheduleMessageDeletion ─────────────────────────────────────────────
exports.scheduleMessageDeletion = onDocumentCreated(
  "messages/{conversationId}/{subId}/{messageId}",
  async (event) => {
    const {conversationId} = event.params;
    const messageData = event.data?.data();
    if (!messageData) return;
    try {
      const convSnap = await db.collection("conversations").doc(conversationId).get();
      if (!convSnap.exists) return;
      const convData = convSnap.data();
      if (!convData?.autoDeleteEnabled || !convData?.autoDeleteDuration) return;

      const timestamp = parseInt(messageData.timestamp ?? Date.now().toString());
      const deleteAt = (timestamp + convData.autoDeleteDuration).toString();
      await event.data.ref.update({autoDeleteAt: deleteAt});
    } catch (err) {
      logger.error("[scheduleMessageDeletion]", err);
    }
  },
);

// ─── 32. sendMessageNotification ─────────────────────────────────────────────
exports.sendMessageNotification = onDocumentCreated(
  "messages/{conversationId}/{subId}/{messageId}",
  async (event) => {
    const {conversationId} = event.params;
    const msgData = event.data?.data();
    if (!msgData || msgData.idFrom === AI_ASSISTANT_ID) return;

    const idFrom       = msgData.idFrom     ?? "";
    const idTo         = msgData.idTo       ?? "";
    const msgType      = msgData.type       ?? 0;
    const msgTimestamp = msgData.timestamp  ?? String(Date.now());

    const TYPE_PREVIEW = {
      1:  "📷 Hình ảnh",
      2:  "🎬 Video",
      3:  "🎤 Tin nhắn thoại",
      4:  "📄 Tài liệu",
      5:  "📄 Tài liệu",
      6:  "📊 Bình chọn",
      10: "😊 Sticker",
      11: "📍 Tin nhắn địa điểm",
    };

    const rawContent = msgType === 0 ?
      String(msgData.content || "") :
      (TYPE_PREVIEW[msgType] ?? "[Tệp đính kèm]");
    const lastMessagePreview = rawContent.substring(0, 100);

    try {
      const convoQuery = await db
        .collection("conversations")
        .where("participants", "array-contains", idFrom)
        .get();

      const convoDoc = convoQuery.docs.find((d) => {
        const parts = d.data().participants || [];
        return parts.includes(idTo);
      });

      if (convoDoc) {
        await convoDoc.ref.set({
          lastMessage:     lastMessagePreview,
          lastMessageTime: msgTimestamp,
          lastMessageType: msgType,
        }, {merge: true});
      } else {
        await db.collection("conversations").doc(conversationId).set({
          lastMessage:     lastMessagePreview,
          lastMessageTime: msgTimestamp,
          lastMessageType: msgType,
          participants:    [idFrom, idTo],
        }, {merge: true});
      }
    } catch (convoErr) {
      logger.warn("[sendMessageNotification] convo update error:", convoErr);
    }

    try {
      const [receiverSnap, senderSnap] = await Promise.all([
        db.collection("users").doc(idTo).get(),
        db.collection("users").doc(idFrom).get(),
      ]);

      if (!receiverSnap.exists) return;
      const receiverData = receiverSnap.data();

      if (receiverData?.chattingWith === idFrom) return;

      const pushToken = receiverData?.pushToken ?? receiverData?.fcmToken;
      if (!pushToken) return;

      const senderData   = senderSnap.exists ? senderSnap.data() : {};
      const senderName   = senderData?.nickname ?? "Ai đó";
      const senderAvatar = senderData?.photoUrl ?? "";

      const notifBody = msgType === 0 ?
        "Bạn có tin nhắn mới" :
        (TYPE_PREVIEW[msgType] ?? "[Tệp đính kèm]");

      const encryptedContent = msgType === 0 ? String(msgData.content ?? "") : "";

      await sendPushNotification({
        pushToken,
        title: senderName,
        body:  notifBody,
        data: {
          conversationId,
          senderId:         idFrom,
          senderName,
          senderAvatar,
          type:             "new_message",
          messageType:      String(msgType),
          encryptedContent,
          participantIds:   JSON.stringify([idTo, idFrom]),
        },
      });
    } catch (err) {
      logger.error("[sendMessageNotification] push error:", err);
    }
  },
);

// ─── 33. updateUserPresence ──────────────────────────────────────────────────
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

// ─── 34. onCallCreated ────────────────────────────────────────────────────────
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
        data: {
          type:         "incoming_call",
          callId:      event.params.callId,
          callerId:    callData.callerId,
          senderId:    callData.callerId,
          userId:      callData.calleeId,
          callerName:  callData.callerName  ?? "",
          callerAvatar: callData.callerAvatar ?? "",
          callType:    String(callData.callType ?? 0),
          channelName: callData.channelName ?? "",
        },
      });
    } catch (err) {
      logger.error("[onCallCreated]", err);
    }
  },
);

// ─── 35. onGroupCallCreated ──────────────────────────────────────────────────
exports.onGroupCallCreated = onDocumentCreated(
  `${GROUP_CALLS_COLLECTION}/{callId}`,
  async (event) => {
    const call = event.data?.data();
    if (!call) return;
    const {
      invitedUserIds = [],
      groupName      = "Nhóm",
      initiatorName  = "Ai đó",
      initiatorId    = "",
      callType       = "video",
    } = call;

    if (!invitedUserIds.length) return;

    const isVideo = callType === "video";
    const callId  = event.params.callId;

    const memberTokens = await getGroupMemberTokens(invitedUserIds);
    if (!memberTokens.length) return;

    const notifications = memberTokens.map(({uid, token}) =>
      sendPushNotification({
        pushToken: token,
        title: `${isVideo ? "📹" : "📞"} ${groupName}`,
        body:  `${initiatorName} đang gọi cho nhóm`,
        data: {
          type:          "group_call_invite",
          callId,
          groupName,
          initiatorName,
          senderId:      initiatorId,
          isVideo:       String(isVideo),
          callType,
        },
      }).catch((e) =>
        logger.warn(`[onGroupCallCreated] FCM fail uid=${uid}:`, e),
      ),
    );

    await Promise.allSettled(notifications);
  },
);

// ─── 36. onCallUpdated ────────────────────────────────────────────────────────
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
        data: {type: "call_status_update", callId, status: after.status},
      });
    } catch (err) {
      logger.error("[onCallUpdated]", err);
    }
  },
);

// ═════════════════════════════════════════════════════════════════════════════
// ─── CRON SCHEDULED TASKS & REMINDERS (v2) ───────────────────────────────────
// ═════════════════════════════════════════════════════════════════════════════

// ─── 37. cleanupExpiredMessages ──────────────────────────────────────────────
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
          .where("isDeleted",    "==", false)
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

// ─── 38. cleanupTypingStatus ─────────────────────────────────────────────────
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

// ─── 39. cleanupExpiredStories ───────────────────────────────────────────────
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
    } catch (err) {
      logger.error("[cleanupExpiredStories]", err);
    }
  },
);

// ─── 40. cleanupStaleCalls ───────────────────────────────────────────────────
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
          status:  "missed",
          endedAt: Date.now().toString(),
        });
      });
    } catch (err) {
      logger.error("[cleanupStaleCalls]", err);
    }
  },
);

// ─── 41. autoMissExpiredGroupCalls ──────────────────────────────────────────
exports.autoMissExpiredGroupCalls = onSchedule(
  {schedule: "every 1 minutes", timeZone: "Asia/Ho_Chi_Minh"},
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
          status:          "missed",
          endedAt:         String(Date.now()),
          durationSeconds: 0,
          participants:    [],
        });
      });
    } catch (err) {
      logger.error("[autoMissExpiredGroupCalls]", err);
    }
  },
);

// ─── 42. autoAbortExpiredGameMatches ────────────────────────────────────────
exports.autoAbortExpiredGameMatches = onSchedule(
  {schedule: "every 1 minutes", timeZone: "Asia/Ho_Chi_Minh"},
  async () => {
    const cutoff = String(Date.now() - GAME_MATCH_TIMEOUT_SEC * 1000);
    try {
      const snap = await db
        .collection(GAME_MATCHES_COLLECTION)
        .where("gameStatus", "==", "waiting")
        .where("createdAt", "<", cutoff)
        .limit(50)
        .get();
      if (snap.empty) return;

      await batchUpdate(snap.docs, (batch, doc) => {
        batch.update(doc.ref, {
          gameStatus:    "aborted",
          gameEndReason: "timeout",
          endedAt:       String(Date.now()),
        });
      });
    } catch (err) {
      logger.error("[autoAbortExpiredGameMatches]", err);
    }
  },
);

// ─── 43. cleanupExpiredAiContent ─────────────────────────────────────────────
exports.cleanupExpiredAiContent = onSchedule(
  {schedule: "every 24 hours", timeZone: "Asia/Ho_Chi_Minh"},
  async () => {
    const now = new Date();
    let totalDeleted = 0;
    try {
      const convDocs = await db.collection("ai_content").listDocuments();
      for (const convRef of convDocs) {
        try {
          const convId = convRef.id;
          const expiredDocs = await db
            .collection("ai_content").doc(convId).collection(convId)
            .where("expireAt", "<=", now)
            .limit(500)
            .get();

          if (expiredDocs.empty) continue;

          const batch = db.batch();
          expiredDocs.docs.forEach((doc) => batch.delete(doc.ref));
          await batch.commit();
          totalDeleted += expiredDocs.size;
        } catch (convErr) {
          logger.warn(`[cleanupExpiredAiContent] Error in conversation ${convRef.id}:`, convErr);
        }
      }
      logger.info(`[cleanupExpiredAiContent] Deleted ${totalDeleted} expired docs`);
    } catch (err) {
      logger.error("[cleanupExpiredAiContent]", err);
    }
  },
);

// ─── 44. weeklyAiRecap (Scheduled) ───────────────────────────────────────────
exports.weeklyAiRecap = onSchedule(
  {
    schedule:       "0 20 * * 0",
    timeZone:       "Asia/Ho_Chi_Minh",
    secrets:        [geminiApiKey],
    memory:         "512MiB",
    timeoutSeconds: 300,
  },
  async () => {
    const sevenDaysAgo = Date.now() - 7 * 24 * 60 * 60 * 1000;
    try {
      const groups = await db
        .collection("conversations")
        .where("isGroup", "==", true)
        .get();
      let recapped = 0;
      for (const groupDoc of groups.docs) {
        const groupId = groupDoc.id;
        const msgsSnap = await db
          .collection("ai_content").doc(groupId).collection(groupId)
          .where("timestamp", ">=", sevenDaysAgo)
          .orderBy("timestamp", "asc")
          .limit(200)
          .get();
        if (msgsSnap.empty) continue;

        const chatHistory = msgsSnap.docs
          .map((d) => {
            const content = d.data().content ?? "";
            if (d.data().idFrom === AI_ASSISTANT_ID) return null;
            if (content.startsWith("{\"iv\":") || content.startsWith("eyJ")) return null;
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
            {maxOutputTokens: 512, temperature: 0.85},
          );
          const recap = await callGeminiWithRetry(model,
            `Đây là lịch sử chat nhóm tuần qua. Đóng vai MC vui nhộn, viết bản tin "Bóc Phốt Tuần" ` +
            `dưới 150 chữ: ai nói nhiều nhất, câu nói ấn tượng, trend hài hước, highlight của tuần. ` +
            `Dùng emoji, tiếng lóng Gen Z vừa phải.\n\nLịch sử:\n${chatHistory}`,
          );

          const recapStructured = await (async () => {
            try {
              const modelJson = createGeminiModel(geminiApiKey.value(), "Phân tích và trả về JSON hợp lệ.", {maxOutputTokens: 256, temperature: 0.2}, true);
              const rawJson = await callGeminiWithRetry(modelJson,
                `Từ bản tin sau, trích xuất JSON:\n` +
                `{"summary":"...","highlights":["..."],"sentiment":"positive"|"neutral"|"negative"}\n\nBản tin: ${recap.trim()}`,
              );
              return safeParseJson(rawJson) ?? {};
            } catch {
              return {};
            }
          })();

          const recapText = `🔥 BẢN TIN BÓC PHỐT TUẦN 🔥\n\n${recap.trim()}`;
          const msgId     = Date.now().toString();
          const batch     = db.batch();
          const msgRef    = db.collection("messages").doc(groupId).collection(groupId).doc(msgId);

          batch.set(msgRef, {
            idFrom: AI_ASSISTANT_ID,
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

          await db.collection("conversations").doc(groupId).set({
            weeklyRecap: {
              summary:      recapStructured.summary ?? recapText,
              highlights:   recapStructured.highlights ?? [],
              sentiment:    recapStructured.sentiment ?? "neutral",
              fullText:     recapText,
              generatedAt:  FieldValue.serverTimestamp(),
              weekStart:    new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString(),
              messageCount: msgsSnap.size,
            },
          }, {merge: true});
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

// ─── 45. extractReminderWithPriority (Callable) ──────────────────────────────
exports.extractReminderWithPriority = onCall(
  {secrets: [geminiApiKey], enforceAppCheck: true},
  async (request) => {
    requireAuth(request.auth);
    await checkRateLimit(request.auth.uid, "extract_reminder");

    const {message = "", conversationContext = ""} = request.data;
    if (!message) throw new HttpsError("invalid-argument", "Thiếu message.");

    const safeMsg = sanitize(message, 600);
    const safeCtx = sanitize(conversationContext, 400);

    const REMINDER_KEYWORDS = [
      "nhắc", "nhớ", "deadline", "hạn chót", "hạn nộp", "cuộc hẹn",
      "họp", "gặp", "gửi", "nộp", "thanh toán", "trả", "mua", "gọi",
      "liên hệ", "xác nhận", "kiểm tra", "follow up", "remind",
    ];

    const lower = safeMsg.toLowerCase();
    const hasContent = REMINDER_KEYWORDS.some((kw) => lower.includes(kw));
    if (!hasContent && safeMsg.length < 25) {
      return {hasReminder: false, reminders: []};
    }

    const cacheKey = `remind_${crypto.createHash("sha256").update(safeMsg).digest("hex").substring(0, 16)}`;
    const cached   = getCached(cacheKey);
    if (cached) return cached;

    try {
      const model = createGeminiModel(
        geminiApiKey.value(),
        "Bạn là trợ lý AI chuyên phân tích tin nhắn để phát hiện tác vụ, lịch hẹn, deadline. Trả về JSON.",
        {maxOutputTokens: 2048, temperature: 0.1},
        true,
      );

      const today = new Date().toLocaleDateString("vi-VN", {
        weekday: "long", year: "numeric", month: "long", day: "numeric",
        timeZone: "Asia/Ho_Chi_Minh",
      });

      const prompt = [
        `Hôm nay là ${today}.`,
        `${safeCtx ? `Ngữ cảnh: "${safeCtx}"` : ""}`,
        `Tin nhắn: "${safeMsg}"`,
        "Trả về JSON dạng: {\"hasReminder\":bool,\"reminders\":[{\"task\":\"...\",\"priority\":\"high|medium|low\",\"reminderTime\":\"ISO 8601 string chuẩn múi giờ Việt Nam\"}]}",
      ].join("\n");

      const raw = await callGeminiWithRetry(model, prompt);
      const parsed = safeParseJson(raw);
      if (!parsed) return {hasReminder: false, reminders: []};

      const reminders = (parsed.reminders || []).map((r) => {
        let finalTime = (Date.now() + 24 * 3600 * 1000).toString();
        if (r.reminderTime) {
          const parsedTime = new Date(r.reminderTime);
          if (!isNaN(parsedTime.getTime())) {
            finalTime = parsedTime.getTime().toString();
          } else {
            logger.warn(`[normalizeTime] Định dạng thời gian không thể xử lý: "${r.reminderTime}"`);
          }
        }
        return {
          task: sanitize(r.task || "", 200),
          priority: ["high", "medium", "low"].includes(r.priority) ? r.priority : "medium",
          reminderTime: finalTime,
        };
      }).filter((r) => r.task.length > 0);

      const result = {hasReminder: reminders.length > 0, reminders};
      setCached(cacheKey, result);
      return result;
    } catch (err) {
      logger.error("[extractReminderWithPriority]", err);
      return {hasReminder: false, reminders: []};
    }
  },
);

// ─── 46. batchExtractReminders (Callable) ────────────────────────────────────
exports.batchExtractReminders = onCall(
  {secrets: [geminiApiKey], memory: "256MiB", timeoutSeconds: 60},
  async (request) => {
    requireAuth(request.auth);
    await checkRateLimit(request.auth.uid, "batch_extract");
    const {messages = []} = request.data;
    if (!Array.isArray(messages) || messages.length === 0) return {reminders: [], processedCount: 0};

    const batch = messages.slice(0, 25).map((m) => ({
      id: m.id || null,
      content: sanitize(String(m.content || ""), 300),
    })).filter((m) => m.content.length >= 8 && !m.content.startsWith("{\"iv\":"));

    if (batch.length === 0) return {reminders: [], processedCount: 0};

    try {
      const model = createGeminiModel(geminiApiKey.value(), "Chuyên gia trích xuất nhắc nhở. Chỉ trả về JSON.", {maxOutputTokens: 2048, temperature: 0.1});
      const today = new Date().toLocaleDateString("vi-VN", {timeZone: "Asia/Ho_Chi_Minh"});
      const formatted = batch.map((m, i) => `[ID:${m.id || i}] ${m.content}`).join("\n");

      const raw = await callGeminiWithRetry(model, `Hôm nay ${today}. Phân tích danh sách tin nhắn sau:\n${formatted}\n\nTrả về JSON dạng {"reminders":[{"messageId":"...","task":"...","priority":"high|medium|low"}]}`);
      const parsed = safeParseJson(raw);
      return {reminders: parsed?.reminders || [], processedCount: batch.length};
    } catch (err) {
      logger.error("[batchExtractReminders]", err);
      return {reminders: [], processedCount: 0};
    }
  },
);

// ─── 47. generateReminderSuggestions (Callable) ──────────────────────────────
exports.generateReminderSuggestions = onCall(
  {secrets: [geminiApiKey], enforceAppCheck: true},
  async (request) => {
    requireAuth(request.auth);
    const {recentMessages = [], existingReminders = [], userContext = ""} = request.data;
    if (recentMessages.length === 0) return {suggestions: []};

    try {
      const model = createGeminiModel(geminiApiKey.value(), "Trợ lý nhắc nhở thông minh.", {maxOutputTokens: 512, temperature: 0.75}, true);
      const safeMessages = sanitizeMessages(recentMessages).slice(0, 10);
      const prompt = `Dựa trên chat sau, gợi ý 3 nhắc nhở cần thiết còn thiếu.\nĐã có: ${JSON.stringify(existingReminders)}\nBối cảnh: ${userContext}\n\nChat:\n${safeMessages.join("\n")}\n\nTrả về JSON: [{"task":"...","priority":"high|medium|low","timeHint":"..."}]`;
      const raw = await callGeminiWithRetry(model, prompt);
      return {suggestions: safeParseJson(raw) || []};
    } catch (err) {
      logger.error("[generateReminderSuggestions]", err);
      return {suggestions: []};
    }
  },
);

// ─── 48. onReminderDue (Scheduled) ───────────────────────────────────────────
exports.onReminderDue = onSchedule(
  {schedule: "* * * * *", timeZone: "Asia/Ho_Chi_Minh"},
  async () => {
    const now = Date.now();
    const windowEnd = (now + 5 * 60 * 1000).toString();
    const windowStart = now.toString();

    try {
      const snap = await db
        .collection("reminders")
        .where("isCompleted",      "==", false)
        .where("notificationSent", "==", false)
        .where("reminderTime",     ">=", parseInt(windowStart))
        .where("reminderTime",     "<=", parseInt(windowEnd))
        .limit(50)
        .get();

      if (snap.empty) return;

      for (const doc of snap.docs) {
        const data = doc.data();

        const pushToken = await getUserPushToken(data.userId);
        if (!pushToken) {
          logger.warn(`[onReminderDue] Không tìm thấy token hợp lệ cho user: ${data.userId}`);
          continue;
        }

        await doc.ref.update({notificationSent: true});

        const priority = data.priority || "medium";
        const badge    = priority === "high" ? "🔴" : priority === "medium" ? "🟡" : "🟢";
        const task     = String(data.task || "").substring(0, 80);

        try {
          await sendPushNotification({
            pushToken,
            title: `${badge} Nhắc nhở công việc sắp tới hạn`,
            body:  task,
            data: {type: "reminder_due", reminderId: doc.id},
          });
        } catch (pushErr) {
          await doc.ref.update({notificationSent: false});
          logger.error(`[onReminderDue] Gửi push thất bại cho doc ${doc.id}:`, pushErr);
        }
      }
    } catch (err) {
      logger.error("[onReminderDue]", err);
    }
  },
);

// ─── 49. cleanupExpiredReminders (Scheduled) ─────────────────────────────────
exports.cleanupExpiredReminders = onSchedule(
  {schedule: "0 3 * * *", timeZone: "Asia/Ho_Chi_Minh"},
  async () => {
    const cutoff = (Date.now() - 7 * 86400000).toString();
    try {
      const oldCompleted = await db.collection("reminders").where("isCompleted", "==", true).where("reminderTime", "<=", cutoff).limit(200).get();
      const oldExpired = await db.collection("reminders").where("isCompleted", "==", false).where("reminderTime", "<=", cutoff).limit(200).get();

      const toDelete = [...oldCompleted.docs, ...oldExpired.docs.filter((d) => (d.data().snoozeCount || 0) <= 3)];
      const batches = [];
      for (let i = 0; i < toDelete.length; i += 400) {
        const b = db.batch();
        toDelete.slice(i, i + 400).forEach((doc) => b.delete(doc.ref));
        batches.push(b.commit());
      }
      await Promise.all(batches);
    } catch (err) {
      logger.error("[cleanupExpiredReminders]", err);
    }
  },
);

// ─── 50. onReminderOverdueDigest (Scheduled) ─────────────────────────────────
exports.onReminderOverdueDigest = onSchedule(
  {schedule: "30 8 * * 1-6", timeZone: "Asia/Ho_Chi_Minh"},
  async () => {
    const now = Date.now();
    const oneDayAgo = (now - 86400000).toString();
    try {
      const snap = await db.collection("reminders").where("isCompleted", "==", false).where("reminderTime", ">=", oneDayAgo).where("reminderTime", "<=", now.toString()).limit(200).get();
      if (snap.empty) return;

      const byUser = {};
      snap.docs.forEach((doc) => {
        const uid = doc.data().userId;
        if (uid) { if (!byUser[uid]) byUser[uid] = []; byUser[uid].push(doc.data()); }
      });

      for (const [uid, reminders] of Object.entries(byUser)) {
        const pushToken = await getUserPushToken(uid);
        if (!pushToken) continue;
        await sendPushNotification({
          pushToken,
          title: `⏰ Tổng hợp việc chưa hoàn thành`,
          body: `Bạn đang có ${reminders.length} nhắc nhở quá hạn cần xử lý.`,
          data: {type: "reminder_digest", overdueCount: String(reminders.length)},
        });
      }
    } catch (err) {
      logger.error("[onReminderOverdueDigest]", err);
    }
  },
);

// ─── 51. dailyConversationDigest (Scheduled) ─────────────────────────────────
exports.dailyConversationDigest = onSchedule(
  {schedule: "0 8 * * 1-5", timeZone: "Asia/Ho_Chi_Minh"},
  async () => {
    try {
      const sevenDaysAgo = new Date(Date.now() - 7 * 86400000);
      const usersSnap = await db.collection("users").where("lastSeen", ">=", sevenDaysAgo).limit(200).get();
      for (const userDoc of usersSnap.docs) {
        const uid = userDoc.id;
        const pushToken = userDoc.data().pushToken ?? userDoc.data().fcmToken;
        if (!pushToken) continue;

        const convSnap = await db.collection("conversations").where("participants", "array-contains", uid).limit(5).get();
        let unreadCount = 0;
        convSnap.docs.forEach((doc) => { unreadCount += (doc.data()[`unread_${uid}`] ?? 0); });

        if (unreadCount > 0) {
          await sendPushNotification({
            pushToken,
            title: "☀️ Tin nhắn chưa đọc đang chờ bạn",
            body: `Bạn có ${unreadCount} tin nhắn chưa xử lý trong hộp thoại.`,
            data: {type: "daily_digest", unreadCount: String(unreadCount)},
          });
        }
      }
    } catch (err) {
      logger.error("[dailyConversationDigest]", err);
    }
  },
);

// ─── 52. smartReplyEnhanced ──────────────────────────────────────────────
exports.smartReplyEnhanced = exports.smartReplyWithContext;

// ─── 53. generateWeeklyRecap (Bổ sung để hỗ trợ gọi thủ công từ Client) ────
exports.generateWeeklyRecap = onCall(
  {secrets: [geminiApiKey], memory: "512MiB", timeoutSeconds: 120},
  async (request) => {
    requireAuth(request.auth);
    const {conversationId, recapStyle = "professional", lookbackDays = 7, conversationType = "personal"} = request.data;
    if (!conversationId) {
      throw new HttpsError("invalid-argument", "Thiếu conversationId.");
    }

    const cutoff = Date.now() - lookbackDays * 24 * 60 * 60 * 1000;

    try {
      const msgsSnap = await db
        .collection("ai_content").doc(conversationId).collection(conversationId)
        .where("timestamp", ">=", cutoff)
        .orderBy("timestamp", "asc")
        .limit(200)
        .get();

      if (msgsSnap.empty) {
        return {success: false, reason: "Không có đủ tin nhắn để tổng hợp trong khoảng thời gian này."};
      }

      const chatHistory = msgsSnap.docs
        .map((d) => {
          const content = d.data().content ?? "";
          if (d.data().idFrom === AI_ASSISTANT_ID) return null;
          if (content.startsWith("{\"iv\":") || content.startsWith("eyJ")) return null;
          if (content.trim().length < 5) return null;
          return `${d.data().idFrom}: ${sanitize(content, 200)}`;
        })
        .filter(Boolean)
        .join("\n");

      if (!chatHistory.trim()) {
        return {success: false, reason: "Dữ liệu trò chuyện không hợp lệ."};
      }

      const config = RECAP_STYLE_CONFIGS[recapStyle] || RECAP_STYLE_CONFIGS["professional"];
      const model = createGeminiModel(
        geminiApiKey.value(),
        config.systemPrompt,
        {maxOutputTokens: 512, temperature: 0.7},
      );

      const recap = await callGeminiWithRetry(model, config.buildPrompt(chatHistory, conversationType));

      const recapStructured = await (async () => {
        try {
          const modelJson = createGeminiModel(geminiApiKey.value(), "Phân tích và trả về JSON hợp lệ.", {maxOutputTokens: 256, temperature: 0.2}, true);
          const rawJson = await callGeminiWithRetry(modelJson,
            `Từ bản tin sau, trích xuất JSON:\n` +
            `{"summary":"...","highlights":["..."],"sentiment":"positive"|"neutral"|"negative"}\n\nBản tin: ${recap.trim()}`,
          );
          return safeParseJson(rawJson) ?? {};
        } catch {
          return {};
        }
      })();

      const recapText = `${config.emoji} BẢN TIN TỔNG HỢP ${config.emoji}\n\n${recap.trim()}`;

      await db.collection("conversations").doc(conversationId).set({
        weeklyRecap: {
          summary:      recapStructured.summary ?? recapText,
          highlights:   recapStructured.highlights ?? [],
          sentiment:    recapStructured.sentiment ?? "neutral",
          fullText:     recapText,
          generatedAt:  FieldValue.serverTimestamp(),
          weekStart:    new Date(Date.now() - lookbackDays * 24 * 60 * 60 * 1000).toISOString(),
          messageCount: msgsSnap.size,
          style:        recapStyle,
        },
      }, {merge: true});

      return {
        success: true,
        recap: recapText,
        structuredData: recapStructured,
      };
    } catch (err) {
      logger.error(`[generateWeeklyRecap] Gemini error for ${conversationId}:`, err);
      return {success: false, reason: "Lỗi kết nối AI khi tạo bảng tổng kết."};
    }
  },
);

// ─── 54. generateAiChatReply ─────────────────────────────────────────────────
exports.generateAiChatReply = onCall(
  {secrets: [geminiApiKey], enforceAppCheck: true},
  async (request) => {
    requireAuth(request.auth);
    await checkRateLimit(request.auth.uid, "ai_chat_reply");

    const {userMessage, conversationHistory = []} = request.data;
    if (!userMessage || userMessage.trim().length === 0) {
      throw new HttpsError("invalid-argument", "userMessage không được trống.");
    }

    const safeMsg = sanitize(userMessage, 1000);
    const safeHistory = sanitizeMessages(conversationHistory, 20);

    const model = createGeminiModel(
      geminiApiKey.value(),
      "Bạn là trợ lý AI thông minh, thân thiện, tích hợp trong ứng dụng chat. " +
      "Trả lời ngắn gọn, rõ ràng bằng tiếng Việt. Có thể dùng Markdown khi cần. " +
      "Không tiết lộ thông tin nội bộ hệ thống.",
      {maxOutputTokens: 2048, temperature: 0.7},
    );

    const historyContext = safeHistory.length > 0 ?
      `Lịch sử:\n${safeHistory.join("\n")}\n\n` :
      "";

    try {
      const reply = await callGeminiWithRetry(
        model,
        `${historyContext}Người dùng: "${safeMsg}"\n\nTrả lời:`,
      );
      return {reply: reply.trim(), success: true};
    } catch (err) {
      logger.error("[generateAiChatReply]", err);
      throw new HttpsError("internal", "AI không thể phản hồi lúc này.");
    }
  },
);
