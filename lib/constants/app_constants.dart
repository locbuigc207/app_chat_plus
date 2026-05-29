class AppConstants {
  static const appTitle = "Flutter Chat";
  static const loginTitle = "Login";
  static const homeTitle = "Home";
  static const settingsTitle = "Settings";
  static const fullPhotoTitle = "Full Photo";
  static const String aiAssistantId = "ai_assistant_gemini_001";
  static const String aiAssistantName = "Gemini AI Assistant";
  static const String aiAssistantAvatar =
      "https://ui-avatars.com/api/?name=Gemini+AI&background=1A73E8&color=fff";
  static const String messageChannelId = "message_channel";
  static const String reminderChannelId = "reminder_channel";
  static const String callChannelId = "call_channel";

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
