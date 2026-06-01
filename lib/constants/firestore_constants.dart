/// Tất cả các hằng số Firestore dùng xuyên suốt ứng dụng.
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
  static const String pathStoryCollection = 'stories';
  static const String pathMediaStorage = 'media';

  // ─── Game Center Collections ──────────────────────────────────────────────
  /// game_matches/{matchId}
  static const String pathGameMatchCollection = 'game_matches';

  /// game_matches/{matchId}/moves/{moveIndex}
  static const String pathGameMovesSubCollection = 'moves';

  /// game_matches/{matchId}/spectator_chat/{msgId}
  /// Chat nội bộ chỉ dành cho khán giả trong phòng đấu.
  static const String pathSpectatorChatSubCollection = 'spectator_chat';

  /// game_matches/{matchId}/reactions/{reactionId}
  /// Lưu các emoji reaction của khán giả (dùng để hiển thị live feed).
  static const String pathGameReactionsSubCollection = 'reactions';

  /// Realtime Database path (nếu dùng RTDB thay vì Firestore cho live state).
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
  static const String matchId = 'matchId';
  static const String gameType = 'gameType';
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

  static const String player1Id = 'player1Id';
  static const String player1Name = 'player1Name';
  static const String player1Avatar = 'player1Avatar';
  static const String player2Id = 'player2Id';
  static const String player2Name = 'player2Name';
  static const String player2Avatar = 'player2Avatar';
  static const String player1Side = 'player1Side';

  /// Thời gian mỗi người (giây). 0 = không giới hạn.
  static const String timeControlSeconds = 'timeControlSeconds';

  /// Giới hạn thời gian mỗi nước Caro (giây). 0 = không giới hạn.
  static const String turnTimerSeconds = 'turnTimerSeconds';

  /// Kích thước bàn Caro: 3 = 3×3, 0 = vô hạn.
  static const String boardSize = 'boardSize';

  /// Trạng thái match: 'waiting' | 'playing' | 'finished' | 'aborted'
  static const String gameStatus = 'gameStatus';

  /// Kết quả: 'player1_win' | 'player2_win' | 'draw' | null
  static const String gameResult = 'gameResult';

  /// Lý do kết thúc: 'checkmate' | 'timeout' | 'resign' | 'draw_agreed' |
  ///                 'disconnect' | 'five_in_row' | 'stalemate' | ...
  static const String gameEndReason = 'gameEndReason';

  /// Nhóm chat nguồn.
  static const String sourceGroupId = 'sourceGroupId';

  /// ID tin nhắn invite trong nhóm chat.
  static const String inviteMessageId = 'inviteMessageId';

  /// List userId đang xem live.
  static const String spectatorIds = 'spectatorIds';

  static const String startedAt = 'startedAt';
  static const String endedAt = 'endedAt';

  // ─── Disconnect handling ──────────────────────────────────────────────────
  static const String disconnectedPlayerId = 'disconnectedPlayerId';
  static const String disconnectedAt = 'disconnectedAt';

  // ─── Draw request ─────────────────────────────────────────────────────────
  static const String drawRequest = 'drawRequest';

  // =========================================================
  // GAME MOVE FIELDS (sub-collection: moves)
  // =========================================================

  static const String moveIndex = 'moveIndex';
  static const String movedBy = 'movedBy';
  static const String moveData = 'moveData';
  static const String movedAt = 'movedAt';
  static const String remainingTimeMs = 'remainingTimeMs';

  // =========================================================
  // SPECTATOR CHAT FIELDS (sub-collection: spectator_chat)
  // =========================================================

  static const String spectatorUserId = 'userId';
  static const String spectatorText = 'text';
  static const String spectatorSentAt = 'sentAt';

  // =========================================================
  // GAME REACTION FIELDS (sub-collection: reactions)
  // =========================================================

  static const String reactionUserId = 'userId';
  static const String reactionEmoji = 'emoji';
  static const String reactionSentAt = 'sentAt';
}
