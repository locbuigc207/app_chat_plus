class AppConstants {
  static const appTitle = "Flutter Chat";
  static const loginTitle = "Login";
  static const homeTitle = "Home";
  static const settingsTitle = "Settings";
  static const fullPhotoTitle = "Full Photo";

  // ─── AI Assistant ────────────────────────────────────────────────────────
  static const String aiAssistantId = "ai_assistant_gemini_001";
  static const String aiAssistantName = "Gemini AI Assistant";

  // [FIX] Thay thế URL 3rd-party (ui-avatars) bằng asset cục bộ để đảm bảo UI không bị vỡ khi mất mạng/lỗi service.
  // Lưu ý: Đảm bảo bạn đã có file ảnh tương ứng (ví dụ: gemini_avatar.png) trong thư mục images/ và đã khai báo trong pubspec.yaml
  static const String aiAssistantAvatar = "images/gemini_avatar.png";

  // [FIX] Tập hợp các ID của Bot, dùng chung để loại trừ logic trên toàn app (Mã hóa E2EE, Insight, AutoPilot)
  static const Set<String> aiBotUserIds = {aiAssistantId};

  // [FIX] Tập trung hóa các magic strings được sử dụng ở gemini_service.dart và các tính năng hệ thống
  static const String systemAlertsCollection = "system_alerts";
  static const String geminiKeyDoc = "gemini_key";

  // ─── Notification Channels ───────────────────────────────────────────────
  static const String messageChannelId = "message_channel";
  static const String reminderChannelId = "reminder_channel";
  static const String callChannelId = "call_channel";

  // Bổ sung Channel ID cho cuộc gọi nhóm để tránh lỗi trùng lặp (Khắc phục Lỗi 1 & Lỗi 2)
  static const String groupCallChannelId = "group_call_channel";

  // Bổ sung Channel ID cho cuộc gọi đang diễn ra để chạy chế độ silent (Khắc phục Lỗi 3)
  static const String ongoingCallChannelId = "ongoing_call_channel";

  // ─── Game Center ──────────────────────────────────────────────────────────

  /// Channel ID cho notification thách đấu game.
  static const String gameChannelId = "game_channel";

  /// Thời gian tối đa chờ đối thủ chấp nhận (giây). Sau đó trận bị huỷ.
  static const int gameInviteTimeoutSeconds = 300; // 5 phút

  /// Thời gian chờ khi player disconnect trước khi xử thua (giây).
  static const int gameDisconnectTimeoutSeconds = 60;

  /// Các mốc thời gian cờ vua (giây) hiển thị trong game_setup_page.
  static const List<int> chessTimeControls = [
    0, // Không giới hạn
    180, // Chớp nhoáng 3 phút
    300, // Nhanh 5 phút
    600, // Nhanh 10 phút
    900, // Nhanh 15 phút
  ];

  /// Nhãn hiển thị tương ứng với chessTimeControls.
  static const List<String> chessTimeControlLabels = [
    'Không giới hạn',
    '3 phút',
    '5 phút',
    '10 phút',
    '15 phút',
  ];

  /// Các mốc turn timer cho Caro (giây/nước). 0 = không giới hạn.
  static const List<int> caroTurnTimers = [0, 15, 30, 60];

  /// Nhãn tương ứng.
  static const List<String> caroTurnTimerLabels = [
    'Không giới hạn',
    '15 giây/nước',
    '30 giây/nước',
    '60 giây/nước',
  ];
}