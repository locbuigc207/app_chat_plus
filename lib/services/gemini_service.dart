// ignore_for_file: avoid_print

import 'dart:async';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';

import '../constants/constants.dart';

enum GeminiTaskType {
  chat,
  scamAnalysis,
  summarize,
  translate,
  codeAssist,
  sentimentAnalysis,
}

class GeminiResponse {
  final String text;
  final bool isError;
  final int? promptTokenCount;
  final int? candidateTokenCount;

  const GeminiResponse({
    required this.text,
    this.isError = false,
    this.promptTokenCount,
    this.candidateTokenCount,
  });

  factory GeminiResponse.error(String message) =>
      GeminiResponse(text: message, isError: true);
}

class GeminiService {
  GeminiService._internal();
  static final GeminiService _instance = GeminiService._internal();
  factory GeminiService() => _instance;

  // gemini-3.5-flash = GA stable (June 2026)
  static const String _modelId = 'gemini-3.5-flash';
  static const int _maxRetries = 3;
  static const Duration _baseRetryDelay = Duration(seconds: 2);
  static const int _maxHistoryMessages = 20;

  // Cache chỉ theo taskType, không cần cache theo apiKey nữa
  GenerativeModel? _cachedModel;

  Future<String> sendMessage(
    String message,
    List<Map<String, dynamic>> historyRaw,
  ) async {
    final response = await sendMessageDetailed(message, historyRaw);
    return response.text;
  }

  Future<GeminiResponse> sendMessageDetailed(
    String message,
    List<Map<String, dynamic>> historyRaw, {
    GeminiTaskType taskType = GeminiTaskType.chat,
  }) async {
    if (message.trim().isEmpty) {
      return GeminiResponse.error('Tin nhắn không được trống.');
    }

    try {
      final model = _getOrCreateModel(taskType);
      final history = _buildValidHistory(
        historyRaw,
        maxMessages: _maxHistoryMessages,
      );
      return await _sendWithRetry(model, history, message);
    } catch (e) {
      return GeminiResponse.error(_handleError(e));
    }
  }

  Stream<String> sendMessageStream(
    String message,
    List<Map<String, dynamic>> historyRaw, {
    GeminiTaskType taskType = GeminiTaskType.chat,
  }) async* {
    if (message.trim().isEmpty) {
      yield 'Tin nhắn không được trống.';
      return;
    }

    try {
      final model = _getOrCreateModel(taskType);
      final history = _buildValidHistory(historyRaw);
      final chat = model.startChat(history: history);

      final stream = chat.sendMessageStream(Content.text(message));
      await for (final chunk in stream) {
        final text = chunk.text;
        if (text != null && text.isNotEmpty) yield text;
      }
    } catch (e) {
      yield _handleError(e);
    }
  }

  Future<String> analyzeScam(String message) async {
    const prompt = '''
Phân tích tin nhắn sau và đánh giá nguy cơ lừa đảo/scam.
Trả về JSON hợp lệ với các trường:
- level: "SAFE" | "WARNING" | "SCAM"
- reason: lý do ngắn gọn (tiếng Việt, tối đa 1 câu)
- confidence: số từ 0.0 đến 1.0

Tin nhắn cần phân tích:
''';
    final response = await sendMessageDetailed(
      '$prompt"$message"',
      [],
      taskType: GeminiTaskType.scamAnalysis,
    );
    return response.text;
  }

  Future<String> summarizeMessages(
    List<String> messages, {
    int maxSentences = 3,
  }) async {
    if (messages.isEmpty) return '';
    final joined = messages.take(50).join('\n');
    final response = await sendMessageDetailed(
      'Tóm tắt cuộc trò chuyện sau trong $maxSentences câu ngắn gọn bằng tiếng Việt:\n\n$joined',
      [],
      taskType: GeminiTaskType.summarize,
    );
    return response.text;
  }

  Future<String> translateForAudience(
    String message,
    String targetAudience,
  ) async {
    final audiencePrompts = {
      'elder': 'người cao tuổi (ngôn ngữ đơn giản, kính trọng)',
      'student': 'học sinh/sinh viên (ngôn ngữ trẻ trung, thân thiện)',
      'work': 'môi trường công việc (lịch sự, chuyên nghiệp)',
      'child': 'trẻ em (đơn giản, vui vẻ, dễ hiểu)',
    };
    final desc = audiencePrompts[targetAudience] ?? targetAudience;

    final response = await sendMessageDetailed(
      'Diễn giải lại tin nhắn sau phù hợp với $desc. '
      'Chỉ trả về nội dung đã diễn giải, không giải thích thêm:\n\n"$message"',
      [],
      taskType: GeminiTaskType.translate,
    );
    return response.text;
  }

