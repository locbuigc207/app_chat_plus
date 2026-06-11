import 'package:flutter/material.dart';

// ══════════════════════════════════════════════════════════════════════════════
// GroupCallConstants
// Toàn bộ hằng số cấu hình cho tính năng Group Call v2
// ══════════════════════════════════════════════════════════════════════════════
class GroupCallConstants {
  GroupCallConstants._();

  // ── Agora ──────────────────────────────────────────────────────────────────
  static const int maxParticipants = 16;
  static const int callTimeoutSeconds = 60;
  static const int reactionCooldownMs = 400;
  static const int maxRecentReactions = 30;
  static const int audioVolumeInterval = 300; // ms
  static const int audioVolumeSmooth = 3;
  static const int videoWidth = 1280;
  static const int videoHeight = 720;
  static const int videoFps = 30;
  static const int videoBitrate = 1500; // kbps
  static const int speakerResetDelayMs = 3000;

  // ── Chat ───────────────────────────────────────────────────────────────────
  static const int chatMessageLimit = 200;
  static const String chatSubCollection = 'call_chat';

  // ── UI timing ──────────────────────────────────────────────────────────────
  static const int controlsHideDelayMs = 5000;
  static const int toastDismissMs = 3000;
  static const int reactionBurstMs = 2800;
  static const int countdownSeconds = 45; // incoming call
  static const int waitingRoomPollMs = 2000;

  // ── Notification channels (phải khớp với AppConstants) ────────────────────
  static const String callChannelId = 'call_channel';
  static const String ongoingChannelId = 'ongoing_call_channel';
  static const int incomingNotifId = 88001;
  static const int ongoingNotifId = 88002;

  // ── Firestore collections ──────────────────────────────────────────────────
  static const String groupCallsCollection = 'group_calls';
  static const String fcmTriggersCollection = '_fcm_triggers';
  static const String usersCollection = 'users';

  // ── Firestore user fields ──────────────────────────────────────────────────
  static const String fieldFcmToken = 'fcmToken';
  static const String fieldNickname = 'nickname';
  static const String fieldPhotoUrl = 'photoUrl';

  // ── Call status strings ────────────────────────────────────────────────────
  static const String statusCalling = 'calling';
  static const String statusWaiting = 'waiting';
  static const String statusOngoing = 'ongoing';
  static const String statusEnded = 'ended';
  static const String statusMissed = 'missed';

  // ── Active statuses (for Firestore queries) ────────────────────────────────
  static const List<String> activeStatuses = [
    statusCalling,
    statusWaiting,
    statusOngoing,
  ];

  // ── Layout breakpoints ─────────────────────────────────────────────────────
  static const int gridCols1Threshold = 1; // ≤1 remote → 1 col
  static const int gridCols2Threshold = 4; // 2-4 remote → 2 cols
  //                                               // >4  remote → 3 cols

  // ── Reaction emojis ────────────────────────────────────────────────────────
  static const List<String> reactionEmojis = [
    '👍',
    '❤️',
    '👏',
    '😂',
    '😮',
    '🔥',
    '😎',
    '🎉',
  ];

  // ── Virtual background blur sigmas ────────────────────────────────────────
  static const double blurSigmaLight = 8.0;
  static const double blurSigmaStrong = 20.0;
}

// ══════════════════════════════════════════════════════════════════════════════
// GroupCallTheme
// Design tokens cho toàn bộ Group Call UI
// ══════════════════════════════════════════════════════════════════════════════
class GroupCallTheme {
  GroupCallTheme._();

  // ── Background palette ─────────────────────────────────────────────────────
  static const Color bg = Color(0xFF080E1C);
  static const Color surface = Color(0xFF111827);
  static const Color surface2 = Color(0xFF1C2333);
  static const Color surface3 = Color(0xFF242D3F);
  static const Color border = Color(0xFF1E2D40);

  // ── Accent palette ─────────────────────────────────────────────────────────
  static const Color accent = Color(0xFF3B82F6); // blue  — video call
  static const Color green = Color(0xFF22C55E); // green — voice call
  static const Color red = Color(0xFFEF4444); // red   — end call / mute
  static const Color amber = Color(0xFFF59E0B); // amber — admin / raise hand
  static const Color purple =
      Color(0xFF8B5CF6); // purple — recording / screen share
  static const Color speaking = Color(0xFF4ADE80); // speaking indicator

  // ── Text palette ───────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF475569);

