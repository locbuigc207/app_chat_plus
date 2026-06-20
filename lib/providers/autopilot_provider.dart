import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:emoji_regex/emoji_regex.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';
import '../providers/providers.dart';
import '../services/services.dart';

// ─── Enums ────────────────────────────────────────────────────────────────────

enum AutoPilotTone { friendly, professional, funny, brief, likeMe }

extension AutoPilotToneX on AutoPilotTone {
  String get label => const {
    AutoPilotTone.friendly: 'Thân thiện',
    AutoPilotTone.professional: 'Chuyên nghiệp',
    AutoPilotTone.funny: 'Hài hước',
    AutoPilotTone.brief: 'Ngắn gọn',
    AutoPilotTone.likeMe: 'Giống tôi',
  }[this]!;

  String get description => const {
    AutoPilotTone.friendly: 'Ấm áp, thân mật, gần gũi',
    AutoPilotTone.professional: 'Lịch sự, trang trọng, súc tích',
    AutoPilotTone.funny: 'Vui vẻ, hài hước, Gen Z',
    AutoPilotTone.brief: 'Ngắn gọn, thẳng vào vấn đề',
    AutoPilotTone.likeMe: 'Học từ cách nhắn tin của bạn',
  }[this]!;

  String get emoji => const {
    AutoPilotTone.friendly: '😊',
    AutoPilotTone.professional: '💼',
    AutoPilotTone.funny: '😂',
    AutoPilotTone.brief: '⚡',
    AutoPilotTone.likeMe: '🪞',
  }[this]!;

  String get systemPromptHint => const {
    AutoPilotTone.friendly:
        'Trả lời THÂN THIỆN: ấm áp, gần gũi như bạn thân nhắn tin, có thể dùng emoji nhẹ nhàng, câu ngắn.',
    AutoPilotTone.professional:
        'Trả lời CHUYÊN NGHIỆP: lịch sự, trang trọng, súc tích, không tiếng lóng, không emoji.',
    AutoPilotTone.funny:
        'Trả lời HÀI HƯỚC Gen Z: vui vẻ, dí dỏm, emoji vừa phải 😂🔥, tiếng lóng tự nhiên.',
    AutoPilotTone.brief:
        'Trả lời CỰC NGẮN: chỉ 1 câu hoặc vài từ, thẳng vào vấn đề, không giải thích.',
    AutoPilotTone.likeMe:
        'Trả lời GIỐNG CHỦ TÀI KHOẢN: bắt chước đúng phong cách đã học từ persona.',
  }[this]!;

  static AutoPilotTone fromString(String s) => AutoPilotTone.values.firstWhere(
    (e) => e.name == s,
    orElse: () => AutoPilotTone.friendly,
  );
}

enum ScheduleMode { always, sleepHours, workHours, custom }

extension ScheduleModeX on ScheduleMode {
  static ScheduleMode fromString(String s) => ScheduleMode.values.firstWhere(
    (e) => e.name == s,
    orElse: () => ScheduleMode.always,
  );
}

// ─── AutoPilotConfig Model ────────────────────────────────────────────────────

class AutoPilotConfig {
  final String conversationId;
  final bool isEnabled;
  final AutoPilotTone tone;
  final ScheduleMode scheduleMode;
  final int startHour;
  final int endHour;
  final String awayMessage;
  final String? learnedPersona;
  final DateTime? personaLearnedAt;

  const AutoPilotConfig({
    required this.conversationId,
    this.isEnabled = false,
    this.tone = AutoPilotTone.friendly,
    this.scheduleMode = ScheduleMode.always,
    this.startHour = 22,
    this.endHour = 7,
    this.awayMessage = 'Mình đang bận, sẽ nhắn lại sau nha! 😊',
    this.learnedPersona,
    this.personaLearnedAt,
  });

