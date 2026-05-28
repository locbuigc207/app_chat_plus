// ignore_for_file: avoid_print

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import '../constants/constants.dart';

// =========================================================
// MODELS
// =========================================================

/// Loại nhiệm vụ của AI — ảnh hưởng đến system prompt và config.
enum GeminiTaskType {
  chat, // Trò chuyện thông thường
  scamAnalysis, // Phát hiện lừa đảo
  summarize, // Tóm tắt cuộc trò chuyện
  translate, // Dịch/diễn giải
  codeAssist, // Hỗ trợ lập trình
  sentimentAnalysis, // Phân tích cảm xúc
}

/// Kết quả trả về từ Gemini, bao gồm text và metadata.
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

// =========================================================
// GEMINI SERVICE
// =========================================================

/// Service tương tác trực tiếp với Gemini API từ phía client (Flutter).
///
/// Tính năng:
/// - Retry tự động khi bị rate-limit (exponential backoff).
/// - Hỗ trợ streaming response cho UX mượt mà.
/// - Multi-task: chat, scam analysis, summarize, translate, code...
/// - Kiểm tra tính hợp lệ của lịch sử hội thoại (role alternation).
/// - Xử lý lỗi chi tiết với thông báo tiếng Việt thân thiện.
class GeminiService {
  // ── Singleton ──────────────────────────────────────────
  GeminiService._internal();
  static final GeminiService _instance = GeminiService._internal();
  factory GeminiService() => _instance;

  // ── Config ─────────────────────────────────────────────
  static const String _modelId = 'gemini-2.0-flash';
  static const int _maxRetries = 3;
  static const Duration _baseRetryDelay = Duration(seconds: 2);
  static const int _maxHistoryMessages = 20; // Tránh vượt context window

  // ── Cache model instance để tránh khởi tạo lại mỗi request ──
  GenerativeModel? _cachedModel;
  String? _cachedApiKey;

  // =========================================================
  // 1. SEND MESSAGE (Chat thông thường)
  // =========================================================

  /// Gửi tin nhắn đến Gemini và nhận phản hồi.
  ///
  /// [message]: Tin nhắn người dùng.
  /// [historyRaw]: Lịch sử hội thoại dạng `[{'idFrom': '...', 'content': '...'}]`.
  Future<String> sendMessage(
    String message,
    List<Map<String, dynamic>> historyRaw,
  ) async {
    final response = await sendMessageDetailed(message, historyRaw);
    return response.text;
  }

  /// Phiên bản trả về [GeminiResponse] đầy đủ metadata.
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

  // =========================================================
  // 2. STREAMING RESPONSE
  // =========================================================

  /// Gửi tin nhắn và trả về Stream<String> để hiển thị từng chunk.
  /// Phù hợp cho response dài — UX mượt hơn so với chờ toàn bộ.
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

  // =========================================================
  // 3. SPECIALIZED TASKS
  // =========================================================

  /// Phân tích một tin nhắn xem có dấu hiệu scam/lừa đảo không.
  /// Trả về JSON string: `{"level":"SAFE"|"WARNING"|"SCAM","reason":"..."}`
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

  /// Tóm tắt danh sách tin nhắn thành đoạn văn ngắn.
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

  /// Diễn giải lại tin nhắn phù hợp với đối tượng nhận.
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

  /// Gợi ý 3 cách trả lời ngắn gọn cho tin nhắn cuối cùng.
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

  /// Phân tích cảm xúc (sentiment) của danh sách tin nhắn.
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

  // =========================================================
  // 4. MODEL MANAGEMENT
  // =========================================================

  /// Lấy hoặc tạo mới model Gemini với system prompt phù hợp task.
  GenerativeModel _getOrCreateModel(GeminiTaskType taskType) {
    final apiKey = _resolveApiKey();

    // Tái sử dụng model nếu cùng API key và chat task
    if (_cachedModel != null &&
        _cachedApiKey == apiKey &&
        taskType == GeminiTaskType.chat) {
      return _cachedModel!;
    }

    final model = GenerativeModel(
      model: _modelId,
      apiKey: apiKey,
      generationConfig: _buildGenerationConfig(taskType),
      safetySettings: _buildSafetySettings(),
      systemInstruction: Content.system(_buildSystemPrompt(taskType)),
    );

    if (taskType == GeminiTaskType.chat) {
      _cachedModel = model;
      _cachedApiKey = apiKey;
    }

    return model;
  }

  String _resolveApiKey() {
    final key = dotenv.env['GEMINI_API_KEY'];
    if (key == null || key.isEmpty) {
      throw const _ApiKeyMissingException();
    }
    return key;
  }

