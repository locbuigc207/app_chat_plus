// ignore_for_file: avoid_print

/// Tiện ích che giấu dữ liệu nhạy cảm trong nội dung tin nhắn trước khi:
/// - Ghi log / debug
/// - Gửi đến AI (phân tích ngôn ngữ, gợi ý...)
/// - Hiển thị trong preview thông báo
/// - Tìm kiếm toàn văn (full-text search index)
///
/// **KHÔNG dùng thay thế cho mã hóa** — đây là lớp bảo vệ bổ sung (defense in depth).
library data_masking_utils;

// =========================================================
// MODELS
// =========================================================

/// Kết quả sau khi masking, có thể truy xuất chi tiết những gì bị ẩn.
class MaskingResult {
  /// Văn bản sau khi đã che giấu dữ liệu nhạy cảm.
  final String maskedText;

  /// Danh sách các loại dữ liệu nhạy cảm được phát hiện.
  final List<MaskingHit> hits;

  /// Tổng số lần thay thế.
  int get totalReplaced => hits.fold(0, (sum, h) => sum + h.count);

  /// Có phát hiện dữ liệu nhạy cảm không.
  bool get hasSensitiveData => hits.isNotEmpty;

  const MaskingResult({
    required this.maskedText,
    required this.hits,
  });

  @override
  String toString() =>
      'MaskingResult(replaced=$totalReplaced, text="${maskedText.length > 40 ? maskedText.substring(0, 40) + "..." : maskedText}")';
}

/// Một loại dữ liệu nhạy cảm được phát hiện và số lần xuất hiện.
class MaskingHit {
  final SensitiveDataType type;
  final int count;

  const MaskingHit(this.type, this.count);
}

/// Các loại dữ liệu nhạy cảm được hỗ trợ.
enum SensitiveDataType {
  phoneNumber,
  email,
  bankAccount,
  creditCard,
  nationalId, // CMND/CCCD Việt Nam
  passport,
  ipAddress,
  jwtToken,
  privateKey, // RSA/PEM private key
  otp, // Mã OTP 4-6 số trong ngữ cảnh rõ ràng
  url, // URL có chứa token/credential
  coordinates, // Tọa độ GPS
}

// =========================================================
// CONFIGURATION
// =========================================================

/// Cấu hình masking — chọn loại dữ liệu cần ẩn.
class MaskingConfig {
  final Set<SensitiveDataType> enabledTypes;

  const MaskingConfig({required this.enabledTypes});

  /// Ẩn tất cả — dùng cho log/debug.
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

  /// Chỉ ẩn PII cơ bản — dùng cho AI context.
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

  /// Chỉ ẩn thông tin tài chính.
  static const financialOnly = MaskingConfig(
    enabledTypes: {
      SensitiveDataType.bankAccount,
      SensitiveDataType.creditCard,
    },
  );

  /// Ẩn thông tin bảo mật / credentials.
  static const securityOnly = MaskingConfig(
    enabledTypes: {
      SensitiveDataType.jwtToken,
      SensitiveDataType.privateKey,
      SensitiveDataType.otp,
      SensitiveDataType.url,
    },
  );
}

// =========================================================
// MASKING RULES
// =========================================================

/// Một rule masking: regex + token thay thế.
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

// =========================================================
// DATA MASKING UTILS
// =========================================================

class DataMaskingUtils {
  DataMaskingUtils._();

