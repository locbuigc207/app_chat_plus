// lib/utils/stateful_masking.dart
// MaskingSession: mask PII trước khi gửi lên AI, restore sau khi AI trả về.
// Dùng cho các tính năng AI (ví dụ: generateMessageTone) để giữ thông tin gốc trong kết quả.

// ─────────────────────────────────────────────────────────────────────────────
// MASK TOKEN MODEL
// ─────────────────────────────────────────────────────────────────────────────

class MaskToken {
  final String placeholder; // Ví dụ: [PHONE_1]
  final String original; // Ví dụ: 0912345678
  final String type; // Ví dụ: PHONE

  const MaskToken(this.placeholder, this.original, this.type);

  @override
  String toString() =>
      'MaskToken($type: $placeholder → ${original.length > 4 ? '${original.substring(0, 4)}***' : original})';
}

// ─────────────────────────────────────────────────────────────────────────────
// MAIN STATEFUL MASKING SESSION
// ─────────────────────────────────────────────────────────────────────────────

class MaskingSession {
  final String original;
  final String masked;
  final List<MaskToken> tokens;

  const MaskingSession({
    required this.original,
    required this.masked,
    required this.tokens,
  });

  // ── Thứ tự ưu tiên của luật Regex (Rules Priority) ─────────────────────────
  // Card đứng trước Account để tránh nhận diện sai (Card number luôn dài hơn)
  static const _rules = [
    _Rule(
      r'(?<!\d)(?:4\d{3}|5[1-5]\d{2}|3[47]\d{2}|6(?:011|5\d{2}))[\s\-]?\d{4}[\s\-]?\d{4}[\s\-]?\d{3,4}(?!\d)',
      'CARD',
    ),
    _Rule(
      r'(?<!\d)(\+84|0)(3[2-9]|5[6-9]|7[06-9]|8[0-9]|9[0-9])\d{7}(?!\d)',
      'PHONE',
    ),
    _Rule(
      r'[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}',
      'EMAIL',
    ),
    _Rule(
      r'(?<!\d)\d{9,14}(?!\d)',
      'ACCOUNT',
    ),
    _Rule(
      r'(?<!\d)(?:\d{9}|\d{12})(?!\d)',
      'ID',
    ),
    _Rule(
      r'\b[A-Z]{1,2}\d{7}\b',
      'PASSPORT',
    ),
  ];

  /// Tạo một MaskingSession từ text gốc — mask PII và ghi nhớ mapping để restore.
  ///
  /// Example:
  /// ```dart
  /// final session = MaskingSession.create('Gọi cho tôi qua 0912345678');
  /// // session.masked = 'Gọi cho tôi qua [PHONE_1]'
  /// final restored = session.restore('[PHONE_1] đã phản hồi');
  /// // restored = '0912345678 đã phản hồi'
  /// ```
  static MaskingSession create(String input) {
    if (input.trim().isEmpty) {
      return const MaskingSession(original: '', masked: '', tokens: []);
    }

    var result = input;
    final tokens = <MaskToken>[];
    final counters = <String, int>{};

    // Ghi lại danh sách các khoảng index đã bị thay thế trong chuỗi hiện tại
    final activeRanges = <_Range>[];

    for (final rule in _rules) {
      final pattern = RegExp(rule.pattern, caseSensitive: false);
      final matches = pattern.allMatches(result).toList();

      // Duyệt ngược (reversed) từ cuối chuỗi lên đầu chuỗi để giữ nguyên index của các match phía trước
      for (final match in matches.reversed) {
        // Kiểm tra xem đoạn match hiện tại có bị đè/gối lên vùng đã xử lý của các rule trước không
        final isOverlap = activeRanges.any(
          (r) => match.start < r.end && match.end > r.start,
        );
        if (isOverlap) continue;

        final originalStr = match.group(0)!;

        // Bỏ qua nếu chuỗi gốc vô tình trùng định dạng placeholder cũ
        if (originalStr.startsWith('[') && originalStr.endsWith(']')) continue;

        final count = (counters[rule.type] ?? 0) + 1;
        counters[rule.type] = count;
        final placeholder = '[${rule.type}_$count]';

        tokens.add(MaskToken(placeholder, originalStr, rule.type));

        // Tính toán độ lệch dịch chuyển độ dài của chuỗi sau khi thay thế
        final delta = placeholder.length - (match.end - match.start);

        // Tiến hành đè placeholder vào vị trí nhạy cảm
        result = result.replaceRange(match.start, match.end, placeholder);

        // Cập nhật lại tọa độ index của tất cả các placeholder nằm sau vị trí vừa thay thế
        for (final range in activeRanges) {
          if (range.start >= match.end) {
            range.start += delta;
            range.end += delta;
          }
        }

        // Đăng ký dải vùng mới cho placeholder vừa tạo
        activeRanges.add(_Range(match.start, match.start + placeholder.length));
      }
    }

    return MaskingSession(
      original: input,
      masked: result,
      tokens: List.unmodifiable(tokens),
    );
  }

