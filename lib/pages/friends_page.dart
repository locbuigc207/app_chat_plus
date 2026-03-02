// lib/pages/friends_page.dart - NEW FRIENDS PAGE
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_chat_demo/pages/pages.dart';
import 'package:flutter_chat_demo/providers/providers.dart';
import 'package:flutter_chat_demo/widgets/widgets.dart';
import 'package:provider/provider.dart';

class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key});

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late final String _currentUserId;
  late final FriendProvider _friendProvider;
  late final FirebaseFirestore _firebaseFirestore;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _currentUserId = context.read<AuthProvider>().userFirebaseId ?? '';
    _friendProvider = FriendProvider(
      firebaseFirestore: context.read<HomeProvider>().firebaseFirestore,
    );
    _firebaseFirestore = context.read<HomeProvider>().firebaseFirestore;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Friends',
          style: TextStyle(color: ColorConstants.primaryColor),
        ),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          labelColor: ColorConstants.primaryColor,
          unselectedLabelColor: ColorConstants.greyColor,
          indicatorColor: ColorConstants.primaryColor,
          tabs: const [
            Tab(
              icon: Icon(Icons.people),
              text: 'My Friends',
            ),
            Tab(
              icon: Icon(Icons.person_add),
              text: 'Suggestions',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          MyFriendsTab(
            currentUserId: _currentUserId,
            friendProvider: _friendProvider,
            firebaseFirestore: _firebaseFirestore,
          ),
          SuggestionsTab(
            currentUserId: _currentUserId,
            friendProvider: _friendProvider,
            firebaseFirestore: _firebaseFirestore,
          ),
        ],
      ),
    );
  }
}

// 🎯 TAB 1: My Friends
class MyFriendsTab extends StatelessWidget {
  final String currentUserId;
  final FriendProvider friendProvider;
  final FirebaseFirestore firebaseFirestore;

