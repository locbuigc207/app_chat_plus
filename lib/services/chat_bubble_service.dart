import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:flutter_chat_demo/models/bubble_models.dart';
import 'package:shared_preferences/shared_preferences.dart';







class ChatBubbleService {
  
  static const _method = MethodChannel('chat_bubble_overlay');
  static const _event = EventChannel('chat_bubble_events');

  
  static final ChatBubbleService _instance = ChatBubbleService._internal();
  factory ChatBubbleService() => _instance;

  ChatBubbleService._internal() {
    if (!kIsWeb && Platform.isAndroid) {
      Future.delayed(const Duration(milliseconds: 400), _bootstrap);
    }
  }

  
  final Map<String, BubbleData> _activeBubbles = {};
  StreamSubscription<dynamic>? _eventSub;
  SharedPreferences? _prefs;
  bool _isInitialized = false;

  
  DateTime? _lastOp;
  static const _minInterval = Duration(milliseconds: 300);

  
  final _bubblesCtrl = StreamController<Map<String, BubbleData>>.broadcast();
  final _clickCtrl = StreamController<BubbleClickEvent>.broadcast();
  final _miniMsgCtrl = StreamController<MiniChatMessage>.broadcast();

  
  final _gameChallengeCtrl = StreamController<GameChallengeEvent>.broadcast();

  Stream<Map<String, BubbleData>> get activeBubblesStream => _bubblesCtrl.stream;
  Stream<BubbleClickEvent> get bubbleClickStream => _clickCtrl.stream;
  Stream<MiniChatMessage> get miniChatMessageStream => _miniMsgCtrl.stream;

  
  Stream<GameChallengeEvent> get gameChallengeStream => _gameChallengeCtrl.stream;

  
  
  

  Future<void> _bootstrap() async {
    _setupEventListener();
    await _restoreBubbles();
  }

  void _setupEventListener() {
    if (_isInitialized || kIsWeb) return;
    try {
      _eventSub?.cancel();
      _eventSub = _event.receiveBroadcastStream().listen(
        (raw) {
          if (raw is! Map) return;
          final event = Map<String, dynamic>.from(raw);
          switch (event['type'] as String?) {
            case 'click':
              _handleClick(event);
              break;
            case 'message':
              _handleMiniMsg(event);
              break;
            case 'dismiss':
              _handleDismiss(event);
              break;
            case 'game_challenge_tap':
              _handleGameChallengeTap(event);
              break;
          }
        },
        onError: (Object err) => debugPrint('❌ ChatBubbleService event error: $err'),
        cancelOnError: false,
      );
      _isInitialized = true;
      debugPrint('✅ ChatBubbleService initialized');
    } catch (e) {
      debugPrint('⚠️ Event channel setup failed: $e');
    }
  }

  void _handleClick(Map<String, dynamic> e) {
    final userId = e['userId'] as String?;
    if (userId == null || _clickCtrl.isClosed) return;
    _clickCtrl.add(BubbleClickEvent(
      userId: userId,
      userName: e['userName'] as String? ?? '',
      avatarUrl: e['avatarUrl'] as String? ?? '',
      message: e['message'] as String? ?? '',
    ));
  }

  void _handleMiniMsg(Map<String, dynamic> e) {
    final userId = e['userId'] as String?;
    final message = e['message'] as String?;
    if (userId == null || message == null || _miniMsgCtrl.isClosed) return;
    _miniMsgCtrl.add(MiniChatMessage(
      userId: userId,
      message: message,
      timestamp: DateTime.now(),
    ));
  }

  void _handleDismiss(Map<String, dynamic> e) {
    final userId = e['userId'] as String?;
    if (userId != null) {
      _activeBubbles.remove(userId);
      _emitBubbles();
      _saveBubbles();
    }
  }

  
  void _handleGameChallengeTap(Map<String, dynamic> e) {
    if (_gameChallengeCtrl.isClosed) return;
    final event = GameChallengeEvent(
      matchId: e['matchId'] as String? ?? '',
      groupId: e['groupId'] as String? ?? '',
      challengerName: e['challengerName'] as String? ?? '',
      gameType: e['gameType'] as String? ?? 'caro',
    );
    _gameChallengeCtrl.add(event);
    debugPrint('🎮 Game challenge tapped: ${event.matchId}');
  }

  
  
  

