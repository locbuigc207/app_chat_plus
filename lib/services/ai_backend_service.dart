import 'package:cloud_functions/cloud_functions.dart';

import '../utils/error_logger.dart';

class AIBackendService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  // Gọi API Dịch phong cách giao tiếp
  Future<String?> translateCommunication(
    String message,
    String targetAudience,
  ) async {
    try {
      final HttpsCallable callable =
          _functions.httpsCallable('translateCommunication');
      final results = await callable.call(<String, dynamic>{
        'message': message,
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
      final HttpsCallable callable =
          _functions.httpsCallable('analyzeChatContext');
      final String chatHistory = messages.join('\n');

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
      final HttpsCallable callable = _functions.httpsCallable('analyzeScam');
      final results = await callable.call(<String, dynamic>{
        'message': message,
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
      final HttpsCallable callable =
          _functions.httpsCallable('extractRelationshipMemory');
      final String chatHistory = messages.join('\n');

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
