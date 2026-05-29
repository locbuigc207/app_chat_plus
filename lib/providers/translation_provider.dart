import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:translator/translator.dart';





class TranslationResult {
  final String originalText;
  final String translatedText;
  final String sourceLanguage;
  final String targetLanguage;
  final bool fromCache;
  final DateTime translatedAt;

  const TranslationResult({
    required this.originalText,
    required this.translatedText,
    required this.sourceLanguage,
    required this.targetLanguage,
    this.fromCache = false,
    required this.translatedAt,
  });

  @override
  String toString() => 'TranslationResult($sourceLanguage→$targetLanguage: "$translatedText")';
}





class TranslationProvider {
  GoogleTranslator? _translator;
  bool _isInitialized = false;

  
  final _cache = <String, TranslationResult>{};
  static const int _maxCacheSize = 200;

  
  final _pending = <String, Future<TranslationResult?>>{};

  TranslationProvider() {
    _initialize();
  }

  
  
  

  void _initialize() {
    try {
      _translator = GoogleTranslator();
      _isInitialized = true;
      debugPrint('✅ TranslationProvider initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize translator: $e');
      _isInitialized = false;
    }
  }

  bool get isAvailable => _isInitialized;

  
  
  

  
  
  Future<TranslationResult?> translate({
    required String text,
    required String targetLanguage,
    String sourceLanguage = 'auto',
  }) async {
    if (text.trim().isEmpty) return null;
    if (!_isInitialized || _translator == null) {
      debugPrint('⚠️ Translator not initialized');
      return null;
    }
    if (!languages.containsKey(targetLanguage)) {
      debugPrint('⚠️ Invalid target language: $targetLanguage');
      return null;
    }

    final cacheKey = '$sourceLanguage|$targetLanguage|${text.trim()}';

    
    if (_cache.containsKey(cacheKey)) {
      final cached = _cache[cacheKey]!;
      _cache.remove(cacheKey);
      _cache[cacheKey] = cached; 
      return cached.copyWith(fromCache: true);
    }

    
    if (_pending.containsKey(cacheKey)) {
      return _pending[cacheKey];
    }

    final future = _performTranslation(
      text: text,
      targetLanguage: targetLanguage,
      sourceLanguage: sourceLanguage,
      cacheKey: cacheKey,
    );

    _pending[cacheKey] = future;
    try {
      return await future;
    } finally {
      _pending.remove(cacheKey);
    }
  }

  Future<TranslationResult?> _performTranslation({
    required String text,
    required String targetLanguage,
    required String sourceLanguage,
    required String cacheKey,
  }) async {
    try {
      final preview = text.length > 50 ? '${text.substring(0, 50)}…' : text;
      debugPrint('🌐 Translating → $targetLanguage: "$preview"');

      final translation = await _translator!
          .translate(text, from: sourceLanguage, to: targetLanguage)
          .timeout(const Duration(seconds: 15));

      final detectedSource = translation.sourceLanguage.code.isNotEmpty
          ? translation.sourceLanguage.code
          : sourceLanguage;

      final result = TranslationResult(
        originalText: text,
        translatedText: translation.text,
        sourceLanguage: detectedSource,
        targetLanguage: targetLanguage,
        fromCache: false,
        translatedAt: DateTime.now(),
      );

      _cacheResult(cacheKey, result);
      debugPrint('✅ Translation done ($detectedSource→$targetLanguage)');
      return result;
    } on TimeoutException {
      debugPrint('❌ Translation timeout');
      return null;
    } catch (e) {
      debugPrint('❌ Translation error: $e');
      return null;
    }
  }