  /// Khôi phục dữ liệu gốc nhạy cảm (PII) trong chuỗi AI trả về dựa trên token mapping.
  String restore(String aiOutput) {
    var result = aiOutput;
    // Duyệt reversed để khôi phục theo thứ tự an toàn nhất
    for (final token in tokens.reversed) {
      result = result.replaceAll(token.placeholder, token.original);
    }
    return result;
  }

  // ── Getters Tiện Ích ────────────────────────────────────────────────────────

  /// True nếu không có dữ liệu PII nào bị mask.
  bool get hasNoPII => tokens.isEmpty;

  /// Trả về true nếu input có chứa dữ liệu nhạy cảm.
  bool get hasSensitiveData => tokens.isNotEmpty;

  /// Số lượng PII đã thực hiện mask.
  int get maskedCount => tokens.length;

  /// Số lượng tokens chi tiết theo từng loại dữ liệu (CARD, PHONE, EMAIL...).
  Map<String, int> get tokenCounts {
    final counts = <String, int>{};
    for (final t in tokens) {
      counts[t.type] = (counts[t.type] ?? 0) + 1;
    }
    return counts;
  }

  // ── Static Utilities ───────────────────────────────────────────────────────

  /// Chỉ thực hiện lấy chuỗi đã che (masked string), bỏ qua việc khởi tạo session khôi phục.
  static String maskOnly(String input) => create(input).masked;

  /// Xử lý mask hàng loạt cho danh sách tin nhắn.
  static List<String> maskBatch(List<String> messages) {
    return messages.map(maskOnly).toList();
  }

  /// Kiểm tra nhanh xem chuỗi text có chứa bất kỳ thông tin PII nào không.
  static bool containsPII(String input) {
    if (input.isEmpty) return false;
    return _rules.any(
        (rule) => RegExp(rule.pattern, caseSensitive: false).hasMatch(input));
  }

  @override
  String toString() =>
      'MaskingSession(maskedCount: $maskedCount, hasSensitiveData: $hasSensitiveData)';
}

// ─────────────────────────────────────────────────────────────────────────────
// PRIVATE STRUCTURAL CLASSES
// ─────────────────────────────────────────────────────────────────────────────

class _Rule {
  final String pattern;
  final String type;
  const _Rule(this.pattern, this.type);
}

class _Range {
  int start;
  int end;
  _Range(this.start, this.end);
}

// ─────────────────────────────────────────────────────────────────────────────
// STRING EXTENSION
// ─────────────────────────────────────────────────────────────────────────────

extension MaskingStringExtension on String {
  /// Mask dữ liệu PII trong string (trả về chuỗi đã được giấu thông tin nhạy cảm).
  String maskPII() => MaskingSession.maskOnly(this);

  /// Tạo MaskingSession cho chuỗi hiện tại để có thể restore lại sau khi AI xử lý.
  MaskingSession toMaskingSession() => MaskingSession.create(this);
}
