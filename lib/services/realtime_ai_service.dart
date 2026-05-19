import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

enum SecurityStatus { safe, scanning, warning, danger }

class RealtimeAIService {
  static final RealtimeAIService _instance = RealtimeAIService._internal();
  factory RealtimeAIService() => _instance;
  RealtimeAIService._internal();

  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _isInitialized = false;
  bool _isListening = false;

  final _captionController = StreamController<String>.broadcast();
  Stream<String> get captionStream => _captionController.stream;

  final _securityController = StreamController<SecurityStatus>.broadcast();
  Stream<SecurityStatus> get securityStream => _securityController.stream;

  final _warningMsgController = StreamController<String>.broadcast();
  Stream<String> get warningMsgStream => _warningMsgController.stream;

  String _currentTranscript = "";
  Timer? _aiAnalysisTimer;

  
  final List<String> _redFlags = [
    "chuyển tiền",
    "ngân hàng",
    "mật khẩu",
    "mã otp",
    "vay gấp",
    "tài khoản",
    "cấp cứu"
  ];

  Future<bool> initialize() async {
    if (_isInitialized) return true;
    try {
      _isInitialized = await _speech.initialize(
        onError: (error) => print("STT Error: $error"),
      );
      return _isInitialized;
    } catch (e) {
      print("Lỗi STT: $e");
      return false;
    }
  }

  Future<void> startProtection(String peerId, String conversationId) async {
    if (!_isInitialized) await initialize();
    if (!_isInitialized || _isListening) return;

    _isListening = true;
    _securityController.add(SecurityStatus.safe);

    
    _speech.listen(
      onResult: (result) {
        _currentTranscript = result.recognizedWords;
        _captionController.add(_currentTranscript);
        _localKeywordScan(_currentTranscript);
      },
      localeId: 'vi_VN',
      cancelOnError: false,
      partialResults: true,
    );

    
    _aiAnalysisTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_currentTranscript.length > 20) {
        _runCloudAIAnalysis(peerId, conversationId);
      }
    });
  }

  
  void _localKeywordScan(String text) {
    final lowerText = text.toLowerCase();
    for (var flag in _redFlags) {
      if (lowerText.contains(flag)) {
        _securityController.add(SecurityStatus.warning);
        _warningMsgController
            .add("Phát hiện từ khóa nhạy cảm: '$flag'. Hãy cẩn thận!");
        return;
      }
    }
  }

  
  Future<void> _runCloudAIAnalysis(String peerId, String conversationId) async {
    _securityController.add(SecurityStatus.scanning);
    try {
      final HttpsCallable callable =
          _functions.httpsCallable('analyzeCallSecurity');
      final results = await callable.call(<String, dynamic>{
        'callTranscript': _currentTranscript,
        'peerId': peerId,
        'conversationId': conversationId,
      });

      final data = results.data;
      if (data['isSafe'] == false || data['riskLevel'] == 'HIGH') {
        _securityController.add(SecurityStatus.danger);
        _warningMsgController
            .add(data['warningMessage'] ?? "Cảnh báo Lừa đảo / Deepfake!");
      } else {
        _securityController.add(SecurityStatus.safe);
        _warningMsgController.add(""); 
      }

      
      _currentTranscript = "";
    } catch (e) {
      _securityController.add(SecurityStatus.safe);
      print("Lỗi Cloud AI: $e");
    }
  }

  Future<void> stopProtection() async {
    _isListening = false;
    _aiAnalysisTimer?.cancel();
    await _speech.stop();
    _securityController.add(SecurityStatus.safe);
    _warningMsgController.add("");
  }

  void dispose() {
    stopProtection();
    _captionController.close();
    _securityController.close();
    _warningMsgController.close();
  }
}
