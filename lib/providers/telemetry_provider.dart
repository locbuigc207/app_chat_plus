import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';

enum TelemetryEvent {
  keystroke,
  backspace,
  paste,
  voiceInput,
  longPress,
  doubleTap,
  swipe,
  emojiUsed,
  messageDeleted,
  messageSent,
  sessionStart,
  sessionEnd,
}

enum BehaviorSuggestion {
  none,
  elderMode,
  reducedMotion,
  largerText,
  simplifiedUI,
}

class TypingPattern {
  final double wordsPerMinute;
  final double errorRate;
  final double pauseFrequency;
  final double avgWordLength;
  final bool usesEmoji;
  final bool usesSlang;

  const TypingPattern({
    required this.wordsPerMinute,
    required this.errorRate,
    required this.pauseFrequency,
    required this.avgWordLength,
    required this.usesEmoji,
    required this.usesSlang,
  });

  Map<String, dynamic> toMap() => {
        'wpm': wordsPerMinute,
        'errorRate': errorRate,
        'pauseFrequency': pauseFrequency,
        'avgWordLength': avgWordLength,
        'usesEmoji': usesEmoji,
        'usesSlang': usesSlang,
      };
}

class SessionStats {
  final int totalKeystrokes;
  final int totalBackspaces;
  final int totalMessages;
  final int totalEmojiUsed;
  final Duration sessionDuration;
  final double averageMessageLength;
  final double errorRate;
  final double wordsPerMinute;

  const SessionStats({
    required this.totalKeystrokes,
    required this.totalBackspaces,
    required this.totalMessages,
    required this.totalEmojiUsed,
    required this.sessionDuration,
    required this.averageMessageLength,
    required this.errorRate,
    required this.wordsPerMinute,
  });

  Map<String, dynamic> toMap() => {
        'keystrokes': totalKeystrokes,
        'backspaces': totalBackspaces,
        'messages': totalMessages,
        'emoji': totalEmojiUsed,
        'durationSec': sessionDuration.inSeconds,
        'avgMsgLen': averageMessageLength,
        'errorRate': errorRate,
        'wpm': wordsPerMinute,
      };
}

class TelemetryProvider with ChangeNotifier {
  int _keystrokeCount = 0;
  int _backspaceCount = 0;
  int _pasteCount = 0;
  int _emojiCount = 0;
  int _messageSentCount = 0;
  int _previousLength = 0;
  int _totalMessageLength = 0;

  final Queue<DateTime> _recentKeystrokes = Queue();
  static const int _wpmWindowSize = 20;
  DateTime? _sessionStart;
  Timer? _sessionTimer;

  DateTime? _lastKeystrokeTime;
  int _pauseCount = 0;
  static const Duration _pauseThreshold = Duration(seconds: 2);
  Timer? _pauseTimer;

  BehaviorSuggestion _currentSuggestion = BehaviorSuggestion.none;
  bool _suggestionHandled = false;
  final Map<BehaviorSuggestion, int> _suggestionTriggerCount = {};

  static const Set<String> _slangWords = {
    'okk',
    'haha',
    'hihi',
    'uh',
    'ừ',
    'oke',
    'ok nha',
    'chịu',
    'bro',
    'tbt',
    'lol',
    'omg',
    'ngl',
    'fr',
    'idk',
    'brb',
    'ty',
    'np',
    'thôi',
    'ừa',
    'á',
    'nhỉ',
    'nè',
    'nha',
    'đỉnh',
    'xịn',
    'slay',
  };
  bool _detectedSlang = false;
  bool _detectedEmoji = false;

  final List<Map<String, dynamic>> _eventHistory = [];
  static const int _maxHistorySize = 500;

  static const double _elderModeErrorThreshold = 0.28;
  static const double _largerTextErrorThreshold = 0.20;
  static const int _minKeystrokesForAnalysis = 25;
  static const double _slowWpmThreshold = 15.0;
  static const int _highPauseCountThreshold = 5;

  TelemetryProvider() {
    _startSession();
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    _pauseTimer?.cancel();
    super.dispose();
  }

  void _startSession() {
    _sessionStart = DateTime.now();
    _logEvent(TelemetryEvent.sessionStart);
  }

  void endSession() {
    _sessionTimer?.cancel();
    _logEvent(TelemetryEvent.sessionEnd);
  }

