import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/message_chat.dart';

enum GameMatchStatus {
  waiting,
  playing,
  finished,
  aborted;

  static GameMatchStatus fromString(String value) {
    switch (value.toLowerCase()) {
      case 'playing':
        return GameMatchStatus.playing;
      case 'finished':
        return GameMatchStatus.finished;
      case 'aborted':
        return GameMatchStatus.aborted;
      case 'waiting':
      default:
        return GameMatchStatus.waiting;
    }
  }

  String get name {
    switch (this) {
      case GameMatchStatus.waiting:
        return 'waiting';
      case GameMatchStatus.playing:
        return 'playing';
      case GameMatchStatus.finished:
        return 'finished';
      case GameMatchStatus.aborted:
        return 'aborted';
    }
  }
}

enum GameResult {
  player1Win,
  player2Win,
  draw;

  static GameResult? fromString(String? value) {
    switch (value) {
      case 'player1_win':
        return GameResult.player1Win;
      case 'player2_win':
        return GameResult.player2Win;
      case 'draw':
        return GameResult.draw;
      default:
        return null;
    }
  }

  String get value {
    switch (this) {
      case GameResult.player1Win:
        return 'player1_win';
      case GameResult.player2Win:
        return 'player2_win';
      case GameResult.draw:
        return 'draw';
    }
  }
}

enum ChessSide {
  white,
  black,
  random;

  static ChessSide fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'white':
        return ChessSide.white;
      case 'black':
        return ChessSide.black;
      case 'random':
      default:
        return ChessSide.random;
    }
  }

  String get name {
    switch (this) {
      case ChessSide.white:
        return 'white';
      case ChessSide.black:
        return 'black';
      case ChessSide.random:
        return 'random';
    }
  }
}

class GameMove {
  final int moveIndex;
  final String movedBy;
  final Map<String, dynamic> moveData;
  final String movedAt;
  final int remainingTimeMs;

  const GameMove({
    required this.moveIndex,
    required this.movedBy,
    required this.moveData,
    required this.movedAt,
    this.remainingTimeMs = 0,
  });

  Map<String, dynamic> toJson() => {
    FirestoreConstants.moveIndex: moveIndex,
    FirestoreConstants.movedBy: movedBy,
    FirestoreConstants.moveData: moveData,
    FirestoreConstants.movedAt: movedAt,
    FirestoreConstants.remainingTimeMs: remainingTimeMs,
  };

  factory GameMove.fromJson(Map<String, dynamic> json) => GameMove(
    moveIndex: json[FirestoreConstants.moveIndex] as int? ?? 0,
    movedBy: json[FirestoreConstants.movedBy] as String? ?? '',
    moveData: Map<String, dynamic>.from(
      json[FirestoreConstants.moveData] as Map? ?? {},
    ),
    movedAt: _parseTs(json[FirestoreConstants.movedAt]),
    remainingTimeMs: json[FirestoreConstants.remainingTimeMs] as int? ?? 0,
  );

  factory GameMove.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return GameMove.fromJson(data);
  }

  static String _parseTs(dynamic v) {
    if (v is String) return v;
    if (v is int) return v.toString();
    if (v is Timestamp) return v.millisecondsSinceEpoch.toString();
    return DateTime.now().millisecondsSinceEpoch.toString();
  }
}

class GameMatch {
  final String matchId;
  final GameType gameType;
  final GameMatchStatus status;

  final String player1Id;
  final String player1Name;
  final String player1Avatar;

  final String? player2Id;
  final String? player2Name;
  final String? player2Avatar;

  // FIX BUG 3: Bổ sung thông tin người được mời đích danh để xác định chính xác Player2
  final String? targetUserId;
  final String? targetUserName;

  final ChessSide player1Side;
  final int timeControlSeconds;
  final int turnTimerSeconds;
  final int boardSize;

  /// FEN ban đầu của bàn cờ vua (nếu không có thì dùng FEN chuẩn).
  final String? initialFen;

  final GameResult? result;
  final String? endReason;

