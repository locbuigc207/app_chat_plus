// ignore_for_file: avoid_print
// lib/providers/smart_reply_provider.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../services/services.dart';

export '../services/ai_backend_service.dart' show AIBackendService;

// ─────────────────────────────────────────────────────────────────────────────
// AI CACHE — tránh gọi AI nhiều lần cho cùng message
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
      // Evict oldest
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

// ─────────────────────────────────────────────────────────────────────────────
// SMART REPLY PROVIDER
// ─────────────────────────────────────────────────────────────────────────────

class SmartReplyProvider {
  static const int maxReplies = 3;

  final _AiReplyCache _cache = _AiReplyCache();

  // ── PUBLIC API ─────────────────────────────────────────────────────────────

  /// Entry point chính — thử AI trước, fallback về rule-based.
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

  // ── AI SMART REPLIES ───────────────────────────────────────────────────────

  /// AI-powered smart reply thay thế rule-based.
  /// Fallback tự động về getRuleBasedReplies() nếu AI thất bại.
  ///
  /// - Sử dụng in-memory cache để tránh gọi AI trùng lặp
  /// - Language detection tự động
  /// - Graceful degradation sang rule-based
  Future<List<SmartReply>> getAiSmartReplies({
    required String lastMessage,
    required List<String> recentMessages,
    String language = 'vi',
    String replyIntent = 'helpful',
  }) async {
    if (lastMessage.trim().isEmpty) return [];

    // Kiểm tra cache
    final cacheKey = _buildCacheKey(lastMessage, recentMessages);
    final cached = _cache.get(cacheKey);
    if (cached != null) {
      _log('AI smart reply: cache hit');
      return cached;
    }

    // Thử AI trước
    try {
      final aiReplies = await AIBackendService().smartReplyWithContext(
        messages: recentMessages.take(6).toList(),
        language: language,
        count: maxReplies,
        replyIntent: replyIntent,
      );
      if (aiReplies.isNotEmpty) {
        final replies = aiReplies
            .where((t) => t.trim().isNotEmpty)
            .take(maxReplies)
            .map((text) => SmartReply(
                  text: text,
                  confidence: 0.9,
                  category: 'general',
                  isAiGenerated: true,
                ))
            .toList();

        if (replies.isNotEmpty) {
          _cache.put(cacheKey, replies);
          _log('AI smart reply: ${replies.length} replies from AI');
          return replies;
        }
      }
    } catch (e) {
      // Silently fallback — không log để tránh spam
      if (kDebugMode) debugPrint('[SmartReplyProvider] AI fallback: $e');
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

  /// Lấy smart replies từ LocalDB messages của conversation.
  Future<List<SmartReply>> getAiSmartRepliesFromConversation({
    required String conversationId,
    required String currentUserId,
    String language = 'vi',
  }) async {
    final messages = LocalDbService().getMessages(conversationId);
    if (messages.isEmpty) return [];

    final last = messages.first;
    // Chỉ suggest khi tin nhắn cuối là từ đối phương
    if (last['idFrom'] == currentUserId) return [];
    if (last['type'] != 0) return []; // chỉ text messages

    final content = last['content'] as String? ?? '';
    if (content.isEmpty || content.startsWith('{"iv":')) return [];

    // Build context từ history
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

  /// Invalidate cache để force refresh lần sau.
  void invalidateCache() => _cache.clear();

  // ── RULE-BASED ─────────────────────────────────────────────────────────────

  List<SmartReply> getRuleBasedReplies(String message) {
    if (message.trim().isEmpty) return [];
    final lower = message.toLowerCase().trim();
    final List<SmartReply> replies = [];

    // ── Vietnamese patterns ──
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
            text: 'Chào! Có gì mình giúp được không?',
            confidence: 0.85,
            category: 'greeting'),
      ]);
    }

