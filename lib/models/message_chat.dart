import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_chat_demo/constants/constants.dart';

// =========================================================
// TYPE MESSAGE CONSTANTS
// =========================================================

class TypeMessage {
  const TypeMessage._();

  static const int text = 0;
  static const int image = 1;
  static const int sticker = 2;
  static const int voice = 3;
  static const int video = 4;
  static const int document = 5; // File tài liệu
  static const int poll = 6; // Bình chọn
  static const int game = 7; // Game (Tic-tac-toe legacy)
  static const int blow = 8;
  static const int shake = 9;
  static const int geoLocked = 10;

  // ─── Game Center ────────────────────────────────────────────────────────
  /// Tin nhắn mời chơi / thách đấu.
  /// content = JSON của GameInvitePayload
  /// Hiển thị: card với nút [Vào bàn] hoặc [Xem trực tiếp]
  static const int gameInvite = 11;

  /// Tin nhắn kết quả trận đấu.
  /// content = JSON của GameResultPayload
  /// Hiển thị: card kết quả với nút [Xem lại]
  static const int gameResult = 12;

  /// Tin nhắn trạng thái live — được UPDATE tại chỗ (không tạo mới).
  /// content = JSON của GameLivePayload
  /// Hiển thị: card "Đang thi đấu (Live)" với nút [Xem trực tiếp]
  static const int gameLive = 13;
}

// =========================================================
// GAME MESSAGE ENUMS
// =========================================================

/// Loại game được hỗ trợ.
enum GameType {
  caro, // Caro / Gomoku
  chess; // Cờ Vua

  String get displayName {
    switch (this) {
      case GameType.caro:
        return 'Caro';
      case GameType.chess:
        return 'Cờ Vua';
    }
  }

  String get emoji {
    switch (this) {
      case GameType.caro:
        return '⭕';
      case GameType.chess:
        return '♟️';
    }
  }

  static GameType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'chess':
        return GameType.chess;
      case 'caro':
      default:
        return GameType.caro;
    }
  }
}

/// Trạng thái trận đấu được nhúng vào tin nhắn trong nhóm.
enum MatchStatus {
  /// Đang chờ đối thủ chấp nhận (Open Challenge hoặc đã tag người chơi).
  waiting,

  /// Trận đấu đang diễn ra.
  live,

  /// Trận đấu đã kết thúc.
  finished,

  /// Trận bị huỷ (hết thời gian chờ, không ai chấp nhận, v.v.).
  aborted;

  static MatchStatus fromString(String value) {
    switch (value.toLowerCase()) {
      case 'live':
        return MatchStatus.live;
      case 'finished':
        return MatchStatus.finished;
      case 'aborted':
        return MatchStatus.aborted;
      case 'waiting':
      default:
        return MatchStatus.waiting;
    }
  }

  String get label {
    switch (this) {
      case MatchStatus.waiting:
        return 'Đang chờ đối thủ...';
      case MatchStatus.live:
        return 'Đang thi đấu (Live)';
      case MatchStatus.finished:
        return 'Đã kết thúc';
      case MatchStatus.aborted:
        return 'Đã huỷ';
    }
  }
}

// =========================================================
// GAME MESSAGE PAYLOAD MODELS
// =========================================================

/// Payload cho TypeMessage.gameInvite / TypeMessage.gameLive.
/// Được serialize thành JSON và lưu vào field [content].
class GameInvitePayload {
  final String matchId;
  final GameType gameType;
  final MatchStatus matchStatus;

  // KHẮC PHỤC LỖI 8: Thêm trường challengerId để định danh chính xác người tạo thách đấu
  final String challengerId;
  final String challengerName;
  final String challengerAvatar;

  /// null = Open Challenge (ai chấp nhận cũng được)
  final String? targetUserId;
  final String? targetUserName;

  /// Cài đặt cờ vua: giây (0 = không giới hạn)
  final int timeControlSeconds;

  /// Cài đặt Caro: kích thước bàn (3 = 3x3, 0 = vô hạn)
  final int boardSize;