  Future<bool> hasOverlayPermission() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      return await _method.invokeMethod<bool>('hasPermission') ?? false;
    } catch (e) {
      debugPrint('❌ hasOverlayPermission: $e');
      return false;
    }
  }

  Future<bool> requestOverlayPermission() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      await _waitRateLimit();
      final granted = await _method.invokeMethod<bool>('requestPermission') ?? false;
      if (granted) {
        await Future.delayed(const Duration(milliseconds: 600));
      }
      return granted;
    } catch (e) {
      debugPrint('❌ requestOverlayPermission: $e');
      return false;
    }
  }

  
  
  

  Future<bool> showChatBubble({
    required String userId,
    required String userName,
    required String avatarUrl,
    String? lastMessage,
    int maxRetries = 2,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return false;
    if (_activeBubbles.containsKey(userId)) return true;

    try {
      await _waitRateLimit();
      if (!await hasOverlayPermission()) return false;

      for (int attempt = 0; attempt <= maxRetries; attempt++) {
        try {
          final success = await _method.invokeMethod<bool>('showBubble', {
                'userId': userId,
                'userName': userName,
                'avatarUrl': avatarUrl,
                'lastMessage': lastMessage ?? '',
              }).timeout(
                const Duration(seconds: 5),
                onTimeout: () => false,
              ) ??
              false;

          if (success) {
            _activeBubbles[userId] = BubbleData(
              userId: userId,
              userName: userName,
              avatarUrl: avatarUrl,
              lastMessage: lastMessage,
              timestamp: DateTime.now(),
            );
            _emitBubbles();
            await _saveBubbles();
            debugPrint('🫧 Overlay bubble shown for $userName');
            return true;
          }
        } catch (e) {
          debugPrint('❌ showChatBubble attempt ${attempt + 1}: $e');
          if (attempt == maxRetries) rethrow;
        }
        await Future.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      }
      return false;
    } catch (e) {
      debugPrint('❌ showChatBubble: $e');
      return false;
    }
  }

  Future<bool> hideChatBubble(String userId) async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      await _waitRateLimit();
      final success = await _method.invokeMethod<bool>('hideBubble', {'userId': userId}).timeout(
              const Duration(seconds: 3),
              onTimeout: () => false) ??
          false;
      if (success) {
        _activeBubbles.remove(userId);
        _emitBubbles();
        await _saveBubbles();
      }
      return success;
    } catch (e) {
      debugPrint('❌ hideChatBubble: $e');
      return false;
    }
  }

  Future<void> hideAllBubbles() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _waitRateLimit();
      await _method.invokeMethod('hideAllBubbles');
      _activeBubbles.clear();
      _emitBubbles();
      await clearSavedBubbles();
    } catch (e) {
      debugPrint('❌ hideAllBubbles: $e');
    }
  }

  Future<void> updateBubbleMessage({
    required String userId,
    required String message,
  }) async {
    final existing = _activeBubbles[userId];
    if (existing == null) return;
    _activeBubbles[userId] = existing.copyWith(
      lastMessage: message,
      timestamp: DateTime.now(),
      unreadCount: existing.unreadCount + 1,
    );
    _emitBubbles();
    await _saveBubbles();

    try {
      await _method.invokeMethod('updateBubble', {
        'userId': userId,
        'message': message,
      });
    } catch (_) {}
  }

  Future<void> clearUnread(String userId) async {
    final existing = _activeBubbles[userId];
    if (existing == null) return;
    _activeBubbles[userId] = existing.copyWith(unreadCount: 0);
    _emitBubbles();
    await _saveBubbles();
  }

  

  Future<bool> showMiniChat({
    required String userId,
    required String userName,
    required String avatarUrl,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      await _waitRateLimit();
      if (!await hasOverlayPermission()) return false;
      return await _method.invokeMethod<bool>('showMiniChat', {
            'userId': userId,
            'userName': userName,
            'avatarUrl': avatarUrl,
          }).timeout(const Duration(seconds: 5), onTimeout: () => false) ??
          false;
    } catch (e) {
      debugPrint('❌ showMiniChat: $e');
      return false;
    }
  }

  Future<bool> hideMiniChat() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      await _waitRateLimit();
      return await _method.invokeMethod<bool>('hideMiniChat') ?? false;
    } catch (e) {
      debugPrint('❌ hideMiniChat: $e');
      return false;
    }
  }

  
  
  

  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  Future<void> sendGameChallengeNotification({
    required String targetUserId,
    required String challengerName,
    required String challengerAvatar,
    required String matchId,
    required String groupId,
    required String gameType,
    String timeControlLabel = '',
  }) async {
    
    
    if (kIsWeb) return;

    final gameEmoji = gameType == 'chess' ? '♟️' : '⭕';
    final timeLabel = timeControlLabel.isNotEmpty ? ' ($timeControlLabel)' : '';
    final title =
        '$gameEmoji $challengerName thách bạn đấu ${_gameDisplayName(gameType)}$timeLabel!';
    const body = 'Bấm để vào bàn đấu ngay';

    try {
      if (Platform.isAndroid) {
        
        await _method.invokeMethod('showGameChallengeNotification', {
          'targetUserId': targetUserId,
          'title': title,
          'body': body,
          'matchId': matchId,
          'groupId': groupId,
          'gameType': gameType,
          'challengerName': challengerName,
          'challengerAvatar': challengerAvatar,
        });
        debugPrint('🔔 Game challenge notification sent to $targetUserId');
      }

      
      if (_activeBubbles.containsKey(targetUserId)) {
        await updateBubbleMessage(
          userId: targetUserId,
          message: title,
        );
      }
    } catch (e) {
      
      debugPrint('⚠️ sendGameChallengeNotification error: $e');
    }
  }

  String _gameDisplayName(String gameType) {
    switch (gameType.toLowerCase()) {
      case 'chess':
        return 'Cờ Vua';
      case 'caro':
      default:
        return 'Caro';
    }
  }

  
  
  

  static const _storageKey = 'active_bubbles_v1';

  Future<void> _saveBubbles() async {
    try {
      await _initPrefs();
      if (_activeBubbles.isEmpty) {
        await _prefs?.remove(_storageKey);
        return;
      }
      final data = _activeBubbles.map((k, v) => MapEntry(k, v.toJson()));
      await _prefs?.setString(_storageKey, jsonEncode(data));
    } catch (e) {
      debugPrint('❌ _saveBubbles: $e');
    }
  }

  Future<void> _restoreBubbles() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _initPrefs();
      final raw = _prefs?.getString(_storageKey);
      if (raw == null || raw.isEmpty) return;
      if (!await hasOverlayPermission()) return;

      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      int restored = 0;
      for (final entry in decoded.entries) {
        try {
          final data = BubbleData.fromJson(Map<String, dynamic>.from(entry.value as Map));
          if (!data.isValid || data.isStale) continue;
          final ok = await showChatBubble(
            userId: data.userId,
            userName: data.userName,
            avatarUrl: data.avatarUrl,
            lastMessage: data.lastMessage,
          );
          if (ok) restored++;
        } catch (e) {
          debugPrint('⚠️ restore bubble ${entry.key}: $e');
        }
      }
      debugPrint('📦 Restored $restored overlay bubble(s)');
    } catch (e) {
      debugPrint('❌ _restoreBubbles: $e');
      await clearSavedBubbles();
    }
  }

  Future<void> clearSavedBubbles() async {
    try {
      await _initPrefs();
      await _prefs?.remove(_storageKey);
    } catch (e) {
      debugPrint('❌ clearSavedBubbles: $e');
    }
  }

  Future<void> _initPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  
  
  

  Future<void> _waitRateLimit() async {
    if (_lastOp != null) {
      final elapsed = DateTime.now().difference(_lastOp!);
      if (elapsed < _minInterval) {
        await Future.delayed(_minInterval - elapsed);
      }
    }
    _lastOp = DateTime.now();
  }

  void _emitBubbles() {
    if (!_bubblesCtrl.isClosed) {
      _bubblesCtrl.add(Map.unmodifiable(_activeBubbles));
    }
  }

  
  
  

  bool isBubbleActive(String userId) => _activeBubbles.containsKey(userId);
  Map<String, BubbleData> get activeBubbles => Map.unmodifiable(_activeBubbles);
  int get activeBubbleCount => _activeBubbles.length;
  bool get isSupported => !kIsWeb && Platform.isAndroid;
  bool get isInitialized => _isInitialized;

  
  
  

  void dispose() {
    _eventSub?.cancel();
    _eventSub = null;
    _isInitialized = false;
    if (!_bubblesCtrl.isClosed) _bubblesCtrl.close();
    if (!_clickCtrl.isClosed) _clickCtrl.close();
    if (!_miniMsgCtrl.isClosed) _miniMsgCtrl.close();
    if (!_gameChallengeCtrl.isClosed) _gameChallengeCtrl.close();
    debugPrint('✅ ChatBubbleService disposed');
  }
}







class GameChallengeEvent {
  final String matchId;
  final String groupId;
  final String challengerName;
  final String gameType;
  final DateTime receivedAt;

  GameChallengeEvent({
    required this.matchId,
    required this.groupId,
    required this.challengerName,
    required this.gameType,
    DateTime? receivedAt,
  }) : receivedAt = receivedAt ?? DateTime.now();

  @override
  String toString() =>
      'GameChallengeEvent(matchId: $matchId, group: $groupId, from: $challengerName)';
}
