import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_chat_demo/models/game_match.dart';
import 'package:flutter_chat_demo/models/message_chat.dart';
import 'package:flutter_chat_demo/services/game_firebase_service.dart';
import 'package:uuid/uuid.dart';

// =========================================================
// ENUMS & SUPPORTING TYPES
// =========================================================

/// Vai trò của user hiện tại trong phòng đấu.
enum PlayerRole {
  player1, // Người tạo thách đấu
  player2, // Người chấp nhận
  spectator, // Khán giả
}

/// Lý do kết thúc trận.
enum EndReason {
  fiveInRow, // Caro: 5 quân liên tiếp
  checkmate, // Chess: chiếu bí
  timeout, // Hết giờ cờ vua
  turnTimeout, // Hết giờ mỗi nước Caro
  resign, // Đầu hàng
  drawAgreed, // Xin hòa được chấp nhận
  disconnect, // Mất kết nối > 60s
  stalemate, // Chess: hết nước đi (hòa)
  insufficientMaterial, // Chess: thiếu quân (hòa)
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

/// Yêu cầu xin hòa.
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

/// Snapshot trạng thái một ô trong bàn Caro (dùng cho UI và logic).
class CaroCell {
  final int row;
  final int col;

  /// '' = trống, 'X' = player1, 'O' = player2
  final String symbol;

  const CaroCell(this.row, this.col, this.symbol);
}

// =========================================================
// GAME STATE PROVIDER
// =========================================================

/// State controller trung tâm cho một trận đấu đang diễn ra.
///
/// Quản lý:
///   • Bàn cờ Caro (ma trận symbol) + thuật toán 5 liên tiếp
///   • Đồng hồ Chess (player1Clock / player2Clock)
///   • Turn Timer Caro (đếm ngược mỗi nước đi)
///   • Xin hòa / Đầu hàng
///   • Disconnect handling (60s timeout → xử thua)
///   • Replay (load moveHistory, bước từng nước)
///   • Spectator (role detection, join/leave)
///
/// KHÔNG chứa: Firebase I/O (→ GameFirebaseService), UI widget (→ match_room_page)
class GameStateProvider extends ChangeNotifier {
  // ── Dependencies ──────────────────────────────────────────────────────────
  final GameFirebaseService _firebase = GameFirebaseService();
  final _uuid = const Uuid();

  // ── Match Info ────────────────────────────────────────────────────────────
  GameMatch? _match;
  String _currentUserId = '';
  PlayerRole _role = PlayerRole.spectator;

  // ── Subscriptions ─────────────────────────────────────────────────────────
  StreamSubscription<GameMatch?>? _matchSub;
  StreamSubscription<GameMove?>? _moveSub;
  StreamSubscription<Map<String, dynamic>?>? _disconnectSub;

  // ── Caro Board State ──────────────────────────────────────────────────────
  /// Map<'row,col', symbol>  — sparse map, chỉ lưu ô đã đánh.
  final Map<String, String> _caroBoard = {};

  /// Ô vừa đánh (để highlight trên UI).
  CaroCell? _lastMove;

  /// Danh sách 5 ô tạo thành đường thắng (để vẽ line).
  List<CaroCell> _winLine = [];

  // ── Turn Tracking ─────────────────────────────────────────────────────────
  /// userId của người được đi nước.
  String _currentTurnUserId = '';

  /// Index nước đi tiếp theo (bắt đầu từ 0).
  int _nextMoveIndex = 0;

  // ── Chess Clock ───────────────────────────────────────────────────────────
  /// Thời gian còn lại của player1 (ms).
  int _player1RemainingMs = 0;

  /// Thời gian còn lại của player2 (ms).
  int _player2RemainingMs = 0;

  Timer? _chessClockTimer;

  // ── Turn Timer (Caro) ─────────────────────────────────────────────────────
  /// Thời gian còn lại của nước đi hiện tại (giây).
  int _turnTimerSeconds = 0;

  Timer? _turnTimer;

  // ── Draw / Resign State ───────────────────────────────────────────────────
  DrawRequest? _pendingDrawRequest;

