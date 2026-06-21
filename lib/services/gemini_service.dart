// ignore_for_file: avoid_print

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../constants/constants.dart';

// ─────────────────────────────────────────────
// Exceptions
// ─────────────────────────────────────────────

class GeminiKeyExpiredException implements Exception {
  const GeminiKeyExpiredException();
  @override
  String toString() =>
      'GeminiKeyExpiredException: Gemini configuration missing or expired';
}

class GeminiUnavailableException implements Exception {
  final String reason;
  const GeminiUnavailableException(this.reason);
  @override
  String toString() => 'GeminiUnavailableException: $reason';
}

// ─────────────────────────────────────────────
// Enums & Models
// ─────────────────────────────────────────────

enum GeminiTaskType {
  chat,
  scamAnalysis,
  summarize,
  translate,
  codeAssist,
  sentimentAnalysis,
}

enum GeminiAvailability {
  available,
  keyExpired,
  rateLimited,
  networkError,
  unknown,
}

class GeminiResponse {
  final String text;
  final bool isError;
  final bool isRetryable;
  final int? promptTokenCount;
  final int? candidateTokenCount;

  const GeminiResponse({
    required this.text,
    this.isError = false,
    this.isRetryable = false,
    this.promptTokenCount,
    this.candidateTokenCount,
  });

  factory GeminiResponse.error(String message, {bool isRetryable = true}) =>
      GeminiResponse(text: message, isError: true, isRetryable: isRetryable);
}

// ─────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────

class GeminiService {
  GeminiService._internal();
  static final GeminiService _instance = GeminiService._internal();
  factory GeminiService() => _instance;

  static const String _modelIdFull = 'gemini-3.5-flash';
  static const String _modelIdLite = 'gemini-3.1-flash-lite';

  static const int _maxRetries = 3;
  static const Duration _baseRetryDelay = Duration(seconds: 2);
  static const int _maxHistoryMessages = 20;
  static const Duration _pingCacheTTL = Duration(minutes: 5);

  final Map<String, GenerativeModel> _modelCache = {};

  // ── Availability state ───────────────────────
  GeminiAvailability _availability = GeminiAvailability.available;
  DateTime? _keyExpiredAt;
  DateTime? _lastPingTime;
  bool _alertSent = false;

  GeminiAvailability get availability => _availability;
  bool get isAvailable => _availability == GeminiAvailability.available;

  // ─────────────────────────────────────────────
  // Model factory
  // ─────────────────────────────────────────────

  String _getModelIdForTask(GeminiTaskType type) {
    switch (type) {
      case GeminiTaskType.chat:
      case GeminiTaskType.codeAssist:
        return _modelIdFull;
      default:
        return _modelIdLite;
    }
  }

  GenerativeModel _buildModel(GeminiTaskType taskType) {
    return FirebaseAI.googleAI().generativeModel(
      model: _getModelIdForTask(taskType),
      generationConfig: _buildGenerationConfig(taskType),
      safetySettings: _buildSafetySettings(),
      systemInstruction: Content.system(_buildSystemPrompt(taskType)),
    );
  }

  GenerativeModel _getModel(GeminiTaskType taskType) {
    final cacheKey = taskType.name;
    return _modelCache.putIfAbsent(cacheKey, () => _buildModel(taskType));
  }

  // ─────────────────────────────────────────────
  // Public API
  // ─────────────────────────────────────────────