  /// Số khán giả hiện tại (chỉ dùng khi matchStatus == live)
  final int spectatorCount;

  const GameInvitePayload({
    required this.matchId,
    required this.gameType,
    required this.matchStatus,
    required this.challengerId,
    required this.challengerName,
    required this.challengerAvatar,
    this.targetUserId,
    this.targetUserName,
    this.timeControlSeconds = 0,
    this.boardSize = 0,
    this.spectatorCount = 0,
  });

  Map<String, dynamic> toJson() => {
    'matchId': matchId,
    'gameType': gameType.name,
    'matchStatus': matchStatus.name,
    'challengerId': challengerId,
    'challengerName': challengerName,
    'challengerAvatar': challengerAvatar,
    if (targetUserId != null) 'targetUserId': targetUserId,
    if (targetUserName != null) 'targetUserName': targetUserName,
    'timeControlSeconds': timeControlSeconds,
    'boardSize': boardSize,
    'spectatorCount': spectatorCount,
  };

  factory GameInvitePayload.fromJson(Map<String, dynamic> json) =>
      GameInvitePayload(
        matchId: json['matchId'] as String? ?? '',
        gameType: GameType.fromString(json['gameType'] as String? ?? 'caro'),
        matchStatus: MatchStatus.fromString(
          json['matchStatus'] as String? ?? 'waiting',
        ),
        challengerId: json['challengerId'] as String? ?? '',
        challengerName: json['challengerName'] as String? ?? '',
        challengerAvatar: json['challengerAvatar'] as String? ?? '',
        targetUserId: json['targetUserId'] as String?,
        targetUserName: json['targetUserName'] as String?,
        timeControlSeconds: json['timeControlSeconds'] as int? ?? 0,
        boardSize: json['boardSize'] as int? ?? 0,
        spectatorCount: json['spectatorCount'] as int? ?? 0,
      );

  GameInvitePayload copyWith({
    MatchStatus? matchStatus,
    int? spectatorCount,
    String? opponentName,
  }) => GameInvitePayload(
    matchId: matchId,
    gameType: gameType,
    matchStatus: matchStatus ?? this.matchStatus,
    challengerId: challengerId,
    challengerName: challengerName,
    challengerAvatar: challengerAvatar,
    targetUserId: targetUserId,
    targetUserName: targetUserName,
    timeControlSeconds: timeControlSeconds,
    boardSize: boardSize,
    spectatorCount: spectatorCount ?? this.spectatorCount,
  );
}

/// Payload cho TypeMessage.gameResult.
class GameResultPayload {
  final String matchId;
  final GameType gameType;

  /// 'player1_win' | 'player2_win' | 'draw'
  final String result;

  final String player1Id;
  final String player1Name;
  final String player1Avatar;
  final String player2Id;
  final String player2Name;
  final String player2Avatar;

  /// Lý do kết thúc (để hiển thị trên card kết quả)
  /// 'checkmate' | 'timeout' | 'resign' | 'draw_agreed' | 'disconnect' | 'five_in_row'
  final String endReason;

  /// Thời gian trận đấu (giây)
  final int durationSeconds;

  /// Tổng số nước đi
  final int totalMoves;

  const GameResultPayload({
    required this.matchId,
    required this.gameType,
    required this.result,
    required this.player1Id,
    required this.player1Name,
    required this.player1Avatar,
    required this.player2Id,
    required this.player2Name,
    required this.player2Avatar,
    required this.endReason,
    required this.durationSeconds,
    required this.totalMoves,
  });

  Map<String, dynamic> toJson() => {
    'matchId': matchId,
    'gameType': gameType.name,
    'result': result,
    'player1Id': player1Id,
    'player1Name': player1Name,
    'player1Avatar': player1Avatar,
    'player2Id': player2Id,
    'player2Name': player2Name,
    'player2Avatar': player2Avatar,
    'endReason': endReason,
    'durationSeconds': durationSeconds,
    'totalMoves': totalMoves,
  };

