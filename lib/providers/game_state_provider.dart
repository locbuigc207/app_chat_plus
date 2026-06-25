import 'dart:async';
import 'dart:math' as math;

import 'package:chess/chess.dart' as ch;
import 'package:flutter/foundation.dart';
import 'package:flutter_chat_demo/models/game_match.dart';
import 'package:flutter_chat_demo/models/message_chat.dart';
import 'package:flutter_chat_demo/services/game_firebase_service.dart';
import 'package:uuid/uuid.dart';

// =========================================================
// ENUMS & VALUE TYPES
// =========================================================

enum PlayerRole { player1, player2, spectator }

enum EndReason {
  threeInRow,
  fiveInRow,
  checkmate,
  timeout,
  turnTimeout,
  resign,
  drawAgreed,
  disconnect,
  stalemate,
  insufficientMaterial;

  String get label {
    switch (this) {
      case EndReason.threeInRow:
        return 'three_in_row';
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
      case EndReason.threeInRow:
        return '3 quân liên tiếp';
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

// =========================================================
// GAME STATE PROVIDER
// =========================================================

class GameStateProvider extends ChangeNotifier {
  // ── Dependencies ──────────────────────────────────────────────────────────
  final GameFirebaseService _firebase = GameFirebaseService();
  final _uuid = const Uuid();

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  bool _disposed = false;

  // ── Match ─────────────────────────────────────────────────────────────────
  GameMatch? _match;
  String _currentUserId = '';
  PlayerRole _role = PlayerRole.spectator;

  // ── Subscriptions ─────────────────────────────────────────────────────────
  StreamSubscription<GameMatch?>? _matchSub;
  StreamSubscription<GameMove?>? _moveSub;
  StreamSubscription<dynamic>? _disconnectSub;
  StreamSubscription<dynamic>? _drawSub;
  final Set<int> _processedMoveIndices = {};

  // ── Board State (Caro) ────────────────────────────────────────────────────
  final Map<String, String> _caroBoard = {};
  CaroCell? _lastMove;
  List<CaroCell> _winLine = [];

  // ── Board State (Chess) ───────────────────────────────────────────────────
  ch.Chess? _chessEngine;
  String _chessFen = ch.Chess.DEFAULT_POSITION;
  String _lastChessMoveUci = '';
  final List<String> _chessSanHistory = [];

  // ── Turn ──────────────────────────────────────────────────────────────────
  String _currentTurnUserId = '';
  int _nextMoveIndex = 0;

  // ── Chess Clock ───────────────────────────────────────────────────────────
  int _player1RemainingMs = 0;
  int _player2RemainingMs = 0;
  Timer? _chessClockTimer;

  // ── Turn Timer ────────────────────────────────────────────────────────────
  int _turnTimerSeconds = 0;
  Timer? _turnTimer;

  // ── Draw / Resign ─────────────────────────────────────────────────────────
  DrawRequest? _pendingDrawRequest;

  // ── Disconnect ────────────────────────────────────────────────────────────
  Timer? _disconnectTimer;
  String? _disconnectedPlayerId;
  int _disconnectCountdown = 60;

  // ── Game Over ─────────────────────────────────────────────────────────────
  bool _isGameOver = false;
  GameResult? _finalResult;
  EndReason? _endReason;
  String? _winnerUserId;

  // ── Replay ────────────────────────────────────────────────────────────────
  bool _isReplayMode = false;
  List<GameMove> _replayMoves = [];
  int _replayIndex = -1;
  Timer? _replayTimer;

  // ── Loading ───────────────────────────────────────────────────────────────
  bool _isLoading = false;
  String? _errorMessage;

  // =========================================================
  // GETTERS
  // =========================================================

  GameMatch? get match => _match;
  PlayerRole get role => _role;
  bool get isPlayer =>
      _role == PlayerRole.player1 || _role == PlayerRole.player2;
  bool get isSpectator => _role == PlayerRole.spectator;
  bool get isMyTurn =>
      _currentTurnUserId == _currentUserId && !_isGameOver && !_isReplayMode;
  bool get isGameOver => _isGameOver;
  GameResult? get finalResult => _finalResult;
  EndReason? get endReason => _endReason;
  String? get winnerUserId => _winnerUserId;
  bool get isPlayer1Turn => _currentTurnUserId == _match?.player1Id;

  // Caro
  Map<String, String> get caroBoard => Map.unmodifiable(_caroBoard);
  CaroCell? get lastMove => _lastMove;
  List<CaroCell> get winLine => List.unmodifiable(_winLine);
  String getCaroCell(int row, int col) => _caroBoard['$row,$col'] ?? '';

  // Chess
  String get chessFen => _chessFen;
  String get lastChessMoveUci => _lastChessMoveUci;
  List<String> get chessSanHistory => List.unmodifiable(_chessSanHistory);
  bool get chessInCheck => _chessEngine?.in_check ?? false;
  bool get chessInCheckmate => _chessEngine?.in_checkmate ?? false;
  bool get chessInStalemate => _chessEngine?.in_stalemate ?? false;
  bool get chessInDraw => _chessEngine?.in_draw ?? false;
  bool get chessGameOver => _chessEngine?.game_over ?? false;

  String get myChessColor {
    if (_match == null) return 'white';
    final isPlayer1 = _currentUserId == _match!.player1Id;
    final p1Side = _match!.player1Side;
    if (p1Side == ChessSide.white) {
      return isPlayer1 ? 'white' : 'black';
    } else {
      return isPlayer1 ? 'black' : 'white';
    }
  }

  // Clocks
  int get player1RemainingMs => _player1RemainingMs;
  int get player2RemainingMs => _player2RemainingMs;
  int get turnTimerSeconds => _turnTimerSeconds;

  // Draw
  DrawRequest? get pendingDrawRequest => _pendingDrawRequest;
  bool get hasIncomingDrawRequest =>
      _pendingDrawRequest != null &&
      !_pendingDrawRequest!.isAnswered &&
      _pendingDrawRequest!.requesterId != _currentUserId;

  // Disconnect
  String? get disconnectedPlayerId => _disconnectedPlayerId;
  int get disconnectCountdown => _disconnectCountdown;

  // Replay
  bool get isReplayMode => _isReplayMode;
  int get replayIndex => _replayIndex;
  int get replayTotal => _replayMoves.length;
  bool get canReplayBack => _replayIndex > -1;
  bool get canReplayForward => _replayIndex < _replayMoves.length - 1;
  List<GameMove> get replayMoves => List.unmodifiable(_replayMoves);
  int get totalMoveCount => _nextMoveIndex;

  // Loading
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  // =========================================================
  // INITIALIZE
  // =========================================================

  Future<void> initialize({
    required String matchId,
    required String currentUserId,
    String currentUserName = '', // MỚI (Fix Bug 2)
    String currentUserAvatar = '', // MỚI (Fix Bug 2)
  }) async {
    _currentUserId = currentUserId;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Lấy dữ liệu dạng nullable từ Firebase
      GameMatch? fetchedMatch = await _firebase.fetchMatch(matchId);
      if (fetchedMatch == null) {
        _errorMessage = 'Không tìm thấy trận đấu';
        _isLoading = false;
        notifyListeners();
        return;
      }

      GameMatch match = fetchedMatch;

      // Xác định Role ngay để xử lý Auto-Accept
      _role = _detectRole(match, currentUserId);

      // AUTO-ACCEPT (Fix Bug 2): Nếu là player2 bước vào phòng chờ, tự động accept
      if (_role == PlayerRole.player2 && match.isWaiting) {
        try {
          await _firebase.acceptMatch(
            matchId: matchId,
            player2Id: currentUserId,
            player2Name: currentUserName,
            player2Avatar: currentUserAvatar,
          );
          final updatedMatch = await _firebase.fetchMatch(matchId);
          if (updatedMatch != null) {
            match = updatedMatch; // Gán lại biến non-nullable hợp lệ
          }
        } catch (e) {
          debugPrint('[GameStateProvider] acceptMatch error: $e');
        }
      } else if (_role == PlayerRole.spectator) {
        await _firebase.joinAsSpectator(matchId, currentUserId);
      }

      _applyMatchData(match);

      if (match.gameType == GameType.chess) {
        // Lưu ý: initialFen trong class GameMatch là String?
        // Nếu hàm _initChessEngine() bắt buộc nhận String (non-null),
        // bạn có thể đổi thành match.initialFen ?? ''
        _initChessEngine(match.initialFen);
      }

      if (match.isPlaying || match.isFinished) {
        final moves = await _firebase.fetchAllMoves(matchId);
        if (moves.isNotEmpty) {
          if (match.gameType == GameType.chess) {
            _rebuildChessFromHistory(moves);
          } else {
            _rebuildBoardFromHistory(moves);
          }
          _nextMoveIndex = moves.last.moveIndex + 1;
          _currentTurnUserId = _computeCurrentTurn(match);

          if (match.timeControlSeconds > 0) {
            final lastMove = moves.last;
            if (lastMove.remainingTimeMs > 0) {
              if (lastMove.movedBy == match.player1Id) {
                _player1RemainingMs = lastMove.remainingTimeMs;
              } else {
                _player2RemainingMs = lastMove.remainingTimeMs;
              }
            }
          }
        }
      }

      _initClocks(match);

      _subscribeMatch(matchId);
      _subscribeLatestMove(matchId);
      _subscribeDisconnect(matchId);
      _subscribeDrawRequest(matchId);

      if (match.isPlaying) {
        _startActiveTimer();
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Lỗi khởi tạo: $e';
      _isLoading = false;
      notifyListeners();
      debugPrint('[GameStateProvider] initialize error: $e');
    }
  }

  // ── Internal helpers ──────────────────────────────────────────────────────

  void _applyMatchData(GameMatch match) {
    _match = match;
    _currentTurnUserId = _computeCurrentTurn(match);
    if (match.isFinished || match.isAborted) {
      _isGameOver = true;
      _finalResult = match.result;
    }
  }

  PlayerRole _detectRole(GameMatch match, String userId) {
    if (match.player1Id == userId) return PlayerRole.player1;
    if (match.player2Id == userId) return PlayerRole.player2;

    // FIX BUG 3: Đảm bảo Player2 không bị nhầm thành spectator khi đang waiting
    if (match.isWaiting && match.targetUserId == userId) {
      return PlayerRole.player2;
    }
    if (match.isWaiting &&
        match.targetUserId == null &&
        match.player1Id != userId) {
      return PlayerRole.player2;
    }

    return PlayerRole.spectator;
  }

  String _computeCurrentTurn(GameMatch match) {
    final player1IsWhite = match.player1Side == ChessSide.white;
    final isWhiteTurn = _nextMoveIndex.isEven;

    // FIX BUG 5: Xử lý fallback chặt chẽ, không trả lại lượt cho Player 1
    // nếu như đó là lượt của quân Trắng mà Player 1 đang cầm quân Đen
    if (isWhiteTurn) {
      return player1IsWhite
          ? match.player1Id
          : (match.player2Id ?? ''); // Trả về rỗng nếu player2 chưa vào
    } else {
      return player1IsWhite ? (match.player2Id ?? '') : match.player1Id;
    }
  }

  void _initClocks(GameMatch match) {
    if (match.timeControlSeconds > 0) {
      final totalMs = match.timeControlSeconds * 1000;
      if (_player1RemainingMs == 0) _player1RemainingMs = totalMs;
      if (_player2RemainingMs == 0) _player2RemainingMs = totalMs;
    }
    if (match.turnTimerSeconds > 0) {
      _turnTimerSeconds = match.turnTimerSeconds;
    }
  }

  // ── Subscriptions ─────────────────────────────────────────────────────────

  void _subscribeMatch(String matchId) {
    bool wasWaiting = _match?.isWaiting ?? true; // Lưu trạng thái cũ

    _matchSub?.cancel();
    _matchSub = _firebase.watchMatch(matchId).listen((match) {
      if (match == null) return;

      // FIX BUG 4: Kiểm tra sự thay đổi trạng thái từ waiting -> playing
      final justBecamePlaying = wasWaiting && match.isPlaying;
      wasWaiting = match.isWaiting;

      _match = match;
      notifyListeners();

      if (justBecamePlaying) {
        _initClocks(match);
        _startActiveTimer(); // Bật đồng hồ ngay lập tức
      }

      if (match.isFinished && !_isGameOver) {
        _handleGameOverFromFirestore(match);
      }
    });
  }

  void _subscribeLatestMove(String matchId) {
    _processedMoveIndices.clear();
    _moveSub?.cancel();
    _moveSub = _firebase.watchLatestMove(matchId).listen((move) {
      if (move == null) return;
      if (move.movedBy == _currentUserId) return;
      if (_processedMoveIndices.contains(move.moveIndex)) return;
      if (move.moveIndex >= _nextMoveIndex) {
        _processedMoveIndices.add(move.moveIndex);
        unawaited(_syncMove(move));
      }
    });
  }

  Future<void> _syncMove(GameMove move) async {
    if (_disposed) return;
    if (move.moveIndex > _nextMoveIndex && _match != null) {
      final allMoves = await _firebase.fetchAllMoves(_match!.matchId);
      if (_disposed) return;
      if (_match?.gameType == GameType.chess) {
        _rebuildChessFromHistory(allMoves);
      } else {
        _rebuildBoardFromHistory(allMoves);
      }
      _nextMoveIndex = allMoves.isNotEmpty ? allMoves.last.moveIndex + 1 : 0;
      _currentTurnUserId = _computeCurrentTurn(_match!);
      if (_match?.gameType == GameType.chess) _checkChessGameOver();
    } else {
      _applyMoveToBoard(move);
      return;
    }
    notifyListeners();
  }

  void _subscribeDisconnect(String matchId) {
    _disconnectSub?.cancel();
    _disconnectSub = _firebase.watchDisconnectStatus(matchId).listen((info) {
      if (info == null) {
        _cancelDisconnectTimer();
      } else if (info is DisconnectInfo && info.userId != _currentUserId) {
        _startDisconnectCountdown(info.userId);
      }
    });
  }

  void _subscribeDrawRequest(String matchId) {
    _drawSub?.cancel();
    _drawSub = _firebase.watchDrawRequest(matchId).listen((info) {
      if (info == null) {
        if (_pendingDrawRequest != null && _pendingDrawRequest!.isAnswered) {
          _pendingDrawRequest = null;
          notifyListeners();
        }
        return;
      }

      if (info is DrawRequestInfo && info.requesterId != _currentUserId) {
        if (_pendingDrawRequest == null ||
            _pendingDrawRequest!.requesterId != info.requesterId) {
          _pendingDrawRequest = DrawRequest(
            requesterId: info.requesterId,
            sentAt: DateTime.fromMillisecondsSinceEpoch(
              int.tryParse(info.sentAt) ??
                  DateTime.now().millisecondsSinceEpoch,
            ),
          );
          notifyListeners();
        }
      }
    });
  }

  // =========================================================
  // CARO LOGIC
  // =========================================================

  Future<bool> playCaroMove(int row, int col) async {
    if (!isMyTurn || _match == null || _isGameOver) return false;
    if (getCaroCell(row, col).isNotEmpty) return false;

    final symbol = _myCaroSymbol;
    _caroBoard['$row,$col'] = symbol;
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
      _caroBoard.remove('$row,$col');
      _lastMove = null;
      _nextMoveIndex--;
      _isGameOver = false;
      _winLine = [];
      _currentTurnUserId = _computeCurrentTurn(_match!);
      notifyListeners();
      debugPrint('[GameStateProvider] addMove failed, rolled back: $e');
      return false;
    }

    if (_isGameOver) {
      await _notifyGameOver();
    } else {
      _startActiveTimer();
    }

    return true;
  }

  String get _myCaroSymbol => _currentUserId == _match?.player1Id ? 'X' : 'O';

  List<CaroCell>? _checkCaroWin(int row, int col, String symbol) {
    final winLength = _match?.boardSize == 3 ? 3 : 5;
    const dirs = [
      [0, 1],
      [1, 0],
      [1, 1],
      [1, -1],
    ];
    for (final dir in dirs) {
      final dr = dir[0], dc = dir[1];
      final line = <CaroCell>[CaroCell(row, col, symbol)];

      for (int i = 1; i <= winLength - 1; i++) {
        final r = row - dr * i, c = col - dc * i;
        if (_caroBoard['$r,$c'] == symbol) {
          line.insert(0, CaroCell(r, c, symbol));
        } else {
          break;
        }
      }

      for (int i = 1; i <= winLength - 1; i++) {
        final r = row + dr * i, c = col + dc * i;
        if (_caroBoard['$r,$c'] == symbol) {
          line.add(CaroCell(r, c, symbol));
        } else {
          break;
        }
      }

      if (line.length >= winLength) return line.take(winLength).toList();
    }
    return null;
  }

  bool _checkCaroDraw() {
    final boardSize = _match?.boardSize ?? 0;
    if (boardSize != 3) return false;

    for (int r = 0; r < 3; r++) {
      for (int c = 0; c < 3; c++) {
        if ((_caroBoard['$r,$c'] ?? '').isEmpty) return false;
      }
    }
    return true;
  }

  void _handleCaroWin() {
    _isGameOver = true;
    _winnerUserId = _currentUserId;
    _finalResult = (_currentUserId == _match!.player1Id)
        ? GameResult.player1Win
        : GameResult.player2Win;
    _endReason = (_match?.boardSize == 3)
        ? EndReason.threeInRow
        : EndReason.fiveInRow;
    _stopAllTimers();
  }

  // =========================================================
  // CHESS LOGIC
  // =========================================================

  void _initChessEngine([String? fen]) {
    if (fen != null && fen.isNotEmpty) {
      try {
        _chessEngine = ch.Chess.fromFEN(fen);
        _chessFen = fen;
      } catch (_) {
        _chessEngine = ch.Chess();
        _chessFen = ch.Chess.DEFAULT_POSITION;
      }
    } else {
      _chessEngine = ch.Chess();
      _chessFen = ch.Chess.DEFAULT_POSITION;
    }
  }

  Future<bool> playChessMove(String uci) async {
    if (!isMyTurn || _isGameOver || _chessEngine == null) return false;
    if (_match?.gameType != GameType.chess) return false;

    final engine = _chessEngine!;
    if (uci.length < 4) return false;

    // Snapshot trạng thái trước khi thay đổi để rollback nếu lỗi
    final snapshotFen = _chessFen;
    final snapshotLastUci = _lastChessMoveUci;
    final snapshotSanLen = _chessSanHistory.length;

    final from = uci.substring(0, 2);
    final to = uci.substring(2, 4);
    final promo = uci.length >= 5 ? uci[4] : null;

    final legalMoves = engine.generate_moves();
    String? san;
    for (final m in legalMoves) {
      final mFrom = m.toAlgebraic.substring(0, 2);
      final mTo = m.toAlgebraic.substring(2, 4);
      final mPromo = m.toAlgebraic.length > 4 ? m.toAlgebraic[4] : null;
      if (mFrom == from && mTo == to && (promo == null || mPromo == promo)) {
        san = engine.move_to_san(m);
        break;
      }
    }

    // FIX BUG 7: Đảm bảo có log khi engine.move thất bại và notify lại state cũ
    final success = promo != null
        ? engine.move({'from': from, 'to': to, 'promotion': promo})
        : engine.move({'from': from, 'to': to});

    if (!success) {
      debugPrint(
        '[Chess] Illegal move rejected: $uci | FEN: ${engine.fen} | '
        'Turn: ${engine.turn} | My color: $myChessColor',
      );
      notifyListeners();
      return false;
    }

    _chessFen = engine.fen;
    _lastChessMoveUci = uci;
    if (san != null) _chessSanHistory.add(san);

    _advanceTurn();
    _checkChessGameOver();
    notifyListeners();

    final move = GameMove(
      moveIndex: _nextMoveIndex - 1,
      movedBy: _currentUserId,
      moveData: {
        'uci': uci,
        'san': san ?? uci,
        'fen': _chessFen,
        'from': from,
        'to': to,
        if (promo != null) 'promotion': promo,
      },
      movedAt: DateTime.now().millisecondsSinceEpoch.toString(),
      remainingTimeMs: _myRemainingMs,
    );

    try {
      await _firebase.addMove(_match!.matchId, move);
    } catch (e) {
      // Rollback TOÀN BỘ — bao gồm cả engine
      try {
        _chessEngine = ch.Chess.fromFEN(snapshotFen);
      } catch (_) {}
      _chessFen = snapshotFen;
      _lastChessMoveUci = snapshotLastUci;

      // Trim SAN history về snapshot length
      while (_chessSanHistory.length > snapshotSanLen) {
        _chessSanHistory.removeLast();
      }

      _nextMoveIndex = _nextMoveIndex - 1; // revert _advanceTurn
      _currentTurnUserId = _computeCurrentTurn(_match!);
      _isGameOver = false;
      notifyListeners();
      debugPrint('[GameStateProvider] chess addMove failed, rolled back: $e');
      return false;
    }

    if (_isGameOver) {
      await _notifyGameOver();
    } else {
      _startActiveTimer();
    }
    return true;
  }

  void _applyChessMoveFromOpponent(GameMove move) {
    final engine = _chessEngine;
    if (engine == null) return;
    final data = move.moveData;
    final uci = data['uci'] as String? ?? '';
    final san = data['san'] as String? ?? uci;
    final fen = data['fen'] as String?;

    if (uci.length < 4) return;

    if (fen != null && fen.isNotEmpty) {
      try {
        _chessEngine = ch.Chess.fromFEN(fen);
        _chessFen = fen;
      } catch (_) {
        _executeChessUci(engine, uci);
      }
    } else {
      _executeChessUci(engine, uci);
    }

    _lastChessMoveUci = uci;
    if (san.isNotEmpty) {
      _chessSanHistory.add(san);
    }

    if (move.remainingTimeMs > 0) {
      if (move.movedBy == _match?.player1Id) {
        _player1RemainingMs = move.remainingTimeMs;
      } else {
        _player2RemainingMs = move.remainingTimeMs;
      }
    }

    _nextMoveIndex = move.moveIndex + 1;
    _currentTurnUserId = _computeCurrentTurn(_match!);
    _checkChessGameOver();
    notifyListeners();

    if (!_isGameOver) _resetTurnTimer();
  }

  void _executeChessUci(ch.Chess engine, String uci) {
    if (uci.length < 4) return;
    final from = uci.substring(0, 2);
    final to = uci.substring(2, 4);
    final promo = uci.length >= 5 ? uci[4] : null;

    if (promo != null) {
      engine.move({'from': from, 'to': to, 'promotion': promo});
    } else {
      engine.move({'from': from, 'to': to});
    }
    _chessFen = engine.fen;
  }

  void _rebuildChessFromHistory(List<GameMove> moves) {
    _chessEngine = ch.Chess();
    _chessSanHistory.clear();
    _chessFen = ch.Chess.DEFAULT_POSITION;
    _lastChessMoveUci = '';

    if (_match?.initialFen != null && _match!.initialFen!.isNotEmpty) {
      try {
        _chessEngine = ch.Chess.fromFEN(_match!.initialFen!);
        _chessFen = _match!.initialFen!;
      } catch (_) {}
    }

    for (final move in moves) {
      final data = move.moveData;
      final fen = data['fen'] as String?;
      final uci = data['uci'] as String? ?? '';
      final san = data['san'] as String? ?? '';

      if (fen != null && fen.isNotEmpty) {
        _chessFen = fen;
        _lastChessMoveUci = uci;
        if (san.isNotEmpty) _chessSanHistory.add(san);
      } else if (uci.length >= 4) {
        _executeChessUci(_chessEngine!, uci);
        _lastChessMoveUci = uci;
        if (san.isNotEmpty) _chessSanHistory.add(san);
      }
    }

    try {
      _chessEngine = ch.Chess.fromFEN(_chessFen);
    } catch (_) {}
  }

  void _checkChessGameOver() {
    final engine = _chessEngine;
    if (engine == null) return;

    if (engine.in_checkmate) {
      _isGameOver = true;
      _endReason = EndReason.checkmate;
      final lastMover = _currentTurnUserId == _match?.player1Id
          ? _match?.player2Id
          : _match?.player1Id;
      _winnerUserId = lastMover;
      _finalResult = (lastMover == _match?.player1Id)
          ? GameResult.player1Win
          : GameResult.player2Win;
      _stopAllTimers();
      return;
    }

    if (engine.in_stalemate) {
      _isGameOver = true;
      _endReason = EndReason.stalemate;
      _finalResult = GameResult.draw;
      _winnerUserId = null;
      _stopAllTimers();
      return;
    }

    if (engine.insufficient_material) {
      _isGameOver = true;
      _endReason = EndReason.insufficientMaterial;
      _finalResult = GameResult.draw;
      _winnerUserId = null;
      _stopAllTimers();
      return;
    }

    if (engine.in_threefold_repetition) {
      _isGameOver = true;
      _endReason = EndReason.drawAgreed;
      _finalResult = GameResult.draw;
      _winnerUserId = null;
      _stopAllTimers();
      return;
    }

    if (engine.in_draw) {
      _isGameOver = true;
      _endReason = EndReason.drawAgreed;
      _finalResult = GameResult.draw;
      _winnerUserId = null;
      _stopAllTimers();
    }
  }

  // =========================================================
  // CHESS CLOCK & TURN TIMER
  // =========================================================

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

    if (match.turnTimerSeconds > 0) {
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
    _winnerUserId = (timedOutUserId == _match?.player1Id)
        ? _match?.player2Id
        : _match?.player1Id;
    _finalResult = (timedOutUserId == _match?.player1Id)
        ? GameResult.player2Win
        : GameResult.player1Win;
    notifyListeners();
    _notifyGameOver();
  }

  void _handleTurnTimeout() {
    _stopAllTimers();

    final timedOutUserId = _currentTurnUserId;
    _isGameOver = true;
    _endReason = EndReason.turnTimeout;
    _winnerUserId = (timedOutUserId == _match?.player1Id)
        ? _match?.player2Id
        : _match?.player1Id;
    _finalResult = (timedOutUserId == _match?.player1Id)
        ? GameResult.player2Win
        : GameResult.player1Win;

    notifyListeners();
    unawaited(_notifyGameOver());
  }

  void _resetTurnTimer() {
    _turnTimer?.cancel();
    final match = _match;
    if (match == null || match.turnTimerSeconds == 0) return;
    _turnTimerSeconds = match.turnTimerSeconds;
    _startActiveTimer();
  }

  int get _myRemainingMs => _currentUserId == _match?.player1Id
      ? _player1RemainingMs
      : _player2RemainingMs;

  // =========================================================
  // RESIGN
  // =========================================================

  Future<void> resign() async {
    if (!isPlayer || _isGameOver) return;
    _stopAllTimers();
    _isGameOver = true;
    _endReason = EndReason.resign;
    _winnerUserId = (_currentUserId == _match?.player1Id)
        ? _match?.player2Id
        : _match?.player1Id;
    _finalResult = (_currentUserId == _match?.player1Id)
        ? GameResult.player2Win
        : GameResult.player1Win;
    notifyListeners();
    await _notifyGameOver();
  }

  // =========================================================
  // DRAW
  // =========================================================

  Future<void> requestDraw() async {
    if (!isPlayer || _isGameOver) return;

    if (_pendingDrawRequest != null &&
        !_pendingDrawRequest!.isAnswered &&
        _pendingDrawRequest!.requesterId == _currentUserId) {
      return;
    }

    _pendingDrawRequest = DrawRequest(
      requesterId: _currentUserId,
      sentAt: DateTime.now(),
    );
    notifyListeners();

    try {
      await _firebase.updateDrawRequest(
        matchId: _match!.matchId,
        requesterId: _currentUserId,
      );
    } catch (e) {
      debugPrint('[GameStateProvider] requestDraw error: $e');
    }
  }

  Future<void> acceptDraw() async {
    if (!hasIncomingDrawRequest || _isGameOver) return;
    _pendingDrawRequest?.isAnswered = true;
    _handleDraw(EndReason.drawAgreed);
    notifyListeners();

    try {
      await _firebase.clearDrawRequest(_match!.matchId);
    } catch (_) {}

    await _notifyGameOver();
  }

  Future<void> declineDraw() async {
    if (!hasIncomingDrawRequest) return;
    _pendingDrawRequest?.isAnswered = true;
    notifyListeners();

    try {
      await _firebase.clearDrawRequest(_match!.matchId);
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

  // =========================================================
  // DISCONNECT
  // =========================================================

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
    _winnerUserId = (loserUserId == _match?.player1Id)
        ? _match?.player2Id
        : _match?.player1Id;
    _finalResult = (loserUserId == _match?.player1Id)
        ? GameResult.player2Win
        : GameResult.player1Win;
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

  // =========================================================
  // GAME OVER → FIREBASE
  // =========================================================

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

  // =========================================================
  // TURN & MOVE
  // =========================================================

  void _advanceTurn() {
    _nextMoveIndex++;
    _currentTurnUserId = _computeCurrentTurn(_match!);
    _resetTurnTimer();
  }

  void _applyMoveToBoard(GameMove move) {
    final match = _match;
    if (match == null) return;

    if (match.gameType == GameType.chess) {
      if (move.movedBy != _currentUserId) {
        _applyChessMoveFromOpponent(move);
      }
      return;
    }

    final data = move.moveData;
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
        _finalResult = (move.movedBy == match.player1Id)
            ? GameResult.player1Win
            : GameResult.player2Win;
        _endReason = (match.boardSize == 3)
            ? EndReason.threeInRow
            : EndReason.fiveInRow;
        _stopAllTimers();
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
    if (_match?.gameType == GameType.chess) {
      _rebuildChessFromHistory(moves);
      return;
    }

    _caroBoard.clear();
    _lastMove = null;
    _winLine = [];

    for (final move in moves) {
      final data = move.moveData;
      final row = data['row'] as int?;
      final col = data['col'] as int?;
      final symbol = data['symbol'] as String?;
      if (row != null && col != null && symbol != null) {
        _caroBoard['$row,$col'] = symbol;
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

  // =========================================================
  // REPLAY
  // =========================================================

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

      if (_match?.gameType == GameType.chess) {
        _lastChessMoveUci = '';
        final initialFen = _match?.initialFen;
        if (initialFen != null && initialFen.isNotEmpty) {
          try {
            _chessEngine = ch.Chess.fromFEN(initialFen);
            _chessFen = initialFen;
          } catch (_) {
            _chessEngine = ch.Chess();
            _chessFen = ch.Chess.DEFAULT_POSITION;
          }
        } else {
          _chessEngine = ch.Chess();
          _chessFen = ch.Chess.DEFAULT_POSITION;
        }
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Không thể tải lịch sử: $e';
      notifyListeners();
    }
  }

  void stopReplay() {
    _isReplayMode = false;
    _replayIndex = -1;
    _replayTimer?.cancel();
    if (_match?.gameType == GameType.chess) {
      _rebuildChessFromHistory(_replayMoves);
    } else {
      _rebuildBoardFromHistory(_replayMoves);
    }
    notifyListeners();
  }

  void jumpToReplayIndex(int index) {
    final clamped = index.clamp(-1, _replayMoves.length - 1);
    _replayIndex = clamped;
    _applyReplayState(clamped);
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
    _replayTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      if (canReplayForward) {
        replayForward();
      } else {
        _replayTimer?.cancel();
      }
    });
  }

  void replayPause() => _replayTimer?.cancel();

  void _applyReplayState(int index) {
    if (_match?.gameType == GameType.chess) {
      _chessEngine = ch.Chess();
      _chessFen = ch.Chess.DEFAULT_POSITION;
      if (_match?.initialFen != null && _match!.initialFen!.isNotEmpty) {
        try {
          _chessEngine = ch.Chess.fromFEN(_match!.initialFen!);
          _chessFen = _match!.initialFen!;
        } catch (_) {}
      }
    } else {
      _caroBoard.clear();
      _lastMove = null;
      _winLine = [];
    }

    String replayLastUci = '';

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
      } else if (_match?.gameType == GameType.chess) {
        final uci = data['uci'] as String?;
        final fen = data['fen'] as String?;

        if (fen != null && fen.isNotEmpty) {
          try {
            _chessEngine = ch.Chess.fromFEN(fen);
          } catch (_) {
            if (uci != null && uci.length >= 4) {
              _executeChessUci(_chessEngine!, uci);
            }
          }
        } else if (uci != null && uci.length >= 4) {
          _executeChessUci(_chessEngine!, uci);
        }

        if (uci != null && uci.isNotEmpty) {
          replayLastUci = uci;
        }
      }
    }

    if (_match?.gameType == GameType.chess) {
      _chessFen = _chessEngine?.fen ?? ch.Chess.DEFAULT_POSITION;
      _lastChessMoveUci = index >= 0 ? replayLastUci : '';
    } else if (_replayIndex >= 0 && _replayIndex < _replayMoves.length) {
      final move = _replayMoves[_replayIndex];
      final data = move.moveData;
      final row = data['row'] as int?;
      final col = data['col'] as int?;
      final symbol = data['symbol'] as String?;
      if (row != null && col != null && symbol != null) {
        final winCells = _checkCaroWin(row, col, symbol);
        if (winCells != null) _winLine = winCells;
      }
    }

    notifyListeners();
  }

  // =========================================================
  // SPECTATOR
  // =========================================================

  Future<void> leaveAsSpectator() async {
    if (_match == null || !isSpectator) return;
    await _firebase.leaveAsSpectator(_match!.matchId, _currentUserId);
  }

  // =========================================================
  // STATIC HELPERS
  // =========================================================

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
      resolvedSide = math.Random().nextBool()
          ? ChessSide.white
          : ChessSide.black;
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

  // =========================================================
  // TIMERS & DISPOSE
  // =========================================================

  void _stopAllTimers() {
    _chessClockTimer?.cancel();
    _turnTimer?.cancel();
    _disconnectTimer?.cancel();
    _replayTimer?.cancel();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopAllTimers();
    _matchSub?.cancel();
    _moveSub?.cancel();
    _disconnectSub?.cancel();
    _drawSub?.cancel();
    if (isSpectator && _match != null) {
      _firebase.leaveAsSpectator(_match!.matchId, _currentUserId);
    }
    super.dispose();
  }
}
