/// Tất cả các hằng số Firestore dùng xuyên suốt ứng dụng.
/// Tập trung tại một chỗ để tránh lỗi typo và dễ refactor.
class FirestoreConstants {
  const FirestoreConstants._();

  // =========================================================
  // COLLECTION PATHS
  // =========================================================

  static const String pathUserCollection = 'users';
  static const String pathMessageCollection = 'messages';
  static const String pathFriendRequestCollection = 'friend_requests';
  static const String pathFriendshipCollection = 'friendships';
  static const String pathGroupCollection = 'groups';
  static const String pathConversationCollection = 'conversations';

  /// Firebase Storage root folder cho ảnh / video đã nén.
  static const String pathMediaStorage = 'media';

  // ─── Game Center Collections ──────────────────────────────────────────────
  /// Collection lưu trữ các trận đấu (matches).
  /// Cấu trúc: game_matches/{matchId}
  static const String pathGameMatchCollection = 'game_matches';

  /// Sub-collection lưu lịch sử nước đi để phục vụ Replay.
  /// Cấu trúc: game_matches/{matchId}/moves/{moveIndex}
  static const String pathGameMovesSubCollection = 'moves';

  /// Realtime Database path cho trạng thái live của trận đấu
  /// (đồng hồ, disconnect signal, spectator count).
  /// Cấu trúc: game_live/{matchId}
  static const String pathGameLiveNode = 'game_live';

  // =========================================================
  // USER FIELDS
  // =========================================================

  static const String nickname = 'nickname';
  static const String aboutMe = 'aboutMe';
  static const String photoUrl = 'photoUrl';
  static const String id = 'id';
  static const String phoneNumber = 'phoneNumber';
  static const String qrCode = 'qrCode';

  /// ID của người dùng mà user hiện tại đang nhắn tin.
  static const String chattingWith = 'chattingWith';

  // =========================================================
  // MESSAGE FIELDS
  // =========================================================

  static const String idFrom = 'idFrom';
  static const String idTo = 'idTo';
  static const String timestamp = 'timestamp';
  static const String content = 'content';
  static const String type = 'type';

  // ─── Game Message Fields ──────────────────────────────────────────────────
  /// ID trận đấu, dùng để navigate vào phòng đấu hoặc replay.
  static const String matchId = 'matchId';

  /// Loại game: 'caro' | 'chess'
  static const String gameType = 'gameType';

  /// Trạng thái trận đấu trên tin nhắn: 'waiting' | 'live' | 'finished'
  static const String matchStatus = 'matchStatus';

  // =========================================================
  // FRIEND REQUEST FIELDS
  // =========================================================

  static const String status = 'status';
  static const String requesterId = 'requesterId';
  static const String receiverId = 'receiverId';

  // =========================================================
  // FRIENDSHIP FIELDS
  // =========================================================

  static const String userId1 = 'userId1';
  static const String userId2 = 'userId2';

  // =========================================================
  // GROUP FIELDS
  // =========================================================

  static const String groupName = 'groupName';
  static const String groupPhotoUrl = 'groupPhotoUrl';
  static const String adminId = 'adminId';
  static const String memberIds = 'memberIds';

  // =========================================================
  // CONVERSATION FIELDS
  // =========================================================

  static const String conversationId = 'conversationId';
  static const String isGroup = 'isGroup';
  static const String participants = 'participants';
  static const String lastMessage = 'lastMessage';
  static const String lastMessageTime = 'lastMessageTime';
  static const String lastMessageType = 'lastMessageType';
  static const String createdAt = 'createdAt';
  static const String pathDocumentStorage = 'documents';

  // =========================================================
  // GAME MATCH FIELDS
  // =========================================================

  /// Thông tin người chơi 1 (người tạo thách đấu).
  static const String player1Id = 'player1Id';
  static const String player1Name = 'player1Name';
  static const String player1Avatar = 'player1Avatar';

  /// Thông tin người chơi 2 (người chấp nhận thách đấu).
  static const String player2Id = 'player2Id';
  static const String player2Name = 'player2Name';
  static const String player2Avatar = 'player2Avatar';

  /// Phe của player1 trong cờ vua: 'white' | 'black' | 'random'
  static const String player1Side = 'player1Side';

  /// Cài đặt thời gian: 0 = không giới hạn, 180 = 3 phút, 600 = 10 phút
  static const String timeControlSeconds = 'timeControlSeconds';

  /// Thời gian giới hạn mỗi nước đi (Caro): giây, 0 = không giới hạn
  static const String turnTimerSeconds = 'turnTimerSeconds';

  /// Kích thước bàn cờ Caro: 3 = 3x3 (Tic-tac-toe), 0 = vô hạn (Gomoku)
  static const String boardSize = 'boardSize';

  /// Trạng thái trận đấu trong Firestore: 'waiting' | 'playing' | 'finished' | 'aborted'
  static const String gameStatus = 'gameStatus';

  /// Kết quả: 'player1_win' | 'player2_win' | 'draw' | null
  static const String gameResult = 'gameResult';

  /// Lý do kết thúc: 'checkmate' | 'timeout' | 'resign' | 'draw_agreed' | 'disconnect'
  static const String gameEndReason = 'gameEndReason';

  /// Nhóm chat nguồn (để push kết quả về đúng nhóm).
  static const String sourceGroupId = 'sourceGroupId';

  /// ID tin nhắn thách đấu trong nhóm (để update trạng thái live/finished).
  static const String inviteMessageId = 'inviteMessageId';

  /// Danh sách khán giả đang online (userId list).
  static const String spectatorIds = 'spectatorIds';

  /// Thời điểm bắt đầu trận (milliseconds since epoch dạng String).
  static const String startedAt = 'startedAt';

  /// Thời điểm kết thúc trận.
  static const String endedAt = 'endedAt';

  // =========================================================
  // GAME MOVE FIELDS (sub-collection)
  // =========================================================

  /// Index thứ tự nước đi (0-based).
  static const String moveIndex = 'moveIndex';

  /// ID người đi nước này.
  static const String movedBy = 'movedBy';

  /// Dữ liệu nước đi:
  /// - Caro: {'row': int, 'col': int, 'symbol': 'X'|'O'}
  /// - Chess: {'from': 'e2', 'to': 'e4', 'promotion': 'q'?, 'san': 'e4', 'fen': '...'}
  static const String moveData = 'moveData';

  /// Thời điểm đi nước này (milliseconds since epoch).
  static const String movedAt = 'movedAt';

  /// Thời gian còn lại của người đi (milliseconds) — dùng cho chess clock.
  static const String remainingTimeMs = 'remainingTimeMs';
}