  GenerationConfig _buildGenerationConfig(GeminiTaskType taskType) {
    switch (taskType) {
      case GeminiTaskType.scamAnalysis:
      case GeminiTaskType.sentimentAnalysis:
        return GenerationConfig(
          maxOutputTokens: 512,
          temperature: 0.1, // Thấp hơn để output nhất quán/deterministic
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
        return GenerationConfig(
          maxOutputTokens: 2048,
          temperature: 0.7,
          topP: 0.9,
          topK: 40,
        );
    }
  }

  List<SafetySetting> _buildSafetySettings() => [
        SafetySetting(HarmCategory.harassment, HarmBlockThreshold.medium),
        SafetySetting(HarmCategory.hateSpeech, HarmBlockThreshold.medium),
        SafetySetting(HarmCategory.sexuallyExplicit, HarmBlockThreshold.high),
        SafetySetting(HarmCategory.dangerousContent, HarmBlockThreshold.medium),
      ];

  String _buildSystemPrompt(GeminiTaskType taskType) {
    const basePrompt = 'Bạn là AI Assistant được tích hợp vào ứng dụng chat. '
        'Luôn phản hồi bằng tiếng Việt trừ khi được yêu cầu khác. ';

    switch (taskType) {
      case GeminiTaskType.chat:
        return '${basePrompt}'
            'Trả lời thân thiện, ngắn gọn, rõ ràng. '
            'Dùng Markdown khi cần (code, danh sách, bảng). '
            'Không tiết lộ thông tin cá nhân hoặc nội bộ hệ thống.';

      case GeminiTaskType.scamAnalysis:
        return '${basePrompt}'
            'Bạn là chuyên gia phát hiện lừa đảo trực tuyến Việt Nam. '
            'Phân tích chính xác, khách quan. '
            'Luôn trả về JSON hợp lệ theo đúng schema được yêu cầu.';

      case GeminiTaskType.summarize:
        return '${basePrompt}'
            'Tóm tắt súc tích, giữ nguyên ý chính. '
            'Không thêm thông tin không có trong văn bản gốc.';

      case GeminiTaskType.translate:
        return '${basePrompt}'
            'Diễn giải tự nhiên, phù hợp văn hóa Việt Nam. '
            'Giữ nguyên ý nghĩa gốc, chỉ điều chỉnh phong cách.';

      case GeminiTaskType.codeAssist:
        return '${basePrompt}'
            'Chuyên gia lập trình. Cung cấp code chính xác, có comment. '
            'Giải thích ngắn gọn bằng tiếng Việt.';

      case GeminiTaskType.sentimentAnalysis:
        return '${basePrompt}'
            'Chuyên gia tâm lý và phân tích ngôn ngữ. '
            'Luôn trả về JSON hợp lệ theo đúng schema được yêu cầu.';
    }
  }

  // =========================================================
  // 5. HISTORY BUILDER
  // =========================================================

  /// Xây dựng lịch sử hội thoại hợp lệ cho Gemini API.
  ///
  /// Quy tắc Gemini:
  /// - Phải xen kẽ user/model.
  /// - Không được bắt đầu bằng 'model'.
  /// - Không được có 2 role giống nhau liên tiếp.
  List<Content> _buildValidHistory(
    List<Map<String, dynamic>> historyRaw, {
    int maxMessages = 20,
  }) {
    final List<Content> contents = [];

    // Lấy N tin nhắn gần nhất
    final recentMessages = historyRaw.length > maxMessages
        ? historyRaw.sublist(historyRaw.length - maxMessages)
        : historyRaw;

    for (final msg in recentMessages) {
      final isAI = msg['idFrom'] == AppConstants.aiAssistantId;
      final role = isAI ? 'model' : 'user';
      final content = msg['content']?.toString().trim() ?? '';

      if (content.isEmpty) continue;

      // Bỏ qua nếu role liên tiếp bị trùng
      if (contents.isNotEmpty && contents.last.role == role) continue;

      contents.add(Content(role, [TextPart(content)]));
    }

    // Không được bắt đầu bằng 'model'
    while (contents.isNotEmpty && contents.first.role == 'model') {
      contents.removeAt(0);
    }

    // Không được kết thúc bằng 'model' (message cuối phải là user)
    while (contents.isNotEmpty && contents.last.role == 'model') {
      contents.removeLast();
    }

    return contents;
  }

  // =========================================================
  // 6. RETRY LOGIC
  // =========================================================

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
          // Kiểm tra safety block
          final candidate = response.candidates.firstOrNull;
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
          candidateTokenCount: response.usageMetadata?.candidatesTokenCount,
        );
      } catch (e) {
        if (_isRateLimitError(e) && attempt < _maxRetries) {
          attempt++;
          // Exponential backoff: 2s, 4s, 8s
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

  // =========================================================
  // 7. ERROR HANDLING
  // =========================================================

  String _handleError(Object e) {
    if (e is _ApiKeyMissingException) {
      return '🔑 Lỗi: API Key Gemini chưa được thiết lập. '
          'Kiểm tra file .env với biến GEMINI_API_KEY.';
    }

    final msg = e.toString().toLowerCase();

    if (msg.contains('429') || msg.contains('quota') || msg.contains('rate')) {
      return '⚠️ Đã đạt giới hạn request. Vui lòng chờ 1 phút rồi thử lại.';
    }
    if (msg.contains('403') ||
        msg.contains('api key') ||
        msg.contains('api_key')) {
      return '🔑 API Key không hợp lệ hoặc chưa được kích hoạt. '
          'Kiểm tra lại Google AI Studio.';
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

  // =========================================================
  // 8. UTILS
  // =========================================================

  /// Xóa cache model (khi đổi API key hoặc cài đặt).
  void clearModelCache() {
    _cachedModel = null;
    _cachedApiKey = null;
  }
}

// =========================================================
// INTERNAL EXCEPTIONS
// =========================================================

class _ApiKeyMissingException implements Exception {
  const _ApiKeyMissingException();
  @override
  String toString() =>
      'ApiKeyMissingException: GEMINI_API_KEY chưa được thiết lập';
}

// =========================================================
// EXTENSION HELPERS
// =========================================================

extension _ListTakeLast<T> on List<T> {
  List<T> takeLast(int count) {
    if (length <= count) return this;
    return sublist(length - count);
  }
}
