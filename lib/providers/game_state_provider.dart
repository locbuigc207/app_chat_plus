import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:flutter_chat_demo/models/game_match.dart';
import 'package:flutter_chat_demo/models/message_chat.dart';
import 'package:flutter_chat_demo/services/game_firebase_service.dart';
import 'package:uuid/uuid.dart';






enum PlayerRole {
  player1, 
  player2, 
  spectator, 
}


enum EndReason {
  fiveInRow, 
  checkmate, 
  timeout, 
  turnTimeout, 
  resign, 
  drawAgreed, 
  disconnect, 
  stalemate, 
  insufficientMaterial, 
  ;

  String get label {
    switch (this) {
      case EndReason.fiveInRow:
        return 'five_in_row';
      case EndReason.checkmate:
        return 'checkmate';
      case EndReason.timeout:
        return 'timeout';
      case EndReason.turnTimeout:
        return 'turn_timeout';
      case EndReason.resign:
        return 'resign';
      case EndReason.drawAgreed:
        return 'draw_agreed';
      case EndReason.disconnect:
        return 'disconnect';
      case EndReason.stalemate:
        return 'stalemate';
      case EndReason.insufficientMaterial:
        return 'insufficient_material';
    }
  }

  String get displayText {
    switch (this) {
      case EndReason.fiveInRow:
        return '5 quân liên tiếp';
      case EndReason.checkmate:
        return 'Chiếu bí';
      case EndReason.timeout:
        return 'Hết giờ';
      case EndReason.turnTimeout:
        return 'Hết giờ nước đi';
      case EndReason.resign:
        return 'Đầu hàng';
      case EndReason.drawAgreed:
        return 'Đồng ý hòa';
      case EndReason.disconnect:
        return 'Mất kết nối';
      case EndReason.stalemate:
        return 'Hết nước đi';
      case EndReason.insufficientMaterial:
        return 'Thiếu quân';
    }
  }
}


class DrawRequest {
  final String requesterId;
  final DateTime sentAt;
  bool isAnswered;

  DrawRequest({
    required this.requesterId,
    required this.sentAt,
    this.isAnswered = false,
  });
}


class CaroCell {
  final int row;
  final int col;

  
  final String symbol;

  const CaroCell(this.row, this.col, this.symbol);
}

















class GameStateProvider extends ChangeNotifier {
  
  final GameFirebaseService _firebase = GameFirebaseService();
  final _uuid = const Uuid();

  
  GameMatch? _match;
  String _currentUserId = '';
  PlayerRole _role = PlayerRole.spectator;

  
  StreamSubscription<GameMatch?>? _matchSub;
  StreamSubscription<GameMove?>? _moveSub;
  StreamSubscription<Map<String, dynamic>?>? _disconnectSub;

  
  
  final Map<String, String> _caroBoard = {};

  
  CaroCell? _lastMove;

  
  List<CaroCell> _winLine = [];

  
  
  String _currentTurnUserId = '';

  
  int _nextMoveIndex = 0;

  
  
  int _player1RemainingMs = 0;

  
  int _player2RemainingMs = 0;

  Timer? _chessClockTimer;

  
  
  int _turnTimerSeconds = 0;

  Timer? _turnTimer;

  
  DrawRequest? _pendingDrawRequest;

  
  Timer? _disconnectTimer;

  
  String? _disconnectedPlayerId;

  
  int _disconnectCountdown = 60;

  
  bool _isGameOver = false;
  GameResult? _finalResult;
  EndReason? _endReason;
  String? _winnerUserId;

  
  bool _isReplayMode = false;
  List<GameMove> _replayMoves = [];
  int _replayIndex = -1; 
  Timer? _replayTimer;

  
  bool _isLoading = false;
  String? _errorMessage;

  
  
  