  void _cacheResult(String key, TranslationResult result) {
    if (_cache.length >= _maxCacheSize) {
      _cache.remove(_cache.keys.first); 
    }
    _cache[key] = result;
  }

  
  
  

  
  Future<String?> translateText({
    required String text,
    required String targetLanguage,
    String sourceLanguage = 'auto',
  }) async {
    final result = await translate(
      text: text,
      targetLanguage: targetLanguage,
      sourceLanguage: sourceLanguage,
    );
    return result?.translatedText;
  }

  
  Future<TranslationResult?> translateWithRetry({
    required String text,
    required String targetLanguage,
    String sourceLanguage = 'auto',
    int maxRetries = 3,
  }) async {
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      final result = await translate(
        text: text,
        targetLanguage: targetLanguage,
        sourceLanguage: sourceLanguage,
      );
      if (result != null) return result;
      if (attempt < maxRetries) {
        final delay = Duration(milliseconds: 400 * (1 << attempt));
        debugPrint('⏳ Retry ${attempt + 1}/$maxRetries in ${delay.inMilliseconds}ms…');
        await Future.delayed(delay);
      }
    }
    return null;
  }

  
  Future<List<TranslationResult?>> translateBatch({
    required List<String> texts,
    required String targetLanguage,
    String sourceLanguage = 'auto',
    int concurrency = 5,
  }) async {
    final results = List<TranslationResult?>.filled(texts.length, null);

    for (int i = 0; i < texts.length; i += concurrency) {
      final end = (i + concurrency).clamp(0, texts.length);
      final chunk = texts.sublist(i, end);
      final futures = chunk.map((t) => translate(
            text: t,
            targetLanguage: targetLanguage,
            sourceLanguage: sourceLanguage,
          ));
      final chunkResults = await Future.wait(futures);
      for (int j = 0; j < chunkResults.length; j++) {
        results[i + j] = chunkResults[j];
      }
    }

    return results;
  }

  
  
  

  
  Future<String?> detectLanguage(String text) async {
    if (!_isInitialized || _translator == null || text.trim().isEmpty) {
      return null;
    }
    try {
      final detection = await _translator!
          .translate(text, from: 'auto', to: 'en')
          .timeout(const Duration(seconds: 10));
      final code = detection.sourceLanguage.code;
      debugPrint('✅ Detected language: $code');
      return code.isNotEmpty ? code : null;
    } catch (e) {
      debugPrint('❌ Language detection error: $e');
      return null;
    }
  }

  
  bool isSameLanguage(String textLanguage, String targetLanguage) {
    final tl = textLanguage.toLowerCase().split('-').first;
    final target = targetLanguage.toLowerCase().split('-').first;
    return tl == target || (tl == 'en' && target == 'en');
  }

  
  
  

  void clearCache() {
    _cache.clear();
    debugPrint('✅ Translation cache cleared');
  }

  int get cacheSize => _cache.length;

  
  
  

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
    'sw': 'Kiswahili',
    'tl': 'Filipino',
    'af': 'Afrikaans',
    'sq': 'Shqip',
    'hy': 'Հայերեն',
    'az': 'Azərbaycanca',
    'be': 'Беларуская',
    'bs': 'Bosanski',
    'bg': 'Български',
    'ca': 'Català',
    'hr': 'Hrvatski',
    'et': 'Eesti',
    'gl': 'Galego',
    'ka': 'ქართული',
    'is': 'Íslenska',
    'kn': 'ಕನ್ನಡ',
    'lv': 'Latviešu',
    'lt': 'Lietuvių',
    'mk': 'Македонски',
    'ml': 'മലയാളം',
    'mr': 'मराठी',
    'mn': 'Монгол',
    'ne': 'नेपाली',
    'pa': 'ਪੰਜਾਬੀ',
    'sr': 'Српски',
    'si': 'සිංහල',
    'sk': 'Slovenčina',
    'sl': 'Slovenščina',
    'ur': 'اردو',
    'uz': "O'zbekcha",
    'cy': 'Cymraeg',
  };

  String getLanguageName(String code) => languages[code] ?? code.toUpperCase();

  static List<MapEntry<String, String>> get commonLanguages => const [
        MapEntry('en', 'English'),
        MapEntry('vi', 'Tiếng Việt'),
        MapEntry('zh-cn', '中文 (简体)'),
        MapEntry('zh-tw', '中文 (繁體)'),
        MapEntry('ja', '日本語'),
        MapEntry('ko', '한국어'),
        MapEntry('es', 'Español'),
        MapEntry('fr', 'Français'),
        MapEntry('de', 'Deutsch'),
        MapEntry('ru', 'Русский'),
        MapEntry('ar', 'العربية'),
        MapEntry('hi', 'हिन्दी'),
        MapEntry('pt', 'Português'),
        MapEntry('it', 'Italiano'),
        MapEntry('th', 'ไทย'),
        MapEntry('id', 'Bahasa Indonesia'),
      ];
}





extension TranslationResultCopy on TranslationResult {
  TranslationResult copyWith({
    String? originalText,
    String? translatedText,
    String? sourceLanguage,
    String? targetLanguage,
    bool? fromCache,
    DateTime? translatedAt,
  }) =>
      TranslationResult(
        originalText: originalText ?? this.originalText,
        translatedText: translatedText ?? this.translatedText,
        sourceLanguage: sourceLanguage ?? this.sourceLanguage,
        targetLanguage: targetLanguage ?? this.targetLanguage,
        fromCache: fromCache ?? this.fromCache,
        translatedAt: translatedAt ?? this.translatedAt,
      );
}
