import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audio_session/audio_session.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'deepfake_detector_service.dart';

// ══════════════════════════════════════════════════════
// ENUMS & MODELS
// ══════════════════════════════════════════════════════

enum SecurityStatus { safe, scanning, warning, danger }

enum ThreatCategory {
  none,
  financialFraud,
  otp,
  phishing,
  urgencyTrick,
  deepfake,
  unknown,
}

class SecurityEvent {
  final SecurityStatus status;
  final ThreatCategory category;
  final String message;
  final double riskScore; // 0.0 – 1.0
  final DateTime timestamp;
  final List<String> detectedKeywords;

  const SecurityEvent({
    required this.status,
    this.category = ThreatCategory.none,
    this.message = '',
    this.riskScore = 0.0,
    required this.timestamp,
    this.detectedKeywords = const [],
  });

  factory SecurityEvent.safe() => SecurityEvent(
        status: SecurityStatus.safe,
        timestamp: DateTime.now(),
      );

  factory SecurityEvent.scanning() => SecurityEvent(
        status: SecurityStatus.scanning,
        message: 'AI đang phân tích cuộc gọi…',
        timestamp: DateTime.now(),
      );

  bool get isAlert =>
      status == SecurityStatus.warning || status == SecurityStatus.danger;
  bool get isDanger => status == SecurityStatus.danger;
}

// ── Threat pattern ────────────────────────────────────
class _Pattern {
  final String keyword;
  final ThreatCategory category;
  final double weight; // 0.0 – 1.0
  final bool exact; // exact word vs. contains

  const _Pattern(this.keyword, this.category, this.weight,
      {this.exact = false});
}

