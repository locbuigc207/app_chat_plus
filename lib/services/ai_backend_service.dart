

import 'package:cloud_functions/cloud_functions.dart';

import '../utils/utils.dart';

class AIBackendService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  
  Future<String?> translateCommunication(
    String message,
    String targetAudience,
  ) async {
    try {
      
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

  
  Future<String?> analyzeChatContext(
    List<String> messages,
    String contextType,
    String action,
  ) async {
    try {
      
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

  
  Future<String> checkScam(String message) async {
    try {
      
      
      final safeMessage = DataMaskingUtils.maskSensitiveData(message);

      final HttpsCallable callable = _functions.httpsCallable('analyzeScam');
      final results = await callable.call(<String, dynamic>{
        'message': safeMessage,
      });
      return results.data['status'] ?? 'SAFE';
    } catch (e, stackTrace) {
      ErrorLogger.logError(e, stackTrace,
          context: 'AIBackendService.checkScam');
      return 'SAFE'; 
    }
  }

  
  Future<Map<String, dynamic>?> extractRelationshipMemory(
      List<String> messages) async {
    try {
      
      final safeMessages = DataMaskingUtils.maskMessageList(messages);
      final String chatHistory = safeMessages.join('\n');

      final HttpsCallable callable =
          _functions.httpsCallable('extractRelationshipMemory');
      final results = await callable.call(<String, dynamic>{
        'messages': chatHistory,
      });

      
      return Map<String, dynamic>.from(results.data);
    } catch (e, stackTrace) {
      ErrorLogger.logError(e, stackTrace,
          context: 'AIBackendService.extractRelationshipMemory');
      return null;
    }
  }
}
