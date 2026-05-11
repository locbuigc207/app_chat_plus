import 'package:google_generative_ai/google_generative_ai.dart';

import '../constants/constants.dart';

class GeminiService {
  Future<String> sendMessage(
      String message, List<Map<String, dynamic>> historyRaw) async {
    try {
      // Khởi tạo model gemini-1.5-flash (nhanh và miễn phí)
      final model = GenerativeModel(
        model: 'gemini-1.5-flash',
        apiKey: AppConstants.geminiApiKey,
        systemInstruction: Content.system(
            "Bạn là một AI Assistant hữu ích, được tích hợp trực tiếp vào ứng dụng chat. "
            "Bạn có khả năng trả lời câu hỏi, viết code, tạo bảng và phân tích. "
            "Hãy phản hồi bằng tiếng Việt một cách thân thiện, ngắn gọn và định dạng Markdown (Artifacts) rõ ràng."),
      );

      // Chuyển đổi lịch sử chat cũ sang định dạng của Gemini (nếu có)
      List<Content> chatHistory = historyRaw.map((msg) {
        final role =
            msg['idFrom'] == AppConstants.aiAssistantId ? 'model' : 'user';
        return Content(role, [TextPart(msg['content'])]);
      }).toList();

      // Bắt đầu phiên chat
      final chat = model.startChat(history: chatHistory);

      // Gửi tin nhắn mới
      final response = await chat.sendMessage(Content.text(message));

      return response.text ?? "Xin lỗi, tôi không thể tạo câu trả lời lúc này.";
    } catch (e) {
      return "Lỗi kết nối Gemini AI: $e\nVui lòng kiểm tra lại kết nối mạng hoặc API Key.";
    }
  }
}