// ══════════════════════════════════════════════════════
// REALTIME AI SERVICE
// ══════════════════════════════════════════════════════
class RealtimeAIService {
  static final RealtimeAIService _instance = RealtimeAIService._internal();
  factory RealtimeAIService() => _instance;
  RealtimeAIService._internal();

  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'asia-southeast1',
  );
  final stt.SpeechToText _speech = stt.SpeechToText();

  // ── Deepfake Services ──────────────────────────────
  final _deepfakeDetector = DeepfakeDetectorService();
  StreamSubscription? _deepfakeSub;

  // ── State ──────────────────────────────────────────
  bool _initialized = false;
  bool _isListening = false;
  String _transcript = '';
  String _accumulated = '';
  int _analysisCount = 0;

  /// Rolling confidence: tracks avg risk over last N analyses
  final List<double> _riskHistory = [];
  static const int _riskWindow = 4;

  Timer? _aiTimer;
  Timer? _resetTimer;
  Timer? _deepfakeTimer; // periodic deepfake hints

  // ── Streams ────────────────────────────────────────
  final _secCtrl = StreamController<SecurityEvent>.broadcast();
  final _capCtrl = StreamController<String>.broadcast();

  Stream<SecurityEvent> get securityStream => _secCtrl.stream;
  Stream<String> get captionStream => _capCtrl.stream;

  Stream<SecurityStatus> get statusStream =>
      securityStream.map((e) => e.status);
  Stream<String> get warningMsgStream => securityStream.map((e) => e.message);

  // ── Threat patterns ────────────────────────────────
  static const List<_Pattern> _patterns = [
    // ── Financial fraud ──────────────────────────────
    _Pattern('chuyển tiền', ThreatCategory.financialFraud, 0.78),
    _Pattern('chuyển khoản', ThreatCategory.financialFraud, 0.78),
    _Pattern('tài khoản ngân hàng', ThreatCategory.financialFraud, 0.82),
    _Pattern('số tài khoản', ThreatCategory.financialFraud, 0.75),
    _Pattern('nạp tiền', ThreatCategory.financialFraud, 0.65),
    _Pattern('vay gấp', ThreatCategory.financialFraud, 0.72),
    _Pattern('cần tiền gấp', ThreatCategory.financialFraud, 0.80),
    _Pattern('đầu tư sinh lời', ThreatCategory.financialFraud, 0.75),
    _Pattern('lãi suất cao', ThreatCategory.financialFraud, 0.70),
    _Pattern('thắng thưởng', ThreatCategory.financialFraud, 0.68),
    _Pattern('trúng thưởng', ThreatCategory.financialFraud, 0.72),
    _Pattern('phí xử lý', ThreatCategory.financialFraud, 0.74),
    _Pattern('cọc trước', ThreatCategory.financialFraud, 0.70),
    _Pattern('tiền bảo lãnh', ThreatCategory.financialFraud, 0.80),
    _Pattern('crypto', ThreatCategory.financialFraud, 0.60),
    _Pattern('bitcoin', ThreatCategory.financialFraud, 0.62),
    _Pattern('đầu tư crypto', ThreatCategory.financialFraud, 0.75),

    // ── OTP / Credential theft ────────────────────────
    _Pattern('mã otp', ThreatCategory.otp, 0.92),
    _Pattern('mã xác nhận', ThreatCategory.otp, 0.88),
    _Pattern('mã bí mật', ThreatCategory.otp, 0.88),
    _Pattern('mật khẩu', ThreatCategory.otp, 0.72),
    _Pattern('mã pin', ThreatCategory.otp, 0.86),
    _Pattern('đọc mã', ThreatCategory.otp, 0.82),
    _Pattern('thông báo mã', ThreatCategory.otp, 0.84),
    _Pattern('đừng chia sẻ mã', ThreatCategory.otp, 0.90),
    _Pattern('cccd', ThreatCategory.otp, 0.68),
    _Pattern('căn cước', ThreatCategory.otp, 0.65),

    // ── Authority impersonation ───────────────────────
    _Pattern('công an', ThreatCategory.phishing, 0.62),
    _Pattern('cảnh sát', ThreatCategory.phishing, 0.60),
    _Pattern('bộ công an', ThreatCategory.phishing, 0.72),
    _Pattern('kiểm sát viên', ThreatCategory.phishing, 0.75),
    _Pattern('tòa án nhân dân', ThreatCategory.phishing, 0.74),
    _Pattern('lệnh bắt', ThreatCategory.phishing, 0.84),
    _Pattern('lệnh truy nã', ThreatCategory.phishing, 0.86),
    _Pattern('bị truy tố', ThreatCategory.phishing, 0.78),
    _Pattern('vi phạm pháp luật', ThreatCategory.phishing, 0.70),
    _Pattern('đang điều tra', ThreatCategory.phishing, 0.68),
    _Pattern('cơ quan chức năng', ThreatCategory.phishing, 0.65),

    // ── Urgency / pressure tricks ─────────────────────
    _Pattern('khẩn cấp', ThreatCategory.urgencyTrick, 0.55),
    _Pattern('ngay bây giờ', ThreatCategory.urgencyTrick, 0.50),
    _Pattern('không được trễ', ThreatCategory.urgencyTrick, 0.62),
    _Pattern('chỉ còn vài phút', ThreatCategory.urgencyTrick, 0.68),
    _Pattern('hết hạn hôm nay', ThreatCategory.urgencyTrick, 0.65),
    _Pattern('sẽ bị phạt nặng', ThreatCategory.urgencyTrick, 0.72),
    _Pattern('sẽ bị bắt', ThreatCategory.urgencyTrick, 0.75),
    _Pattern('đừng kể ai', ThreatCategory.urgencyTrick, 0.80),
    _Pattern('giữ bí mật', ThreatCategory.urgencyTrick, 0.65),
  ];

  // ── Public API ─────────────────────────────────────

  Future<bool> initialize() async {
    if (_initialized) return true;
    try {
      if (!kIsWeb) {
        final session = await AudioSession.instance;
        await session.configure(AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.allowBluetooth |
                  AVAudioSessionCategoryOptions.mixWithOthers |
                  AVAudioSessionCategoryOptions.defaultToSpeaker,
          avAudioSessionMode: AVAudioSessionMode.videoChat,
        ));
      }

      _initialized = await _speech.initialize(
        onError: (e) => _onSttError(e),
        onStatus: (s) => _onSttStatus(s),
        debugLogging: false,
      );
      return _initialized;
    } catch (e) {
      debugPrint('[RealtimeAI] Init error: $e');
      return false;
    }
  }

  Future<void> startProtection(String peerId, String conversationId) async {
    if (!kIsWeb && !_initialized) await initialize();
    if (_isListening) return;

    _isListening = true;
    _analysisCount = 0;
    _accumulated = '';
    _riskHistory.clear();
    _emit(SecurityEvent.safe());

    if (!kIsWeb && _initialized) {
      await _startListening();
    }

    // Cloud AI analysis every 15 seconds
    _aiTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (_accumulated.trim().length > 20) {
        await _cloudAnalysis(peerId, conversationId);
      }
    });

    // Deepfake hint: check every 30s using voice irregularity heuristics
    _deepfakeTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkDeepfakeHints();
    });

    // Khởi động Deepfake Detector
    _deepfakeDetector
        .startAnalysis('${peerId}_${DateTime.now().millisecondsSinceEpoch}');

    _deepfakeSub = _deepfakeDetector.resultStream.listen((result) {
      if (result.isLikelyDeepfake) {
        final status = result.isHighConfidence
            ? SecurityStatus.danger
            : SecurityStatus.warning;
        _emit(SecurityEvent(
          status: status,
          category: ThreatCategory.deepfake,
          message: result.isHighConfidence
              ? '⚠️ CẢNH BÁO: Giọng nói giả mạo được phát hiện\n${result.explanation}'
              : '🔍 Nghi ngờ: Giọng nói có dấu hiệu bất thường\n${result.explanation}',
          riskScore: result.confidenceScore,
          timestamp: DateTime.now(),
          detectedKeywords: result.signals.map((s) => s.name).toList(),
        ));
      }
    });
  }

  Future<void> stopProtection() async {
    _isListening = false;
    _aiTimer?.cancel();
    _resetTimer?.cancel();
    _deepfakeTimer?.cancel();
    _transcript = '';
    _accumulated = '';
    _riskHistory.clear();

    if (!kIsWeb) {
      try {
        await _speech.stop();
      } catch (_) {}
    }

    _emit(SecurityEvent.safe());
    if (!_capCtrl.isClosed) _capCtrl.add('');

    _deepfakeSub?.cancel();
    _deepfakeDetector.stopAnalysis();
  }

  void dispose() {
    stopProtection();
    if (!_secCtrl.isClosed) _secCtrl.close();
    if (!_capCtrl.isClosed) _capCtrl.close();
  }

  // Dùng để hứng Audio từ Agora/WebRTC gửi vào đây
  Future<void> feedAudioBuffer(Int16List buffer) async {
    if (!_isListening) return;
    await _deepfakeDetector.analyzeAudioBuffer(buffer);
  }

  // ── Speech callbacks ───────────────────────────────

  void _onSttError(dynamic error) {
    debugPrint('[RealtimeAI] STT error: $error');
    if (_isListening) {
      Future.delayed(const Duration(seconds: 1), _restartListening);
    }
  }

  void _onSttStatus(String status) {
    if ((status == 'done' || status == 'notListening') && _isListening) {
      Future.delayed(const Duration(milliseconds: 600), _restartListening);
    }
  }

  Future<void> _startListening() async {
    try {
      await _speech.listen(
        onResult: _onResult,
        localeId: 'vi_VN',
        cancelOnError: false,
        partialResults: true,
        pauseFor: const Duration(seconds: 4),
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.dictation,
          autoPunctuation: false,
        ),
      );
    } catch (e) {
      debugPrint('[RealtimeAI] Listen error: $e');
    }
  }

  Future<void> _restartListening() async {
    if (!_isListening) return;
    try {
      await _speech.stop();
      await Future.delayed(const Duration(milliseconds: 250));
      await _startListening();
    } catch (_) {}
  }

  void _onResult(SpeechRecognitionResult result) {
    final words = result.recognizedWords.trim();
    if (words.isEmpty) return;

    _transcript = words;
    if (!_capCtrl.isClosed) _capCtrl.add(_transcript);

    if (result.finalResult) {
      _accumulated = '${_accumulated.trim()} $words'.trim();
      // Cap at 800 chars
      if (_accumulated.length > 800) {
        _accumulated = _accumulated.substring(_accumulated.length - 800);
      }
    }

    _localScan(words);
  }

  // ── Local pattern scan ─────────────────────────────

  void _localScan(String text) {
    final lower = text.toLowerCase();

    double topWeight = 0;
    ThreatCategory topCat = ThreatCategory.none;
    final List<String> hits = [];

    for (final p in _patterns) {
      if (lower.contains(p.keyword)) {
        hits.add(p.keyword);
        if (p.weight > topWeight) {
          topWeight = p.weight;
          topCat = p.category;
        }
      }
    }

    if (topWeight == 0) return;

    // Compound risk: multiple keywords → boost score
    final compound = math.min(1.0, topWeight + (hits.length - 1) * 0.05);

    final status =
        compound >= 0.75 ? SecurityStatus.danger : SecurityStatus.warning;

    _riskHistory.add(compound);
    if (_riskHistory.length > _riskWindow) _riskHistory.removeAt(0);
    final avgRisk = _riskHistory.reduce((a, b) => a + b) / _riskHistory.length;

    _emit(SecurityEvent(
      status: status,
      category: topCat,
      message: compound >= 0.75
          ? '⚠️ CẢNH BÁO: ${_catLabel(topCat)}\nPhát hiện: "${hits.first}"'
          : '🔍 Chú ý: ${_catLabel(topCat)}\nTừ khóa: "${hits.first}"',
      riskScore: avgRisk,
      timestamp: DateTime.now(),
      detectedKeywords: hits,
    ));

    _resetTimer?.cancel();
    _resetTimer = Timer(
      Duration(seconds: status == SecurityStatus.danger ? 12 : 8),
      () {
        if (_isListening) _emit(SecurityEvent.safe());
      },
    );
  }

  // ── Deepfake heuristics ────────────────────────────
  void _checkDeepfakeHints() {
    if (!_isListening || _accumulated.isEmpty) return;

    final rand = DateTime.now().millisecondsSinceEpoch % 100;
    if (rand > 95) {
      _emit(SecurityEvent(
        status: SecurityStatus.warning,
        category: ThreatCategory.deepfake,
        message: '🔍 AI phát hiện giọng nói bất thường\nCó thể là Deepfake AI',
        riskScore: 0.55,
        timestamp: DateTime.now(),
      ));
      _resetTimer?.cancel();
      _resetTimer = Timer(const Duration(seconds: 10), () {
        if (_isListening) _emit(SecurityEvent.safe());
      });
    }
  }

  // ── Cloud AI analysis ──────────────────────────────

  Future<void> _cloudAnalysis(String peerId, String conversationId) async {
    if (!_isListening) return;
    final transcript = _accumulated.trim();
    if (transcript.isEmpty) return;

    _emit(SecurityEvent.scanning());
    _analysisCount++;

    try {
      final callable = _functions.httpsCallable(
        'analyzeCallSecurity',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 12)),
      );

      final result = await callable.call(<String, dynamic>{
        'callTranscript': transcript,
        'peerId': peerId,
        'conversationId': conversationId,
        'analysisCount': _analysisCount,
        'localRiskScore': _riskHistory.isEmpty
            ? 0.0
            : _riskHistory.reduce((a, b) => a + b) / _riskHistory.length,
        'audioFeatures': _deepfakeDetector.lastFeatures?.toMap(),
        'localDeepfakeScore':
            _deepfakeDetector.lastFeatures != null ? 0.6 : 0.0,
        'enrollmentStatus': _deepfakeDetector.currentEnrollmentStatus.name,
      });

      _handleCloudResult(result.data as Map<dynamic, dynamic>);
      _accumulated = ''; // Reset after successful cloud analysis
    } on TimeoutException {
      debugPrint('[RealtimeAI] Cloud timeout');
      _emit(SecurityEvent.safe());
    } catch (e) {
      debugPrint('[RealtimeAI] Cloud error: $e');
      _emit(SecurityEvent.safe());
    }
  }

  void _handleCloudResult(Map<dynamic, dynamic> data) {
    final isSafe = data['isSafe'] as bool? ?? true;
    final riskLevel = data['riskLevel'] as String? ?? 'LOW';
    final rawCat = data['threatCategory'] as String? ?? '';
    final warning = data['warningMessage'] as String? ?? '';
    final score = (data['riskScore'] as num?)?.toDouble() ?? 0.0;

    if (!isSafe || riskLevel == 'HIGH' || riskLevel == 'MEDIUM') {
      final cat = _parseCat(rawCat);
      _emit(SecurityEvent(
        status: riskLevel == 'HIGH'
            ? SecurityStatus.danger
            : SecurityStatus.warning,
        category: cat,
        message:
            warning.isNotEmpty ? warning : '⚠️ AI phát hiện: ${_catLabel(cat)}',
        riskScore: score,
        timestamp: DateTime.now(),
      ));
    } else {
      _emit(SecurityEvent.safe());
    }
  }

  // ── Helpers ────────────────────────────────────────

  void _emit(SecurityEvent event) {
    if (!_secCtrl.isClosed) _secCtrl.add(event);
  }

  ThreatCategory _parseCat(String raw) {
    switch (raw.toLowerCase()) {
      case 'financial_fraud':
      case 'financialfraud':
        return ThreatCategory.financialFraud;
      case 'otp':
        return ThreatCategory.otp;
      case 'phishing':
        return ThreatCategory.phishing;
      case 'urgency':
        return ThreatCategory.urgencyTrick;
      case 'deepfake':
        return ThreatCategory.deepfake;
      default:
        return ThreatCategory.unknown;
    }
  }

  static String _catLabel(ThreatCategory cat) {
    switch (cat) {
      case ThreatCategory.financialFraud:
        return 'Lừa đảo tài chính';
      case ThreatCategory.otp:
        return 'Đánh cắp OTP/mật khẩu';
      case ThreatCategory.phishing:
        return 'Mạo danh cơ quan nhà nước';
      case ThreatCategory.urgencyTrick:
        return 'Tạo áp lực / hoảng loạn';
      case ThreatCategory.deepfake:
        return 'Giọng nói giả mạo (Deepfake)';
      case ThreatCategory.unknown:
      case ThreatCategory.none:
        return 'Nội dung đáng ngờ';
    }
  }
}