  // ── Tất cả rules ─────────────────────────────────────
  static final List<_MaskingRule> _rules = [
    // Số điện thoại Việt Nam (0xxx hoặc +84xxx, 10 số)
    _MaskingRule(
      type: SensitiveDataType.phoneNumber,
      pattern: RegExp(
          r'(?<!\d)(\+84|0)(3[2-9]|5[6-9]|7[0|6-9]|8[0-9]|9[0-9])\d{7}(?!\d)'),
      replacement: '[SĐT_ĐÃ_ẨN]',
    ),

    // Email
    _MaskingRule(
      type: SensitiveDataType.email,
      pattern: RegExp(r'[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}',
          caseSensitive: false),
      replacement: '[EMAIL_ĐÃ_ẨN]',
    ),

    // Số thẻ tín dụng/ghi nợ (Luhn-format, 13-19 chữ số, có/không có dấu cách/gạch)
    _MaskingRule(
      type: SensitiveDataType.creditCard,
      pattern:
          RegExp(r'(?<!\d)(?:4\d{3}|5[1-5]\d{2}|3[47]\d{2}|6(?:011|5\d{2}))'
              r'[\s\-]?\d{4}[\s\-]?\d{4}[\s\-]?\d{3,4}(?!\d)'),
      replacement: '[THẺ_ĐÃ_ẨN]',
    ),

    // Số tài khoản ngân hàng Việt Nam (9-14 chữ số, không phải số điện thoại)
    _MaskingRule(
      type: SensitiveDataType.bankAccount,
      pattern: RegExp(r'(?<!\d)\d{9,14}(?!\d)'),
      replacement: '[STK_ĐÃ_ẨN]',
    ),

    // CMND (9 số) / CCCD (12 số)
    _MaskingRule(
      type: SensitiveDataType.nationalId,
      pattern: RegExp(r'(?<!\d)(?:\d{9}|\d{12})(?!\d)'),
      replacement: '[CMND_ĐÃ_ẨN]',
    ),

    // Hộ chiếu Việt Nam (B + 7 số, hoặc 2 chữ cái + 7 số)
    _MaskingRule(
      type: SensitiveDataType.passport,
      pattern: RegExp(r'\b[A-Z]{1,2}\d{7}\b'),
      replacement: '[HỘ_CHIẾU_ĐÃ_ẨN]',
    ),

    // Địa chỉ IP (IPv4)
    _MaskingRule(
      type: SensitiveDataType.ipAddress,
      pattern: RegExp(r'\b(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}'
          r'(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\b'),
      replacement: '[IP_ĐÃ_ẨN]',
    ),

    // JWT Token (3 phần base64 ngăn cách bởi dấu chấm)
    _MaskingRule(
      type: SensitiveDataType.jwtToken,
      pattern:
          RegExp(r'eyJ[A-Za-z0-9_\-]+\.eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+'),
      replacement: '[JWT_ĐÃ_ẨN]',
    ),

    // PEM Private Key (bắt đầu bằng -----BEGIN)
    _MaskingRule(
      type: SensitiveDataType.privateKey,
      pattern: RegExp(
          r'-----BEGIN[^-]+PRIVATE KEY-----[\s\S]+?-----END[^-]+PRIVATE KEY-----',
          multiLine: true),
      replacement: '[PRIVATE_KEY_ĐÃ_ẨN]',
    ),

    // OTP — mã 4-6 chữ số trong ngữ cảnh rõ ràng (kèm từ khóa otp/mã/code)
    _MaskingRule(
      type: SensitiveDataType.otp,
      pattern: RegExp(
          r'(?:otp|mã\s*otp|mã\s*xác\s*nhận|verification\s*code|code)[:\s]+(\d{4,6})',
          caseSensitive: false),
      replacement: '[OTP_ĐÃ_ẨN]',
    ),

    // URL có chứa token/key/password trong query string
    _MaskingRule(
      type: SensitiveDataType.url,
      pattern: RegExp(
          r'https?://[^\s]*(?:token|key|secret|password|auth|access_token|api_key)[^\s]*',
          caseSensitive: false),
      replacement: '[URL_NHẠY_CẢM_ĐÃ_ẨN]',
    ),

    // Tọa độ GPS (latitude, longitude dạng decimal)
    _MaskingRule(
      type: SensitiveDataType.coordinates,
      pattern: RegExp(
          r'(?:lat|latitude|lng|longitude|tọa\s*độ)[:\s]+(-?\d{1,3}\.\d+)[,\s]+(-?\d{1,3}\.\d+)',
          caseSensitive: false),
      replacement: '[TỌA_ĐỘ_ĐÃ_ẨN]',
    ),
  ];

  // =========================================================
  // 1. MASK SINGLE STRING
  // =========================================================

  /// Che giấu dữ liệu nhạy cảm trong một chuỗi.
  ///
  /// [config] mặc định là [MaskingConfig.all].
  /// Trả về [MaskingResult] với text đã mask và danh sách loại bị phát hiện.
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

  /// Phiên bản đơn giản — chỉ trả về chuỗi đã mask.
  static String maskText(
    String input, {
    MaskingConfig config = MaskingConfig.all,
  }) =>
      mask(input, config: config).maskedText;

  // =========================================================
  // 2. MASK BATCH
  // =========================================================

  /// Che giấu dữ liệu nhạy cảm cho danh sách chuỗi.
  static List<String> maskList(
    List<String> messages, {
    MaskingConfig config = MaskingConfig.all,
  }) =>
      messages.map((msg) => maskText(msg, config: config)).toList();

