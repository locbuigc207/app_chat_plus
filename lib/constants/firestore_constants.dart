class FirestoreConstants {
  static const pathUserCollection = "users";
  static const pathMessageCollection = "messages";
  static const pathFriendRequestCollection = "friend_requests";
  static const pathFriendshipCollection = "friendships";
  static const pathGroupCollection = "groups";
  static const pathConversationCollection = "conversations";

  static const nickname = "nickname";
  static const aboutMe = "aboutMe";
  static const photoUrl = "photoUrl";
  static const id = "id";
  static const phoneNumber = "phoneNumber";
  static const qrCode = "qrCode";
  static const chattingWith = "chattingWith";
  static const idFrom = "idFrom";
  static const idTo = "idTo";
  static const timestamp = "timestamp";
  static const createdAt = "createdAt";
  static const content = "content";
  static const type = "type";

  // Friend request fields
  static const status = "status";
  static const requesterId = "requesterId";
  static const receiverId = "receiverId";

  // Friendship fields
  static const userId1 = "userId1";
  static const userId2 = "userId2";

  // Group fields
  static const groupName = "groupName";
  static const groupPhotoUrl = "groupPhotoUrl";
  static const adminId = "adminId";
  static const memberIds = "memberIds";

  // Conversation fields
  static const conversationId = "conversationId";
  static const isGroup = "isGroup";
  static const participants = "participants";
  static const lastMessage = "lastMessage";
  static const lastMessageTime = "lastMessageTime";
  static const lastMessageType = "lastMessageType";
}