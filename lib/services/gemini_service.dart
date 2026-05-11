import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import '../constants/constants.dart';

class GeminiService {
  Future<String> sendMessage(
      String message, List<Map<String, dynamic>> historyRaw) async {
    try {
      final apiKey = dotenv.env['GEMINI_API_KEY'];

      if (apiKey == null || apiKey.isEmpty) {
        return "Lỗi: API Key của Gemini chưa được thiết lập. Vui lòng kiểm tra file .env";
      }

      final model = GenerativeModel(
        model: 'gemini-1.5-flash',
        apiKey: apiKey,
        systemInstruction: Content.system(
            "Bạn là một AI Assistant hữu ích, được tích hợp trực tiếp vào ứng dụng chat. "
            "Bạn có khả năng trả lời câu hỏi, viết code, tạo bảng và phân tích. "
            "Hãy phản hồi bằng tiếng Việt một cách thân thiện, ngắn gọn và định dạng Markdown rõ ràng."),
      );

      List<Content> chatHistory = historyRaw.map((msg) {
        final role =
            msg['idFrom'] == AppConstants.aiAssistantId ? 'model' : 'user';
        return Content(role, [TextPart(msg['content'])]);
      }).toList();

      final chat = model.startChat(history: chatHistory);
      final response = await chat.sendMessage(Content.text(message));

      return response.text ?? "Xin lỗi, tôi không thể tạo câu trả lời lúc này.";
    } catch (e) {
      return "Lỗi kết nối Gemini AI: $e\nVui lòng kiểm tra lại kết nối mạng hoặc API Key.";
    }
  }
}
