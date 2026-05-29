import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;

enum ReplyCategory {
  greeting,
  farewell,
  acknowledgement,
  question,
  affirmation,
  negation,
  scheduling,
  location,
  urgent,
  work,
  emotional,
  general,
}

class SmartReply {
  final String text;
  final double confidence;
  final ReplyCategory category;
  final bool isAiGenerated;

  const SmartReply({
    required this.text,
    required this.confidence,
    this.category = ReplyCategory.general,
    this.isAiGenerated = false,
  });

  @override
  String toString() => 'SmartReply(text: $text, confidence: $confidence)';
}

class SmartReplyProvider {
  static const int maxReplies = 3;

  Future<List<SmartReply>> getSmartReplies({
    required String message,
    List<String>? conversationHistory,
    String? anthropicApiKey,
  }) async {
    final ruleReplies = getRuleBasedReplies(message);
    if (ruleReplies.isNotEmpty) return ruleReplies;

    if (conversationHistory != null && conversationHistory.isNotEmpty) {
      final contextReplies = getContextAwareReplies(message, conversationHistory);
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

  List<SmartReply> getRuleBasedReplies(String message) {
    final lower = message.toLowerCase().trim();
    final List<SmartReply> replies = [];

    if (_matchesAny(
        lower, ['hello', 'hi ', 'hey', 'greetings', 'howdy', 'sup', 'what\'s up', 'hiya'])) {
      replies.addAll([
        const SmartReply(
            text: 'Hey! How are you? 😊', confidence: 0.95, category: ReplyCategory.greeting),
        const SmartReply(
            text: 'Hi there! What\'s up?', confidence: 0.90, category: ReplyCategory.greeting),
        const SmartReply(
            text: 'Hello! Great to hear from you!',
            confidence: 0.85,
            category: ReplyCategory.greeting),
      ]);
    }

    if (_matchesAny(lower, [
      'how are you',
      'how r u',
      'how\'s it going',
      'how do you do',
      'how have you been',
      'you okay',
      'u ok'
    ])) {
      replies.addAll([
        const SmartReply(
            text: 'I\'m doing great, thanks! You? 😄',
            confidence: 0.95,
            category: ReplyCategory.greeting),
        const SmartReply(
            text: 'Pretty good! How about you?',
            confidence: 0.90,
            category: ReplyCategory.greeting),
        const SmartReply(
            text: 'All good here! What\'s new?',
            confidence: 0.85,
            category: ReplyCategory.greeting),
      ]);
    }

    if (_matchesAny(
        lower, ['thank you', 'thanks', 'thx', 'ty ', 'appreciate', 'grateful', 'cheers', 'thnx'])) {
      replies.addAll([
        const SmartReply(
            text: 'You\'re welcome! 😊', confidence: 0.95, category: ReplyCategory.acknowledgement),
        const SmartReply(
            text: 'No problem at all!', confidence: 0.90, category: ReplyCategory.acknowledgement),
        const SmartReply(
            text: 'Happy to help! 🙌', confidence: 0.85, category: ReplyCategory.acknowledgement),
      ]);
    }

    if (_matchesAny(
        lower, ['sorry', 'apologize', 'my bad', 'excuse me', 'forgive', 'pardon', 'oops'])) {
      replies.addAll([
        const SmartReply(
            text: 'No worries at all! 😊',
            confidence: 0.95,
            category: ReplyCategory.acknowledgement),
        const SmartReply(
            text: 'It\'s totally okay!', confidence: 0.90, category: ReplyCategory.acknowledgement),
        const SmartReply(
            text: 'Don\'t worry about it 👍',
            confidence: 0.85,
            category: ReplyCategory.acknowledgement),
      ]);
    }

    if (_matchesAny(lower, [
      'bye',
      'goodbye',
      'see you',
      'later',
      'gotta go',
      'ttyl',
      'take care',
      'cya',
      'night',
      'good night'
    ])) {
      replies.addAll([
        const SmartReply(
            text: 'Bye! Take care! 👋', confidence: 0.95, category: ReplyCategory.farewell),
        const SmartReply(
            text: 'See you soon! 😊', confidence: 0.90, category: ReplyCategory.farewell),
        const SmartReply(
            text: 'Talk to you later! 💬', confidence: 0.85, category: ReplyCategory.farewell),
      ]);
    }

    if (lower.endsWith('?') ||
        _matchesAny(lower, ['can you', 'could you', 'would you', 'is it', 'are you', 'do you'])) {
      replies.addAll([
        const SmartReply(
            text: 'Let me check and get back to you!',
            confidence: 0.80,
            category: ReplyCategory.question),
        const SmartReply(
            text: 'I\'ll look into it right away 🔍',
            confidence: 0.75,
            category: ReplyCategory.question),
        const SmartReply(
            text: 'Good question! Give me a moment.',
            confidence: 0.70,
            category: ReplyCategory.question),
      ]);
    }

    if (_matchesAny(lower, [
      ' yes',
      'yeah',
      'yep',
      'sure',
      'okay',
      ' ok ',
      'alright',
      'absolutely',
      'definitely',
      'of course',
      'roger',
      'affirmative'
    ])) {
      replies.addAll([
        const SmartReply(text: 'Great! 🎉', confidence: 0.85, category: ReplyCategory.affirmation),
        const SmartReply(
            text: 'Sounds good to me!', confidence: 0.80, category: ReplyCategory.affirmation),
        const SmartReply(
            text: 'Perfect! Let\'s do it 👍',
            confidence: 0.75,
            category: ReplyCategory.affirmation),
      ]);
    }

    if (_matchesAny(lower, [
      ' no ',
      'nope',
      'nah',
      'not really',
      'don\'t think so',
      'negative',
      'can\'t',
      'cannot',
      'won\'t'
    ])) {
      replies.addAll([
        const SmartReply(
            text: 'I understand, no problem!', confidence: 0.85, category: ReplyCategory.negation),
        const SmartReply(
            text: 'Okay, that\'s alright 👌', confidence: 0.80, category: ReplyCategory.negation),
        const SmartReply(
            text: 'Got it, thanks for letting me know',
            confidence: 0.75,
            category: ReplyCategory.negation),
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
            category: ReplyCategory.scheduling),
        const SmartReply(
            text: 'I\'ll confirm the time shortly',
            confidence: 0.75,
            category: ReplyCategory.scheduling),
        const SmartReply(
            text: 'I\'ll get back to you on that!',
            confidence: 0.70,
            category: ReplyCategory.scheduling),
      ]);
    }

    if (_matchesAny(
        lower, ['where', 'location', 'address', 'place', 'directions', 'map', 'how to get'])) {
      replies.addAll([
        const SmartReply(
            text: 'I\'ll share the location with you 📍',
            confidence: 0.80,
            category: ReplyCategory.location),
        const SmartReply(
            text: 'Let me send you the address',
            confidence: 0.75,
            category: ReplyCategory.location),
        const SmartReply(
            text: 'I\'ll look up directions for you 🗺️',
            confidence: 0.70,
            category: ReplyCategory.location),
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
            text: 'On it right away! 🚀', confidence: 0.95, category: ReplyCategory.urgent),
        const SmartReply(
            text: 'I\'ll handle this immediately!',
            confidence: 0.90,
            category: ReplyCategory.urgent),
        const SmartReply(
            text: 'Prioritizing this now — give me a sec',
            confidence: 0.85,
            category: ReplyCategory.urgent),
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
            text: 'I\'ll take care of it ✅', confidence: 0.80, category: ReplyCategory.work),
        const SmartReply(
            text: 'Working on it now!', confidence: 0.75, category: ReplyCategory.work),
        const SmartReply(
            text: 'I\'ll update you soon 📊', confidence: 0.70, category: ReplyCategory.work),
      ]);
    }

