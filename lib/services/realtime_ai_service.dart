import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:audio_session/audio_session.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;





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
  final double riskScore; 
  final DateTime timestamp;

  const SecurityEvent({
    required this.status,
    this.category = ThreatCategory.none,
    this.message = '',
    this.riskScore = 0.0,
    required this.timestamp,
  });

  factory SecurityEvent.safe() => SecurityEvent(
        status: SecurityStatus.safe,
        timestamp: DateTime.now(),
      );

  factory SecurityEvent.scanning() => SecurityEvent(
        status: SecurityStatus.scanning,
        message: 'AI đang phân tích cuộc gọi...',
        timestamp: DateTime.now(),
      );

  bool get isAlert => status == SecurityStatus.warning || status == SecurityStatus.danger;
}

class _ThreatPattern {
  final String keyword;
  final ThreatCategory category;
  final double weight;

  const _ThreatPattern(this.keyword, this.category, this.weight);
}





class RealtimeAIService {
  
  static final RealtimeAIService _instance = RealtimeAIService._internal();
  factory RealtimeAIService() => _instance;
  RealtimeAIService._internal();

  
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final stt.SpeechToText _speech = stt.SpeechToText();

  
  bool _isInitialized = false;
  bool _isListening = false;
  String _currentTranscript = '';
  String _accumulatedTranscript = ''; 
  Timer? _aiAnalysisTimer;
  Timer? _resetStatusTimer;
  int _analysisCount = 0;

  
  final _captionController = StreamController<String>.broadcast();
  Stream<String> get captionStream => _captionController.stream;

  final _securityController = StreamController<SecurityEvent>.broadcast();
  Stream<SecurityEvent> get securityStream => _securityController.stream;

  
  Stream<SecurityStatus> get statusStream => securityStream.map((e) => e.status);

  
  Stream<String> get warningMsgStream => securityStream.map((e) => e.message);

  

  static const List<_ThreatPattern> _threatPatterns = [
    
    _ThreatPattern('chuyển tiền', ThreatCategory.financialFraud, 0.75),
    _ThreatPattern('chuyển khoản', ThreatCategory.financialFraud, 0.75),
    _ThreatPattern('ngân hàng', ThreatCategory.financialFraud, 0.5),
    _ThreatPattern('tài khoản ngân hàng', ThreatCategory.financialFraud, 0.8),
    _ThreatPattern('số tài khoản', ThreatCategory.financialFraud, 0.7),
    _ThreatPattern('nạp tiền', ThreatCategory.financialFraud, 0.65),
    _ThreatPattern('vay tiền', ThreatCategory.financialFraud, 0.6),
    _ThreatPattern('vay gấp', ThreatCategory.financialFraud, 0.7),
    _ThreatPattern('cần tiền gấp', ThreatCategory.financialFraud, 0.8),

    
    _ThreatPattern('mã otp', ThreatCategory.otp, 0.9),
    _ThreatPattern('mã xác nhận', ThreatCategory.otp, 0.85),
    _ThreatPattern('mật khẩu', ThreatCategory.otp, 0.7),
    _ThreatPattern('mã pin', ThreatCategory.otp, 0.85),
    _ThreatPattern('số bí mật', ThreatCategory.otp, 0.8),
    _ThreatPattern('đừng chia sẻ', ThreatCategory.otp, 0.65),

    
    _ThreatPattern('công an', ThreatCategory.phishing, 0.6),
    _ThreatPattern('cảnh sát', ThreatCategory.phishing, 0.55),
    _ThreatPattern('kiểm sát', ThreatCategory.phishing, 0.6),
    _ThreatPattern('tòa án', ThreatCategory.phishing, 0.6),
    _ThreatPattern('bộ công an', ThreatCategory.phishing, 0.7),
    _ThreatPattern('truy tố', ThreatCategory.phishing, 0.75),
    _ThreatPattern('lệnh bắt', ThreatCategory.phishing, 0.8),

    
    _ThreatPattern('cấp cứu', ThreatCategory.urgencyTrick, 0.65),
    _ThreatPattern('tai nạn', ThreatCategory.urgencyTrick, 0.5),
    _ThreatPattern('khẩn cấp', ThreatCategory.urgencyTrick, 0.55),
    _ThreatPattern('ngay bây giờ', ThreatCategory.urgencyTrick, 0.45),
    _ThreatPattern('không được trễ', ThreatCategory.urgencyTrick, 0.6),
    _ThreatPattern('bị phạt', ThreatCategory.urgencyTrick, 0.5),
  ];

  

