// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/models.dart';
import '../services/services.dart';

export '../services/ai_backend_service.dart' show AIBackendService;

// ─────────────────────────────────────────────────────────────────────────────
// AI CACHE — Tránh gọi AI nhiều lần cho cùng một ngữ cảnh message
// ─────────────────────────────────────────────────────────────────────────────

class _AiReplyCache {
  final Map<String, _CacheEntry> _cache = {};
  static const _maxEntries = 50;
  static const _ttl = Duration(minutes: 5);

  List<SmartReply>? get(String key) {
    final entry = _cache[key];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.timestamp) > _ttl) {
      _cache.remove(key);
      return null;
    }
    return entry.replies;
  }

  void put(String key, List<SmartReply> replies) {
    if (_cache.length >= _maxEntries) {
      // Evict oldest entry
      final oldest = _cache.entries.reduce(
          (a, b) => a.value.timestamp.isBefore(b.value.timestamp) ? a : b);
      _cache.remove(oldest.key);
    }
    _cache[key] = _CacheEntry(replies, DateTime.now());
  }

  void clear() => _cache.clear();
}

class _CacheEntry {
  final List<SmartReply> replies;
  final DateTime timestamp;
  const _CacheEntry(this.replies, this.timestamp);
}

// ── Enhanced Cache ───────────────────────────────────────────────────────────

class _EnhancedCache {
  final Map<String, _EnhancedEntry> _cache = {};
  static const _maxEntries = 50;
  static const _ttl = Duration(minutes: 5);

  EnhancedSmartReplyResult? get(String key) {
    final e = _cache[key];
    if (e == null) return null;
    if (DateTime.now().difference(e.timestamp) > _ttl) {
      _cache.remove(key);
      return null;
    }
    return e.result;
  }

  void put(String key, EnhancedSmartReplyResult result) {
    if (_cache.length >= _maxEntries) {
      final oldest = _cache.entries.reduce(
          (a, b) => a.value.timestamp.isBefore(b.value.timestamp) ? a : b);
      _cache.remove(oldest.key);
    }
    _cache[key] = _EnhancedEntry(result, DateTime.now());
  }

  void clear() => _cache.clear();
}

class _EnhancedEntry {
  final EnhancedSmartReplyResult result;
  final DateTime timestamp;
  const _EnhancedEntry(this.result, this.timestamp);
}

// ─────────────────────────────────────────────────────────────────────────────
// SMART REPLY PROVIDER
// ─────────────────────────────────────────────────────────────────────────────

class SmartReplyProvider {
  static const int maxReplies = 3;

  final _AiReplyCache _cache = _AiReplyCache();
  final _EnhancedCache _enhancedCache = _EnhancedCache();

  // ═══════════════════════════════════════════════════════════════════════════
  // ENHANCED API — Multi-media + Tone-aware
  // ═══════════════════════════════════════════════════════════════════════════