  GameMatch? get match => _match;
  PlayerRole get role => _role;
  bool get isPlayer => _role == PlayerRole.player1 || _role == PlayerRole.player2;
  bool get isSpectator => _role == PlayerRole.spectator;
  bool get isMyTurn => _currentTurnUserId == _currentUserId && !_isGameOver && !_isReplayMode;
  bool get isGameOver => _isGameOver;
  GameResult? get finalResult => _finalResult;
  EndReason? get endReason => _endReason;
  String? get winnerUserId => _winnerUserId;

  
  Map<String, String> get caroBoard => Map.unmodifiable(_caroBoard);
  CaroCell? get lastMove => _lastMove;
  List<CaroCell> get winLine => List.unmodifiable(_winLine);
  String getCaroCell(int row, int col) => _caroBoard['$row,$col'] ?? '';

  
  int get player1RemainingMs => _player1RemainingMs;
  int get player2RemainingMs => _player2RemainingMs;
  int get turnTimerSeconds => _turnTimerSeconds;
  bool get isPlayer1Turn => _currentTurnUserId == _match?.player1Id;

  
  DrawRequest? get pendingDrawRequest => _pendingDrawRequest;
  bool get hasIncomingDrawRequest =>
      _pendingDrawRequest != null &&
      !_pendingDrawRequest!.isAnswered &&
      _pendingDrawRequest!.requesterId != _currentUserId;

  
  String? get disconnectedPlayerId => _disconnectedPlayerId;
  int get disconnectCountdown => _disconnectCountdown;

  
  bool get isReplayMode => _isReplayMode;
  int get replayIndex => _replayIndex;
  int get replayTotal => _replayMoves.length;
  bool get canReplayBack => _replayIndex > 0;
  bool get canReplayForward => _replayIndex < _replayMoves.length - 1;

  
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  
  
  

  
  
  Future<void> initialize({
    required String matchId,
    required String currentUserId,
  }) async {
    _currentUserId = currentUserId;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      
      final match = await _firebase.fetchMatch(matchId);
      if (match == null) {
        _errorMessage = 'Không tìm thấy trận đấu';
        _isLoading = false;
        notifyListeners();
        return;
      }

      _applyMatchData(match);

      
      _role = _detectRole(match, currentUserId);

      
      if (_role == PlayerRole.spectator) {
        await _firebase.joinAsSpectator(matchId, currentUserId);
      }

      
      _initClocks(match);

      
      _subscribeMatch(matchId);
      _subscribeLatestMove(matchId);
      _subscribeDisconnect(matchId);

      
      if (match.isPlaying) {
        _startActiveTimer();
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Lỗi khởi tạo trận: $e';
      _isLoading = false;
      notifyListeners();
      debugPrint('[GameStateProvider] initialize error: $e');
    }
  }

  

  void _applyMatchData(GameMatch match) {
    _match = match;
    if (match.moveHistory.isNotEmpty) {
      
      _rebuildBoardFromHistory(match.moveHistory);
      _nextMoveIndex = match.moveHistory.length;
    }
    _currentTurnUserId = _computeCurrentTurn(match);
    if (match.isFinished || match.isAborted) {
      _isGameOver = true;
      _finalResult = match.result;
    }
  }

  PlayerRole _detectRole(GameMatch match, String userId) {
    if (match.player1Id == userId) return PlayerRole.player1;
    if (match.player2Id == userId) return PlayerRole.player2;
    return PlayerRole.spectator;
  }

  String _computeCurrentTurn(GameMatch match) {
    if (_nextMoveIndex == 0) return match.player1Id;
    
    return _nextMoveIndex.isEven ? match.player1Id : (match.player2Id ?? match.player1Id);
  }

  

  void _initClocks(GameMatch match) {
    if (match.timeControlSeconds > 0) {
      final totalMs = match.timeControlSeconds * 1000;
      _player1RemainingMs = totalMs;
      _player2RemainingMs = totalMs;
    }
    if (match.turnTimerSeconds > 0) {
      _turnTimerSeconds = match.turnTimerSeconds;
    }
  }

  

  void _subscribeMatch(String matchId) {
    _matchSub?.cancel();
    _matchSub = _firebase.watchMatch(matchId).listen((match) {
      if (match == null) return;
      final wasPlaying = _match?.isPlaying ?? false;
      _match = match;

      
      notifyListeners();

      
      if (match.isFinished && !_isGameOver) {
        _handleGameOverFromFirestore(match);
      }
    });
  }

  void _subscribeLatestMove(String matchId) {
    _moveSub?.cancel();
    _moveSub = _firebase.watchLatestMove(matchId).listen((move) {
      if (move == null) return;
      
      if (move.movedBy != _currentUserId && move.moveIndex >= _nextMoveIndex) {
        _applyMoveToBoard(move);
      }
    });
  }

  void _subscribeDisconnect(String matchId) {
    _disconnectSub?.cancel();
    _disconnectSub = _firebase.watchDisconnectStatus(matchId).listen((info) {
      if (info == null) {
        
        _cancelDisconnectTimer();
      } else {
        final userId = info['userId'] as String?;
        if (userId != null && userId != _currentUserId) {
          _startDisconnectCountdown(userId);
        }
      }
    });
  }

  
  
  

  
  