    if (_matchesAny(lower, [
      'happy',
      'sad',
      'excited',
      'angry',
      'frustrated',
      'stressed',
      'tired',
      'amazing',
      'awesome',
      'terrible',
      'love',
      'hate'
    ])) {
      replies.addAll([
        const SmartReply(
            text: 'I totally get that! 💯', confidence: 0.80, category: ReplyCategory.emotional),
        const SmartReply(
            text: 'That makes complete sense 😊',
            confidence: 0.75,
            category: ReplyCategory.emotional),
        const SmartReply(
            text: 'Thanks for sharing that with me',
            confidence: 0.70,
            category: ReplyCategory.emotional),
      ]);
    }

    if (replies.isEmpty) return [];

    replies.sort((a, b) => b.confidence.compareTo(a.confidence));
    return replies.take(maxReplies).toList();
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
              text: 'Yes, I can definitely help with that!',
              confidence: 0.85,
              category: ReplyCategory.question),
          SmartReply(text: 'Let me explain...', confidence: 0.80, category: ReplyCategory.question),
          SmartReply(
              text: 'Here\'s what I know about that:',
              confidence: 0.75,
              category: ReplyCategory.question),
        ];
      case 'plan':
        return const [
          SmartReply(
              text: 'Sounds like a great plan! 🙌',
              confidence: 0.85,
              category: ReplyCategory.scheduling),
          SmartReply(
              text: 'I\'m available for that!',
              confidence: 0.80,
              category: ReplyCategory.scheduling),
          SmartReply(text: 'Count me in! 🎯', confidence: 0.75, category: ReplyCategory.scheduling),
        ];
      case 'problem':
        return const [
          SmartReply(
              text: 'Let\'s figure this out together 💪',
              confidence: 0.85,
              category: ReplyCategory.urgent),
          SmartReply(
              text: 'What can I do to help?', confidence: 0.80, category: ReplyCategory.urgent),
          SmartReply(
              text: 'I\'ve got you covered!', confidence: 0.75, category: ReplyCategory.urgent),
        ];
      case 'celebration':
        return const [
          SmartReply(
              text: 'That\'s amazing! 🎉', confidence: 0.90, category: ReplyCategory.emotional),
          SmartReply(
              text: 'Congrats!! So happy for you 🥳',
              confidence: 0.85,
              category: ReplyCategory.emotional),
          SmartReply(
              text: 'Awesome news!! 🚀', confidence: 0.80, category: ReplyCategory.emotional),
        ];
      default:
        return [];
    }
  }

  String _analyzeContext(List<String> messages) {
    final recent = messages.take(5).join(' ').toLowerCase();
    if (recent.contains('?') ||
        recent.contains('how') ||
        recent.contains('what') ||
        recent.contains('why') ||
        recent.contains('when') ||
        recent.contains('where')) {
      return 'question';
    }
    if (recent.contains('plan') ||
        recent.contains('meet') ||
        recent.contains('schedule') ||
        recent.contains('tomorrow') ||
        recent.contains('weekend') ||
        recent.contains('tonight')) {
      return 'plan';
    }
    if (recent.contains('problem') ||
        recent.contains('issue') ||
        recent.contains('help') ||
        recent.contains('wrong') ||
        recent.contains('broken') ||
        recent.contains('fail')) {
      return 'problem';
    }
    if (recent.contains('congrat') ||
        recent.contains('amazing') ||
        recent.contains('excited') ||
        recent.contains('great news') ||
        recent.contains('won') ||
        recent.contains('passed')) {
      return 'celebration';
    }
    return 'general';
  }

  Future<List<SmartReply>> getAnthropicReplies({
    required String message,
    required String apiKey,
    List<String>? conversationHistory,
    String model = 'claude-haiku-4-5-20251001',
  }) async {
    try {
      final systemPrompt = 'You are a smart reply assistant for a chat application. '
          'Generate exactly 3 short, natural, conversational reply suggestions for the given message. '
          'Each reply should be on its own line. '
          'Keep replies concise (under 15 words each). '
          'Vary the tone: one warm/friendly, one neutral/professional, one brief/casual. '
          'Do NOT include numbers, bullets, or any formatting — just the plain text of each reply, one per line. '
          'No preamble or explanation.';

      final List<Map<String, String>> messages = [];

      if (conversationHistory != null && conversationHistory.isNotEmpty) {
        final historyContext = conversationHistory.take(6).join('\n');
        messages.add({
          'role': 'user',
          'content':
              'Recent conversation context:\n$historyContext\n\nGenerate replies for the latest message: $message',
        });
      } else {
        messages.add({
          'role': 'user',
          'content': message,
        });
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
        final text =
            content.where((c) => c['type'] == 'text').map((c) => c['text'] as String).join();

        final suggestions = text
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty && s.length > 2)
            .take(maxReplies)
            .map((t) => SmartReply(
                  text: t,
                  confidence: 0.92,
                  category: ReplyCategory.general,
                  isAiGenerated: true,
                ))
            .toList();

        if (suggestions.isNotEmpty) {
          debugPrint('✅ Got ${suggestions.length} AI replies from Claude');
          return suggestions;
        }
      } else {
        debugPrint('⚠️ Anthropic API error: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      debugPrint('⚠️ Anthropic API unavailable: $e');
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
      final system = 'You are helping a user draft a chat reply. '
          'Tone: $tone. Keep it concise and natural (1–3 sentences). '
          'Return only the reply text, nothing else.';

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
      debugPrint('⚠️ Error generating reply draft: $e');
    }
    return null;
  }

  bool _matchesAny(String text, List<String> keywords) => keywords.any((k) => text.contains(k));

  static const List<SmartReply> _fallbackReplies = [
    SmartReply(text: 'Got it! 👍', confidence: 0.50, category: ReplyCategory.general),
    SmartReply(
        text: 'Thanks for letting me know!', confidence: 0.45, category: ReplyCategory.general),
    SmartReply(text: 'Understood!', confidence: 0.40, category: ReplyCategory.general),
  ];
}
