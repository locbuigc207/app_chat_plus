
import 'dart:async';
import 'dart:convert'; 
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/models/bubble_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

























class BubbleServiceV2 {
  static const MethodChannel _channel = MethodChannel('chat_bubbles_v2');
  static const EventChannel _eventChannel =
      EventChannel('chat_bubble_events_v2');

  static final BubbleServiceV2 _instance = BubbleServiceV2._internal();
  factory BubbleServiceV2() => _instance;

  BubbleServiceV2._internal() {
    _initialize();
  }

  bool _isInitialized = false;
  bool _isDisposing = false; 
  bool _isBubbleApiSupported = false;
  StreamSubscription<dynamic>? _eventSubscription;
  SharedPreferences? _prefs;

  final Map<String, BubbleData> _activeBubbles = {};

  
  StreamController<BubbleClickEvent>? _bubbleClickController;
  StreamController<Map<String, BubbleData>>? _activeBubblesController;

  Stream<BubbleClickEvent> get bubbleClickStream {
    if (_bubbleClickController == null || _bubbleClickController!.isClosed) {
      _bubbleClickController = StreamController<BubbleClickEvent>.broadcast();
    }
    return _bubbleClickController!.stream;
  }

  Stream<Map<String, BubbleData>> get activeBubblesStream {
    if (_activeBubblesController == null ||
        _activeBubblesController!.isClosed) {
      _activeBubblesController =
          StreamController<Map<String, BubbleData>>.broadcast();
    }
    return _activeBubblesController!.stream;
  }

  
  
  

  Future<void> _initialize() async {
    
    if (_isInitialized || _isDisposing) return;

    try {
      _isBubbleApiSupported = await checkBubbleApiSupport();
      if (!_isBubbleApiSupported) {
        debugPrint('⚠️ BubbleServiceV2: Bubble API not supported');
        return;
      }

      
      _bubbleClickController ??= StreamController<BubbleClickEvent>.broadcast();
      _activeBubblesController ??=
          StreamController<Map<String, BubbleData>>.broadcast();

      _setupEventListener();
      _prefs = await SharedPreferences.getInstance();
      await _restoreBubbles();

      _isInitialized = true;
      debugPrint('✅ BubbleServiceV2 initialized');
    } catch (e) {
      debugPrint('❌ BubbleServiceV2 init failed: $e');
    }
  }

  Future<bool> checkBubbleApiSupport() async {
    if (!Platform.isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<bool>('checkBubbleApiSupport');
      return result ?? false;
    } catch (e) {
      debugPrint('❌ checkBubbleApiSupport: $e');
      return false;
    }
  }

  
  
  