  // ── Disconnect Handling ───────────────────────────────────────────────────
  Timer? _disconnectTimer;

  /// userId của player đang bị disconnect.
  String? _disconnectedPlayerId;

  /// Số giây countdown trước khi xử thua.
  int _disconnectCountdown = 60;

  // ── Match State ───────────────────────────────────────────────────────────
  bool _isGameOver = false;
  GameResult? _finalResult;
  EndReason? _endReason;
  String? _winnerUserId;

  // ── Replay State ──────────────────────────────────────────────────────────
  bool _isReplayMode = false;
  List<GameMove> _replayMoves = [];
  int _replayIndex = -1; // -1 = belum mulai, 0..n = nước đang xem
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

  // Caro
  Map<String, String> get caroBoard => Map.unmodifiable(_caroBoard);
  CaroCell? get lastMove => _lastMove;
  List<CaroCell> get winLine => List.unmodifiable(_winLine);
  String getCaroCell(int row, int col) => _caroBoard['$row,$col'] ?? '';

  // Clocks
  int get player1RemainingMs => _player1RemainingMs;
  int get player2RemainingMs => _player2RemainingMs;
  int get turnTimerSeconds => _turnTimerSeconds;
  bool get isPlayer1Turn => _currentTurnUserId == _match?.player1Id;

  // Draw / Resign
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
  bool get canReplayBack => _replayIndex > 0;
  bool get canReplayForward => _replayIndex < _replayMoves.length - 1;

  // Loading
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  // =========================================================
  // INITIALIZATION
  // =========================================================