  void recordTextChange(String currentText) {
    final now = DateTime.now();

    if (currentText.length < _previousLength) {
      final deletedCount = _previousLength - currentText.length;
      _backspaceCount += deletedCount;
      _logEvent(TelemetryEvent.backspace, metadata: {'count': deletedCount});
    } else if (currentText.length > _previousLength) {
      final added = currentText.length - _previousLength;

      if (added > 3 && !_recentKeystrokes.isNotEmpty) {
        _pasteCount++;
        _logEvent(TelemetryEvent.paste, metadata: {'chars': added});
      } else {
        _keystrokeCount += added;
        _trackKeystrokeTime(now);
        _logEvent(TelemetryEvent.keystroke, metadata: {'count': added});
      }
    }

    final hasEmoji = _containsEmoji(currentText);
    if (hasEmoji && !_detectedEmoji) {
      _detectedEmoji = true;
      _emojiCount++;
      _logEvent(TelemetryEvent.emojiUsed);
    }

    if (!_detectedSlang) {
      final lower = currentText.toLowerCase();
      _detectedSlang = _slangWords.any((w) => lower.contains(w));
    }

    _lastKeystrokeTime = now;
    _pauseTimer?.cancel();
    _pauseTimer = Timer(_pauseThreshold, () {
      if (_lastKeystrokeTime != null) {
        _pauseCount++;
        _logEvent(TelemetryEvent.keystroke, metadata: {'pause': true});
      }
    });

    _previousLength = currentText.length;
    _analyzeBehavior();
  }

  void recordPaste(int charCount) {
    _pasteCount++;
    _logEvent(TelemetryEvent.paste, metadata: {'chars': charCount});
  }

  void recordMessageSent(String messageText) {
    _messageSentCount++;
    _totalMessageLength += messageText.length;
    _detectedSlang = false;
    _detectedEmoji = false;
    _logEvent(TelemetryEvent.messageSent, metadata: {'length': messageText.length});
    _analyzeBehavior();
  }

  void recordEmojiUsed() {
    _emojiCount++;
    _logEvent(TelemetryEvent.emojiUsed);
  }

  void recordSwipe(String direction) {
    _logEvent(TelemetryEvent.swipe, metadata: {'direction': direction});
  }

  void recordLongPress(String target) {
    _logEvent(TelemetryEvent.longPress, metadata: {'target': target});
  }

  BehaviorSuggestion get currentSuggestion =>
      _suggestionHandled ? BehaviorSuggestion.none : _currentSuggestion;

  bool get shouldSuggestElderMode =>
      !_suggestionHandled && _currentSuggestion == BehaviorSuggestion.elderMode;

  bool get shouldSuggestLargerText =>
      !_suggestionHandled && _currentSuggestion == BehaviorSuggestion.largerText;

  bool get shouldSuggestReducedMotion =>
      !_suggestionHandled && _currentSuggestion == BehaviorSuggestion.reducedMotion;

  int get keystrokeCount => _keystrokeCount;
  int get backspaceCount => _backspaceCount;
  int get messageSentCount => _messageSentCount;
  int get pauseCount => _pauseCount;

  double get errorRate {
    final total = _keystrokeCount + _backspaceCount;
    if (total == 0) return 0;
    return _backspaceCount / total;
  }

  double get wordsPerMinute {
    if (_recentKeystrokes.length < 2) return 0;
    final oldest = _recentKeystrokes.first;
    final newest = _recentKeystrokes.last;
    final durationMin = newest.difference(oldest).inMilliseconds / 60000;
    if (durationMin <= 0) return 0;

    final words = _recentKeystrokes.length / 5;
    return words / durationMin;
  }

  double get averageMessageLength {
    if (_messageSentCount == 0) return 0;
    return _totalMessageLength / _messageSentCount;
  }

  TypingPattern get currentPattern => TypingPattern(
        wordsPerMinute: wordsPerMinute,
        errorRate: errorRate,
        pauseFrequency: _keystrokeCount > 0 ? _pauseCount / _keystrokeCount : 0,
        avgWordLength: averageMessageLength / 5,
        usesEmoji: _detectedEmoji || _emojiCount > 0,
        usesSlang: _detectedSlang,
      );

