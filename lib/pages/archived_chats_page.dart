import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/constants.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import 'chat_page.dart';
import 'group_chat_page.dart';

class ArchivedChatsPage extends StatelessWidget {
  const ArchivedChatsPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final authProvider = context.read<AuthProvider>();
    final conversationProvider = context.read<ConversationProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentUserId = authProvider.userFirebaseId ?? '';

    return Scaffold(
      backgroundColor: isDark
          ? ColorConstants.backgroundDark
          : ColorConstants.backgroundLight,
      appBar: AppBar(
        backgroundColor: isDark ? ColorConstants.surfaceDark : Colors.white,
        title: Text(
          'Archived Chats',
          style: TextStyle(
            color: isDark ? Colors.white : const Color(0xFF1A1D2E),
            fontWeight: FontWeight.w700,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: isDark ? Colors.white70 : ColorConstants.primaryColor),
          onPressed: () => Navigator.pop(context),
        ),
        elevation: 0,
      ),
      body: StreamBuilder<List<QueryDocumentSnapshot>>(
        stream: conversationProvider.getConversationsWithPinned(currentUserId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final allDocs = snapshot.data ?? [];
          final archivedConversations = allDocs.where((doc) {
            final conv = Conversation.fromDocument(doc);
            return conv.archivedBy.contains(currentUserId);
          }).toList();

          if (archivedConversations.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.archive_outlined,
                      size: 64,
                      color: ColorConstants.greyColor.withOpacity(0.5)),
                  const SizedBox(height: 16),
                  Text(
                    "No archived conversations.",
                    style: TextStyle(
                        color: ColorConstants.greyColor, fontSize: 16),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: archivedConversations.length,
            itemBuilder: (context, index) {
              final conversation =
                  Conversation.fromDocument(archivedConversations[index]);

              // Dùng lại Logic hiển thị của Home Page để vẽ item
              if (conversation.isGroup) {
                return FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance
                      .collection(FirestoreConstants.pathGroupCollection)
                      .doc(conversation.id)
                      .get(),
                  builder: (_, groupSnapshot) {
                    if (!groupSnapshot.hasData) return const SizedBox.shrink();
                    final group = Group.fromDocument(groupSnapshot.data!);
                    return ListTile(
                      leading: CircleAvatar(
                          backgroundImage: NetworkImage(group.groupPhotoUrl)),
                      title: Text(group.groupName,
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black)),
                      subtitle: Text("Archived",
                          style: TextStyle(color: ColorConstants.greyColor)),
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => GroupChatPage(group: group))),
                      trailing: IconButton(
                        icon: const Icon(Icons.unarchive_rounded,
                            color: Colors.orange),
                        onPressed: () =>
                            conversationProvider.toggleArchiveConversation(
                                conversation.id, currentUserId, false),
                      ),
                    );
                  },
                );
              }

              final otherUserId = conversation.participants
                  .firstWhere((id) => id != currentUserId, orElse: () => '');
              if (otherUserId.isEmpty) return const SizedBox.shrink();

              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance
                    .collection(FirestoreConstants.pathUserCollection)
                    .doc(otherUserId)
                    .get(),
                builder: (_, userSnapshot) {
                  if (!userSnapshot.hasData) return const SizedBox.shrink();
                  final userChat = UserChat.fromDocument(userSnapshot.data!);
                  return ListTile(
                    leading: CircleAvatar(
                        backgroundImage: NetworkImage(userChat.photoUrl)),
                    title: Text(userChat.nickname,
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black)),
                    subtitle: Text("Archived",
                        style: TextStyle(color: ColorConstants.greyColor)),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatPage(
                            arguments: ChatPageArguments(
                                peerId: userChat.id,
                                peerAvatar: userChat.photoUrl,
                                peerNickname: userChat.nickname)),
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.unarchive_rounded,
                          color: Colors.orange),
                      onPressed: () =>
                          conversationProvider.toggleArchiveConversation(
                              conversation.id, currentUserId, false),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