  /// Khởi tạo provider với một trận đấu cụ thể.
  /// Gọi từ match_room_page sau khi navigation.
  Future<void> initialize({
    required String matchId,
    required String currentUserId,
  }) async {
    _currentUserId = currentUserId;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Load match document
      final match = await _firebase.fetchMatch(matchId);
      if (match == null) {
        _errorMessage = 'Không tìm thấy trận đấu';
        _isLoading = false;
        notifyListeners();
        return;
      }

      _applyMatchData(match);

      // Determine role
      _role = _detectRole(match, currentUserId);

      // Spectator: join spectator list
      if (_role == PlayerRole.spectator) {
        await _firebase.joinAsSpectator(matchId, currentUserId);
      }

      // Init clocks
      _initClocks(match);

      // Subscribe realtime
      _subscribeMatch(matchId);
      _subscribeLatestMove(matchId);
      _subscribeDisconnect(matchId);

      // If playing, start appropriate timer
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

  // ── Apply match data ──────────────────────────────────────────────────────

  void _applyMatchData(GameMatch match) {
    _match = match;
    if (match.moveHistory.isNotEmpty) {
      // Rebuild board từ move history nếu có
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
    // Caro & Chess: luân phiên player1 → player2 → player1...
    return _nextMoveIndex.isEven
        ? match.player1Id
        : (match.player2Id ?? match.player1Id);
  }

  // ── Clocks initialization ─────────────────────────────────────────────────

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

  // ── Subscriptions ─────────────────────────────────────────────────────────

  void _subscribeMatch(String matchId) {
    _matchSub?.cancel();
    _matchSub = _firebase.watchMatch(matchId).listen((match) {
      if (match == null) return;
      final wasPlaying = _match?.isPlaying ?? false;
      _match = match;

      // Detect spectator count change
      notifyListeners();

      // Detect game over from Firestore (e.g., server-side trigger)
      if (match.isFinished && !_isGameOver) {
        _handleGameOverFromFirestore(match);
      }
    });
  }

  void _subscribeLatestMove(String matchId) {
    _moveSub?.cancel();
    _moveSub = _firebase.watchLatestMove(matchId).listen((move) {
      if (move == null) return;
      // Chỉ apply nước đi của đối thủ (nước của mình đã apply local)
      if (move.movedBy != _currentUserId && move.moveIndex >= _nextMoveIndex) {
        _applyMoveToBoard(move);
      }
    });
  }

  void _subscribeDisconnect(String matchId) {
    _disconnectSub?.cancel();
    _disconnectSub = _firebase.watchDisconnectStatus(matchId).listen((info) {
      if (info == null) {
        // Reconnected
        _cancelDisconnectTimer();
      } else {
        final userId = info['userId'] as String?;
        if (userId != null && userId != _currentUserId) {
          _startDisconnectCountdown(userId);
        }
      }
    });
  }

  // =========================================================
  // CARO LOGIC
  // =========================================================

  /// Người chơi đánh vào ô (row, col).
  /// Trả về true nếu nước đi hợp lệ và được xử lý.
  Future<bool> playCaroMove(int row, int col) async {
    if (!isMyTurn) return false;
    if (_match == null || _isGameOver) return false;
    if (getCaroCell(row, col).isNotEmpty) return false; // Ô đã có quân

    final symbol = _myCaroSymbol;
    final key = '$row,$col';

    // 1. Apply local ngay để UI phản hồi tức thì
    _caroBoard[key] = symbol;
    _lastMove = CaroCell(row, col, symbol);

    // Đổi lượt
    _advanceTurn();

    // 2. Kiểm tra thắng
    final winCells = _checkCaroWin(row, col, symbol);
    if (winCells != null) {
      _winLine = winCells;
      _handleCaroWin();
    } else if (_checkCaroDraw()) {
      _handleDraw(EndReason.drawAgreed); // Hết bàn = hòa
    }

    notifyListeners();

    // 3. Ghi lên Firebase
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

    // 4. Nếu game over, thông báo Firebase
    if (_isGameOver) {
      await _notifyGameOver();
    } else {
      _startActiveTimer();
    }

    return true;
  }

  // ── Caro: Symbol assignment ───────────────────────────────────────────────

  String get _myCaroSymbol {
    if (_match == null) return 'X';
    return _currentUserId == _match!.player1Id ? 'X' : 'O';
  }

  // ── Caro: Win detection (5 liên tiếp) ────────────────────────────────────

  /// Kiểm tra 5 quân liên tiếp sau nước đi tại (row, col).
  /// Trả về danh sách 5 CaroCell tạo thành đường thắng, hoặc null nếu chưa thắng.
  List<CaroCell>? _checkCaroWin(int row, int col, String symbol) {
    // 4 hướng: ngang, dọc, chéo /, chéo \
    const directions = [
      [0, 1], // →
      [1, 0], // ↓
      [1, 1], // ↘
      [1, -1], // ↙
    ];

    for (final dir in directions) {
      final dr = dir[0];
      final dc = dir[1];
      final line = <CaroCell>[];

      // Đếm về phía âm
      for (int i = 4; i >= 1; i--) {
        final r = row - dr * i;
        final c = col - dc * i;
        if (_caroBoard['$r,$c'] == symbol) {
          line.add(CaroCell(r, c, symbol));
        } else {
          line.clear();
        }
      }

      // Thêm ô hiện tại
      line.add(CaroCell(row, col, symbol));

      // Đếm về phía dương
      for (int i = 1; i <= 4; i++) {
        final r = row + dr * i;
        final c = col + dc * i;
        if (_caroBoard['$r,$c'] == symbol) {
          line.add(CaroCell(r, c, symbol));
          if (line.length >= 5) {
            // Kiểm tra "overline" rule nếu cần — hiện tại bỏ qua (cho phép > 5)
            return line.take(5).toList();
          }
        } else {
          break;
        }
      }

      // Kiểm tra tổng đủ 5 chưa
      if (line.length >= 5) {
        return line.take(5).toList();
      }
    }

    return null;
  }

  /// Kiểm tra hòa cho bàn 3x3 (Tic-tac-toe): tất cả ô đã có quân.
  bool _checkCaroDraw() {
    final boardSize = _match?.boardSize ?? 0;
    if (boardSize == 0) return false; // Bàn vô hạn không bao giờ hòa kiểu này
    // 3x3
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

  /// Thuật toán thắng Tic-tac-toe 3x3 (cũng dùng cho legacy TicTacToeMessageWidget).
  /// Trả về symbol người thắng hoặc '' nếu chưa có.
  static String checkTicTacToeWinner(List<String> board) {
    const lines = [
      [0, 1, 2], [3, 4, 5], [6, 7, 8], // hàng ngang
      [0, 3, 6], [1, 4, 7], [2, 5, 8], // hàng dọc
      [0, 4, 8], [2, 4, 6], // đường chéo
    ];
    for (final l in lines) {
      if (board[l[0]].isNotEmpty &&
          board[l[0]] == board[l[1]] &&
          board[l[1]] == board[l[2]]) {
        return board[l[0]];
      }
    }
    return '';
  }

  // ── Caro: Handle win/lose ─────────────────────────────────────────────────

  void _handleCaroWin() {
    _isGameOver = true;
    _winnerUserId = _currentUserId; // Người vừa đánh là người thắng
    _finalResult = (_currentUserId == _match!.player1Id)
        ? GameResult.player1Win
        : GameResult.player2Win;
    _endReason = EndReason.fiveInRow;
    _stopAllTimers();
  }

  // =========================================================
  // CHESS CLOCK
  // =========================================================

  void _startActiveTimer() {
    _chessClockTimer?.cancel();
    _turnTimer?.cancel();

    final match = _match;
    if (match == null || _isGameOver) return;

    // Chess clock (nếu có time control)
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

    // Turn timer Caro
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
    _turnTimer?.cancel();
    if (!isMyTurn) return; // Chỉ xử lý nếu đang là lượt mình
    _isGameOver = true;
    _endReason = EndReason.turnTimeout;
    _winnerUserId = (_currentUserId == _match?.player1Id)
        ? _match?.player2Id
        : _match?.player1Id;
    _finalResult = (_currentUserId == _match?.player1Id)
        ? GameResult.player2Win
        : GameResult.player1Win;
    notifyListeners();
    _notifyGameOver();
  }

  // ── Reset turn timer sau mỗi nước đi ─────────────────────────────────────

  void _resetTurnTimer() {
    _turnTimer?.cancel();
    final match = _match;
    if (match == null || match.turnTimerSeconds == 0) return;
    _turnTimerSeconds = match.turnTimerSeconds;
    _startActiveTimer();
  }

  // ── Remaining time helper ─────────────────────────────────────────────────

  int get _myRemainingMs {
    if (_currentUserId == _match?.player1Id) return _player1RemainingMs;
    return _player2RemainingMs;
  }

  // =========================================================
  // RESIGN (ĐẦU HÀNG)
  // =========================================================

  /// Người chơi đầu hàng — kết thúc trận ngay lập tức.
  Future<void> resign() async {
    if (!isPlayer || _isGameOver) return;

    _isGameOver = true;
    _endReason = EndReason.resign;
    _winnerUserId = (_currentUserId == _match?.player1Id)
        ? _match?.player2Id
        : _match?.player1Id;
    _finalResult = (_currentUserId == _match?.player1Id)
        ? GameResult.player2Win
        : GameResult.player1Win;
    _stopAllTimers();
    notifyListeners();

    await _notifyGameOver();
  }

  // =========================================================
  // DRAW REQUEST (XIN HÒA)
  // =========================================================

  /// Gửi đề nghị hòa.
  Future<void> requestDraw() async {
    if (!isPlayer || _isGameOver) return;
    if (_pendingDrawRequest != null && !_pendingDrawRequest!.isAnswered) return;

    _pendingDrawRequest = DrawRequest(
      requesterId: _currentUserId,
      sentAt: DateTime.now(),
    );
    notifyListeners();

    // Lưu vào Firebase để đối thủ nhận được
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

  /// Chấp nhận đề nghị hòa.
  Future<void> acceptDraw() async {
    if (!hasIncomingDrawRequest || _isGameOver) return;

    _pendingDrawRequest?.isAnswered = true;
    _handleDraw(EndReason.drawAgreed);
    notifyListeners();
    await _notifyGameOver();
  }

  /// Từ chối đề nghị hòa.
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

  // =========================================================
  // DISCONNECT HANDLING (60s timeout → xử thua)
  // =========================================================

  /// Gọi từ match_room_page khi detect mình bị mất kết nối.
  Future<void> onDisconnected() async {
    if (_match == null || _isGameOver) return;
    await _firebase.markPlayerDisconnected(_match!.matchId, _currentUserId);
  }

  /// Gọi từ match_room_page khi kết nối lại.
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
        // Xử thua người bị disconnect
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
  // GAME OVER → NOTIFY FIREBASE
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
  // TURN & MOVE HELPERS
  // =========================================================

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

        // Kiểm tra thắng từ nước đi của đối thủ
        final winCells = _checkCaroWin(row, col, symbol);
        if (winCells != null) {
          _winLine = winCells;
          _isGameOver = true;
          _winnerUserId = move.movedBy;
          _finalResult = (move.movedBy == match.player1Id)
              ? GameResult.player1Win
              : GameResult.player2Win;
          _endReason = EndReason.fiveInRow;
          _stopAllTimers();
        }
      }
    }

    // Cập nhật đồng hồ từ move
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

  // =========================================================
  // REPLAY MODE
  // =========================================================

  /// Bật chế độ Replay — load toàn bộ lịch sử nước đi.
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

  /// Thoát Replay — quay lại board state hiện tại.
  void stopReplay() {
    _isReplayMode = false;
    _replayIndex = -1;
    _replayTimer?.cancel();
    // Rebuild board từ toàn bộ moves
    _rebuildBoardFromHistory(_replayMoves);
    notifyListeners();
  }

  /// Tua tới 1 nước.
  void replayForward() {
    if (!canReplayForward) return;
    _replayIndex++;
    _applyReplayState(_replayIndex);
  }

  /// Tua lùi 1 nước.
  void replayBack() {
    if (!canReplayBack) return;
    _replayIndex--;
    _applyReplayState(_replayIndex);
  }

  /// Phát tự động toàn bộ replay.
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

  /// Tạm dừng auto-play.
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

    // Kiểm tra nếu trạng thái hiện tại là winning move
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

  // =========================================================
  // TIMER UTILITIES
  // =========================================================

  void _stopAllTimers() {
    _chessClockTimer?.cancel();
    _turnTimer?.cancel();
    _disconnectTimer?.cancel();
    _replayTimer?.cancel();
  }

  // =========================================================
  // SPECTATOR: JOIN / LEAVE
  // =========================================================

  /// Gọi khi spectator rời phòng.
  Future<void> leaveAsSpectator() async {
    if (_match == null || !isSpectator) return;
    await _firebase.leaveAsSpectator(_match!.matchId, _currentUserId);
  }

  // =========================================================
  // MATCH CREATION HELPER
  // =========================================================

  /// Tạo GameMatch mới từ các tham số cài đặt trận.
  /// Dùng trong game_setup_page trước khi gọi GameFirebaseService.createMatch().
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
    // Resolve random side
    ChessSide resolvedSide = player1Side;
    if (player1Side == ChessSide.random) {
      resolvedSide =
          math.Random().nextBool() ? ChessSide.white : ChessSide.black;
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

  // =========================================================
  // CLOCK DISPLAY HELPER
  // =========================================================

  /// Format milliseconds → "MM:SS" hoặc "M:SS.t" nếu < 10s.
  static String formatClock(int ms) {
    if (ms <= 0) return '0:00';
    final totalSeconds = (ms / 1000).ceil();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// Format milliseconds với tenths (cho hiển thị khi < 10 giây).
  static String formatClockPrecise(int ms) {
    if (ms <= 0) return '0:00.0';
    if (ms >= 10000) return formatClock(ms);
    final seconds = ms ~/ 1000;
    final tenths = (ms % 1000) ~/ 100;
    return '0:0$seconds.$tenths';
  }

  // =========================================================
  // DISPOSE
  // =========================================================

  @override
  void dispose() {
    _stopAllTimers();
    _matchSub?.cancel();
    _moveSub?.cancel();
    _disconnectSub?.cancel();
    // Spectator leave khi rời trang
    if (isSpectator && _match != null) {
      _firebase.leaveAsSpectator(_match!.matchId, _currentUserId);
    }
    super.dispose();
  }
}
