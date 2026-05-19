// lib/services/ai_backend_service.dart

import 'package:cloud_functions/cloud_functions.dart';

import '../utils/utils.dart';

class AIBackendService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  // Gọi API Dịch phong cách giao tiếp
  Future<String?> translateCommunication(
    String message,
    String targetAudience,
  ) async {
    try {
      // BẢO MẬT: Che dữ liệu nhạy cảm
      final safeMessage = DataMaskingUtils.maskSensitiveData(message);

      final HttpsCallable callable =
          _functions.httpsCallable('translateCommunication');
      final results = await callable.call(<String, dynamic>{
        'message': safeMessage,
        'targetAudience': targetAudience,
      });
      return results.data['translatedText'];
    } catch (e, stackTrace) {
      ErrorLogger.logError(e, stackTrace,
          context: 'AIBackendService.translateCommunication');
      return null;
    }
  }

  // Gọi API Phân tích Context
  Future<String?> analyzeChatContext(
    List<String> messages,
    String contextType,
    String action,
  ) async {
    try {
      // BẢO MẬT: Che toàn bộ lịch sử trò chuyện
      final safeMessages = DataMaskingUtils.maskMessageList(messages);
      final String chatHistory = safeMessages.join('\n');

      final HttpsCallable callable =
          _functions.httpsCallable('analyzeChatContext');
      final results = await callable.call(<String, dynamic>{
        'messages': chatHistory,
        'contextType': contextType,
        'action': action,
      });
      return results.data['analysisResult'];
    } catch (e, stackTrace) {
      ErrorLogger.logError(e, stackTrace,
          context: 'AIBackendService.analyzeChatContext');
      return null;
    }
  }

  // Gọi API Kiểm tra lừa đảo
  Future<String> checkScam(String message) async {
    try {
      // Đối với Scam Detection, che số tài khoản nhưng giữ lại link
      // để AI nhận diện URL độc hại. Điều chỉnh logic trong DataMasking nếu cần.
      final safeMessage = DataMaskingUtils.maskSensitiveData(message);

      final HttpsCallable callable = _functions.httpsCallable('analyzeScam');
      final results = await callable.call(<String, dynamic>{
        'message': safeMessage,
      });
      return results.data['status'] ?? 'SAFE';
    } catch (e, stackTrace) {
      ErrorLogger.logError(e, stackTrace,
          context: 'AIBackendService.checkScam');
      return 'SAFE'; // Mặc định an toàn nếu lỗi mạng để không block UX
    }
  }

  // Gọi API Trích xuất Kỷ niệm & Điểm số quan hệ
  Future<Map<String, dynamic>?> extractRelationshipMemory(
      List<String> messages) async {
    try {
      // BẢO MẬT: Che toàn bộ lịch sử trò chuyện
      final safeMessages = DataMaskingUtils.maskMessageList(messages);
      final String chatHistory = safeMessages.join('\n');

      final HttpsCallable callable =
          _functions.httpsCallable('extractRelationshipMemory');
      final results = await callable.call(<String, dynamic>{
        'messages': chatHistory,
      });

      // Map trả về từ JSON của Gemini
      return Map<String, dynamic>.from(results.data);
    } catch (e, stackTrace) {
      ErrorLogger.logError(e, stackTrace,
          context: 'AIBackendService.extractRelationshipMemory');
      return null;
    }
  }
}
