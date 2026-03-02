// lib/providers/smart_reply_provider.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class SmartReply {
  final String text;
  final double confidence;

  const SmartReply({
    required this.text,
    required this.confidence,
  });
}

class SmartReplyProvider {
  // Rule-based smart replies
  List<SmartReply> getRuleBasedReplies(String message) {
    final lowerMessage = message.toLowerCase().trim();
    final List<SmartReply> replies = [];

    // Greetings
    if (_containsAny(lowerMessage, ['hello', 'hi', 'hey', 'greetings'])) {
      replies.addAll([
        const SmartReply(text: 'Hello! How are you?', confidence: 0.9),
        const SmartReply(text: 'Hi there!', confidence: 0.85),
        const SmartReply(text: 'Hey! What\'s up?', confidence: 0.8),
      ]);
    }

    // Questions about wellbeing
    if (_containsAny(lowerMessage,
        ['how are you', 'how\'s it going', 'what\'s up', 'how do you do'])) {
      replies.addAll([
        const SmartReply(text: 'I\'m doing great, thanks!', confidence: 0.9),
        const SmartReply(text: 'Pretty good, how about you?', confidence: 0.85),
        const SmartReply(text: 'All good here!', confidence: 0.8),
      ]);
    }

    // Thanks
    if (_containsAny(lowerMessage,
        ['thank you', 'thanks', 'thx', 'appreciate it', 'grateful'])) {
      replies.addAll([
        const SmartReply(text: 'You\'re welcome!', confidence: 0.9),
        const SmartReply(text: 'No problem!', confidence: 0.85),
        const SmartReply(text: 'Happy to help!', confidence: 0.8),
      ]);
    }

    // Apologies
    if (_containsAny(lowerMessage, ['sorry', 'apologize', 'my bad', 'excuse me'])) {
      replies.addAll([
        const SmartReply(text: 'No worries!', confidence: 0.9),
        const SmartReply(text: 'It\'s okay!', confidence: 0.85),
        const SmartReply(text: 'Don\'t worry about it', confidence: 0.8),
      ]);
    }

    // Questions (general)
    if (lowerMessage.contains('?')) {
      replies.addAll([
        const SmartReply(text: 'Let me check and get back to you', confidence: 0.7),
        const SmartReply(text: 'I\'ll look into it', confidence: 0.65),
        const SmartReply(text: 'Good question!', confidence: 0.6),
      ]);
    }

    // Agreement
    if (_containsAny(lowerMessage, ['yes', 'yeah', 'sure', 'okay', 'ok', 'alright'])) {
      replies.addAll([
        const SmartReply(text: 'Great!', confidence: 0.8),
        const SmartReply(text: 'Sounds good!', confidence: 0.75),
        const SmartReply(text: 'Perfect!', confidence: 0.7),
      ]);
    }

    // Disagreement
    if (_containsAny(lowerMessage, ['no', 'nope', 'not really', 'don\'t think so'])) {
      replies.addAll([
        const SmartReply(text: 'I understand', confidence: 0.8),
        const SmartReply(text: 'No problem', confidence: 0.75),
        const SmartReply(text: 'That\'s fine', confidence: 0.7),
      ]);
    }

    // Time-related
    if (_containsAny(lowerMessage,
        ['when', 'what time', 'schedule', 'meeting', 'appointment'])) {
      replies.addAll([
        const SmartReply(text: 'I\'ll check my calendar', confidence: 0.7),
        const SmartReply(text: 'Let me confirm the time', confidence: 0.65),
        const SmartReply(text: 'I\'ll get back to you on that', confidence: 0.6),
      ]);
    }

    // Location-related
    if (_containsAny(lowerMessage, ['where', 'location', 'place', 'address'])) {
      replies.addAll([
        const SmartReply(text: 'I\'ll send you the location', confidence: 0.7),
        const SmartReply(text: 'Let me share the address', confidence: 0.65),
        const SmartReply(text: 'I\'ll look it up', confidence: 0.6),
      ]);
    }

    // Farewell
    if (_containsAny(lowerMessage,
        ['bye', 'goodbye', 'see you', 'later', 'talk to you'])) {
      replies.addAll([
        const SmartReply(text: 'Goodbye! Take care!', confidence: 0.9),
        const SmartReply(text: 'See you later!', confidence: 0.85),
        const SmartReply(text: 'Talk to you soon!', confidence: 0.8),
      ]);
    }

    // Work/Business
    if (_containsAny(lowerMessage,
        ['work', 'project', 'deadline', 'meeting', 'presentation'])) {
      replies.addAll([
        const SmartReply(text: 'I\'ll take care of it', confidence: 0.7),
        const SmartReply(text: 'Working on it now', confidence: 0.65),
        const SmartReply(text: 'Will update you soon', confidence: 0.6),
      ]);
    }

    // Emergencies
    if (_containsAny(lowerMessage, ['urgent', 'emergency', 'asap', 'important', 'help'])) {
      replies.addAll([
        const SmartReply(text: 'On it right away!', confidence: 0.9),
        const SmartReply(text: 'I\'ll handle it immediately', confidence: 0.85),
        const SmartReply(text: 'Prioritizing this now', confidence: 0.8),
      ]);
    }

    // Sort by confidence and return top 3
    replies.sort((a, b) => b.confidence.compareTo(a.confidence));
    return replies.take(3).toList();
  }