  /// Che giấu dữ liệu nhạy cảm trong list và trả về cả kết quả chi tiết.
  static List<MaskingResult> maskListDetailed(
    List<String> messages, {
    MaskingConfig config = MaskingConfig.all,
  }) =>
      messages.map((msg) => mask(msg, config: config)).toList();

  // =========================================================
  // 3. MASK MAP / JSON
  // =========================================================

  /// Che giấu dữ liệu trong một Map<String, dynamic> (ví dụ Firestore document).
  /// Chỉ mask các value kiểu String; các kiểu khác giữ nguyên.
  static Map<String, dynamic> maskMap(
    Map<String, dynamic> data, {
    MaskingConfig config = MaskingConfig.all,
    Set<String>? skipKeys, // Các key không cần mask (vd: 'userId', 'timestamp')
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
            key, maskMap(value, config: config, skipKeys: skipKeys));
      }
      return MapEntry(key, value);
    });
  }

  // =========================================================
  // 4. DETECTION ONLY (không thay đổi text)
  // =========================================================

  /// Kiểm tra xem chuỗi có chứa dữ liệu nhạy cảm không.
  static bool containsSensitiveData(
    String input, {
    MaskingConfig config = MaskingConfig.all,
  }) {
    if (input.isEmpty) return false;
    return _rules
        .where((r) => config.enabledTypes.contains(r.type))
        .any((r) => r.pattern.hasMatch(input));
  }

  /// Trả về danh sách các loại dữ liệu nhạy cảm tìm thấy trong chuỗi.
  static Set<SensitiveDataType> detectTypes(
    String input, {
    MaskingConfig config = MaskingConfig.all,
  }) {
    if (input.isEmpty) return {};
    return _rules
        .where((r) =>
            config.enabledTypes.contains(r.type) && r.pattern.hasMatch(input))
        .map((r) => r.type)
        .toSet();
  }

  // =========================================================
  // 5. PARTIAL MASKING (hiển thị một phần)
  // =========================================================

  /// Ẩn một phần số điện thoại: `0912345678` → `091****678`
  static String maskPhonePartial(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7) return '[SĐT_ĐÃ_ẨN]';
    return '${digits.substring(0, 3)}${'*' * (digits.length - 6)}${digits.substring(digits.length - 3)}';
  }

  /// Ẩn một phần email: `user@example.com` → `us**@example.com`
  static String maskEmailPartial(String email) {
    final atIndex = email.indexOf('@');
    if (atIndex <= 1) return '[EMAIL_ĐÃ_ẨN]';
    final local = email.substring(0, atIndex);
    final domain = email.substring(atIndex);
    final visibleChars = (local.length * 0.3).ceil().clamp(1, 3);
    return '${local.substring(0, visibleChars)}${'*' * (local.length - visibleChars)}$domain';
  }

  /// Ẩn một phần số tài khoản: `123456789012` → `****6789****`
  static String maskBankAccountPartial(String account) {
    final digits = account.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 8) return '[STK_ĐÃ_ẨN]';
    final visibleStart = 0;
    final visibleEnd = 4;
    return '${'*' * visibleEnd}${digits.substring(visibleEnd, digits.length - visibleEnd)}${'*' * visibleEnd}';
  }

  // =========================================================
  // 6. AI CONTEXT PREPARATION
  // =========================================================

  /// Chuẩn bị danh sách tin nhắn để gửi đến AI (ẩn PII, giữ ngữ cảnh ngôn ngữ).
  /// Dùng [MaskingConfig.piiOnly] để không ẩn quá nhiều làm mất nghĩa câu.
  static List<String> prepareForAI(List<String> messages) =>
      maskList(messages, config: MaskingConfig.piiOnly);

  /// Chuẩn bị một tin nhắn đơn cho AI.
  static String prepareMessageForAI(String message) =>
      maskText(message, config: MaskingConfig.piiOnly);

  // =========================================================
  // 7. LOG SAFE
  // =========================================================

  /// Che giấu toàn bộ dữ liệu nhạy cảm trước khi ghi log.
  /// Dùng [MaskingConfig.all] để đảm bảo không có gì lọt vào log.
  static String sanitizeForLog(String message) =>
      maskText(message, config: MaskingConfig.all);

  /// Tóm tắt nội dung tin nhắn để log (cắt ngắn + mask).
  static String summarizeForLog(String message, {int maxLength = 80}) {
    final masked = sanitizeForLog(message);
    if (masked.length <= maxLength) return masked;
    return '${masked.substring(0, maxLength)}…[+${masked.length - maxLength} chars]';
  }
}
