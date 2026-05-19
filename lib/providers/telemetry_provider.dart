
import 'package:flutter/material.dart';

class TelemetryProvider with ChangeNotifier {
  int _keystrokeCount = 0;
  int _backspaceCount = 0;
  int _previousLength = 0;

  bool _hasSuggestedElderMode = false; 

  
  void recordTextChange(String currentText) {
    if (currentText.length < _previousLength) {
      
      _backspaceCount++;
    } else {
      _keystrokeCount++;
    }

    _previousLength = currentText.length;

    _analyzeBehavior();
  }

  void _analyzeBehavior() {
    if (_hasSuggestedElderMode || _keystrokeCount < 20) return;

    
    double errorRate = _backspaceCount / (_keystrokeCount + _backspaceCount);

    
    if (errorRate > 0.3) {
      _hasSuggestedElderMode = true;
      notifyListeners(); 
    }
  }

  bool get shouldSuggestElderMode => _hasSuggestedElderMode;

  void resetSuggestion() {
    _hasSuggestedElderMode = false;
    _keystrokeCount = 0;
    _backspaceCount = 0;
    notifyListeners();
  }

  
  void markAsHandled() {
    _hasSuggestedElderMode = false;
    notifyListeners();
  }
}
