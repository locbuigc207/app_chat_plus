import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_chat_demo/providers/auth_provider.dart';
import 'package:flutter_chat_demo/providers/friend_provider.dart';
import 'package:flutter_chat_demo/providers/home_provider.dart';
import 'package:flutter_chat_demo/widgets/widgets.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';

class CreateGroupPage extends StatefulWidget {
  const CreateGroupPage({super.key});

  @override
  State<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<CreateGroupPage> {
  final _groupNameController = TextEditingController();
  final _selectedMembers = <String>{};
  bool _isLoading = false;

  late final String _currentUserId;
  late final FriendProvider _friendProvider;
  late final FirebaseFirestore _firebaseFirestore;

  @override
  void initState() {
    super.initState();
    _currentUserId = context.read<AuthProvider>().userFirebaseId ?? '';
    _friendProvider = FriendProvider(
      firebaseFirestore: context.read<HomeProvider>().firebaseFirestore,
    );
    _firebaseFirestore = context.read<HomeProvider>().firebaseFirestore;
  }

  Future<void> _createGroup() async {
    if (_groupNameController.text.trim().isEmpty) {
      Fluttertoast.showToast(msg: "Please enter group name");
      return;
    }

    if (_selectedMembers.isEmpty) {
      Fluttertoast.showToast(msg: "Please select at least one member");
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Create group
      final memberIds = [_currentUserId, ..._selectedMembers];
      final groupDoc = await _firebaseFirestore
          .collection(FirestoreConstants.pathGroupCollection)
          .add({
        FirestoreConstants.groupName: _groupNameController.text.trim(),
        FirestoreConstants.groupPhotoUrl: '',
        FirestoreConstants.adminId: _currentUserId,
        FirestoreConstants.memberIds: memberIds,
        FirestoreConstants.createdAt:
        DateTime.now().millisecondsSinceEpoch.toString(),
      });

      // Create conversation for group
      await _firebaseFirestore
          .collection(FirestoreConstants.pathConversationCollection)
          .doc(groupDoc.id)
          .set({
        FirestoreConstants.isGroup: true,
        FirestoreConstants.participants: memberIds,
        FirestoreConstants.lastMessage: 'Group created',
        FirestoreConstants.lastMessageTime:
        DateTime.now().millisecondsSinceEpoch.toString(),
        FirestoreConstants.lastMessageType: TypeMessage.text,
      });

      Fluttertoast.showToast(msg: "Group created successfully!");
      Navigator.pop(context);
    } catch (e) {
      Fluttertoast.showToast(msg: "Failed to create group: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildFriendsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _friendProvider.getFriendsList(_currentUserId),
      builder: (_, snapshot1) {
        return StreamBuilder<QuerySnapshot>(
          stream: _friendProvider.getFriendsList2(_currentUserId),
          builder: (_, snapshot2) {
            final friends1 = snapshot1.data?.docs ?? [];
            final friends2 = snapshot2.data?.docs ?? [];
            final allFriends = [...friends1, ...friends2];

            if (allFriends.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.people_outline,
                        size: 60,
                        color: ColorConstants.greyColor,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'No friends yet',
                        style: TextStyle(
                          color: ColorConstants.greyColor,
                          fontSize: 16,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Add friends to create a group',
                        style: TextStyle(
                          color: ColorConstants.greyColor,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: allFriends.length,
              itemBuilder: (_, index) {
                final friendship = Friendship.fromDocument(allFriends[index]);
                final friendId = friendship.userId1 == _currentUserId
                    ? friendship.userId2
                    : friendship.userId1;

                return FutureBuilder<DocumentSnapshot>(
                  future: _firebaseFirestore
                      .collection(FirestoreConstants.pathUserCollection)
                      .doc(friendId)
                      .get(),
                  builder: (_, userSnapshot) {
                    if (!userSnapshot.hasData) {
                      return const SizedBox.shrink();
                    }

                    final userChat = UserChat.fromDocument(userSnapshot.data!);
                    final isSelected = _selectedMembers.contains(friendId);

                    return CheckboxListTile(
                      value: isSelected,
                      onChanged: (value) {
                        setState(() {
                          if (value == true) {
                            _selectedMembers.add(friendId);
                          } else {
                            _selectedMembers.remove(friendId);
                          }
                        });
                      },
                      title: Text(
                        userChat.nickname,
                        style: const TextStyle(
                          color: ColorConstants.primaryColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        userChat.aboutMe.isEmpty ? 'No bio' : userChat.aboutMe,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: ColorConstants.greyColor,
                          fontSize: 14,
                        ),
                      ),
                      secondary: ClipOval(
                        child: userChat.photoUrl.isNotEmpty
                            ? Image.network(
                          userChat.photoUrl,
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.account_circle,
                            size: 50,
                            color: ColorConstants.greyColor,
                          ),
                        )
                            : const Icon(
                          Icons.account_circle,
                          size: 50,
                          color: ColorConstants.greyColor,
                        ),
                      ),
                      activeColor: ColorConstants.primaryColor,
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Create Group',
          style: TextStyle(color: ColorConstants.primaryColor),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _createGroup,
            child: const Text(
              'CREATE',
              style: TextStyle(
                color: ColorConstants.primaryColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Group Name Input
                const Text(
                  'Group Name',
                  style: TextStyle(
                    color: ColorConstants.primaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _groupNameController,
                  decoration: InputDecoration(
                    hintText: 'Enter group name',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  style: const TextStyle(
                    color: ColorConstants.primaryColor,
                  ),
                ),
                const SizedBox(height: 24),

                // Selected Members Count
                Text(
                  'Select Members (${_selectedMembers.length} selected)',
                  style: const TextStyle(
                    color: ColorConstants.primaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),

                // Friends List
                _buildFriendsList(),
              ],
            ),
          ),

          // Loading Overlay
          if (_isLoading)
            Positioned.fill(
              child: LoadingView(),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    super.dispose();
  }
}