  factory GameResultPayload.fromJson(Map<String, dynamic> json) =>
      GameResultPayload(
        matchId: json['matchId'] as String? ?? '',
        gameType: GameType.fromString(json['gameType'] as String? ?? 'caro'),
        result: json['result'] as String? ?? 'draw',
        player1Id: json['player1Id'] as String? ?? '',
        player1Name: json['player1Name'] as String? ?? '',
        player1Avatar: json['player1Avatar'] as String? ?? '',
        player2Id: json['player2Id'] as String? ?? '',
        player2Name: json['player2Name'] as String? ?? '',
        player2Avatar: json['player2Avatar'] as String? ?? '',
        endReason: json['endReason'] as String? ?? '',
        durationSeconds: json['durationSeconds'] as int? ?? 0,
        totalMoves: json['totalMoves'] as int? ?? 0,
      );

  /// Trả về ID của người thắng, null nếu hòa.
  String? get winnerId {
    if (result == 'player1_win') return player1Id;
    if (result == 'player2_win') return player2Id;
    return null;
  }

  /// Tên hiển thị của kết quả.
  String resultLabel(String currentUserId) {
    if (result == 'draw') return '🤝 Hòa nhau!';
    if (winnerId == currentUserId) return '🏆 Bạn đã thắng!';
    return '💀 Bạn đã thua!';
  }
}

// =========================================================
// MESSAGE CHAT MODEL
// =========================================================

class MessageChat {
  final String idFrom;
  final String idTo;
  final String timestamp;
  final String content;
  final int type;

  /// Tin nhắn đã bị xóa mềm hay chưa.
  final bool isDeleted;

  /// Thời điểm chỉnh sửa lần cuối (null nếu chưa chỉnh sửa).
  final String? editedAt;

  /// Tin nhắn có được ghim hay không.
  final bool isPinned;

  /// Người nhận đã đọc tin nhắn hay chưa.
  final bool isRead;

  /// Thời điểm đọc tin nhắn (null nếu chưa đọc).
  final String? readAt;

  /// Cờ cảnh báo scam do AI Backend phân tích.
  final bool? scamWarning;

  // ─── Game Center Fields ────────────────────────────────────────────────
  /// ID trận đấu — chỉ có giá trị khi type là gameInvite / gameResult / gameLive.
  final String? matchId;

  /// Loại game: 'caro' | 'chess'
  final String? gameType;

  /// Trạng thái trận đấu: 'waiting' | 'live' | 'finished' | 'aborted'
  final String? matchStatus;

  const MessageChat({
    required this.idFrom,
    required this.idTo,
    required this.timestamp,
    required this.content,
    required this.type,
    this.isDeleted = false,
    this.editedAt,
    this.isPinned = false,
    this.isRead = false,
    this.readAt,
    this.scamWarning,
    // Game fields
    this.matchId,
    this.gameType,
    this.matchStatus,
  });

  // =========================================================
  // SERIALIZATION
  // =========================================================

  Map<String, dynamic> toJson() {
    return {
      FirestoreConstants.idFrom: idFrom,
      FirestoreConstants.idTo: idTo,
      FirestoreConstants.timestamp: timestamp,
      FirestoreConstants.content: content,
      FirestoreConstants.type: type,
      'isDeleted': isDeleted,
      'editedAt': editedAt,
      'isPinned': isPinned,
      'isRead': isRead,
      'readAt': readAt,
      'scamWarning': scamWarning,
      // Game fields — chỉ serialize khi có giá trị
      if (matchId != null) FirestoreConstants.matchId: matchId,
      if (gameType != null) FirestoreConstants.gameType: gameType,
      if (matchStatus != null) FirestoreConstants.matchStatus: matchStatus,
    };
  }

  // =========================================================
  // DESERIALIZATION
  // =========================================================

  factory MessageChat.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;

    if (data == null) {
      throw Exception('MessageChat.fromDocument: data is null (id: ${doc.id})');
    }

