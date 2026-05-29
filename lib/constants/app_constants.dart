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

  static const String gameChannelId = "game_channel";

  static const int gameInviteTimeoutSeconds = 300;

  static const int gameDisconnectTimeoutSeconds = 60;

  static const List<int> chessTimeControls = [
    0,
    180,
    300,
    600,
    900,
  ];

  static const List<String> chessTimeControlLabels = [
    'Không giới hạn',
    '3 phút',
    '5 phút',
    '10 phút',
    '15 phút',
  ];

  static const List<int> caroTurnTimers = [0, 15, 30, 60];

  static const List<String> caroTurnTimerLabels = [
    'Không giới hạn',
    '15 giây/nước',
    '30 giây/nước',
    '60 giây/nước',
  ];
}