  /// Kiểm tra AutoPilot có đang trong giờ hoạt động không
  bool get isActiveNow {
    if (!isEnabled) return false;
    final now = DateTime.now().hour;
    switch (scheduleMode) {
      case ScheduleMode.always:
        return true;
      case ScheduleMode.sleepHours:
        return now >= 22 || now < 7;
      case ScheduleMode.workHours:
        return now >= 8 && now < 18;
      case ScheduleMode.custom:
        if (startHour <= endHour) return now >= startHour && now < endHour;
        return now >= startHour || now < endHour; // qua nửa đêm
    }
  }

  AutoPilotConfig copyWith({
    bool? isEnabled,
    AutoPilotTone? tone,
    ScheduleMode? scheduleMode,
    int? startHour,
    int? endHour,
    String? awayMessage,
    String? learnedPersona,
    DateTime? personaLearnedAt,
  }) => AutoPilotConfig(
    conversationId: conversationId,
    isEnabled: isEnabled ?? this.isEnabled,
    tone: tone ?? this.tone,
    scheduleMode: scheduleMode ?? this.scheduleMode,
    startHour: startHour ?? this.startHour,
    endHour: endHour ?? this.endHour,
    awayMessage: awayMessage ?? this.awayMessage,
    learnedPersona: learnedPersona ?? this.learnedPersona,
    personaLearnedAt: personaLearnedAt ?? this.personaLearnedAt,
  );