  final String sourceGroupId;
  final String? inviteMessageId;
  final List<String> spectatorIds;
  final List<GameMove> moveHistory;

  final String createdAt;
  final String? startedAt;
  final String? endedAt;

  const GameMatch({
    required this.matchId,
    required this.gameType,
    required this.status,
    required this.player1Id,
    required this.player1Name,
    required this.player1Avatar,
    this.player2Id,
    this.player2Name,
    this.player2Avatar,
    this.targetUserId,
    this.targetUserName,
    this.player1Side = ChessSide.random,
    this.timeControlSeconds = 0,
    this.turnTimerSeconds = 0,
    this.boardSize = 0,
    this.initialFen,
    this.result,
    this.endReason,
    required this.sourceGroupId,
    this.inviteMessageId,
    this.spectatorIds = const [],
    this.moveHistory = const [],
    required this.createdAt,
    this.startedAt,
    this.endedAt,
  });

  bool get isWaiting => status == GameMatchStatus.waiting;
  bool get isPlaying => status == GameMatchStatus.playing;
  bool get isFinished => status == GameMatchStatus.finished;
  bool get isAborted => status == GameMatchStatus.aborted;

  bool get hasOpponent => player2Id != null && player2Id!.isNotEmpty;
  int get spectatorCount => spectatorIds.length;
  int get totalMoves => moveHistory.length;

  String? get winnerId {
    if (result == GameResult.player1Win) return player1Id;
    if (result == GameResult.player2Win) return player2Id;
    return null;
  }

  String get matchTitle => '$player1Name vs ${player2Name ?? "???"}';

  int? get durationSeconds {
    if (startedAt == null || endedAt == null) return null;
    final start = int.tryParse(startedAt!) ?? 0;
    final end = int.tryParse(endedAt!) ?? 0;
    if (start == 0 || end == 0) return null;
    return ((end - start) / 1000).round();
  }

  Map<String, dynamic> toJson() => {
    FirestoreConstants.matchId: matchId,
    FirestoreConstants.gameType: gameType.name,
    FirestoreConstants.gameStatus: status.name,
    FirestoreConstants.player1Id: player1Id,
    FirestoreConstants.player1Name: player1Name,
    FirestoreConstants.player1Avatar: player1Avatar,
    if (player2Id != null) FirestoreConstants.player2Id: player2Id,
    if (player2Name != null) FirestoreConstants.player2Name: player2Name,
    if (player2Avatar != null) FirestoreConstants.player2Avatar: player2Avatar,

    // FIX BUG 3: Lưu trữ dữ liệu target user
    if (targetUserId != null) 'targetUserId': targetUserId,
    if (targetUserName != null) 'targetUserName': targetUserName,

    FirestoreConstants.player1Side: player1Side.name,
    FirestoreConstants.timeControlSeconds: timeControlSeconds,
    FirestoreConstants.turnTimerSeconds: turnTimerSeconds,
    FirestoreConstants.boardSize: boardSize,
    if (initialFen != null) FirestoreConstants.initialFen: initialFen,
    if (result != null) FirestoreConstants.gameResult: result!.value,
    if (endReason != null) FirestoreConstants.gameEndReason: endReason,
    FirestoreConstants.sourceGroupId: sourceGroupId,
    if (inviteMessageId != null)
      FirestoreConstants.inviteMessageId: inviteMessageId,
    FirestoreConstants.spectatorIds: spectatorIds,
    FirestoreConstants.createdAt: createdAt,
    if (startedAt != null) FirestoreConstants.startedAt: startedAt,
    if (endedAt != null) FirestoreConstants.endedAt: endedAt,
  };

