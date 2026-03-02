// lib/providers/translation_provider.dart - COMPLETE FIXED
import 'dart:async';

import 'package:translator/translator.dart';

class TranslationProvider {
  GoogleTranslator? _translator;
  bool _isInitialized = false;

  TranslationProvider() {
    _initialize();
  }

  void _initialize() {
    try {
      _translator = GoogleTranslator();
      _isInitialized = true;
      print('✅ Translation provider initialized');
    } catch (e) {
      print('❌ Failed to initialize translator: $e');
      _isInitialized = false;
    }
  }

  /// Translate text to target language
  Future<String?> translateText({
    required String text,
    required String targetLanguage,
    String sourceLanguage = 'auto',
  }) async {
    if (!_isInitialized || _translator == null) {
      print('⚠️ Translator not initialized');
      return text; // Return original text
    }

    // Validate input
    if (text.trim().isEmpty) {
      return null;
    }

    // Validate target language
    if (!languages.containsKey(targetLanguage)) {
      print('⚠️ Invalid target language: $targetLanguage');
      return text;
    }

    try {
      print(
          '🌐 Translating to $targetLanguage: "${text.substring(0, text.length > 50 ? 50 : text.length)}..."');

      final translation = await _translator!
          .translate(
        text,
        from: sourceLanguage,
        to: targetLanguage,
      )
          .timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('Translation timeout');
        },
      );

      print('✅ Translation successful');
      return translation.text;
    } on TimeoutException {
      print('❌ Translation timeout');
      return null;
    } catch (e) {
      print('❌ Translation error: $e');
      // Return original text if translation fails
      return null;
    }
  }

  /// Detect language of text
  Future<String?> detectLanguage(String text) async {
    if (!_isInitialized || _translator == null) {
      return null;
    }

    if (text.trim().isEmpty) {
      return null;
    }

    try {
      final detection = await _translator!
          .translate(text, from: 'auto', to: 'en')
          .timeout(const Duration(seconds: 10));

      final sourceLanguage = detection.sourceLanguage.toString();
      print('✅ Detected language: $sourceLanguage');
      return sourceLanguage;
    } catch (e) {
      print('❌ Language detection error: $e');
      return null;
    }
  }

  /// Check if translation is available
  bool get isAvailable => _isInitialized;

  /// Popular language codes with full names
  static const Map<String, String> languages = {
    'en': 'English',
    'vi': 'Tiếng Việt',
    'zh-cn': '中文 (简体)',
    'zh-tw': '中文 (繁體)',
    'ja': '日本語',
    'ko': '한국어',
    'es': 'Español',
    'fr': 'Français',
    'de': 'Deutsch',
    'ru': 'Русский',
    'ar': 'العربية',
    'hi': 'हिन्दी',
    'pt': 'Português',
    'it': 'Italiano',
    'th': 'ไทย',
    'id': 'Bahasa Indonesia',
    'ms': 'Bahasa Melayu',
    'nl': 'Nederlands',
    'pl': 'Polski',
    'tr': 'Türkçe',
    'uk': 'Українська',
    'cs': 'Čeština',
    'sv': 'Svenska',
    'da': 'Dansk',
    'fi': 'Suomi',
    'no': 'Norsk',
    'el': 'Ελληνικά',
    'he': 'עברית',
    'ro': 'Română',
    'hu': 'Magyar',
    'bn': 'বাংলা',
    'ta': 'தமிழ்',
    'te': 'తెలుగు',
  };

  /// Get language name from code
  String getLanguageName(String code) {
    return languages[code] ?? code.toUpperCase();
  }

  /// Get most common languages (for quick selection)
  static List<MapEntry<String, String>> get commonLanguages {
    return [
      MapEntry('en', 'English'),
      MapEntry('vi', 'Tiếng Việt'),
      MapEntry('zh-cn', '中文 (简体)'),
      MapEntry('ja', '日本語'),
      MapEntry('ko', '한국어'),
      MapEntry('es', 'Español'),
      MapEntry('fr', 'Français'),
      MapEntry('de', 'Deutsch'),
    ];
  }

  /// Translate with auto-retry
  Future<String?> translateWithRetry({
    required String text,
    required String targetLanguage,
    String sourceLanguage = 'auto',
    int maxRetries = 2,
  }) async {
    for (int i = 0; i <= maxRetries; i++) {
      final result = await translateText(
        text: text,
        targetLanguage: targetLanguage,
        sourceLanguage: sourceLanguage,
      );

      if (result != null) {
        return result;
      }

      if (i < maxRetries) {
        print('⏳ Retrying translation (${i + 1}/$maxRetries)...');
        await Future.delayed(Duration(milliseconds: 500 * (i + 1)));
      }
    }

    return null;
  }
}