  static String _categoryLabel(ThreatCategory cat) {
    switch (cat) {
      case ThreatCategory.financialFraud:
        return 'Lừa đảo tài chính';
      case ThreatCategory.otp:
        return 'Đánh cắp mã OTP / mật khẩu';
      case ThreatCategory.phishing:
        return 'Mạo danh cơ quan nhà nước';
      case ThreatCategory.urgencyTrick:
        return 'Tạo áp lực khẩn cấp';
      case ThreatCategory.deepfake:
        return 'Giọng nói giả mạo (Deepfake)';
      default:
        return 'Nội dung đáng ngờ';
    }
  }

  

  Future<bool> initialize() async {
    if (_isInitialized) return true;
    try {
      final session = await AudioSession.instance;
      await session.configure(
        AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.allowBluetooth |
              AVAudioSessionCategoryOptions.mixWithOthers |
              AVAudioSessionCategoryOptions.defaultToSpeaker,
          avAudioSessionMode: AVAudioSessionMode.videoChat,
        ),
      );

      _isInitialized = await _speech.initialize(
        onError: (error) => _onSpeechError(error),
        onStatus: (status) => _onSpeechStatus(status),
        debugLogging: false,
      );
      return _isInitialized;
    } catch (e) {
      debugLog('Initialize error: $e');
      return false;
    }
  }

  void _onSpeechError(dynamic error) {
    debugLog('STT error: $error');
    
    if (_isListening) {
      Future.delayed(const Duration(seconds: 1), _restartListening);
    }
  }

  void _onSpeechStatus(String status) {
    debugLog('STT status: $status');
    if (status == 'done' || status == 'notListening') {
      if (_isListening) {
        Future.delayed(const Duration(milliseconds: 500), _restartListening);
      }
    }
  }

  

  Future<void> startProtection(String peerId, String conversationId) async {
    if (!_isInitialized) await initialize();
    if (!_isInitialized || _isListening) return;

    _isListening = true;
    _analysisCount = 0;
    _emit(SecurityEvent.safe());

    await _startListening();

    
    await Future.delayed(const Duration(seconds: 5));
    _aiAnalysisTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (_accumulatedTranscript.trim().length > 15) {
        await _runCloudAIAnalysis(peerId, conversationId);
      }
    });
  }

  Future<void> _startListening() async {
    await _speech.listen(
      onResult: _onSpeechResult,
      localeId: 'vi_VN',
      cancelOnError: false,
      partialResults: true,
      pauseFor: const Duration(seconds: 3),
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        autoPunctuation: false,
      ),
    );
  }

  Future<void> _restartListening() async {
    if (!_isListening) return;
    try {
      await _speech.stop();
      await Future.delayed(const Duration(milliseconds: 200));
      await _startListening();
    } catch (_) {}
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    final words = result.recognizedWords.trim();
    if (words.isEmpty) return;

    _currentTranscript = words;
    _captionController.add(_currentTranscript);

    if (result.finalResult) {
      _accumulatedTranscript = '${_accumulatedTranscript.trim()} $words'.trim();
      
      if (_accumulatedTranscript.length > 600) {
        _accumulatedTranscript =
            _accumulatedTranscript.substring(_accumulatedTranscript.length - 600);
      }
    }

    _localPatternScan(words);
  }

  

  void _localPatternScan(String text) {
    final lower = text.toLowerCase();

    double maxWeight = 0;
    ThreatCategory dominantCategory = ThreatCategory.none;
    String? matchedKeyword;

    for (final pattern in _threatPatterns) {
      if (lower.contains(pattern.keyword)) {
        if (pattern.weight > maxWeight) {
          maxWeight = pattern.weight;
          dominantCategory = pattern.category;
          matchedKeyword = pattern.keyword;
        }
      }
    }

    if (maxWeight == 0) return;

    final isHighRisk = maxWeight >= 0.75;
    final status = isHighRisk ? SecurityStatus.danger : SecurityStatus.warning;
    final label = _categoryLabel(dominantCategory);

    _emit(SecurityEvent(
      status: status,
      category: dominantCategory,
      message: isHighRisk
          ? '⚠️ CẢNH BÁO: $label\nPhát hiện: "$matchedKeyword"'
          : '🔍 Chú ý: $label\nPhát hiện từ khóa: "$matchedKeyword"',
      riskScore: maxWeight,
      timestamp: DateTime.now(),
    ));

    
    _resetStatusTimer?.cancel();
    _resetStatusTimer = Timer(const Duration(seconds: 8), () {
      if (_isListening) _emit(SecurityEvent.safe());
    });
  }

  

  Future<void> _runCloudAIAnalysis(String peerId, String conversationId) async {
    if (!_isListening) return;

    final transcript = _accumulatedTranscript.trim();
    if (transcript.isEmpty) return;

    _emit(SecurityEvent.scanning());
    _analysisCount++;

    try {
      final callable = _functions.httpsCallable('analyzeCallSecurity');
      final result = await callable.call(<String, dynamic>{
        'callTranscript': transcript,
        'peerId': peerId,
        'conversationId': conversationId,
        'analysisCount': _analysisCount,
      }).timeout(const Duration(seconds: 12));

      final data = result.data as Map<dynamic, dynamic>;
      _handleCloudResult(data);

      
      _accumulatedTranscript = '';
    } on TimeoutException {
      debugLog('Cloud AI timeout – falling back to safe');
      _emit(SecurityEvent.safe());
    } catch (e) {
      debugLog('Cloud AI error: $e');
      _emit(SecurityEvent.safe());
    }
  }

  void _handleCloudResult(Map<dynamic, dynamic> data) {
    final isSafe = data['isSafe'] as bool? ?? true;
    final riskLevel = (data['riskLevel'] as String?) ?? 'LOW';
    final rawCategory = (data['threatCategory'] as String?) ?? '';
    final warningMsg = (data['warningMessage'] as String?) ?? '';
    final riskScore = (data['riskScore'] as num?)?.toDouble() ?? 0.0;

    if (!isSafe || riskLevel == 'HIGH' || riskLevel == 'MEDIUM') {
      final category = _parseThreatCategory(rawCategory);
      _emit(SecurityEvent(
        status: riskLevel == 'HIGH' ? SecurityStatus.danger : SecurityStatus.warning,
        category: category,
        message:
            warningMsg.isNotEmpty ? warningMsg : '⚠️ AI phát hiện: ${_categoryLabel(category)}',
        riskScore: riskScore,
        timestamp: DateTime.now(),
      ));
    } else {
      _emit(SecurityEvent.safe());
    }
  }

  ThreatCategory _parseThreatCategory(String raw) {
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

  

  void _emit(SecurityEvent event) {
    if (!_securityController.isClosed) {
      _securityController.add(event);
    }
  }

  // ignore: avoid_print
  void debugLog(String msg) => debugPrint('[RealtimeAI] $msg');

  

  Future<void> stopProtection() async {
    _isListening = false;
    _aiAnalysisTimer?.cancel();
    _resetStatusTimer?.cancel();
    _currentTranscript = '';
    _accumulatedTranscript = '';
    try {
      await _speech.stop();
    } catch (_) {}
    _emit(SecurityEvent.safe());
    _captionController.add('');
  }

  void dispose() {
    stopProtection();
    _securityController.close();
    _captionController.close();
  }
}
