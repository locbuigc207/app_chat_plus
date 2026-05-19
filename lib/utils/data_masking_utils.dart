

class DataMaskingUtils {
  
  static String maskSensitiveData(String input) {
    if (input.isEmpty) return input;

    String output = input;

    
    final phoneRegex = RegExp(r'(0|\+84)[3|5|7|8|9][0-9]{8}\b');
    output = output.replaceAll(phoneRegex, '[SĐT_ĐÃ_ẨN]');

    
    final emailRegex =
        RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}');
    output = output.replaceAll(emailRegex, '[EMAIL_ĐÃ_ẨN]');

    
    final bankRegex = RegExp(r'\b\d{10,16}\b');
    output = output.replaceAll(bankRegex, '[SỐ_TÀI_KHOẢN_ĐÃ_ẨN]');

    return output;
  }

  
  static List<String> maskMessageList(List<String> messages) {
    return messages.map((msg) => maskSensitiveData(msg)).toList();
  }
}