  // ── Gradients ──────────────────────────────────────────────────────────────
  static const LinearGradient videoCallGradient = LinearGradient(
    colors: [Color(0xFF1D4ED8), Color(0xFF3B82F6)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient voiceCallGradient = LinearGradient(
    colors: [Color(0xFF15803D), Color(0xFF22C55E)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const RadialGradient videoWaitingBg = RadialGradient(
    center: Alignment(0, -0.3),
    radius: 1.5,
    colors: [Color(0xFF162240), Color(0xFF060A14)],
  );

  static const LinearGradient voiceUiBg = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF090F1E), Color(0xFF060A13), Color(0xFF060A13)],
    stops: [0, 0.5, 1],
  );

  // ── Shadows ────────────────────────────────────────────────────────────────
  static List<BoxShadow> endCallShadow = [
    BoxShadow(
        color: red.withOpacity(0.5),
        blurRadius: 20,
        offset: const Offset(0, 6)),
  ];

  static List<BoxShadow> speakingShadow = [
    BoxShadow(
        color: speaking.withOpacity(0.4), blurRadius: 16, spreadRadius: 3),
  ];

  static List<BoxShadow> glassCardShadow = [
    BoxShadow(
        color: Colors.black.withOpacity(0.5),
        blurRadius: 24,
        offset: const Offset(0, 8)),
  ];

  // ── Border radius ──────────────────────────────────────────────────────────
  static const BorderRadius radiusSM = BorderRadius.all(Radius.circular(10));
  static const BorderRadius radiusMD = BorderRadius.all(Radius.circular(14));
  static const BorderRadius radiusLG = BorderRadius.all(Radius.circular(20));
  static const BorderRadius radiusXL = BorderRadius.all(Radius.circular(28));
  static const BorderRadius radiusFull = BorderRadius.all(Radius.circular(100));

  // ── Typography ─────────────────────────────────────────────────────────────
  static const TextStyle titleStyle = TextStyle(
    color: textPrimary,
    fontSize: 22,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.4,
  );

  static const TextStyle subtitleStyle = TextStyle(
    color: textSecondary,
    fontSize: 14,
    height: 1.5,
  );

  static const TextStyle badgeStyle = TextStyle(
    color: Colors.white,
    fontSize: 10,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.5,
  );

  static const TextStyle labelStyle = TextStyle(
    color: textSecondary,
    fontSize: 11,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle nameBadgeStyle = TextStyle(
    color: Colors.white,
    fontSize: 10,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle timerStyle = TextStyle(
    color: green,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.2,
  );

  // ── Helper methods ─────────────────────────────────────────────────────────

  /// Returns the primary color for a call type
  static Color callTypeColor(bool isVideo) => isVideo ? accent : green;

  /// Returns gradient for a call type
  static LinearGradient callTypeGradient(bool isVideo) =>
      isVideo ? videoCallGradient : voiceCallGradient;

  /// Glassmorphism box decoration
  static BoxDecoration glassCard({
    Color? borderColor,
    double opacity = 0.82,
    BorderRadius? radius,
  }) =>
      BoxDecoration(
        color: Colors.black.withOpacity(opacity),
        borderRadius: radius ?? radiusLG,
        border: Border.all(
          color: borderColor ?? Colors.white.withOpacity(0.08),
        ),
        boxShadow: glassCardShadow,
      );

  /// Active control button decoration
  static BoxDecoration activeControl(Color color) => BoxDecoration(
        color: color.withOpacity(0.22),
        shape: BoxShape.circle,
        border: Border.all(color: color.withOpacity(0.55)),
        boxShadow: [BoxShadow(color: color.withOpacity(0.22), blurRadius: 12)],
      );

  /// Inactive control button decoration
  static BoxDecoration inactiveControl() => BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.16)),
      );

  /// Status badge for call status
  static Color statusColor(String status) {
    switch (status) {
      case GroupCallConstants.statusOngoing:
      case GroupCallConstants.statusCalling:
        return green;
      case GroupCallConstants.statusMissed:
        return red;
      default:
        return textMuted;
    }
  }

  static String statusLabel(String status) {
    switch (status) {
      case GroupCallConstants.statusCalling:
        return 'Đang gọi';
      case GroupCallConstants.statusWaiting:
        return 'Phòng chờ';
      case GroupCallConstants.statusOngoing:
        return 'Đang diễn ra';
      case GroupCallConstants.statusMissed:
        return 'Nhỡ';
      case GroupCallConstants.statusEnded:
        return 'Đã kết thúc';
      default:
        return 'Không rõ';
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// GroupCallAnimations
// Duration/Curve constants để animation đồng nhất toàn app
// ══════════════════════════════════════════════════════════════════════════════
class GroupCallAnimations {
  GroupCallAnimations._();

  // Entry animations
  static const Duration entryDuration = Duration(milliseconds: 400);
  static const Duration exitDuration = Duration(milliseconds: 280);
  static const Curve entryCurve = Curves.easeOutCubic;
  static const Curve exitCurve = Curves.easeInCubic;

  // Control feedback
  static const Duration tapDuration = Duration(milliseconds: 100);
  static const Duration tapReverse = Duration(milliseconds: 200);
  static const Curve tapCurve = Curves.easeOut;

  // State transitions
  static const Duration stateDuration = Duration(milliseconds: 200);
  static const Curve stateCurve = Curves.easeOut;

  // Pulse / glow
  static const Duration pulseDuration = Duration(milliseconds: 1400);
  static const Duration glowDuration = Duration(milliseconds: 900);
  static const Curve pulseCurve = Curves.easeInOut;

  // Ripple (incoming call)
  static const Duration rippleDuration = Duration(milliseconds: 2400);
  static const Curve rippleCurve = Curves.easeOut;

  // Reaction burst
  static const Duration burstDuration = Duration(milliseconds: 2800);

  // Panel slide
  static const Duration panelDuration = Duration(milliseconds: 350);
  static const Curve panelCurve = Curves.easeOutCubic;
}
