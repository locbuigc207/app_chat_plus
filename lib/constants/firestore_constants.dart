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
  /// Dùng bởi [ChatProvider.sendMediaMessage] và [ChatProvider._uploadFileAndGetUrl].
  static const String pathMediaStorage = 'media';

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
  /// Được cập nhật mỗi khi mở / đóng [ChatPage].
  static const String chattingWith = 'chattingWith';

  // =========================================================
  // MESSAGE FIELDS
  // =========================================================

  static const String idFrom = 'idFrom';
  static const String idTo = 'idTo';
  static const String timestamp = 'timestamp';
  static const String content = 'content';
  static const String type = 'type';

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
}