  Future<bool> playCaroMove(int row, int col) async {
    if (!isMyTurn) return false;
    if (_match == null || _isGameOver) return false;
    if (getCaroCell(row, col).isNotEmpty) return false; 

    final symbol = _myCaroSymbol;
    final key = '$row,$col';

    
    _caroBoard[key] = symbol;
    _lastMove = CaroCell(row, col, symbol);

    
    _advanceTurn();

    
    final winCells = _checkCaroWin(row, col, symbol);
    if (winCells != null) {
      _winLine = winCells;
      _handleCaroWin();
    } else if (_checkCaroDraw()) {
      _handleDraw(EndReason.drawAgreed); 
    }

    notifyListeners();

    
    final move = GameMove(
      moveIndex: _nextMoveIndex - 1,
      movedBy: _currentUserId,
      moveData: {'row': row, 'col': col, 'symbol': symbol},
      movedAt: DateTime.now().millisecondsSinceEpoch.toString(),
      remainingTimeMs: _myRemainingMs,
    );

    try {
      await _firebase.addMove(_match!.matchId, move);
    } catch (e) {
      debugPrint('[GameStateProvider] playCaroMove firebase error: $e');
    }

    
    if (_isGameOver) {
      await _notifyGameOver();
    } else {
      _startActiveTimer();
    }

    return true;
  }

  

  String get _myCaroSymbol {
    if (_match == null) return 'X';
    return _currentUserId == _match!.player1Id ? 'X' : 'O';
  }

  

  
  
  List<CaroCell>? _checkCaroWin(int row, int col, String symbol) {
    
    const directions = [
      [0, 1], 
      [1, 0], 
      [1, 1], 
      [1, -1], 
    ];

    for (final dir in directions) {
      final dr = dir[0];
      final dc = dir[1];
      final line = <CaroCell>[];

      
      for (int i = 4; i >= 1; i--) {
        final r = row - dr * i;
        final c = col - dc * i;
        if (_caroBoard['$r,$c'] == symbol) {
          line.add(CaroCell(r, c, symbol));
        } else {
          line.clear();
        }
      }

      
      line.add(CaroCell(row, col, symbol));

      
      for (int i = 1; i <= 4; i++) {
        final r = row + dr * i;
        final c = col + dc * i;
        if (_caroBoard['$r,$c'] == symbol) {
          line.add(CaroCell(r, c, symbol));
          if (line.length >= 5) {
            
            return line.take(5).toList();
          }
        } else {
          break;
        }
      }

      
      if (line.length >= 5) {
        return line.take(5).toList();
      }
    }

    return null;
  }

  
  bool _checkCaroDraw() {
    final boardSize = _match?.boardSize ?? 0;
    if (boardSize == 0) return false; 
    
    if (boardSize == 3) {
      for (int r = 0; r < 3; r++) {
        for (int c = 0; c < 3; c++) {
          if (_caroBoard['$r,$c'] == null || _caroBoard['$r,$c']!.isEmpty) {
            return false;
          }
        }
      }
      return true;
    }
    return false;
  }

  
  
  static String checkTicTacToeWinner(List<String> board) {
    const lines = [
      [0, 1, 2], [3, 4, 5], [6, 7, 8], 
      [0, 3, 6], [1, 4, 7], [2, 5, 8], 
      [0, 4, 8], [2, 4, 6], 
    ];
    for (final l in lines) {
      if (board[l[0]].isNotEmpty && board[l[0]] == board[l[1]] && board[l[1]] == board[l[2]]) {
        return board[l[0]];
      }
    }
    return '';
  }

  

  void _handleCaroWin() {
    _isGameOver = true;
    _winnerUserId = _currentUserId; 
    _finalResult =
        (_currentUserId == _match!.player1Id) ? GameResult.player1Win : GameResult.player2Win;
    _endReason = EndReason.fiveInRow;
    _stopAllTimers();
  }

  
  
  