  /// Entry point chính cho Enhanced Mode — trả về EnhancedSmartReplyResult gồm cả text và stickers.
  /// Tự động fallback về rule-based nếu AI thất bại hoặc gặp lỗi kết nối.
  Future<EnhancedSmartReplyResult> getEnhancedSmartReplies({
    required String lastMessage,
    required List<String> recentMessages,
    int closenessLevel = 3,
    String relationshipType = 'friend',
    String language = 'vi',
    int count = 3,
  }) async {
    if (lastMessage.trim().isEmpty) return EnhancedSmartReplyResult.empty();

    final cacheKey = _buildEnhancedCacheKey(
        lastMessage, recentMessages, closenessLevel, relationshipType);
    final cached = _enhancedCache.get(cacheKey);
    if (cached != null) {
      _log('Enhanced cache hit');
      return cached;
    }

    // ── Thử AI Backend ────────────────────────────────────────────────────
    try {
      final result = await AIBackendService().smartReplyEnhanced(
        messages: recentMessages.take(6).toList(),
        closenessLevel: closenessLevel,
        relationshipType: relationshipType,
        language: language,
        count: count,
      );

      if (result != null && result.isNotEmpty) {
        _enhancedCache.put(cacheKey, result);
        _log('Enhanced AI reply: ${result.suggestions.length} texts, '
            '${result.suggestStickers.length} stickers');
        return result;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[SmartReplyProvider] Enhanced AI error: $e');
    }

    // ── Fallback rule-based ───────────────────────────────────────────────
    final ruleReplies = getRuleBasedReplies(lastMessage);
    final fallback = EnhancedSmartReplyResult.fromLegacy(ruleReplies);
    _log('Enhanced fallback to rule-based (${ruleReplies.length} replies)');
    return fallback;
  }

  /// Lấy dữ liệu phân tích nâng cao từ LocalDB conversation (E2EE-safe).
  Future<EnhancedSmartReplyResult> getEnhancedSmartRepliesFromConversation({
    required String conversationId,
    required String currentUserId,
    int closenessLevel = 3,
    String relationshipType = 'friend',
  }) async {
    final messages = LocalDbService().getMessages(conversationId);
    if (messages.isEmpty) return EnhancedSmartReplyResult.empty();

    final last = messages.first;
    if (last['idFrom'] == currentUserId)
      return EnhancedSmartReplyResult.empty();
    if (last['type'] != 0) return EnhancedSmartReplyResult.empty();

    final content = last['content'] as String? ?? '';
    if (content.isEmpty || content.startsWith('{"iv":')) {
      return EnhancedSmartReplyResult.empty();
    }

    final history = messages
        .take(6)
        .map((m) => m['content']?.toString() ?? '')
        .where((c) => c.isNotEmpty && !c.startsWith('{"iv":'))
        .toList()
        .reversed
        .toList();

    return getEnhancedSmartReplies(
      lastMessage: content,
      recentMessages: history,
      closenessLevel: closenessLevel,
      relationshipType: relationshipType,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LEGACY API — Dùng List<SmartReply> (Giữ tương thích ngược hoàn chỉnh)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Entry point chính cho luồng xử lý Legacy cũ.
  Future<List<SmartReply>> getSmartReplies({
    required String message,
    List<String>? conversationHistory,
    String? anthropicApiKey,
  }) async {
    final ruleReplies = getRuleBasedReplies(message);
    if (ruleReplies.isNotEmpty) return ruleReplies;

    if (conversationHistory != null && conversationHistory.isNotEmpty) {
      final contextReplies =
          getContextAwareReplies(message, conversationHistory);
      if (contextReplies.isNotEmpty) return contextReplies;
    }

    if (anthropicApiKey != null && anthropicApiKey.isNotEmpty) {
      final aiReplies = await getAnthropicReplies(
        message: message,
        apiKey: anthropicApiKey,
        conversationHistory: conversationHistory,
      );
      if (aiReplies.isNotEmpty) return aiReplies;
    }

    return _fallbackReplies;
  }

  /// AI smart reply sử dụng tích hợp Typed endpoint và luồng map chuỗi ký tự.
  Future<List<SmartReply>> getAiSmartReplies({
    required String lastMessage,
    required List<String> recentMessages,
    String language = 'vi',
    String replyIntent = 'helpful',
  }) async {
    if (lastMessage.trim().isEmpty) return [];

    final cacheKey = _buildCacheKey(lastMessage, recentMessages);
    final cached = _cache.get(cacheKey);
    if (cached != null) {
      _log('AI smart reply: cache hit');
      return cached;
    }

    // ── Thử AI Backend Typed Endpoint ─────────────────────────────────────
    try {
      final replies = await AIBackendService().smartReplyWithContextTyped(
        messages: recentMessages.take(6).toList(),
        language: language,
        count: maxReplies,
        replyIntent: replyIntent,
      );

      if (replies.isNotEmpty) {
        _cache.put(cacheKey, replies);
        _log('AI smart reply: ${replies.length} replies from AI (Typed)');
        return replies;
      }
    } catch (e) {
      if (kDebugMode)
        debugPrint('[SmartReplyProvider] AI Typed failure, trying raw: $e');
    }

    try {
      // Vì recentMessages đã là List<String>, chỉ cần take(6) rồi toList() luôn
      final List<SmartReply> aiReplies =
          await AIBackendService().smartReplyWithContextTyped(
        messages: recentMessages.take(6).toList(),
        language: language,
        count: maxReplies,
        replyIntent: replyIntent,
      );

      if (aiReplies.isNotEmpty) {
        _cache.put(cacheKey, aiReplies);
        _log('AI smart reply: ${aiReplies.length} replies from AI');
        return aiReplies;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SmartReplyProvider] AI fallback completely failed: $e');
      }
    }

    // Fallback về rule-based
    final ruleReplies = getRuleBasedReplies(lastMessage);
    if (ruleReplies.isNotEmpty) {
      _log(
          'AI smart reply: fallback to rule-based (${ruleReplies.length} replies)');
      return ruleReplies;
    }

    return _fallbackReplies;
  }

  /// Lấy danh sách smart replies legacy từ hội thoại trong Local DB.
  Future<List<SmartReply>> getAiSmartRepliesFromConversation({
    required String conversationId,
    required String currentUserId,
    String language = 'vi',
  }) async {
    final messages = LocalDbService().getMessages(conversationId);
    if (messages.isEmpty) return [];

    final last = messages.first;
    if (last['idFrom'] == currentUserId) return [];
    if (last['type'] != 0) return [];

    final content = last['content'] as String? ?? '';
    if (content.isEmpty || content.startsWith('{"iv":')) return [];

    final history = messages
        .take(6)
        .map((m) => m['content']?.toString() ?? '')
        .where((c) => c.isNotEmpty && !c.startsWith('{"iv":'))
        .toList()
        .reversed
        .toList();

    return getAiSmartReplies(
      lastMessage: content,
      recentMessages: history,
      language: language,
    );
  }

  /// Làm sạch toàn bộ các tầng cache lưu trong Memory.
  void invalidateCache() {
    _cache.clear();
    _enhancedCache.clear();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RULE-BASED REGEX ENGINE
  // ═══════════════════════════════════════════════════════════════════════════

  List<SmartReply> getRuleBasedReplies(String message) {
    if (message.trim().isEmpty) return [];
    final lower = message.toLowerCase().trim();
    final List<SmartReply> replies = [];

    // ── Vietnamese & English Greetings ──
    if (_matchesAny(
        lower, ['chào', 'hi', 'hello', 'hey', 'xin chào', 'alo', 'hola'])) {
      replies.addAll([
        const SmartReply(
            text: 'Chào bạn! 😊', confidence: 0.95, category: 'greeting'),
        const SmartReply(
            text: 'Hi! Bạn khỏe không?',
            confidence: 0.90,
            category: 'greeting'),
        const SmartReply(
            text: 'Chào! Có gì mình giúp không?',
            confidence: 0.85,
            category: 'greeting'),
      ]);
    }

    if (_matchesAny(lower, [
      'bạn có khỏe',
      'khỏe không',
      'sao rồi',
      'dạo này thế nào',
      'how are you',
      'how r u',
      "how's it going"
    ])) {
      replies.addAll([
        const SmartReply(
            text: 'Mình ổn, cảm ơn! Bạn thì sao? 😄',
            confidence: 0.95,
            category: 'greeting'),
        const SmartReply(
            text: 'Khỏe lắm! Bạn thế nào?',
            confidence: 0.90,
            category: 'greeting'),
        const SmartReply(
            text: "I'm doing great, thanks! You? 😄",
            confidence: 0.88,
            category: 'greeting'),
      ]);
    }

    // ── Acknowledgements & Thank you ──
    if (_matchesAny(lower, [
      'cảm ơn',
      'thanks',
      'thank you',
      'cám ơn',
      'thx',
      'ty',
      'cảm ơn bạn'
    ])) {
      replies.addAll([
        const SmartReply(
            text: 'Không có gì! 😊',
            confidence: 0.95,
            category: 'acknowledgement'),
        const SmartReply(
            text: 'Mình vui khi giúp được bạn!',
            confidence: 0.90,
            category: 'acknowledgement'),
        const SmartReply(
            text: 'Dạ, không có gì ạ 🙏',
            confidence: 0.85,
            category: 'acknowledgement'),
      ]);
    }

    // ── Apologies ──
    if (_matchesAny(lower, [
      'xin lỗi',
      'lỗi mình',
      'mình xin lỗi',
      'bỏ qua nhé',
      'sorry',
      'apologize',
      'my bad',
      'oops'
    ])) {
      replies.addAll([
        const SmartReply(
            text: 'Không sao cả! 😊',
            confidence: 0.95,
            category: 'acknowledgement'),
        const SmartReply(
            text: 'Không có gì đâu bạn ơi',
            confidence: 0.90,
            category: 'acknowledgement'),
        const SmartReply(
            text: 'Oke bạn, mình hiểu 👌',
            confidence: 0.85,
            category: 'acknowledgement'),
      ]);
    }

    // ── Farewells ──
    if (_matchesAny(lower, [
      'tạm biệt',
      'bye',
      'goodbye',
      'hẹn gặp lại',
      'gặp lại sau',
      'cya',
      'tạm biệt nhé'
    ])) {
      replies.addAll([
        const SmartReply(
            text: 'Tạm biệt! 👋', confidence: 0.95, category: 'farewell'),
        const SmartReply(
            text: 'Hẹn gặp lại bạn nhé!',
            confidence: 0.90,
            category: 'farewell'),
        const SmartReply(
            text: 'Bai bai, giữ sức khỏe! 💪',
            confidence: 0.85,
            category: 'farewell'),
      ]);
    }

    // ── General Questions & Information Requests ──
    if (lower.endsWith('?') ||
        _matchesAny(lower, [
          'bạn có thể',
          'bạn có biết',
          'cho mình hỏi',
          'hỏi chút',
          'cái này là gì',
          'can you',
          'could you',
          'would you',
          'do you'
        ])) {
      replies.addAll([
        const SmartReply(
            text: 'Để mình check và trả lời bạn nhé!',
            confidence: 0.80,
            category: 'question'),
        const SmartReply(
            text: 'Mình sẽ xem qua ngay 🔍',
            confidence: 0.75,
            category: 'question'),
        const SmartReply(
            text: 'Câu hỏi hay! Chờ mình một chút.',
            confidence: 0.70,
            category: 'question'),
      ]);
    }

    // ── Affirmations ──
    if (_matchesAny(lower, [
      'đồng ý',
      'oke',
      'ok',
      'được',
      'nhất trí',
      'yes',
      'yep',
      'chắc chắn',
      'dĩ nhiên'
    ])) {
      replies.addAll([
        const SmartReply(
            text: 'Tuyệt vời! 🎉', confidence: 0.85, category: 'affirmation'),
        const SmartReply(
            text: 'Nghe hay đó, làm thôi!',
            confidence: 0.80,
            category: 'affirmation'),
        const SmartReply(
            text: 'Perfect! Mình hiểu rồi 👍',
            confidence: 0.75,
            category: 'affirmation'),
      ]);
    }

    // ── Negations ──
    if (_matchesAny(lower, [
      'không được',
      'không thể',
      'không oke',
      'thôi đừng',
      'no',
      'nope',
      'từ chối'
    ])) {
      replies.addAll([
        const SmartReply(
            text: 'Oke, mình hiểu rồi', confidence: 0.85, category: 'negation'),
        const SmartReply(
            text: 'Không sao, mình thông cảm 👌',
            confidence: 0.80,
            category: 'negation'),
        const SmartReply(
            text: 'Được rồi, cảm ơn bạn đã báo!',
            confidence: 0.75,
            category: 'negation'),
      ]);
    }

    // ── Scheduling ──
    if (_matchesAny(lower, [
      'khi nào',
      'mấy giờ',
      'lịch',
      'hẹn',
      'gặp',
      'cuộc họp',
      'when',
      'what time',
      'schedule',
      'meeting',
      'calendar',
      'available'
    ])) {
      replies.addAll([
        const SmartReply(
            text: 'Để mình check lịch rồi báo bạn 📅',
            confidence: 0.80,
            category: 'scheduling'),
        const SmartReply(
            text: 'Mình sẽ xác nhận thời gian sớm nhất',
            confidence: 0.75,
            category: 'scheduling'),
        const SmartReply(
            text: 'Let me check my calendar 📅',
            confidence: 0.70,
            category: 'scheduling'),
      ]);
    }

    // ── Location ──
    if (_matchesAny(lower, [
      'ở đâu',
      'địa chỉ',
      'chỗ nào',
      'đường đi',
      'bản đồ',
      'where',
      'location',
      'address',
      'directions',
      'map'
    ])) {
      replies.addAll([
        const SmartReply(
            text: 'Mình gửi vị trí cho bạn nhé 📍',
            confidence: 0.80,
            category: 'location'),
        const SmartReply(
            text: 'Để mình share địa chỉ',
            confidence: 0.75,
            category: 'location'),
        const SmartReply(
            text: "I'll share the location with you 📍",
            confidence: 0.70,
            category: 'location'),
      ]);
    }

    // ── Urgency ──
    if (_matchesAny(lower, [
      'khẩn cấp',
      'gấp',
      'ngay bây giờ',
      'quan trọng lắm',
      'cần gấp',
      'urgent',
      'emergency',
      'asap',
      'immediately'
    ])) {
      replies.addAll([
        const SmartReply(
            text: 'Mình xử lý ngay! 🚀', confidence: 0.95, category: 'urgent'),
        const SmartReply(
            text: 'Ok, mình handle luôn!',
            confidence: 0.90,
            category: 'urgent'),
        const SmartReply(
            text: 'Đang xử lý gấp cho bạn ⚡',
            confidence: 0.85,
            category: 'urgent'),
      ]);
    }

    // ── Work / Projects ──
    if (_matchesAny(lower, [
      'công việc',
      'dự án',
      'báo cáo',
      'khách hàng',
      'work',
      'project',
      'deadline',
      'task',
      'client'
    ])) {
      replies.addAll([
        const SmartReply(
            text: 'Mình lo việc này! ✅', confidence: 0.80, category: 'work'),
        const SmartReply(
            text: 'Đang xử lý, update ngay nhé',
            confidence: 0.75,
            category: 'work'),
        const SmartReply(
            text: 'Working on it now!', confidence: 0.70, category: 'work'),
      ]);
    }

    // ── Emotional state ──
    if (_matchesAny(lower,
        ['vui', 'buồn', 'mệt', 'stress', 'lo lắng', 'tuyệt', 'tệ quá'])) {
      replies.addAll([
        const SmartReply(
            text: 'Mình hiểu cảm giác đó! 💯',
            confidence: 0.80,
            category: 'emotional'),
        const SmartReply(
            text: 'Chia sẻ thêm cho mình nghe 😊',
            confidence: 0.75,
            category: 'emotional'),
        const SmartReply(
            text: 'Cảm ơn bạn đã chia sẻ 🙏',
            confidence: 0.70,
            category: 'emotional'),
      ]);
    }

    if (replies.isEmpty) return [];

    final uniqueReplies = <String, SmartReply>{};
    for (final r in replies) {
      if (!uniqueReplies.containsKey(r.text)) uniqueReplies[r.text] = r;
    }

    return uniqueReplies.values.toList()
      ..sort((a, b) => (b.confidence ?? 0.0).compareTo(a.confidence ?? 0.0))
      ..take(maxReplies).toList();
  }

  /// Phân tích cục bộ lịch sử tin nhắn để đoán ngữ cảnh hội thoại.
  List<SmartReply> getContextAwareReplies(
      String currentMessage, List<String> history) {
    final context = _analyzeContext(history);
    switch (context) {
      case 'question':
        return const [
          SmartReply(
              text: 'Được, mình có thể giúp!',
              confidence: 0.85,
              category: 'question'),
          SmartReply(
              text: 'Để mình giải thích nhé...',
              confidence: 0.80,
              category: 'question'),
          SmartReply(
              text: 'Câu hỏi thú vị, để mình nghĩ:',
              confidence: 0.75,
              category: 'question'),
        ];
      case 'plan':
        return const [
          SmartReply(
              text: 'Kế hoạch hay đó! 🙌',
              confidence: 0.85,
              category: 'scheduling'),
          SmartReply(
              text: 'Mình rảnh, làm được!',
              confidence: 0.80,
              category: 'scheduling'),
          SmartReply(
              text: 'Count mình vào nhé! 🎯',
              confidence: 0.75,
              category: 'scheduling'),
        ];
      case 'problem':
        return const [
          SmartReply(
              text: 'Mình giúp bạn giải quyết nha 💪',
              confidence: 0.85,
              category: 'urgent'),
          SmartReply(
              text: 'Mình có thể hỗ trợ gì không?',
              confidence: 0.80,
              category: 'urgent'),
          SmartReply(
              text: 'Để mình xem bạn cần gì!',
              confidence: 0.75,
              category: 'urgent'),
        ];
      case 'celebration':
        return const [
          SmartReply(
              text: 'Tuyệt vời quá! 🎉',
              confidence: 0.90,
              category: 'emotional'),
          SmartReply(
              text: 'Chúc mừng!! Mình vui cho bạn 🥳',
              confidence: 0.85,
              category: 'emotional'),
          SmartReply(
              text: 'Đỉnh lắm!! 🚀', confidence: 0.80, category: 'emotional'),
        ];
      default:
        return [];
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ANTHROPIC CLAUDE API INTEGRATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Gọi trực tiếp API của Claude Anthropic để tạo 3 câu gợi ý.
  Future<List<SmartReply>> getAnthropicReplies({
    required String message,
    required String apiKey,
    List<String>? conversationHistory,
    String model = 'claude-haiku-4-5-20260101',
  }) async {
    try {
      const systemPrompt =
          'You are a smart reply assistant for a Vietnamese chat app. '
          'Generate exactly 3 short, natural, conversational reply suggestions. '
          'Each reply on its own line. Keep under 15 words each. '
          'Mix warm/friendly, neutral/professional, brief/casual. '
          'Prefer Vietnamese, but adapt if the user speaks English. '
          'No numbers, bullets, or formatting.';

      final List<Map<String, String>> messages = [];
      if (conversationHistory != null && conversationHistory.isNotEmpty) {
        final historyContext = conversationHistory.take(6).join('\n');
        messages.add({
          'role': 'user',
          'content':
              'Conversation:\n$historyContext\n\nGenerate replies for: $message',
        });
      } else {
        messages.add({'role': 'user', 'content': message});
      }

      final response = await http
          .post(
            Uri.parse('https://api.anthropic.com/v1/messages'),
            headers: {
              'Content-Type': 'application/json',
              'x-api-key': apiKey,
              'anthropic-version': '2023-06-01',
            },
            body: jsonEncode({
              'model': model,
              'max_tokens': 150,
              'system': systemPrompt,
              'messages': messages,
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final content = data['content'] as List<dynamic>;
        final text = content
            .where((c) => c['type'] == 'text')
            .map((c) => c['text'] as String)
            .join();

        final suggestions = text
            .split('\n')
            .map((s) => s.replaceAll(RegExp(r'^[-•*\d.]+\s*'), '').trim())
            .where((s) => s.isNotEmpty && s.length > 2)
            .take(maxReplies)
            .map((t) => SmartReply(
                  text: t,
                  confidence: 0.92,
                  category: 'general',
                  isAiGenerated: true,
                ))
            .toList();

        if (suggestions.isNotEmpty) return suggestions;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Anthropic API error: $e');
    }

    return getRuleBasedReplies(message);
  }

  /// Sinh ra một đoạn nháp phản hồi dài hơn (Draft) theo cấu trúc lịch sử chat.
  Future<String?> generateReplyDraft({
    required String message,
    required String apiKey,
    String tone = 'friendly',
    List<String>? conversationHistory,
  }) async {
    try {
      final system = 'Bạn đang giúp user soạn tin nhắn trả lời. '
          'Tông giọng: $tone. Ngắn gọn và tự nhiên (1–3 câu). '
          'Chỉ trả về nội dung tin nhắn, không thêm gì khác.';

      final history = conversationHistory?.take(4).toList() ?? [];
      final msgs = <Map<String, String>>[];
      for (int i = 0; i < history.length; i++) {
        msgs.add(
            {'role': i.isEven ? 'user' : 'assistant', 'content': history[i]});
      }
      msgs.add({'role': 'user', 'content': message});

      final response = await http
          .post(
            Uri.parse('https://api.anthropic.com/v1/messages'),
            headers: {
              'Content-Type': 'application/json',
              'x-api-key': apiKey,
              'anthropic-version': '2023-06-01',
            },
            body: jsonEncode({
              'model': 'claude-haiku-4-5-20260101',
              'max_tokens': 200,
              'system': system,
              'messages': msgs,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final content = data['content'] as List<dynamic>;
        return content
            .where((c) => c['type'] == 'text')
            .map((c) => (c['text'] as String).trim())
            .join();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Error generating reply draft: $e');
    }
    return null;
  }

  // ── Private Helpers ────────────────────────────────────────────────────────

  String _analyzeContext(List<String> messages) {
    final recent = messages.take(5).join(' ').toLowerCase();
    if (recent.contains('?') ||
        _matchesAny(recent, [
          'how',
          'what',
          'why',
          'when',
          'where',
          'cái gì',
          'tại sao',
          'như thế nào'
        ])) {
      return 'question';
    }
    if (_matchesAny(recent, [
      'plan',
      'meet',
      'schedule',
      'tomorrow',
      'hẹn',
      'kế hoạch',
      'ngày mai',
      'cuối tuần',
      'tonight'
    ])) {
      return 'plan';
    }
    if (_matchesAny(recent, [
      'problem',
      'issue',
      'help',
      'wrong',
      'broken',
      'vấn đề',
      'lỗi',
      'giúp',
      'hỏng',
      'fail'
    ])) {
      return 'problem';
    }
    if (_matchesAny(recent, [
      'congrat',
      'amazing',
      'excited',
      'great news',
      'won',
      'passed',
      'chúc mừng',
      'tuyệt',
      'thắng'
    ])) {
      return 'celebration';
    }
    return 'general';
  }

  bool _matchesAny(String text, List<String> keywords) =>
      keywords.any((k) => text.contains(k));

  String _buildCacheKey(String message, List<String> history) {
    final historyKey = history.take(3).join('|');
    return '${message.hashCode}_${historyKey.hashCode}';
  }

  String _buildEnhancedCacheKey(
      String message, List<String> history, int closeness, String rel) {
    final historyKey = history.take(3).join('|');
    return '${message.hashCode}_${historyKey.hashCode}_${closeness}_$rel';
  }

  void _log(String msg) {
    if (kDebugMode) debugPrint('[SmartReplyProvider] $msg');
  }

  static const List<SmartReply> _fallbackReplies = [
    SmartReply(text: 'Ok bạn! 👍', confidence: 0.50, category: 'general'),
    SmartReply(
        text: 'Cảm ơn đã chia sẻ!', confidence: 0.45, category: 'general'),
    SmartReply(text: 'Mình hiểu rồi!', confidence: 0.40, category: 'general'),
  ];
}