  Future<List<String>> suggestReplies(
    List<String> recentMessages, {
    String tone = 'friendly',
  }) async {
    if (recentMessages.isEmpty) return [];

    final toneDesc = {
          'friendly': 'thân thiện, tự nhiên',
          'formal': 'lịch sự, trang trọng',
          'casual': 'vui vẻ, hài hước',
        }[tone] ??
        'thân thiện';

    final context = recentMessages.takeLast(5).join('\n');
    final response = await sendMessageDetailed(
      'Dựa vào cuộc trò chuyện sau, gợi ý đúng 3 cách trả lời ngắn gọn ($toneDesc) '
      'bằng tiếng Việt. Mỗi gợi ý trên một dòng, không đánh số, không thêm giải thích:\n\n$context',
      [],
      taskType: GeminiTaskType.chat,
    );

    return response.text
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .take(3)
        .toList();
  }

  Future<String> analyzeSentiment(List<String> messages) async {
    if (messages.isEmpty) return 'neutral';
    final joined = messages.takeLast(10).join('\n');
    final response = await sendMessageDetailed(
      'Phân tích cảm xúc tổng thể của cuộc trò chuyện sau. '
      'Trả về JSON: {"sentiment":"positive"|"neutral"|"negative","score":0.0-1.0,"emoji":"..."}\n\n$joined',
      [],
      taskType: GeminiTaskType.sentimentAnalysis,
    );
    return response.text;
  }

  GenerativeModel _getOrCreateModel(GeminiTaskType taskType) {
    // Chỉ cache model chat vì được dùng thường xuyên nhất
    if (_cachedModel != null && taskType == GeminiTaskType.chat) {
      return _cachedModel!;
    }

    // firebase_ai: không cần apiKey, lấy từ Firebase project
    final model = FirebaseAI.googleAI().generativeModel(
      model: _modelId,
      generationConfig: _buildGenerationConfig(taskType),
      safetySettings: _buildSafetySettings(),
      systemInstruction: Content.system(_buildSystemPrompt(taskType)),
    );

    if (taskType == GeminiTaskType.chat) {
      _cachedModel = model;
    }

    return model;
  }

  GenerationConfig _buildGenerationConfig(GeminiTaskType taskType) {
    switch (taskType) {
      case GeminiTaskType.scamAnalysis:
      case GeminiTaskType.sentimentAnalysis:
        // responseMimeType vẫn hợp lệ trong firebase_ai
        return GenerationConfig(
          maxOutputTokens: 512,
          temperature: 0.1,
          responseMimeType: 'application/json',
        );
      case GeminiTaskType.summarize:
      case GeminiTaskType.translate:
        return GenerationConfig(
          maxOutputTokens: 1024,
          temperature: 0.4,
        );
      case GeminiTaskType.codeAssist:
        return GenerationConfig(
          maxOutputTokens: 4096,
          temperature: 0.2,
        );
      case GeminiTaskType.chat:
        // topP và topK vẫn được hỗ trợ trong firebase_ai GenerationConfig,
        // nhưng không được khuyến nghị với gemini-3.5-flash (thinking model).
        // Chỉ dùng temperature để tránh conflict với thinking pipeline.
        return GenerationConfig(
          maxOutputTokens: 2048,
          temperature: 0.7,
        );
    }
  }

  List<SafetySetting> _buildSafetySettings() => [
        // firebase_ai: enum values giữ nguyên tên (low/medium/high/none/off)
        // Đã xác nhận từ pub.dev docs: HarmBlockThreshold.medium, HarmBlockThreshold.high
        SafetySetting(HarmCategory.harassment, HarmBlockThreshold.medium, null),
        SafetySetting(HarmCategory.hateSpeech, HarmBlockThreshold.medium, null),
        SafetySetting(
            HarmCategory.sexuallyExplicit, HarmBlockThreshold.high, null),
        SafetySetting(
            HarmCategory.dangerousContent, HarmBlockThreshold.medium, null),
      ];

  String _buildSystemPrompt(GeminiTaskType taskType) {
    const basePrompt = 'Bạn là AI Assistant được tích hợp vào ứng dụng chat. '
        'Luôn phản hồi bằng tiếng Việt trừ khi được yêu cầu khác. ';

    switch (taskType) {
      case GeminiTaskType.chat:
        return '$basePrompt'
            'Trả lời thân thiện, ngắn gọn, rõ ràng. '
            'Dùng Markdown khi cần (code, danh sách, bảng). '
            'Không tiết lộ thông tin cá nhân hoặc nội bộ hệ thống.';

      case GeminiTaskType.scamAnalysis:
        return '$basePrompt'
            'Bạn là chuyên gia phát hiện lừa đảo trực tuyến Việt Nam. '
            'Phân tích chính xác, khách quan. '
            'Luôn trả về JSON hợp lệ theo đúng schema được yêu cầu.';

      case GeminiTaskType.summarize:
        return '$basePrompt'
            'Tóm tắt súc tích, giữ nguyên ý chính. '
            'Không thêm thông tin không có trong văn bản gốc.';

      case GeminiTaskType.translate:
        return '$basePrompt'
            'Diễn giải tự nhiên, phù hợp văn hóa Việt Nam. '
            'Giữ nguyên ý nghĩa gốc, chỉ điều chỉnh phong cách.';

      case GeminiTaskType.codeAssist:
        return '$basePrompt'
            'Chuyên gia lập trình. Cung cấp code chính xác, có comment. '
            'Giải thích ngắn gọn bằng tiếng Việt.';

      case GeminiTaskType.sentimentAnalysis:
        return '$basePrompt'
            'Chuyên gia tâm lý và phân tích ngôn ngữ. '
            'Luôn trả về JSON hợp lệ theo đúng schema được yêu cầu.';
    }
  }

