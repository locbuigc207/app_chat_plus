import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import '../constants/constants.dart';

class GeminiService {
  
  static const String _model = 'gemini-2.0-flash';
  static const int _maxRetries = 2;
  static const Duration _retryDelay = Duration(seconds: 5);

  Future<String> sendMessage(
      String message, List<Map<String, dynamic>> historyRaw) async {
    try {
      final apiKey = dotenv.env['GEMINI_API_KEY'];

      if (apiKey == null || apiKey.isEmpty) {
        return "Lỗi: API Key của Gemini chưa được thiết lập. Vui lòng kiểm tra file .env";
      }

      final model = GenerativeModel(
        model: _model,
        apiKey: apiKey,
        generationConfig: GenerationConfig(
          maxOutputTokens: 1024, 
          temperature: 0.7,
        ),
        systemInstruction: Content.system(
          "Bạn là một AI Assistant hữu ích, được tích hợp trực tiếp vào ứng dụng chat. "
          "Bạn có khả năng trả lời câu hỏi, viết code, tạo bảng và phân tích. "
          "Hãy phản hồi bằng tiếng Việt một cách thân thiện, ngắn gọn và định dạng Markdown rõ ràng.",
        ),
      );

      
      final List<Content> chatHistory = _buildValidHistory(historyRaw);

      return await _sendWithRetry(model, chatHistory, message);
    } catch (e) {
      return _handleError(e);
    }
  }

  
  List<Content> _buildValidHistory(List<Map<String, dynamic>> historyRaw) {
    final List<Content> contents = [];

    for (final msg in historyRaw) {
      final role =
          msg['idFrom'] == AppConstants.aiAssistantId ? 'model' : 'user';
      final content = msg['content']?.toString() ?? '';
      if (content.isEmpty) continue;

      
      if (contents.isNotEmpty && contents.last.role == role) continue;

      contents.add(Content(role, [TextPart(content)]));
    }

    
    if (contents.isNotEmpty && contents.first.role == 'model') {
      contents.removeAt(0);
    }

    return contents;
  }

  Future<String> _sendWithRetry(
    GenerativeModel model,
    List<Content> history,
    String message,
  ) async {
    int attempt = 0;

    while (attempt <= _maxRetries) {
      try {
        final chat = model.startChat(history: history);
        final response = await chat.sendMessage(Content.text(message));
        return response.text ??
            "Xin lỗi, tôi không thể tạo câu trả lời lúc này.";
      } catch (e) {
        final isRateLimit = e.toString().contains('429') ||
            e.toString().toLowerCase().contains('quota') ||
            e.toString().toLowerCase().contains('rate');

        if (isRateLimit && attempt < _maxRetries) {
          attempt++;
          
          await Future.delayed(_retryDelay * attempt);
          continue;
        }
        rethrow;
      }
    }

    return "Xin lỗi, hệ thống đang bận. Vui lòng thử lại sau vài giây.";
  }

  String _handleError(Object e) {
    final errorStr = e.toString();

    if (errorStr.contains('429') || errorStr.toLowerCase().contains('quota')) {
      return "⚠️ Đã đạt giới hạn request miễn phí. Vui lòng chờ 1 phút rồi thử lại.";
    }
    if (errorStr.contains('403') ||
        errorStr.toLowerCase().contains('api key')) {
      return "🔑 API Key không hợp lệ hoặc chưa được kích hoạt. Kiểm tra lại Google AI Studio.";
    }
    if (errorStr.contains('SocketException') || errorStr.contains('network')) {
      return "📶 Lỗi kết nối mạng. Vui lòng kiểm tra internet.";
    }

    return "❌ Lỗi: $e\nVui lòng thử lại.";
  }
}
