// lib/utils/data_masking_utils.dart

class DataMaskingUtils {
  /// Hàm che giấu các thông tin định danh (PII) trong chuỗi văn bản
  static String maskSensitiveData(String input) {
    if (input.isEmpty) return input;

    String output = input;

    // 1. Che giấu Số điện thoại (Định dạng VN: 09xxx, +84xxx)
    final phoneRegex = RegExp(r'(0|\+84)[3|5|7|8|9][0-9]{8}\b');
    output = output.replaceAll(phoneRegex, '[SĐT_ĐÃ_ẨN]');

    // 2. Che giấu Email
    final emailRegex =
        RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}');
    output = output.replaceAll(emailRegex, '[EMAIL_ĐÃ_ẨN]');

    // 3. Che giấu Số tài khoản ngân hàng / Thẻ tín dụng (10 - 16 số liên tiếp)
    final bankRegex = RegExp(r'\b\d{10,16}\b');
    output = output.replaceAll(bankRegex, '[SỐ_TÀI_KHOẢN_ĐÃ_ẨN]');

    return output;
  }

  /// Áp dụng cho một danh sách tin nhắn
  static List<String> maskMessageList(List<String> messages) {
    return messages.map((msg) => maskSensitiveData(msg)).toList();
  }
}
