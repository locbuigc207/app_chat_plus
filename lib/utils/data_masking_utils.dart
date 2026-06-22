// ignore_for_file: avoid_print

library;

// ─────────────────────────────────────────────────────────────────────────────
// MODELS & ENUMS
// ─────────────────────────────────────────────────────────────────────────────

class MaskingResult {
  final String maskedText;
  final List<MaskingHit> hits;

  int get totalReplaced => hits.fold(0, (sum, h) => sum + h.count);

  bool get hasSensitiveData => hits.isNotEmpty;

  const MaskingResult({required this.maskedText, required this.hits});

  @override
  String toString() =>
      'MaskingResult(replaced=$totalReplaced, text="${maskedText.length > 40 ? "${maskedText.substring(0, 40)}..." : maskedText}")';
}

class MaskingHit {
  final SensitiveDataType type;
  final int count;

  const MaskingHit(this.type, this.count);
}

enum SensitiveDataType {
  phoneNumber,
  email,
  bankAccount,
  creditCard,
  nationalId,
  passport,
  ipAddress,
  jwtToken,
  privateKey,
  otp,
  url,
  coordinates,
}

class MaskingConfig {
  final Set<SensitiveDataType> enabledTypes;

  const MaskingConfig({required this.enabledTypes});

  static const all = MaskingConfig(
    enabledTypes: {
      SensitiveDataType.phoneNumber,
      SensitiveDataType.email,
      SensitiveDataType.bankAccount,
      SensitiveDataType.creditCard,
      SensitiveDataType.nationalId,
      SensitiveDataType.passport,
      SensitiveDataType.ipAddress,
      SensitiveDataType.jwtToken,
      SensitiveDataType.privateKey,
      SensitiveDataType.otp,
      SensitiveDataType.url,
      SensitiveDataType.coordinates,
    },
  );

  static const piiOnly = MaskingConfig(
    enabledTypes: {
      SensitiveDataType.phoneNumber,
      SensitiveDataType.email,
      SensitiveDataType.bankAccount,
      SensitiveDataType.creditCard,
      SensitiveDataType.nationalId,
      SensitiveDataType.passport,
    },
  );

  static const financialOnly = MaskingConfig(
    enabledTypes: {SensitiveDataType.bankAccount, SensitiveDataType.creditCard},
  );

  static const securityOnly = MaskingConfig(
    enabledTypes: {
      SensitiveDataType.jwtToken,
      SensitiveDataType.privateKey,
      SensitiveDataType.otp,
      SensitiveDataType.url,
    },
  );
}

class _MaskingRule {
  final SensitiveDataType type;
  final RegExp pattern;
  final String replacement;