  void _setupEventListener() {
    
    _eventSubscription?.cancel();

    try {
      _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
        (event) {
          if (_isDisposing) return; 
          if (event is Map) {
            _handleBubbleEvent(Map<String, dynamic>.from(event));
          }
        },
        onError: (error) {
          
          debugPrint('❌ BubbleServiceV2 event error: $error');
        },
        cancelOnError: false, 
      );
      debugPrint('✅ BubbleServiceV2 event listener active');
    } catch (e) {
      debugPrint('❌ Event listener setup failed: $e');
    }
  }

  void _handleBubbleEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    if (type == 'click') {
      final userId = event['userId'] as String?;
      final userName = event['userName'] as String? ?? '';
      final avatarUrl = event['avatarUrl'] as String? ?? '';
      final message = event['message'] as String? ?? '';

      if (userId != null) {
        final ctrl = _bubbleClickController;
        if (ctrl != null && !ctrl.isClosed) {
          ctrl.add(BubbleClickEvent(
            userId: userId,
            userName: userName,
            avatarUrl: avatarUrl,
            message: message,
          ));
        }
      }
    }
  }

  
  
  

  Future<bool> showBubble({
    required String userId,
    required String userName,
    required String message,
    String? avatarUrl,
  }) async {
    if (!_isBubbleApiSupported) return false;

    try {
      if (_activeBubbles.containsKey(userId)) {
        return await updateBubble(userId: userId, message: message);
      }

      final result = await _channel.invokeMethod<bool>('showBubble', {
        'userId': userId,
        'userName': userName,
        'message': message,
        'avatarUrl': avatarUrl ?? '',
      });

      if (result == true) {
        _activeBubbles[userId] = BubbleData(
          userId: userId,
          userName: userName,
          avatarUrl: avatarUrl ?? '',
          lastMessage: message,
          timestamp: DateTime.now(),
        );
        _emitActiveBubbles();
        await _saveBubbles();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('❌ showBubble: $e');
      return false;
    }
  }

  Future<bool> updateBubble({
    required String userId,
    required String message,
  }) async {
    if (!_isBubbleApiSupported) return false;
    try {
      final bubble = _activeBubbles[userId];
      if (bubble == null) return false;

      final result = await _channel.invokeMethod<bool>('updateBubble', {
        'userId': userId,
        'message': message,
      });

      if (result == true) {
        _activeBubbles[userId] = BubbleData(
          userId: bubble.userId,
          userName: bubble.userName,
          avatarUrl: bubble.avatarUrl,
          lastMessage: message,
          timestamp: DateTime.now(),
          unreadCount: bubble.unreadCount + 1,
        );
        _emitActiveBubbles();
        await _saveBubbles();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('❌ updateBubble: $e');
      return false;
    }
  }

  Future<bool> hideBubble(String userId) async {
    if (!_isBubbleApiSupported) return false;
    try {
      final result = await _channel.invokeMethod<bool>('hideBubble', {
        'userId': userId,
      });
      if (result == true) {
        _activeBubbles.remove(userId);
        _emitActiveBubbles();
        await _saveBubbles();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('❌ hideBubble: $e');
      return false;
    }
  }

  Future<void> hideAllBubbles() async {
    if (!_isBubbleApiSupported) return;
    try {
      await _channel.invokeMethod('hideAllBubbles');
      _activeBubbles.clear();
      _emitActiveBubbles();
      await _clearSavedBubbles();
    } catch (e) {
      debugPrint('❌ hideAllBubbles: $e');
    }
  }

  
  
  

  
  Future<void> _saveBubbles() async {
    try {
      await _initPrefs();
      if (_activeBubbles.isEmpty) {
        await _prefs?.remove('bubbles_v2');
        return;
      }
      
      final data = _activeBubbles.map((k, v) => MapEntry(k, v.toJson()));
      final jsonStr = jsonEncode(data);
      await _prefs?.setString('bubbles_v2', jsonStr);
      debugPrint('💾 Saved ${_activeBubbles.length} bubbles');
    } catch (e) {
      debugPrint('❌ _saveBubbles: $e');
    }
  }

  
  Future<void> _restoreBubbles() async {
    try {
      await _initPrefs();
      final jsonStr = _prefs?.getString('bubbles_v2');
      if (jsonStr == null || jsonStr.isEmpty) {
        debugPrint('ℹ️ No saved bubbles to restore');
        return;
      }

      
      final Map<String, dynamic> decoded =
          jsonDecode(jsonStr) as Map<String, dynamic>;

      int restored = 0;
      for (final entry in decoded.entries) {
        try {
          final bubbleData = BubbleData.fromJson(
              Map<String, dynamic>.from(entry.value as Map));

          
          final age = DateTime.now().difference(bubbleData.timestamp);
          if (age.inMinutes >= 1440) {
            debugPrint('⏰ Skipping stale bubble: ${bubbleData.userName}');
            continue;
          }

          
          _activeBubbles[entry.key] = bubbleData;
          restored++;
        } catch (e) {
          debugPrint('⚠️ Failed to restore bubble ${entry.key}: $e');
        }
      }

      debugPrint('📦 Restored $restored bubbles');
      if (restored > 0) _emitActiveBubbles();
    } catch (e) {
      debugPrint('❌ _restoreBubbles: $e');
      await _clearSavedBubbles();
    }
  }

  Future<void> _clearSavedBubbles() async {
    try {
      await _initPrefs();
      await _prefs?.remove('bubbles_v2');
    } catch (e) {
      debugPrint('❌ _clearSavedBubbles: $e');
    }
  }

  Future<void> _initPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  
  
  

  void _emitActiveBubbles() {
    final ctrl = _activeBubblesController;
    if (ctrl != null && !ctrl.isClosed) {
      ctrl.add(Map.from(_activeBubbles));
    }
  }

  
  
  

  bool get isSupported => _isBubbleApiSupported;
  bool get isInitialized => _isInitialized;

  bool isBubbleActive(String userId) => _activeBubbles.containsKey(userId);

  Map<String, BubbleData> get activeBubbles => Map.unmodifiable(_activeBubbles);

  int get activeBubbleCount => _activeBubbles.length;

  Future<int> getShortcutCount() async {
    try {
      final result = await _channel.invokeMethod<int>('getShortcutCount');
      return result ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<bool> verifyShortcut(String userId) async {
    try {
      final result = await _channel
          .invokeMethod<bool>('verifyShortcut', {'userId': userId});
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  
  
  

  
  
  void dispose() {
    if (_isDisposing) return;
    _isDisposing = true;

    debugPrint('🗑️ BubbleServiceV2 disposing...');

    
    _eventSubscription?.cancel();
    _eventSubscription = null;

    
    if (_bubbleClickController != null && !_bubbleClickController!.isClosed) {
      _bubbleClickController!.close();
    }
    if (_activeBubblesController != null &&
        !_activeBubblesController!.isClosed) {
      _activeBubblesController!.close();
    }
    _bubbleClickController = null;
    _activeBubblesController = null;

    _isInitialized = false;
    _isDisposing = false; 

    debugPrint('✅ BubbleServiceV2 disposed');
  }

  
  Future<void> reinitialize() async {
    if (_isInitialized) return;
    await _initialize();
  }
}


void debugPrint(String msg) => print(msg);