  void _startActiveTimer() {
    _chessClockTimer?.cancel();
    _turnTimer?.cancel();

    final match = _match;
    if (match == null || _isGameOver) return;

    
    if (match.timeControlSeconds > 0) {
      _chessClockTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (_isGameOver) {
          _chessClockTimer?.cancel();
          return;
        }
        if (isPlayer1Turn) {
          _player1RemainingMs -= 100;
          if (_player1RemainingMs <= 0) {
            _player1RemainingMs = 0;
            _handleClockTimeout(match.player1Id);
          }
        } else {
          _player2RemainingMs -= 100;
          if (_player2RemainingMs <= 0) {
            _player2RemainingMs = 0;
            _handleClockTimeout(match.player2Id ?? '');
          }
        }
        notifyListeners();
      });
    }

    
    if (match.gameType == GameType.caro && match.turnTimerSeconds > 0) {
      _turnTimerSeconds = match.turnTimerSeconds;
      _turnTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_isGameOver) {
          _turnTimer?.cancel();
          return;
        }
        _turnTimerSeconds--;
        if (_turnTimerSeconds <= 0) {
          _turnTimerSeconds = 0;
          _handleTurnTimeout();
        }
        notifyListeners();
      });
    }
  }

  void _handleClockTimeout(String timedOutUserId) {
    _chessClockTimer?.cancel();
    _isGameOver = true;
    _endReason = EndReason.timeout;
    _winnerUserId = (timedOutUserId == _match?.player1Id) ? _match?.player2Id : _match?.player1Id;
    _finalResult =
        (timedOutUserId == _match?.player1Id) ? GameResult.player2Win : GameResult.player1Win;
    notifyListeners();
    _notifyGameOver();
  }

  void _handleTurnTimeout() {
    _turnTimer?.cancel();
    if (!isMyTurn) return; 
    _isGameOver = true;
    _endReason = EndReason.turnTimeout;
    _winnerUserId = (_currentUserId == _match?.player1Id) ? _match?.player2Id : _match?.player1Id;
    _finalResult =
        (_currentUserId == _match?.player1Id) ? GameResult.player2Win : GameResult.player1Win;
    notifyListeners();
    _notifyGameOver();
  }

  

  void _resetTurnTimer() {
    _turnTimer?.cancel();
    final match = _match;
    if (match == null || match.turnTimerSeconds == 0) return;
    _turnTimerSeconds = match.turnTimerSeconds;
    _startActiveTimer();
  }

  

  int get _myRemainingMs {
    if (_currentUserId == _match?.player1Id) return _player1RemainingMs;
    return _player2RemainingMs;
  }

  
  
  

  
  Future<void> resign() async {
    if (!isPlayer || _isGameOver) return;

    _isGameOver = true;
    _endReason = EndReason.resign;
    _winnerUserId = (_currentUserId == _match?.player1Id) ? _match?.player2Id : _match?.player1Id;
    _finalResult =
        (_currentUserId == _match?.player1Id) ? GameResult.player2Win : GameResult.player1Win;
    _stopAllTimers();
    notifyListeners();

    await _notifyGameOver();
  }

  
  
  

  
  Future<void> requestDraw() async {
    if (!isPlayer || _isGameOver) return;
    if (_pendingDrawRequest != null && !_pendingDrawRequest!.isAnswered) return;

    _pendingDrawRequest = DrawRequest(
      requesterId: _currentUserId,
      sentAt: DateTime.now(),
    );
    notifyListeners();

    
    try {
      await _firebase.updateMatch(_match!.matchId, {
        'drawRequest': {
          'requesterId': _currentUserId,
          'sentAt': DateTime.now().millisecondsSinceEpoch.toString(),
        },
      });
    } catch (e) {
      debugPrint('[GameStateProvider] requestDraw error: $e');
    }
  }

  
  Future<void> acceptDraw() async {
    if (!hasIncomingDrawRequest || _isGameOver) return;

    _pendingDrawRequest?.isAnswered = true;
    _handleDraw(EndReason.drawAgreed);
    notifyListeners();
    await _notifyGameOver();
  }

  
  Future<void> declineDraw() async {
    if (!hasIncomingDrawRequest) return;
    _pendingDrawRequest?.isAnswered = true;
    notifyListeners();

    try {
      await _firebase.updateMatch(_match!.matchId, {
        'drawRequest': null,
      });
    } catch (e) {
      debugPrint('[GameStateProvider] declineDraw error: $e');
    }
  }

  void _handleDraw(EndReason reason) {
    _isGameOver = true;
    _endReason = reason;
    _finalResult = GameResult.draw;
    _winnerUserId = null;
    _stopAllTimers();
  }

  
  
  

  
  Future<void> onDisconnected() async {
    if (_match == null || _isGameOver) return;
    await _firebase.markPlayerDisconnected(_match!.matchId, _currentUserId);
  }

  
  Future<void> onReconnected() async {
    if (_match == null) return;
    await _firebase.markPlayerReconnected(_match!.matchId);
    _cancelDisconnectTimer();
  }

  void _startDisconnectCountdown(String disconnectedUserId) {
    _disconnectedPlayerId = disconnectedUserId;
    _disconnectCountdown = 60;
    notifyListeners();

    _disconnectTimer?.cancel();
    _disconnectTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _disconnectCountdown--;
      notifyListeners();

      if (_disconnectCountdown <= 0) {
        _disconnectTimer?.cancel();
        
        _handleDisconnectLoss(disconnectedUserId);
      }
    });
  }

  void _handleDisconnectLoss(String loserUserId) {
    if (_isGameOver) return;
    _isGameOver = true;
    _endReason = EndReason.disconnect;
    _winnerUserId = (loserUserId == _match?.player1Id) ? _match?.player2Id : _match?.player1Id;
    _finalResult =
        (loserUserId == _match?.player1Id) ? GameResult.player2Win : GameResult.player1Win;
    _disconnectedPlayerId = null;
    _stopAllTimers();
    notifyListeners();
    _notifyGameOver();
  }

  void _cancelDisconnectTimer() {
    _disconnectTimer?.cancel();
    _disconnectCountdown = 60;
    _disconnectedPlayerId = null;
    notifyListeners();
  }

  
  
  

  Future<void> _notifyGameOver() async {
    final match = _match;
    if (match == null || _finalResult == null) return;

    try {
      await _firebase.finishMatch(
        matchId: match.matchId,
        result: _finalResult!,
        endReason: _endReason?.label ?? 'unknown',
        totalMoves: _nextMoveIndex,
      );
    } catch (e) {
      debugPrint('[GameStateProvider] _notifyGameOver error: $e');
    }
  }

  void _handleGameOverFromFirestore(GameMatch match) {
    _isGameOver = true;
    _finalResult = match.result;
    _winnerUserId = match.winnerId;
    _stopAllTimers();
    notifyListeners();
  }

  
  
  

  void _advanceTurn() {
    _nextMoveIndex++;
    _currentTurnUserId = _computeCurrentTurn(_match!);
    _resetTurnTimer();
  }

  void _applyMoveToBoard(GameMove move) {
    final data = move.moveData;
    final match = _match;
    if (match == null) return;

    if (match.gameType == GameType.caro) {
      final row = data['row'] as int?;
      final col = data['col'] as int?;
      final symbol = data['symbol'] as String?;
      if (row != null && col != null && symbol != null) {
        _caroBoard['$row,$col'] = symbol;
        _lastMove = CaroCell(row, col, symbol);

        
        final winCells = _checkCaroWin(row, col, symbol);
        if (winCells != null) {
          _winLine = winCells;
          _isGameOver = true;
          _winnerUserId = move.movedBy;
          _finalResult =
              (move.movedBy == match.player1Id) ? GameResult.player1Win : GameResult.player2Win;
          _endReason = EndReason.fiveInRow;
          _stopAllTimers();
        }
      }
    }

    
    if (move.remainingTimeMs > 0) {
      if (move.movedBy == match.player1Id) {
        _player1RemainingMs = move.remainingTimeMs;
      } else {
        _player2RemainingMs = move.remainingTimeMs;
      }
    }

    _nextMoveIndex = move.moveIndex + 1;
    _currentTurnUserId = _computeCurrentTurn(match);
    notifyListeners();
  }

  void _rebuildBoardFromHistory(List<GameMove> moves) {
    _caroBoard.clear();
    for (final move in moves) {
      final data = move.moveData;
      if (_match?.gameType == GameType.caro) {
        final row = data['row'] as int?;
        final col = data['col'] as int?;
        final symbol = data['symbol'] as String?;
        if (row != null && col != null && symbol != null) {
          _caroBoard['$row,$col'] = symbol;
        }
      }
    }
    if (moves.isNotEmpty) {
      final last = moves.last;
      final data = last.moveData;
      final row = data['row'] as int?;
      final col = data['col'] as int?;
      final symbol = data['symbol'] as String?;
      if (row != null && col != null && symbol != null) {
        _lastMove = CaroCell(row, col, symbol);
      }
    }
  }

  
  
  

  
  Future<void> startReplay() async {
    if (_match == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      _replayMoves = await _firebase.fetchAllMoves(_match!.matchId);
      _isReplayMode = true;
      _replayIndex = -1;
      _caroBoard.clear();
      _lastMove = null;
      _winLine = [];
      _stopAllTimers();
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Không thể tải lịch sử trận: $e';
      notifyListeners();
    }
  }

  
  void stopReplay() {
    _isReplayMode = false;
    _replayIndex = -1;
    _replayTimer?.cancel();
    
    _rebuildBoardFromHistory(_replayMoves);
    notifyListeners();
  }

  
  void replayForward() {
    if (!canReplayForward) return;
    _replayIndex++;
    _applyReplayState(_replayIndex);
  }

  
  void replayBack() {
    if (!canReplayBack) return;
    _replayIndex--;
    _applyReplayState(_replayIndex);
  }

  
  void replayPlay({int intervalMs = 800}) {
    _replayTimer?.cancel();
    _replayTimer = Timer.periodic(
      Duration(milliseconds: intervalMs),
      (_) {
        if (canReplayForward) {
          replayForward();
        } else {
          _replayTimer?.cancel();
        }
      },
    );
  }

  
  void replayPause() {
    _replayTimer?.cancel();
  }

  void _applyReplayState(int index) {
    _caroBoard.clear();
    _lastMove = null;
    _winLine = [];

    for (int i = 0; i <= index && i < _replayMoves.length; i++) {
      final move = _replayMoves[i];
      final data = move.moveData;
      if (_match?.gameType == GameType.caro) {
        final row = data['row'] as int?;
        final col = data['col'] as int?;
        final symbol = data['symbol'] as String?;
        if (row != null && col != null && symbol != null) {
          _caroBoard['$row,$col'] = symbol;
          _lastMove = CaroCell(row, col, symbol);
        }
      }
    }

    
    if (_replayIndex >= 0 && _replayIndex < _replayMoves.length) {
      final move = _replayMoves[_replayIndex];
      final data = move.moveData;
      final row = data['row'] as int?;
      final col = data['col'] as int?;
      final symbol = data['symbol'] as String?;
      if (row != null && col != null && symbol != null) {
        final winCells = _checkCaroWin(row, col, symbol);
        if (winCells != null) {
          _winLine = winCells;
        }
      }
    }

    notifyListeners();
  }

  
  
  

  void _stopAllTimers() {
    _chessClockTimer?.cancel();
    _turnTimer?.cancel();
    _disconnectTimer?.cancel();
    _replayTimer?.cancel();
  }

  
  
  

  
  Future<void> leaveAsSpectator() async {
    if (_match == null || !isSpectator) return;
    await _firebase.leaveAsSpectator(_match!.matchId, _currentUserId);
  }

  
  
  

  
  
  static GameMatch buildNewMatch({
    required String matchId,
    required GameType gameType,
    required String player1Id,
    required String player1Name,
    required String player1Avatar,
    required String sourceGroupId,
    ChessSide player1Side = ChessSide.random,
    int timeControlSeconds = 0,
    int turnTimerSeconds = 0,
    int boardSize = 0,
    String? targetUserId,
    String? targetUserName,
  }) {
    
    ChessSide resolvedSide = player1Side;
    if (player1Side == ChessSide.random) {
      resolvedSide = math.Random().nextBool() ? ChessSide.white : ChessSide.black;
    }

    return GameMatch(
      matchId: matchId,
      gameType: gameType,
      status: GameMatchStatus.waiting,
      player1Id: player1Id,
      player1Name: player1Name,
      player1Avatar: player1Avatar,
      player1Side: resolvedSide,
      timeControlSeconds: timeControlSeconds,
      turnTimerSeconds: turnTimerSeconds,
      boardSize: boardSize,
      sourceGroupId: sourceGroupId,
      createdAt: DateTime.now().millisecondsSinceEpoch.toString(),
    );
  }

  
  
  

  
  static String formatClock(int ms) {
    if (ms <= 0) return '0:00';
    final totalSeconds = (ms / 1000).ceil();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  
  static String formatClockPrecise(int ms) {
    if (ms <= 0) return '0:00.0';
    if (ms >= 10000) return formatClock(ms);
    final seconds = ms ~/ 1000;
    final tenths = (ms % 1000) ~/ 100;
    return '0:0$seconds.$tenths';
  }

  
  
  

  @override
  void dispose() {
    _stopAllTimers();
    _matchSub?.cancel();
    _moveSub?.cancel();
    _disconnectSub?.cancel();
    
    if (isSpectator && _match != null) {
      _firebase.leaveAsSpectator(_match!.matchId, _currentUserId);
    }
    super.dispose();
  }
}