  bool _containsAny(String text, List<String> keywords) {
    return keywords.any((keyword) => text.contains(keyword));
  }

  // Context-aware replies based on conversation history
  List<SmartReply> getContextAwareReplies(
      String currentMessage,
      List<String> previousMessages,
      ) {
    final replies = <SmartReply>[];

    // Analyze conversation context
    final context = _analyzeContext(previousMessages);

    if (context == 'question') {
      replies.addAll([
        const SmartReply(text: 'Yes, I can help with that', confidence: 0.8),
        const SmartReply(text: 'Let me explain...', confidence: 0.75),
        const SmartReply(text: 'Here\'s what I know...', confidence: 0.7),
      ]);
    } else if (context == 'plan') {
      replies.addAll([
        const SmartReply(text: 'Sounds like a plan!', confidence: 0.8),
        const SmartReply(text: 'I\'m available', confidence: 0.75),
        const SmartReply(text: 'Count me in!', confidence: 0.7),
      ]);
    } else if (context == 'problem') {
      replies.addAll([
        const SmartReply(text: 'I can help with that', confidence: 0.8),
        const SmartReply(text: 'Let\'s solve this together', confidence: 0.75),
        const SmartReply(text: 'What can I do to help?', confidence: 0.7),
      ]);
    }

    return replies;
  }

  String _analyzeContext(List<String> messages) {
    final recentMessages = messages.take(5).join(' ').toLowerCase();

    if (recentMessages.contains('?') || recentMessages.contains('how') ||
        recentMessages.contains('what') || recentMessages.contains('why')) {
      return 'question';
    } else if (recentMessages.contains('plan') || recentMessages.contains('meet') ||
        recentMessages.contains('schedule') || recentMessages.contains('tomorrow')) {
      return 'plan';
    } else if (recentMessages.contains('problem') || recentMessages.contains('issue') ||
        recentMessages.contains('help') || recentMessages.contains('wrong')) {
      return 'problem';
    }

    return 'general';
  }

  // Optional: AI API-based smart replies (requires API key)
  Future<List<SmartReply>> getAIReplies({
    required String message,
    required String apiKey,
    List<String>? conversationHistory,
  }) async {
    try {
      // Example using OpenAI API (you can replace with any AI service)
      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': 'gpt-3.5-turbo',
          'messages': [
            {
              'role': 'system',
              'content': 'Generate 3 short, casual reply suggestions for the given message. Return only the suggestions separated by newlines, no numbering or formatting.',
            },
            if (conversationHistory != null && conversationHistory.isNotEmpty)
              ...conversationHistory.map((msg) => {
                'role': 'user',
                'content': msg,
              }),
            {
              'role': 'user',
              'content': message,
            },
          ],
          'max_tokens': 100,
          'temperature': 0.7,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['choices'][0]['message']['content'] as String;
        final suggestions = content.split('\n').where((s) => s.trim().isNotEmpty).toList();

        return suggestions.take(3).map((text) => SmartReply(
          text: text.trim(),
          confidence: 0.85,
        )).toList();
      }
    } catch (e) {
      print('Error getting AI replies: $e');
    }

    // Fallback to rule-based
    return getRuleBasedReplies(message);
  }

  // Get smart replies combining multiple approaches
  Future<List<SmartReply>> getSmartReplies({
    required String message,
    List<String>? conversationHistory,
    String? apiKey,
  }) async {
    // Try rule-based first (instant)
    final ruleReplies = getRuleBasedReplies(message);

    if (ruleReplies.isNotEmpty) {
      return ruleReplies;
    }

    // Try context-aware
    if (conversationHistory != null && conversationHistory.isNotEmpty) {
      final contextReplies = getContextAwareReplies(message, conversationHistory);
      if (contextReplies.isNotEmpty) {
        return contextReplies;
      }
    }

    // Try AI if API key provided
    if (apiKey != null && apiKey.isNotEmpty) {
      return await getAIReplies(
        message: message,
        apiKey: apiKey,
        conversationHistory: conversationHistory,
      );
    }

    // Default fallback replies
    return const [
      SmartReply(text: 'Got it!', confidence: 0.5),
      SmartReply(text: 'Thanks for letting me know', confidence: 0.45),
      SmartReply(text: 'Understood', confidence: 0.4),
    ];
  }
}