    if (_matchesAny(
        lower, ['bạn có khỏe', 'khỏe không', 'sao rồi', 'dạo này thế nào'])) {
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
            text: 'Vẫn ổn, cảm ơn bạn hỏi thăm 🙏',
            confidence: 0.85,
            category: 'greeting'),
      ]);
    }

    if (_matchesAny(lower, [
      'cảm ơn',
      'thanks',
      'thank you',
      'cảm ơn bạn',
      'cám ơn',
      'thx',
      'ty'
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

    if (_matchesAny(
        lower, ['xin lỗi', 'lỗi mình', 'mình xin lỗi', 'bỏ qua nhé'])) {
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

    if (_matchesAny(lower, [
      'tạm biệt',
      'bye',
      'goodbye',
      'hẹn gặp lại',
      'tạm biệt nhé',
      'gặp lại sau',
      'cya'
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

    if (_matchesAny(lower, [
      'bạn có thể',
      'bạn có biết',
      'cho mình hỏi',
      'hỏi chút',
      'cái này là gì'
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
            text: 'Câu hỏi hay đó! Chờ mình một chút.',
            confidence: 0.70,
            category: 'question'),
      ]);
    }

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

    if (_matchesAny(
        lower, ['khi nào', 'mấy giờ', 'lịch', 'hẹn', 'gặp', 'cuộc họp'])) {
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
            text: 'Được, mình sẽ sắp xếp!',
            confidence: 0.70,
            category: 'scheduling'),
      ]);
    }

    if (_matchesAny(
        lower, ['ở đâu', 'địa chỉ', 'chỗ nào', 'đường đi', 'bản đồ'])) {
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
            text: 'Mình sẽ chỉ đường cho bạn 🗺️',
            confidence: 0.70,
            category: 'location'),
      ]);
    }

    if (_matchesAny(lower,
        ['khẩn cấp', 'gấp', 'ngay bây giờ', 'quan trọng lắm', 'cần gấp'])) {
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

    if (_matchesAny(lower, ['công việc', 'dự án', 'báo cáo', 'khách hàng'])) {
      replies.addAll([
        const SmartReply(
            text: 'Mình lo việc này! ✅', confidence: 0.80, category: 'work'),
        const SmartReply(
            text: 'Đang xử lý, update ngay nhé',
            confidence: 0.75,
            category: 'work'),
        const SmartReply(
            text: 'Oke, mình sẽ cập nhật bạn sớm 📊',
            confidence: 0.70,
            category: 'work'),
      ]);
    }

    if (_matchesAny(lower,
        ['vui', 'buồn', 'mệt', 'stress', 'lo lắng', 'tuyệt', 'tệ quá'])) {
      replies.addAll([
        const SmartReply(
            text: 'Mình hiểu cảm giác đó! 💯',
            confidence: 0.80,
            category: 'emotional'),
        const SmartReply(
            text: 'Chia sẻ thêm cho mình nghe với 😊',
            confidence: 0.75,
            category: 'emotional'),
        const SmartReply(
            text: 'Cảm ơn bạn đã chia sẻ 🙏',
            confidence: 0.70,
            category: 'emotional'),
      ]);
    }

    // ── English fallback patterns ──
    if (_matchesAny(lower, [
      'how are you',
      'how r u',
      "how's it going",
      'how do you do',
      'you okay',
      'u ok'
    ])) {
      replies.addAll([
        const SmartReply(
            text: "I'm doing great, thanks! You? 😄",
            confidence: 0.95,
            category: 'greeting'),
        const SmartReply(
            text: 'Pretty good! How about you?',
            confidence: 0.90,
            category: 'greeting'),
      ]);
    }

    if (_matchesAny(lower, [
      'sorry',
      'apologize',
      'my bad',
      'excuse me',
      'forgive',
      'pardon',
      'oops'
    ])) {
      replies.addAll([
        const SmartReply(
            text: 'No worries at all! 😊',
            confidence: 0.95,
            category: 'acknowledgement'),
        const SmartReply(
            text: "It's totally okay!",
            confidence: 0.90,
            category: 'acknowledgement'),
      ]);
    }

    if (_matchesAny(lower, [
      'when',
      'what time',
      'schedule',
      'meeting',
      'appointment',
      'calendar',
      'available',
      'free'
    ])) {
      replies.addAll([
        const SmartReply(
            text: 'Let me check my calendar 📅',
            confidence: 0.80,
            category: 'scheduling'),
        const SmartReply(
            text: "I'll confirm the time shortly",
            confidence: 0.75,
            category: 'scheduling'),
      ]);
    }

    if (_matchesAny(lower, [
      'where',
      'location',
      'address',
      'place',
      'directions',
      'map',
      'how to get'
    ])) {
      replies.addAll([
        const SmartReply(
            text: "I'll share the location with you 📍",
            confidence: 0.80,
            category: 'location'),
        const SmartReply(
            text: 'Let me send you the address',
            confidence: 0.75,
            category: 'location'),
      ]);
    }

    if (_matchesAny(lower, [
      'urgent',
      'emergency',
      'asap',
      'immediately',
      'critical',
      'important',
      'help me',
      'need help'
    ])) {
      replies.addAll([
        const SmartReply(
            text: 'On it right away! 🚀', confidence: 0.95, category: 'urgent'),
        const SmartReply(
            text: "I'll handle this immediately!",
            confidence: 0.90,
            category: 'urgent'),
      ]);
    }

    if (_matchesAny(lower, [
      'work',
      'project',
      'deadline',
      'presentation',
      'task',
      'report',
      'client',
      'deliverable'
    ])) {
      replies.addAll([
        const SmartReply(
            text: "I'll take care of it ✅", confidence: 0.80, category: 'work'),
        const SmartReply(
            text: 'Working on it now!', confidence: 0.75, category: 'work'),
      ]);
    }

    if (lower.endsWith('?') ||
        _matchesAny(lower, [
          'can you',
          'could you',
          'would you',
          'is it',
          'are you',
          'do you'
        ])) {
      replies.addAll([
        const SmartReply(
            text: 'Let me check and get back to you!',
            confidence: 0.80,
            category: 'question'),
        const SmartReply(
            text: "I'll look into it right away 🔍",
            confidence: 0.75,
            category: 'question'),
      ]);
    }

    if (replies.isEmpty) return [];

    // Lọc trùng và sắp xếp
    final uniqueReplies = <String, SmartReply>{};
    for (var r in replies) {
      if (!uniqueReplies.containsKey(r.text)) {
        uniqueReplies[r.text] = r;
      }
    }

    final sortedReplies = uniqueReplies.values.toList()
      ..sort((a, b) => (b.confidence ?? 0.0).compareTo(a.confidence ?? 0.0));

    return sortedReplies.take(maxReplies).toList();
  }

  List<SmartReply> getContextAwareReplies(
    String currentMessage,
    List<String> history,
  ) {
    final context = _analyzeContext(history);
    switch (context) {
      case 'question':
        return const [
          SmartReply(
              text: 'Được, mình có thể giúp! / Yes, I can help!',
              confidence: 0.85,
              category: 'question'),
          SmartReply(
              text: 'Để mình giải thích... / Let me explain...',
              confidence: 0.80,
              category: 'question'),
          SmartReply(
              text: 'Câu hỏi thú vị, đây là điều mình biết:',
              confidence: 0.75,
              category: 'question'),
        ];
      case 'plan':
        return const [
          SmartReply(
              text: 'Kế hoạch hay đó! 🙌 / Sounds like a plan!',
              confidence: 0.85,
              category: 'scheduling'),
          SmartReply(
              text: 'Mình rảnh, làm được! / I am available!',
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
              text: 'Mình giúp bạn giải quyết nha 💪 / Let\'s fix this',
              confidence: 0.85,
              category: 'urgent'),
          SmartReply(
              text: 'Mình có thể hỗ trợ gì không? / How can I help?',
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
              text: 'Tuyệt vời quá! 🎉 / That is amazing!',
              confidence: 0.90,
              category: 'emotional'),
          SmartReply(
              text: 'Chúc mừng bạn!! Mình vui cho bạn 🥳',
              confidence: 0.85,
              category: 'emotional'),
          SmartReply(
              text: 'Đỉnh lắm!! 🚀 / Awesome news!',
              confidence: 0.80,
              category: 'emotional'),
        ];
      default:
        return [];
    }
  }

  Future<List<SmartReply>> getAnthropicReplies({
    required String message,
    required String apiKey,
    List<String>? conversationHistory,
    String model = 'claude-haiku-4-5-20251001',
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

        if (suggestions.isNotEmpty) {
          debugPrint('✅ Got ${suggestions.length} AI replies from Claude');
          return suggestions;
        }
      } else {
        if (kDebugMode)
          debugPrint(
              '⚠️ Anthropic API error: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Anthropic API error: $e');
    }

    return getRuleBasedReplies(message);
  }

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
        msgs.add({
          'role': i.isEven ? 'user' : 'assistant',
          'content': history[i],
        });
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
              'model': 'claude-haiku-4-5-20251001',
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

  // ── PRIVATE HELPERS ────────────────────────────────────────────────────────

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