  const MyFriendsTab({
    super.key,
    required this.currentUserId,
    required this.friendProvider,
    required this.firebaseFirestore,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: friendProvider.getFriendsList(currentUserId),
      builder: (_, snapshot1) {
        return StreamBuilder<QuerySnapshot>(
          stream: friendProvider.getFriendsList2(currentUserId),
          builder: (_, snapshot2) {
            final friends1 = snapshot1.data?.docs ?? [];
            final friends2 = snapshot2.data?.docs ?? [];
            final allFriends = [...friends1, ...friends2];

            if (snapshot1.connectionState == ConnectionState.waiting &&
                snapshot2.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(
                  color: ColorConstants.themeColor,
                ),
              );
            }

            if (allFriends.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.people_outline,
                      size: 80,
                      color: ColorConstants.greyColor.withOpacity(0.5),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No friends yet',
                      style: TextStyle(
                        color: ColorConstants.greyColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Add friends to start chatting',
                      style: TextStyle(
                        color: ColorConstants.greyColor,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: allFriends.length,
              itemBuilder: (_, index) {
                final friendship = Friendship.fromDocument(allFriends[index]);
                final friendId = friendship.userId1 == currentUserId
                    ? friendship.userId2
                    : friendship.userId1;

                return FutureBuilder<DocumentSnapshot>(
                  future: firebaseFirestore
                      .collection(FirestoreConstants.pathUserCollection)
                      .doc(friendId)
                      .get(),
                  builder: (_, userSnapshot) {
                    if (!userSnapshot.hasData) {
                      return const SizedBox.shrink();
                    }

                    final userChat = UserChat.fromDocument(userSnapshot.data!);

                    return _buildFriendItem(context, userChat);
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildFriendItem(BuildContext context, UserChat userChat) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => UserProfilePage(userChat: userChat),
              ),
            );
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ColorConstants.greyColor2.withOpacity(0.3),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                // Avatar with online status
                AvatarWithStatus(
                  userId: userChat.id,
                  photoUrl: userChat.photoUrl,
                  size: 55,
                  indicatorSize: 14,
                ),
                const SizedBox(width: 15),

                // User info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userChat.nickname,
                        style: const TextStyle(
                          color: ColorConstants.primaryColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (userChat.aboutMe.isNotEmpty)
                        Text(
                          userChat.aboutMe,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: ColorConstants.greyColor,
                            fontSize: 13,
                          ),
                        )
                      else
                        const Text(
                          'No bio',
                          style: TextStyle(
                            color: ColorConstants.greyColor,
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                    ],
                  ),
                ),

                // Action button
                IconButton(
                  icon: const Icon(
                    Icons.message,
                    color: ColorConstants.primaryColor,
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatPage(
                          arguments: ChatPageArguments(
                            peerId: userChat.id,
                            peerAvatar: userChat.photoUrl,
                            peerNickname: userChat.nickname,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// 🎯 TAB 2: Friend Suggestions (Based on mutual friends)
class SuggestionsTab extends StatefulWidget {
  final String currentUserId;
  final FriendProvider friendProvider;
  final FirebaseFirestore firebaseFirestore;

  const SuggestionsTab({
    super.key,
    required this.currentUserId,
    required this.friendProvider,
    required this.firebaseFirestore,
  });

  @override
  State<SuggestionsTab> createState() => _SuggestionsTabState();
}

class _SuggestionsTabState extends State<SuggestionsTab> {
  List<String> _myFriendIds = [];
  Map<String, List<String>> _mutualFriendsMap = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  Future<void> _loadSuggestions() async {
    setState(() => _isLoading = true);

    try {
      // Get my friends
      final friendships1 = await widget.firebaseFirestore
          .collection(FirestoreConstants.pathFriendshipCollection)
          .where(FirestoreConstants.userId1, isEqualTo: widget.currentUserId)
          .get();

      final friendships2 = await widget.firebaseFirestore
          .collection(FirestoreConstants.pathFriendshipCollection)
          .where(FirestoreConstants.userId2, isEqualTo: widget.currentUserId)
          .get();

      final myFriends = <String>{};

      for (var doc in friendships1.docs) {
        final friendship = Friendship.fromDocument(doc);
        myFriends.add(friendship.userId2);
      }

      for (var doc in friendships2.docs) {
        final friendship = Friendship.fromDocument(doc);
        myFriends.add(friendship.userId1);
      }

      _myFriendIds = myFriends.toList();

      // Find mutual friends for suggestions
      final mutualFriendsMap = <String, List<String>>{};

      for (var friendId in _myFriendIds) {
        // Get friends of my friend
        final friendFriendships1 = await widget.firebaseFirestore
            .collection(FirestoreConstants.pathFriendshipCollection)
            .where(FirestoreConstants.userId1, isEqualTo: friendId)
            .get();

        final friendFriendships2 = await widget.firebaseFirestore
            .collection(FirestoreConstants.pathFriendshipCollection)
            .where(FirestoreConstants.userId2, isEqualTo: friendId)
            .get();

        for (var doc in friendFriendships1.docs) {
          final friendship = Friendship.fromDocument(doc);
          final suggestedUserId = friendship.userId2;

          if (suggestedUserId != widget.currentUserId &&
              !_myFriendIds.contains(suggestedUserId)) {
            mutualFriendsMap.putIfAbsent(suggestedUserId, () => []);
            mutualFriendsMap[suggestedUserId]!.add(friendId);
          }
        }

        for (var doc in friendFriendships2.docs) {
          final friendship = Friendship.fromDocument(doc);
          final suggestedUserId = friendship.userId1;

          if (suggestedUserId != widget.currentUserId &&
              !_myFriendIds.contains(suggestedUserId)) {
            mutualFriendsMap.putIfAbsent(suggestedUserId, () => []);
            mutualFriendsMap[suggestedUserId]!.add(friendId);
          }
        }
      }

      setState(() {
        _mutualFriendsMap = mutualFriendsMap;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading suggestions: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: ColorConstants.themeColor,
        ),
      );
    }

    if (_mutualFriendsMap.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_search,
              size: 80,
              color: ColorConstants.greyColor.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            const Text(
              'No suggestions yet',
              style: TextStyle(
                color: ColorConstants.greyColor,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Add more friends to get suggestions',
              style: TextStyle(
                color: ColorConstants.greyColor,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    // Sort by number of mutual friends (descending)
    final sortedSuggestions = _mutualFriendsMap.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));

    return RefreshIndicator(
      onRefresh: _loadSuggestions,
      child: ListView.builder(
        padding: const EdgeInsets.all(10),
        itemCount: sortedSuggestions.length,
        itemBuilder: (_, index) {
          final userId = sortedSuggestions[index].key;
          final mutualFriendIds = sortedSuggestions[index].value;

          return FutureBuilder<DocumentSnapshot>(
            future: widget.firebaseFirestore
                .collection(FirestoreConstants.pathUserCollection)
                .doc(userId)
                .get(),
            builder: (_, userSnapshot) {
              if (!userSnapshot.hasData) {
                return const SizedBox.shrink();
              }

              final userChat = UserChat.fromDocument(userSnapshot.data!);

              return _buildSuggestionItem(
                context,
                userChat,
                mutualFriendIds.length,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildSuggestionItem(
    BuildContext context,
    UserChat userChat,
    int mutualCount,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => UserProfilePage(userChat: userChat),
              ),
            );
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ColorConstants.primaryColor.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: ColorConstants.primaryColor.withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                // Avatar
                ClipOval(
                  child: userChat.photoUrl.isNotEmpty
                      ? Image.network(
                          userChat.photoUrl,
                          width: 55,
                          height: 55,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.account_circle,
                            size: 55,
                            color: ColorConstants.greyColor,
                          ),
                        )
                      : const Icon(
                          Icons.account_circle,
                          size: 55,
                          color: ColorConstants.greyColor,
                        ),
                ),
                const SizedBox(width: 15),

                // User info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userChat.nickname,
                        style: const TextStyle(
                          color: ColorConstants.primaryColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.people,
                            size: 14,
                            color: ColorConstants.greyColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$mutualCount mutual friend${mutualCount > 1 ? 's' : ''}',
                            style: const TextStyle(
                              color: ColorConstants.greyColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      if (userChat.aboutMe.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          userChat.aboutMe,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: ColorConstants.greyColor,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Add friend button
                IconButton(
                  icon: const Icon(
                    Icons.person_add,
                    color: ColorConstants.primaryColor,
                  ),
                  onPressed: () async {
                    final success =
                        await widget.friendProvider.sendFriendRequest(
                      widget.currentUserId,
                      userChat.id,
                    );

                    if (success) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Friend request sent!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                      // Refresh suggestions
                      _loadSuggestions();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Failed to send request'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