  Future<GeminiAvailability> checkAvailability() async {
    if (_lastPingTime != null &&
        DateTime.now().difference(_lastPingTime!) < _pingCacheTTL) {
      return _availability;
    }

    try {
      final model = _getModel(GeminiTaskType.chat);
      final chat = model.startChat();
      final response = await chat
          .sendMessage(Content.text('ping'))
          .timeout(const Duration(seconds: 10));

      if (response.text != null) {
        _availability = GeminiAvailability.available;
        _alertSent = false;
        _lastPingTime = DateTime.now();
        debugPrint('[GeminiService] ✅ Available');
      }
    } catch (e) {
      _availability = _classifyAvailability(e);
      debugPrint('[GeminiService] ⚠️ Availability: $_availability — $e');
    }
    return _availability;
  }

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
      return GeminiResponse.error(
        'Tin nhắn không được trống.',
        isRetryable: false,
      );
    }

    try {
      final model = _getModel(taskType);
      final history = _buildValidHistory(
        historyRaw,
        maxMessages: _maxHistoryMessages,
      );
      return await _sendWithRetry(model, history, message);
    } on GeminiKeyExpiredException {
      rethrow;
    } catch (e) {
      return GeminiResponse.error(_handleError(e), isRetryable: true);
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

    int attempt = 0;
    while (attempt <= _maxRetries) {
      try {
        final model = _getModel(taskType);
        final history = _buildValidHistory(historyRaw);
        final chat = model.startChat(history: history);

        final stream = chat.sendMessageStream(Content.text(message));
        await for (final chunk in stream) {
          final text = chunk.text;
          if (text != null && text.isNotEmpty) yield text;
        }
        break;
      } on GeminiKeyExpiredException {
        yield '🔑 Gemini service configuration error. Vui lòng liên hệ admin.';
        break;
      } catch (e) {
        if (_isRateLimitError(e) && attempt < _maxRetries) {
          attempt++;
          final delay = _baseRetryDelay * (1 << attempt);
          debugPrint(
            '[GeminiService] Stream Rate limited, retry $attempt sau ${delay.inSeconds}s',
          );
          await Future.delayed(delay);
          continue;
        }
        yield _handleError(e);
        break;
      }
    }
  }

  // ─────────────────────────────────────────────
  // Task-specific methods
  // ─────────────────────────────────────────────

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

    final toneDesc =
        {
          'friendly': 'thân thiện, tự nhiên',
          'formal': 'lịch sự, trang trọng',
          'casual': 'vui vẻ, hài hước', // Đã sửa lỗi chính tả tại đây
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

  // ─────────────────────────────────────────────
  // Private — Model config
  // ─────────────────────────────────────────────

  GenerationConfig _buildGenerationConfig(GeminiTaskType taskType) {
    switch (taskType) {
      case GeminiTaskType.scamAnalysis:
      case GeminiTaskType.sentimentAnalysis:
        return GenerationConfig(
          maxOutputTokens: 512,
          temperature: 0.1,
          responseMimeType: 'application/json',
        );
      case GeminiTaskType.summarize:
      case GeminiTaskType.translate:
        return GenerationConfig(maxOutputTokens: 1024, temperature: 0.4);
      case GeminiTaskType.codeAssist:
        return GenerationConfig(maxOutputTokens: 4096, temperature: 0.2);
      case GeminiTaskType.chat:
        return GenerationConfig(maxOutputTokens: 2048, temperature: 0.7);
    }
  }

  List<SafetySetting> _buildSafetySettings() => [
    SafetySetting(HarmCategory.harassment, HarmBlockThreshold.medium, null),
    SafetySetting(HarmCategory.hateSpeech, HarmBlockThreshold.medium, null),
    SafetySetting(HarmCategory.sexuallyExplicit, HarmBlockThreshold.high, null),
    SafetySetting(
      HarmCategory.dangerousContent,
      HarmBlockThreshold.medium,
      null,
    ),
  ];

  String _buildSystemPrompt(GeminiTaskType taskType) {
    const base =
        'Bạn là AI Assistant được tích hợp vào ứng dụng chat. '
        'Luôn phản hồi bằng tiếng Việt trừ khi được yêu cầu khác. ';
    switch (taskType) {
      case GeminiTaskType.chat:
        return '${base}Trả lời thân thiện, ngắn gọn, rõ ràng. '
            'Dùng Markdown khi cần (code, danh sách, bảng). '
            'Không tiết lộ thông tin cá nhân hoặc nội bộ hệ thống.';
      case GeminiTaskType.scamAnalysis:
        return '${base}Bạn là chuyên gia phát hiện lừa đảo trực tuyến Việt Nam. '
            'Phân tích chính xác, khách quan. '
            'Luôn trả về JSON hợp lệ theo đúng schema được yêu cầu.';
      case GeminiTaskType.summarize:
        return '${base}Tóm tắt súc tích, giữ nguyên ý chính. '
            'Không thêm thông tin không có trong văn bản gốc.';
      case GeminiTaskType.translate:
        return '${base}Diễn giải tự nhiên, phù hợp văn hóa Việt Nam. '
            'Giữ nguyên ý nghĩa gốc, chỉ điều chỉnh phong cách.';
      case GeminiTaskType.codeAssist:
        return '${base}Chuyên gia lập trình. Cung cấp code chính xác, có comment. '
            'Giải thích ngắn gọn bằng tiếng Việt.';
      case GeminiTaskType.sentimentAnalysis:
        return '${base}Chuyên gia tâm lý và phân tích ngôn ngữ. '
            'Luôn trả về JSON hợp lệ theo đúng schema được yêu cầu.';
    }
  }

  // ─────────────────────────────────────────────
  // Private — History
  // ─────────────────────────────────────────────

  List<Content> _buildValidHistory(
    List<Map<String, dynamic>> historyRaw, {
    int maxMessages = 20,
  }) {
    final List<Content> contents = [];

    final recent = historyRaw.length > maxMessages
        ? historyRaw.sublist(historyRaw.length - maxMessages)
        : historyRaw;

    for (final msg in recent) {
      final isAI = msg['idFrom'] == AppConstants.aiAssistantId;
      final role = isAI ? 'model' : 'user';
      final content = msg['content']?.toString().trim() ?? '';

      if (content.isEmpty) continue;

      // Guard Check: Chặn tuyệt đối nội dung Ciphertext bị lọt vào History Local Database
      if (content.startsWith('{"iv":') || content.startsWith('eyJ')) continue;

      if (contents.isNotEmpty && contents.last.role == role) {
        final existingParts = contents.last.parts
            .whereType<TextPart>()
            .map((p) => p.text)
            .join('\n');
        contents.last = Content(role, [TextPart('$existingParts\n$content')]);
        continue;
      }

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

  // ─────────────────────────────────────────────
  // Private — Retry
  // ─────────────────────────────────────────────

  Future<GeminiResponse> _sendWithRetry(
    GenerativeModel model,
    List<Content> history,
    String message,
  ) async {
    int attempt = 0;

    while (attempt <= _maxRetries) {
      try {
        final chat = model.startChat(history: history);
        final response = await chat
            .sendMessage(Content.text(message))
            .timeout(const Duration(seconds: 30));

        if (response.promptFeedback?.blockReason != null) {
          return GeminiResponse.error(
            '⚠️ Câu hỏi của bạn bị chặn (Lý do: ${response.promptFeedback?.blockReason?.name}).',
            isRetryable: false,
          );
        }

        final text = response.text;
        final candidate = response.candidates.firstOrNull;

        if (text == null || text.isEmpty) {
          if (candidate?.finishReason == FinishReason.safety) {
            return GeminiResponse.error(
              '⚠️ Nội dung trả lời bị chặn bởi bộ lọc an toàn. Vui lòng diễn đạt lại.',
              isRetryable: false,
            );
          } else if (candidate?.finishReason == FinishReason.recitation) {
            return GeminiResponse.error(
              '⚠️ Câu trả lời bị chặn do vấn đề trùng lặp bản quyền dữ liệu.',
              isRetryable: false,
            );
          }
          return GeminiResponse.error(
            'Xin lỗi, tôi không thể tạo câu trả lời lúc này.',
            isRetryable: true,
          );
        }

        if (_availability != GeminiAvailability.available) {
          _availability = GeminiAvailability.available;
          _alertSent = false;
        }

        String finalText = text;
        if (candidate?.finishReason == FinishReason.maxTokens) {
          finalText += '\n\n*(Câu trả lời bị cắt ngang do giới hạn độ dài)*';
        }

        return GeminiResponse(
          text: finalText,
          promptTokenCount: response.usageMetadata?.promptTokenCount,
          candidateTokenCount: response.usageMetadata?.candidatesTokenCount,
        );
      } catch (e) {
        if (_isAuthError(e)) {
          await _handleAuthError(e);
          return GeminiResponse.error(
            '🔑 Lỗi xác thực hoặc API Key hết hạn. Vui lòng liên hệ admin.',
            isRetryable: false,
          );
        }

        if (_isRateLimitError(e) && attempt < _maxRetries) {
          attempt++;
          final delay = _baseRetryDelay * (1 << attempt);
          debugPrint(
            '[GeminiService] Rate limited, retry $attempt sau ${delay.inSeconds}s',
          );
          _availability = GeminiAvailability.rateLimited;
          await Future.delayed(delay);
          continue;
        }

        return GeminiResponse.error(_handleError(e), isRetryable: true);
      }
    }

    return GeminiResponse.error(
      'Xin lỗi, hệ thống đang bận. Vui lòng thử lại sau vài giây.',
      isRetryable: true,
    );
  }

  // ─────────────────────────────────────────────
  // Private — Error classification
  // ─────────────────────────────────────────────

  bool _isAuthError(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('api key expired') ||
        msg.contains('api_key_invalid') ||
        msg.contains('key expired') ||
        msg.contains('403') ||
        msg.contains('permission_denied') ||
        msg.contains('unauthenticated') ||
        msg.contains('invalid_api_key') ||
        e is GeminiKeyExpiredException;
  }

  bool _isRateLimitError(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('429') ||
        msg.contains('quota') ||
        msg.contains('rate') ||
        msg.contains('resource_exhausted');
  }

  GeminiAvailability _classifyAvailability(Object e) {
    if (e is GeminiKeyExpiredException) return GeminiAvailability.keyExpired;
    if (_isAuthError(e)) return GeminiAvailability.keyExpired;
    if (_isRateLimitError(e)) return GeminiAvailability.rateLimited;
    final msg = e.toString().toLowerCase();
    if (msg.contains('socket') ||
        msg.contains('network') ||
        msg.contains('connection')) {
      return GeminiAvailability.networkError;
    }
    return GeminiAvailability.unknown;
  }

  String _handleError(Object e) {
    if (e is GeminiKeyExpiredException) {
      return '🔑 Gemini service configuration error. Vui lòng liên hệ admin.';
    }

    final msg = e.toString().toLowerCase();

    if (msg.contains('api key expired') ||
        msg.contains('key expired') ||
        msg.contains('api_key_invalid') ||
        msg.contains('invalid_api_key')) {
      return '🔑 Gemini service configuration error. Vui lòng liên hệ admin.';
    }
    if (msg.contains('429') || msg.contains('quota') || msg.contains('rate')) {
      return '⚠️ Đã đạt giới hạn request. Vui lòng chờ 1 phút rồi thử lại.';
    }
    if (msg.contains('403') ||
        msg.contains('permission') ||
        msg.contains('unauthenticated')) {
      return '🔑 Lỗi xác thực hệ thống AI. Vui lòng thử lại sau.';
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

  // ─────────────────────────────────────────────
  // Private — Auth error handler
  // ─────────────────────────────────────────────

  Future<void> _handleAuthError(Object e) async {
    _availability = GeminiAvailability.keyExpired;
    _keyExpiredAt ??= DateTime.now();

    debugPrint('[GeminiService] 🔑 Auth error: $e');

    if (_alertSent) return;
    _alertSent = true;

    try {
      await FirebaseFirestore.instance
          .collection('system_alerts')
          .doc('gemini_key')
          .set({
            'status': 'expired',
            'error': e.toString(),
            'detected_at': FieldValue.serverTimestamp(),
            'detected_by': FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
            'notified': false,
          }, SetOptions(merge: true));

      debugPrint('[GeminiService] 📣 Alert sent to Firestore');
    } catch (firestoreError) {
      debugPrint('[GeminiService] ⚠️ Không gửi được alert: $firestoreError');
    }
  }

  // ─────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────

  void clearModelCache() {
    _modelCache.clear();
    debugPrint('[GeminiService] 🗑️ Model cache cleared');
  }

  void dispose() {
    clearModelCache();
  }
}

// ─────────────────────────────────────────────
// Extension
// ─────────────────────────────────────────────

extension _ListTakeLast<T> on List<T> {
  List<T> takeLast(int count) {
    if (length <= count) return this;
    return sublist(length - count);
  }
}