    return MessageChat(
      idFrom: data[FirestoreConstants.idFrom] as String? ?? '',
      idTo: data[FirestoreConstants.idTo] as String? ?? '',
      timestamp: _parseTimestamp(data[FirestoreConstants.timestamp]),
      content: data[FirestoreConstants.content] as String? ?? '',
      type: data[FirestoreConstants.type] as int? ?? TypeMessage.text,
      isDeleted: data['isDeleted'] as bool? ?? false,
      editedAt: _parseOptionalTimestamp(data['editedAt']),
      isPinned: data['isPinned'] as bool? ?? false,
      isRead: data['isRead'] as bool? ?? false,
      readAt: _parseOptionalTimestamp(data['readAt']),
      scamWarning: data['scamWarning'] as bool?,
      // Game fields
      matchId: data[FirestoreConstants.matchId] as String?,
      gameType: data[FirestoreConstants.gameType] as String?,
      matchStatus: data[FirestoreConstants.matchStatus] as String?,
    );
  }

  // =========================================================
  // COPY WITH
  // =========================================================

  MessageChat copyWith({
    String? content,
    String? editedAt,
    bool? isPinned,
    bool? isRead,
    String? readAt,
    bool? scamWarning,
    bool? isDeleted,
    String? matchId,
    String? gameType,
    String? matchStatus,
  }) {
    return MessageChat(
      idFrom: idFrom,
      idTo: idTo,
      timestamp: timestamp,
      content: content ?? this.content,
      type: type,
      isDeleted: isDeleted ?? this.isDeleted,
      editedAt: editedAt ?? this.editedAt,
      isPinned: isPinned ?? this.isPinned,
      isRead: isRead ?? this.isRead,
      readAt: readAt ?? this.readAt,
      scamWarning: scamWarning ?? this.scamWarning,
      matchId: matchId ?? this.matchId,
      gameType: gameType ?? this.gameType,
      matchStatus: matchStatus ?? this.matchStatus,
    );
  }

  // =========================================================
  // HELPERS
  // =========================================================

  /// Trả về `true` nếu đây là tin nhắn video.
  bool get isVideo => type == TypeMessage.video;

  /// Trả về `true` nếu đây là tin nhắn tài liệu.
  bool get isDocument => type == TypeMessage.document;

  /// Trả về `true` nếu đây là tin nhắn bình chọn.
  bool get isPoll => type == TypeMessage.poll;

  // ─── Game Center Helpers ─────────────────────────────────────────────────
  /// Trả về `true` nếu đây là tin nhắn liên quan đến Game Center.
  bool get isGameMessage =>
      type == TypeMessage.gameInvite ||
      type == TypeMessage.gameResult ||
      type == TypeMessage.gameLive;

  /// Trả về `true` nếu đây là lời mời chơi game (đang chờ hoặc live).
  bool get isGameInvite => type == TypeMessage.gameInvite;

  /// Trả về `true` nếu đây là tin nhắn kết quả.
  bool get isGameResult => type == TypeMessage.gameResult;

  /// Trả về `true` nếu đây là tin nhắn trạng thái live.
  bool get isGameLive => type == TypeMessage.gameLive;

  /// Parse MatchStatus từ field [matchStatus].
  MatchStatus get parsedMatchStatus =>
      MatchStatus.fromString(matchStatus ?? 'waiting');

  /// Parse GameType từ field [gameType].
  GameType get parsedGameType => GameType.fromString(gameType ?? 'caro');

  /// Với video, content có dạng `"videoUrl|thumbnailUrl"`.
  String get videoUrl {
    if (!isVideo) return content;
    final parts = content.split('|');
    return parts.isNotEmpty ? parts[0] : content;
  }

  String get videoThumbnailUrl {
    if (!isVideo) return '';
    final parts = content.split('|');
    return parts.length > 1 ? parts[1] : '';
  }

  // =========================================================
  // PRIVATE HELPERS
  // =========================================================

  static String _parseTimestamp(dynamic value) {
    if (value is String) return value;
    if (value is Timestamp) return value.millisecondsSinceEpoch.toString();
    if (value is int) return value.toString();
    return DateTime.now().millisecondsSinceEpoch.toString();
  }

  static String? _parseOptionalTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    if (value is Timestamp) return value.millisecondsSinceEpoch.toString();
    if (value is int) return value.toString();
    return null;
  }
}
