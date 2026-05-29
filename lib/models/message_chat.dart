import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_chat_demo/constants/constants.dart';





class TypeMessage {
  const TypeMessage._();

  static const int text = 0;
  static const int image = 1;
  static const int sticker = 2;
  static const int voice = 3;
  static const int video = 4;
  static const int document = 5; 
  static const int poll = 6; 
  static const int game = 7; 
  static const int blow = 8;
  static const int shake = 9;
  static const int geoLocked = 10;

  
  
  
  
  static const int gameInvite = 11;

  
  
  
  static const int gameResult = 12;

  
  
  
  static const int gameLive = 13;
}






enum GameType {
  caro, 
  chess; 

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


enum MatchStatus {
  
  waiting,

  
  live,

  
  finished,

  
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







class GameInvitePayload {
  final String matchId;
  final GameType gameType;
  final MatchStatus matchStatus;
  final String challengerName;
  final String challengerAvatar;

  
  final String? targetUserId;
  final String? targetUserName;

  
  final int timeControlSeconds;

  
  final int boardSize;

  
  final int spectatorCount;

  const GameInvitePayload({
    required this.matchId,
    required this.gameType,
    required this.matchStatus,
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
        'challengerName': challengerName,
        'challengerAvatar': challengerAvatar,
        if (targetUserId != null) 'targetUserId': targetUserId,
        if (targetUserName != null) 'targetUserName': targetUserName,
        'timeControlSeconds': timeControlSeconds,
        'boardSize': boardSize,
        'spectatorCount': spectatorCount,
      };

  factory GameInvitePayload.fromJson(Map<String, dynamic> json) => GameInvitePayload(
        matchId: json['matchId'] as String? ?? '',
        gameType: GameType.fromString(json['gameType'] as String? ?? 'caro'),
        matchStatus: MatchStatus.fromString(
          json['matchStatus'] as String? ?? 'waiting',
        ),
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
  }) =>
      GameInvitePayload(
        matchId: matchId,
        gameType: gameType,
        matchStatus: matchStatus ?? this.matchStatus,
        challengerName: challengerName,
        challengerAvatar: challengerAvatar,
        targetUserId: targetUserId,
        targetUserName: targetUserName,
        timeControlSeconds: timeControlSeconds,
        boardSize: boardSize,
        spectatorCount: spectatorCount ?? this.spectatorCount,
      );
}


class GameResultPayload {
  final String matchId;
  final GameType gameType;

  
  final String result;

  final String player1Id;
  final String player1Name;
  final String player1Avatar;
  final String player2Id;
  final String player2Name;
  final String player2Avatar;

  
  
  final String endReason;

  
  final int durationSeconds;

  
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

  factory GameResultPayload.fromJson(Map<String, dynamic> json) => GameResultPayload(
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

  
  String? get winnerId {
    if (result == 'player1_win') return player1Id;
    if (result == 'player2_win') return player2Id;
    return null;
  }

  
  String resultLabel(String currentUserId) {
    if (result == 'draw') return '🤝 Hòa nhau!';
    if (winnerId == currentUserId) return '🏆 Bạn đã thắng!';
    return '💀 Bạn đã thua!';
  }
}





class MessageChat {
  final String idFrom;
  final String idTo;
  final String timestamp;
  final String content;
  final int type;

  
  final bool isDeleted;

  
  final String? editedAt;

  
  final bool isPinned;

  
  final bool isRead;

  
  final String? readAt;

  
  final bool? scamWarning;

  
  
  final String? matchId;

  
  final String? gameType;

  
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
    
    this.matchId,
    this.gameType,
    this.matchStatus,
  });

  
  
  

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
      
      if (matchId != null) FirestoreConstants.matchId: matchId,
      if (gameType != null) FirestoreConstants.gameType: gameType,
      if (matchStatus != null) FirestoreConstants.matchStatus: matchStatus,
    };
  }

  
  
  

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
      
      matchId: data[FirestoreConstants.matchId] as String?,
      gameType: data[FirestoreConstants.gameType] as String?,
      matchStatus: data[FirestoreConstants.matchStatus] as String?,
    );
  }

  
  
  

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

  
  
  

  
  bool get isVideo => type == TypeMessage.video;

  
  bool get isDocument => type == TypeMessage.document;

  
  bool get isPoll => type == TypeMessage.poll;

  
  
  bool get isGameMessage =>
      type == TypeMessage.gameInvite ||
      type == TypeMessage.gameResult ||
      type == TypeMessage.gameLive;

  
  bool get isGameInvite => type == TypeMessage.gameInvite;

  
  bool get isGameResult => type == TypeMessage.gameResult;

  
  bool get isGameLive => type == TypeMessage.gameLive;

  
  MatchStatus get parsedMatchStatus => MatchStatus.fromString(matchStatus ?? 'waiting');

  
  GameType get parsedGameType => GameType.fromString(gameType ?? 'caro');

  
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