  SessionStats get sessionStats {
    final duration =
        _sessionStart != null ? DateTime.now().difference(_sessionStart!) : Duration.zero;
    return SessionStats(
      totalKeystrokes: _keystrokeCount,
      totalBackspaces: _backspaceCount,
      totalMessages: _messageSentCount,
      totalEmojiUsed: _emojiCount,
      sessionDuration: duration,
      averageMessageLength: averageMessageLength,
      errorRate: errorRate,
      wordsPerMinute: wordsPerMinute,
    );
  }

  List<Map<String, dynamic>> get recentEvents => _eventHistory.reversed.take(50).toList();

  void markAsHandled() {
    _suggestionHandled = true;
    notifyListeners();
  }

  void resetSuggestion() {
    _currentSuggestion = BehaviorSuggestion.none;
    _suggestionHandled = false;
    notifyListeners();
  }

  void resetAll() {
    _keystrokeCount = 0;
    _backspaceCount = 0;
    _pasteCount = 0;
    _emojiCount = 0;
    _messageSentCount = 0;
    _totalMessageLength = 0;
    _previousLength = 0;
    _pauseCount = 0;
    _recentKeystrokes.clear();
    _eventHistory.clear();
    _detectedSlang = false;
    _detectedEmoji = false;
    _currentSuggestion = BehaviorSuggestion.none;
    _suggestionHandled = false;
    _suggestionTriggerCount.clear();
    _sessionStart = DateTime.now();
    notifyListeners();
  }

  void _analyzeBehavior() {
    if (_keystrokeCount < _minKeystrokesForAnalysis) return;
    if (_suggestionHandled) return;

    final rate = errorRate;
    final wpm = wordsPerMinute;
    final pauses = _pauseCount;

    BehaviorSuggestion newSuggestion = BehaviorSuggestion.none;

    if (rate > _elderModeErrorThreshold &&
        (wpm < _slowWpmThreshold || pauses > _highPauseCountThreshold)) {
      newSuggestion = BehaviorSuggestion.elderMode;
    } else if (rate > _largerTextErrorThreshold && wpm < _slowWpmThreshold) {
      newSuggestion = BehaviorSuggestion.largerText;
    } else if (pauses > _highPauseCountThreshold * 2 && rate < 0.1) {
      newSuggestion = BehaviorSuggestion.reducedMotion;
    }

    if (newSuggestion != BehaviorSuggestion.none && newSuggestion != _currentSuggestion) {
      final count = (_suggestionTriggerCount[newSuggestion] ?? 0) + 1;
      _suggestionTriggerCount[newSuggestion] = count;

      if (count >= 2) {
        _currentSuggestion = newSuggestion;
        _suggestionHandled = false;
        notifyListeners();
      }
    }
  }

  void _trackKeystrokeTime(DateTime now) {
    _recentKeystrokes.addLast(now);
    if (_recentKeystrokes.length > _wpmWindowSize) {
      _recentKeystrokes.removeFirst();
    }
  }

  void _logEvent(
    TelemetryEvent event, {
    Map<String, dynamic>? metadata,
  }) {
    if (_eventHistory.length >= _maxHistorySize) {
      _eventHistory.removeAt(0);
    }
    _eventHistory.add({
      'event': event.name,
      'time': DateTime.now().toIso8601String(),
      if (metadata != null) ...metadata,
    });
  }

  bool _containsEmoji(String text) {
    final emojiRegex = RegExp(
      r'[\u{1F300}-\u{1F9FF}]|[\u{2600}-\u{26FF}]|[\u{2700}-\u{27BF}]',
      unicode: true,
    );
    return emojiRegex.hasMatch(text);
  }

  Map<String, dynamic> exportDebugData() => {
        'session': sessionStats.toMap(),
        'pattern': currentPattern.toMap(),
        'suggestion': _currentSuggestion.name,
        'suggestionHandled': _suggestionHandled,
        'triggerCounts': _suggestionTriggerCount.map((k, v) => MapEntry(k.name, v)),
        'recentEvents': recentEvents.take(20).toList(),
      };

  @override
  String toString() => 'TelemetryProvider(keystrokes: $_keystrokeCount, '
      'backspaces: $_backspaceCount, errorRate: ${errorRate.toStringAsFixed(2)}, '
      'wpm: ${wordsPerMinute.toStringAsFixed(1)}, '
      'suggestion: ${_currentSuggestion.name})';
}