  List<Content> _buildValidHistory(
    List<Map<String, dynamic>> historyRaw, {
    int maxMessages = 20,
  }) {
    final List<Content> contents = [];

    final recentMessages = historyRaw.length > maxMessages
        ? historyRaw.sublist(historyRaw.length - maxMessages)
        : historyRaw;

    for (final msg in recentMessages) {
      final isAI = msg['idFrom'] == AppConstants.aiAssistantId;
      final role = isAI ? 'model' : 'user';
      final content = msg['content']?.toString().trim() ?? '';

      if (content.isEmpty) continue;

      if (contents.isNotEmpty && contents.last.role == role) continue;

      contents.add(Content(role, [TextPart(content)]));
    }

    while (contents.isNotEmpty && contents.first.role == 'model') {
      contents.removeAt(0);
    }

    while (contents.isNotEmpty && contents.last.role == 'model') {
      contents.removeLast();
    }

    return contents;
  }

  Future<GeminiResponse> _sendWithRetry(
    GenerativeModel model,
    List<Content> history,
    String message,
  ) async {
    int attempt = 0;

    while (attempt <= _maxRetries) {
      try {
        final chat = model.startChat(history: history);
        final response = await chat.sendMessage(Content.text(message));

        final text = response.text;
        if (text == null || text.isEmpty) {
          final candidate = response.candidates.firstOrNull;
          // firebase_ai: FinishReason.safety (lowercase, đã xác nhận từ docs)
          if (candidate?.finishReason == FinishReason.safety) {
            return GeminiResponse.error(
              '⚠️ Nội dung bị chặn bởi bộ lọc an toàn. Vui lòng diễn đạt lại.',
            );
          }
          return GeminiResponse.error(
            'Xin lỗi, tôi không thể tạo câu trả lời lúc này.',
          );
        }

        return GeminiResponse(
          text: text,
          promptTokenCount: response.usageMetadata?.promptTokenCount,
          // firebase_ai UsageMetadata: field tên là candidatesTokenCount (có 's')
          // giống google_generative_ai, xác nhận từ JSON response schema
          candidateTokenCount: response.usageMetadata?.candidatesTokenCount,
        );
      } catch (e) {
        if (_isRateLimitError(e) && attempt < _maxRetries) {
          attempt++;
          final delay = _baseRetryDelay * (1 << attempt);
          debugPrint(
              '[GeminiService] Rate limited, retry $attempt sau ${delay.inSeconds}s');
          await Future.delayed(delay);
          continue;
        }
        rethrow;
      }
    }

    return GeminiResponse.error(
      'Xin lỗi, hệ thống đang bận. Vui lòng thử lại sau vài giây.',
    );
  }

  bool _isRateLimitError(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('429') ||
        msg.contains('quota') ||
        msg.contains('rate') ||
        msg.contains('resource_exhausted');
  }

  String _handleError(Object e) {
    final msg = e.toString().toLowerCase();

    if (msg.contains('429') || msg.contains('quota') || msg.contains('rate')) {
      return '⚠️ Đã đạt giới hạn request. Vui lòng chờ 1 phút rồi thử lại.';
    }
    if (msg.contains('403') ||
        msg.contains('permission') ||
        msg.contains('unauthenticated')) {
      return '🔑 Lỗi xác thực Firebase AI. Kiểm tra cấu hình Firebase project.';
    }
    if (msg.contains('socketexception') ||
        msg.contains('network') ||
        msg.contains('connection')) {
      return '📶 Lỗi kết nối mạng. Vui lòng kiểm tra internet.';
    }
    if (msg.contains('timeout') || msg.contains('deadline')) {
      return '⏱️ Hết thời gian chờ. Vui lòng thử lại.';
    }
    if (msg.contains('safety') || msg.contains('blocked')) {
      return '⚠️ Nội dung bị chặn bởi bộ lọc an toàn.';
    }

    debugPrint('[GeminiService] Unhandled error: $e');
    return '❌ Có lỗi xảy ra. Vui lòng thử lại sau.';
  }

  void clearModelCache() {
    _cachedModel = null;
  }
}

extension _ListTakeLast<T> on List<T> {
  List<T> takeLast(int count) {
    if (length <= count) return this;
    return sublist(length - count);
  }
}