  const _MaskingRule({
    required this.type,
    required this.pattern,
    required this.replacement,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// DATA MASKING UTILS
// ─────────────────────────────────────────────────────────────────────────────

class DataMaskingUtils {
  DataMaskingUtils._();

  static final List<_MaskingRule> _rules = [
    _MaskingRule(
      type: SensitiveDataType.phoneNumber,
      pattern: RegExp(
        r'(?<!\d)(\+84|0)(3[2-9]|5[6-9]|7[06-9]|8[0-9]|9[0-9])\d{7}(?!\d)',
      ),
      replacement: '[SĐT_ĐÃ_ẨN]',
    ),
    _MaskingRule(
      type: SensitiveDataType.email,
      pattern: RegExp(
        r'[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}',
        caseSensitive: false,
      ),
      replacement: '[EMAIL_ĐÃ_ẨN]',
    ),
    _MaskingRule(
      type: SensitiveDataType.creditCard,
      pattern: RegExp(
        r'(?<!\d)(?:4\d{3}|5[1-5]\d{2}|3[47]\d{2}|6(?:011|5\d{2}))'
        r'[\s\-]?\d{4}[\s\-]?\d{4}[\s\-]?\d{3,4}(?!\d)',
      ),
      replacement: '[THẺ_ĐÃ_ẨN]',
    ),
    _MaskingRule(
      type: SensitiveDataType.bankAccount,
      pattern: RegExp(r'(?<!\d)\d{9,14}(?!\d)'),
      replacement: '[STK_ĐÃ_ẨN]',
    ),
    _MaskingRule(
      type: SensitiveDataType.nationalId,
      pattern: RegExp(r'(?<!\d)(?:\d{9}|\d{12})(?!\d)'),
      replacement: '[CMND_ĐÃ_ẨN]',
    ),
    _MaskingRule(
      type: SensitiveDataType.passport,
      pattern: RegExp(r'\b[A-Z]{1,2}\d{7}\b'),
      replacement: '[HỘ_CHIẾU_ĐÃ_ẨN]',
    ),
    _MaskingRule(
      type: SensitiveDataType.ipAddress,
      pattern: RegExp(
        r'\b(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}'
        r'(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\b',
      ),
      replacement: '[IP_ĐÃ_ẨN]',
    ),
    _MaskingRule(
      type: SensitiveDataType.jwtToken,
      pattern: RegExp(
        r'eyJ[A-Za-z0-9_\-]+\.eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+',
      ),
      replacement: '[JWT_ĐÃ_ẨN]',
    ),
    _MaskingRule(
      type: SensitiveDataType.privateKey,
      pattern: RegExp(
        r'-----BEGIN[^-]+PRIVATE KEY-----[\s\S]+?-----END[^-]+PRIVATE KEY-----',
        multiLine: true,
      ),
      replacement: '[PRIVATE_KEY_ĐÃ_ẨN]',
    ),
    _MaskingRule(
      type: SensitiveDataType.otp,
      pattern: RegExp(
        r'(?:otp|mã\s*otp|mã\s*xác\s*nhận|verification\s*code|code)[:\s]+(\d{4,6})',
        caseSensitive: false,
      ),
      replacement: '[OTP_ĐÃ_ẨN]',
    ),
    _MaskingRule(
      type: SensitiveDataType.url,
      pattern: RegExp(
        r'https?://[^\s]*(?:token|key|secret|password|auth|access_token|api_key)[^\s]*',
        caseSensitive: false,
      ),
      replacement: '[URL_NHẠY_CẢM_ĐÃ_ẨN]',
    ),
    _MaskingRule(
      type: SensitiveDataType.coordinates,
      pattern: RegExp(
        r'(?:lat|latitude|lng|longitude|tọa\s*độ)[:\s]+(-?\d{1,3}\.\d+)[,\s]+(-?\d{1,3}\.\d+)',
        caseSensitive: false,
      ),
      replacement: '[TỌA_ĐỘ_ĐÃ_ẨN]',
    ),
  ];

  static MaskingResult mask(
    String input, {
    MaskingConfig config = MaskingConfig.all,
  }) {
    if (input.isEmpty) return MaskingResult(maskedText: input, hits: []);

    String output = input;
    final hits = <MaskingHit>[];

    for (final rule in _rules) {
      if (!config.enabledTypes.contains(rule.type)) continue;

      final matches = rule.pattern.allMatches(output);
      final count = matches.length;
      if (count > 0) {
        output = output.replaceAll(rule.pattern, rule.replacement);
        hits.add(MaskingHit(rule.type, count));
      }
    }

    return MaskingResult(maskedText: output, hits: hits);
  }

  static String maskText(
    String input, {
    MaskingConfig config = MaskingConfig.all,
  }) => mask(input, config: config).maskedText;

  static List<String> maskList(
    List<String> messages, {
    MaskingConfig config = MaskingConfig.all,
  }) => messages.map((msg) => maskText(msg, config: config)).toList();

  static List<MaskingResult> maskListDetailed(
    List<String> messages, {
    MaskingConfig config = MaskingConfig.all,
  }) => messages.map((msg) => mask(msg, config: config)).toList();

  static Map<String, dynamic> maskMap(
    Map<String, dynamic> data, {
    MaskingConfig config = MaskingConfig.all,
    Set<String>? skipKeys,
  }) {
    return data.map((key, value) {
      if (skipKeys != null && skipKeys.contains(key)) {
        return MapEntry(key, value);
      }
      if (value is String) {
        return MapEntry(key, maskText(value, config: config));
      }
      if (value is List) {
        return MapEntry(
          key,
          value
              .map((e) => e is String ? maskText(e, config: config) : e)
              .toList(),
        );
      }
      if (value is Map<String, dynamic>) {
        return MapEntry(
          key,
          maskMap(value, config: config, skipKeys: skipKeys),
        );
      }
      return MapEntry(key, value);
    });
  }

  static bool containsSensitiveData(
    String input, {
    MaskingConfig config = MaskingConfig.all,
  }) {
    if (input.isEmpty) return false;
    return _rules
        .where((r) => config.enabledTypes.contains(r.type))
        .any((r) => r.pattern.hasMatch(input));
  }

  static Set<SensitiveDataType> detectTypes(
    String input, {
    MaskingConfig config = MaskingConfig.all,
  }) {
    if (input.isEmpty) return {};
    return _rules
        .where(
          (r) =>
              config.enabledTypes.contains(r.type) && r.pattern.hasMatch(input),
        )
        .map((r) => r.type)
        .toSet();
  }

  static String maskPhonePartial(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7) return '[SĐT_ĐÃ_ẨN]';
    return '${digits.substring(0, 3)}${'*' * (digits.length - 6)}${digits.substring(digits.length - 3)}';
  }

  static String maskEmailPartial(String email) {
    final atIndex = email.indexOf('@');
    if (atIndex <= 1) return '[EMAIL_ĐÃ_ẨN]';
    final local = email.substring(0, atIndex);
    final domain = email.substring(atIndex);
    final visibleChars = (local.length * 0.3).ceil().clamp(1, 3);
    return '${local.substring(0, visibleChars)}${'*' * (local.length - visibleChars)}$domain';
  }

  static String maskBankAccountPartial(String account) {
    final digits = account.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 8) return '[STK_ĐÃ_ẨN]';
    final visibleEnd = 4;
    // Fix logic hiển thị để giữ phần số cuối (VD: **** **** 1234)
    return '${'*' * (digits.length - visibleEnd)}${digits.substring(digits.length - visibleEnd)}';
  }

  static List<String> prepareForAI(List<String> messages) =>
      maskList(messages, config: MaskingConfig.piiOnly);

  static String prepareMessageForAI(String message) =>
      maskText(message, config: MaskingConfig.piiOnly);

  static String sanitizeForLog(String message) =>
      maskText(message, config: MaskingConfig.all);

  static String summarizeForLog(String message, {int maxLength = 80}) {
    final masked = sanitizeForLog(message);
    if (masked.length <= maxLength) return masked;
    return '${masked.substring(0, maxLength)}…[+${masked.length - maxLength} chars]';
  }
}