  factory GameMatch.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return GameMatch.fromJson(data);
  }

  factory GameMatch.fromJson(Map<String, dynamic> data) => GameMatch(
    matchId: data[FirestoreConstants.matchId] as String? ?? '',
    gameType: GameType.fromString(
      data[FirestoreConstants.gameType] as String? ?? 'caro',
    ),
    status: GameMatchStatus.fromString(
      data[FirestoreConstants.gameStatus] as String? ?? 'waiting',
    ),
    player1Id: data[FirestoreConstants.player1Id] as String? ?? '',
    player1Name: data[FirestoreConstants.player1Name] as String? ?? '',
    player1Avatar: data[FirestoreConstants.player1Avatar] as String? ?? '',
    player2Id: data[FirestoreConstants.player2Id] as String?,
    player2Name: data[FirestoreConstants.player2Name] as String?,
    player2Avatar: data[FirestoreConstants.player2Avatar] as String?,

    // FIX BUG 3: Đọc dữ liệu target user từ Firestore
    targetUserId: data['targetUserId'] as String?,
    targetUserName: data['targetUserName'] as String?,

    player1Side: ChessSide.fromString(
      data[FirestoreConstants.player1Side] as String?,
    ),
    timeControlSeconds:
        data[FirestoreConstants.timeControlSeconds] as int? ?? 0,
    turnTimerSeconds: data[FirestoreConstants.turnTimerSeconds] as int? ?? 0,
    boardSize: data[FirestoreConstants.boardSize] as int? ?? 0,
    initialFen: data[FirestoreConstants.initialFen] as String?,
    result: GameResult.fromString(
      data[FirestoreConstants.gameResult] as String?,
    ),
    endReason: data[FirestoreConstants.gameEndReason] as String?,
    sourceGroupId: data[FirestoreConstants.sourceGroupId] as String? ?? '',
    inviteMessageId: data[FirestoreConstants.inviteMessageId] as String?,
    spectatorIds: List<String>.from(
      data[FirestoreConstants.spectatorIds] as List? ?? [],
    ),
    moveHistory: const [],
    createdAt: _parseTs(data[FirestoreConstants.createdAt]),
    startedAt: _parseTsNullable(data[FirestoreConstants.startedAt]),
    endedAt: _parseTsNullable(data[FirestoreConstants.endedAt]),
  );

  GameMatch copyWith({
    GameMatchStatus? status,
    String? player2Id,
    String? player2Name,
    String? player2Avatar,
    String? targetUserId,
    String? targetUserName,
    ChessSide? player1Side,
    String? initialFen,
    GameResult? result,
    String? endReason,
    String? inviteMessageId,
    List<String>? spectatorIds,
    List<GameMove>? moveHistory,
    String? startedAt,
    String? endedAt,
  }) => GameMatch(
    matchId: matchId,
    gameType: gameType,
    status: status ?? this.status,
    player1Id: player1Id,
    player1Name: player1Name,
    player1Avatar: player1Avatar,
    player2Id: player2Id ?? this.player2Id,
    player2Name: player2Name ?? this.player2Name,
    player2Avatar: player2Avatar ?? this.player2Avatar,
    targetUserId: targetUserId ?? this.targetUserId,
    targetUserName: targetUserName ?? this.targetUserName,
    player1Side: player1Side ?? this.player1Side,
    timeControlSeconds: timeControlSeconds,
    turnTimerSeconds: turnTimerSeconds,
    boardSize: boardSize,
    initialFen: initialFen ?? this.initialFen,
    result: result ?? this.result,
    endReason: endReason ?? this.endReason,
    sourceGroupId: sourceGroupId,
    inviteMessageId: inviteMessageId ?? this.inviteMessageId,
    spectatorIds: spectatorIds ?? this.spectatorIds,
    moveHistory: moveHistory ?? this.moveHistory,
    createdAt: createdAt,
    startedAt: startedAt ?? this.startedAt,
    endedAt: endedAt ?? this.endedAt,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GameMatch && other.matchId == matchId);

  @override
  int get hashCode => matchId.hashCode;

  @override
  String toString() =>
      'GameMatch(id: $matchId, type: ${gameType.name}, status: ${status.name})';

  static String _parseTs(dynamic v) {
    if (v is String) return v;
    if (v is int) return v.toString();
    if (v is Timestamp) return v.millisecondsSinceEpoch.toString();
    return DateTime.now().millisecondsSinceEpoch.toString();
  }

  static String? _parseTsNullable(dynamic v) {
    if (v == null) return null;
    return _parseTs(v);
  }
}