  Map<String, dynamic> toMap() => {
    'conversationId': conversationId,
    'isEnabled': isEnabled,
    'tone': tone.name,
    'scheduleMode': scheduleMode.name,
    'startHour': startHour,
    'endHour': endHour,
    'awayMessage': awayMessage,
    if (learnedPersona != null) 'learnedPersona': learnedPersona,
    if (personaLearnedAt != null)
      'personaLearnedAt': personaLearnedAt!.millisecondsSinceEpoch,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  factory AutoPilotConfig.fromMap(String convId, Map<String, dynamic> m) =>
      AutoPilotConfig(
        conversationId: convId,
        isEnabled: m['isEnabled'] as bool? ?? false,
        tone: AutoPilotToneX.fromString(m['tone'] as String? ?? 'friendly'),
        scheduleMode: ScheduleModeX.fromString(
          m['scheduleMode'] as String? ?? 'always',
        ),
        startHour: m['startHour'] as int? ?? 22,
        endHour: m['endHour'] as int? ?? 7,
        awayMessage:
            m['awayMessage'] as String? ??
            'Mình đang bận, sẽ nhắn lại sau nha! 😊',
        learnedPersona: m['learnedPersona'] as String?,
        personaLearnedAt: m['personaLearnedAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(m['personaLearnedAt'] as int)
            : null,
      );
}

// ─── AutoPilotProvider ────────────────────────────────────────────────────────

class AutoPilotProvider extends ChangeNotifier {
  final FirebaseFirestore firebaseFirestore;
  final SharedPreferences prefs;

  AutoPilotProvider({required this.firebaseFirestore, required this.prefs});

  final Map<String, AutoPilotConfig> _configs = {};
  final Map<String, DateTime> _lastReplyTime = {};

  static const Duration _cooldown = Duration(seconds: 30);

  // ── Getters ──────────────────────────────────────────────────────────────

  AutoPilotConfig getConfig(String conversationId) =>
      _configs[conversationId] ??
      AutoPilotConfig(conversationId: conversationId);

  bool isActiveForConversation(String conversationId) =>
      getConfig(conversationId).isActiveNow;

  // ── Load config từ Firestore ─────────────────────────────────────────────

  Future<void> loadConfig(String conversationId, String userId) async {
    try {
      final doc = await firebaseFirestore
          .collection('users')
          .doc(userId)
          .collection('autopilot_config')
          .doc(conversationId)
          .get();

      if (doc.exists && doc.data() != null) {
        _configs[conversationId] = AutoPilotConfig.fromMap(
          conversationId,
          doc.data()!,
        );
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[AutoPilot] loadConfig error: $e');
    }
  }

  // ── Mutations ────────────────────────────────────────────────────────────

  void toggleAutoPlayForConversation(String id, {required bool enabled}) {
    _configs[id] = getConfig(id).copyWith(isEnabled: enabled);
    notifyListeners();
    _persist(id);
  }

  void updateTone(String id, AutoPilotTone tone) {
    _configs[id] = getConfig(id).copyWith(tone: tone);
    notifyListeners();
    _persist(id);
  }

  void updateScheduleMode(String id, ScheduleMode mode) {
    _configs[id] = getConfig(id).copyWith(scheduleMode: mode);
    notifyListeners();
    _persist(id);
  }

  void updateCustomSchedule(
    String id, {
    required int startHour,
    required int endHour,
  }) {
    _configs[id] = getConfig(id).copyWith(
      scheduleMode: ScheduleMode.custom,
      startHour: startHour,
      endHour: endHour,
    );
    notifyListeners();
    _persist(id);
  }

  void updateAwayMessage(String id, String message) {
    _configs[id] = getConfig(id).copyWith(awayMessage: message);
    _persist(id); // Không notifyListeners vì user đang gõ
  }

  void _persist(String id) {
    final uid = prefs.getString('id');
    if (uid == null) return;
    unawaited(_saveAsync(id, uid));
  }

  Future<void> _saveAsync(String id, String uid) async {
    try {
      await firebaseFirestore
          .collection('users')
          .doc(uid)
          .collection('autopilot_config')
          .doc(id)
          .set(_configs[id]!.toMap(), SetOptions(merge: true));
    } catch (e) {
      debugPrint('[AutoPilot] save error: $e');
    }
  }

  // ── Generate Reply (gọi Cloud Function/AI Backend) ───────────────────────

  Future<String?> generateReply({
    required String conversationId,
    required String incomingMessage,
    required String senderId,
    String? currentUserId,
    List<String> contextMessages = const [],
  }) async {
    final config = getConfig(conversationId);

    // Guards
    if (!config.isActiveNow) return null;
    if (currentUserId != null && senderId == currentUserId) return null;
    // Fix: Thay AI_BOT thành AppConstants.aiAssistantId
    if (senderId == AppConstants.aiAssistantId) return null;

    // Rate limit
    final last = _lastReplyTime[conversationId];
    if (last != null && DateTime.now().difference(last) < _cooldown) {
      debugPrint('[AutoPilot] rate-limited: $conversationId');
      return null;
    }

    final personaCtx = _buildPersonaContext(config);

    try {
      final reply = await AIBackendService().generateAutoPilotReply(
        incomingMessage: incomingMessage,
        myStyleContext: personaCtx,
        awayMessage: config.awayMessage,
        // Fix: Bổ sung 2 params quan trọng để AIBackendService đẩy xuống Cloud Functions
        tone: config.tone.name,
        contextMessages: contextMessages,
      );

      if (reply != null && reply.isNotEmpty) {
        _lastReplyTime[conversationId] = DateTime.now();
      }
      return reply;
    } catch (e) {
      debugPrint('[AutoPilot] generateReply error: $e');
      return config.awayMessage; // Fallback
    }
  }

  String _buildPersonaContext(AutoPilotConfig config) {
    if (config.tone == AutoPilotTone.likeMe && config.learnedPersona != null) {
      return '${config.tone.systemPromptHint}\n\nPhong cách đã học:\n${config.learnedPersona}';
    }
    return config.tone.systemPromptHint;
  }

  // ── Persona Learning (offline, không cần API) ────────────────────────────

  Future<bool> learnStyleFromHistory({
    required String conversationId,
    required String currentUserId,
  }) async {
    try {
      final msgs = LocalDbService()
          .getMessages(conversationId)
          .where(
            (m) =>
                m['idFrom'] == currentUserId &&
                m['type'] == 0 &&
                (m['content']?.toString().length ?? 0) > 3 &&
                !(m['content']?.toString().startsWith('{"iv":') ?? false),
          )
          .take(100)
          .map((m) => m['content']?.toString() ?? '')
          .where((c) => c.isNotEmpty)
          .toList();

      if (msgs.length < 10) return false;

      final persona = _analyzePersonaLocally(msgs);
      _configs[conversationId] = getConfig(
        conversationId,
      ).copyWith(learnedPersona: persona, personaLearnedAt: DateTime.now());
      notifyListeners();
      _persist(conversationId);
      return true;
    } catch (e) {
      debugPrint('[AutoPilot] learnStyle error: $e');
      return false;
    }
  }

  String _analyzePersonaLocally(List<String> messages) {
    int emojiCount = 0;

    // Gọi hàm emojiRegex() từ package
    final emojiRe = emojiRegex();

    for (final m in messages) {
      emojiCount += emojiRe.allMatches(m).length;
    }

    // Avg length
    final avgLen =
        messages.fold<int>(0, (s, m) => s + m.length) / messages.length;

    // Top words (loại stopword)
    final stop = {
      'là',
      'và',
      'có',
      'không',
      'được',
      'của',
      'với',
      'cho',
      'trong',
      'mình',
      'bạn',
      'thì',
      'đã',
      'sẽ',
      'ở',
      'tôi',
      'mày',
      'tao',
      'nha',
      'nhé',
      'ạ',
      'ra',
      'vào',
      'thôi',
      'rồi',
    };
    final freq = <String, int>{};
    for (final m in messages) {
      for (final w in m.toLowerCase().split(RegExp(r'\s+'))) {
        final clean = w.replaceAll(RegExp(r'[^\w]'), '');
        if (clean.length >= 3 && !stop.contains(clean)) {
          freq[clean] = (freq[clean] ?? 0) + 1;
        }
      }
    }
    final topWords =
        (freq.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
            .take(5)
            .map((e) => e.key)
            .join(', ');

    final emojiLevel = emojiCount > messages.length * 0.5
        ? 'thường xuyên dùng emoji'
        : emojiCount > messages.length * 0.2
        ? 'đôi khi dùng emoji'
        : 'ít dùng emoji';

    final lenStyle = avgLen < 20
        ? 'nhắn rất ngắn (1–2 từ hoặc 1 câu)'
        : avgLen < 60
        ? 'nhắn vừa phải (1–2 câu)'
        : 'nhắn dài và chi tiết';

    final greetCount = messages.where((m) {
      final l = m.toLowerCase();
      return l.startsWith('ê') || l.startsWith('hey') || l.startsWith('alo');
    }).length;
    final greetStyle = greetCount > 2
        ? ', hay bắt đầu bằng "Ê" hoặc "Hey"'
        : '';

    return '$lenStyle$greetStyle. $emojiLevel.'
        '${topWords.isNotEmpty ? ' Hay dùng: $topWords.' : ''}';
  }

  // ── Preview Reply cho UI ─────────────────────────────────────────────────

  Future<String?> generatePreviewReply({
    required AutoPilotTone tone,
    required String sampleMessage,
  }) async {
    try {
      return await AIBackendService().generateAutoPilotReply(
        incomingMessage: sampleMessage,
        myStyleContext: tone.systemPromptHint,
      );
    } catch (_) {
      // Fallback cục bộ nếu API lỗi
      return const {
        AutoPilotTone.friendly: 'Mình rảnh nha! 😊 Tối nay đi đâu vậy?',
        AutoPilotTone.professional:
            'Cảm ơn bạn đã liên hệ. Tôi sẽ phản hồi sớm nhất có thể.',
        AutoPilotTone.funny: 'Ơ tất nhiên rảnh rồi 😂 đang chờ đây nè! 🔥',
        AutoPilotTone.brief: 'Rảnh. Đi đâu?',
        AutoPilotTone.likeMe: 'Ê rảnh á! Tối đi đâu vui không?',
      }[tone];
    }
  }

  void clearCache(String id) {
    _configs.remove(id);
    _lastReplyTime.remove(id);
    notifyListeners();
  }
}
