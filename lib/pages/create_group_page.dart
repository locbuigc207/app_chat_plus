// lib/pages/create_group_page.dart
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
  final _descController = TextEditingController();
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
      Fluttertoast.showToast(msg: 'Please enter group name');
      return;
    }
    if (_selectedMembers.isEmpty) {
      Fluttertoast.showToast(msg: 'Select at least one member');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final memberIds = [_currentUserId, ..._selectedMembers];
      final now = DateTime.now().millisecondsSinceEpoch.toString();

      // System message
      final systemMsg = '${_groupNameController.text.trim()} group created';

      final groupDoc = await _firebaseFirestore
          .collection(FirestoreConstants.pathGroupCollection)
          .add({
        FirestoreConstants.groupName: _groupNameController.text.trim(),
        FirestoreConstants.groupPhotoUrl: '',
        FirestoreConstants.adminId: _currentUserId,
        FirestoreConstants.memberIds: memberIds,
        FirestoreConstants.createdAt: now,
        'description': _descController.text.trim(),
      });

      await _firebaseFirestore
          .collection(FirestoreConstants.pathConversationCollection)
          .doc(groupDoc.id)
          .set({
        FirestoreConstants.isGroup: true,
        FirestoreConstants.participants: memberIds,
        FirestoreConstants.lastMessage: systemMsg,
        FirestoreConstants.lastMessageTime: now,
        FirestoreConstants.lastMessageType: TypeMessage.text,
      });

      // System message in chat
      await _firebaseFirestore
          .collection(FirestoreConstants.pathMessageCollection)
          .doc(groupDoc.id)
          .collection(groupDoc.id)
          .doc(now)
          .set({
        FirestoreConstants.idFrom: _currentUserId,
        FirestoreConstants.idTo: groupDoc.id,
        FirestoreConstants.timestamp: now,
        FirestoreConstants.content: systemMsg,
        FirestoreConstants.type: TypeMessage.text,
        'isDeleted': false,
        'isPinned': false,
        'isRead': false,
        'isSystemMessage': true,
        'groupId': groupDoc.id,
      });

      Fluttertoast.showToast(msg: 'Group created!');
      Navigator.pop(context);
    } catch (e) {
      Fluttertoast.showToast(msg: 'Failed to create group: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildFriendsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _friendProvider.getFriendsList(_currentUserId),
      builder: (_, snap1) => StreamBuilder<QuerySnapshot>(
        stream: _friendProvider.getFriendsList2(_currentUserId),
        builder: (_, snap2) {
          final all = [...(snap1.data?.docs ?? []), ...(snap2.data?.docs ?? [])];
          if (all.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text('No friends yet. Add friends to create a group.',
                    style: TextStyle(color: ColorConstants.greyColor), textAlign: TextAlign.center),
              ),
            );
          }
          return ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: all.length,
            itemBuilder: (_, i) {
              final friendship = Friendship.fromDocument(all[i]);
              final friendId = friendship.userId1 == _currentUserId
                  ? friendship.userId2
                  : friendship.userId1;

              return FutureBuilder<DocumentSnapshot>(
                future: _firebaseFirestore
                    .collection(FirestoreConstants.pathUserCollection)
                    .doc(friendId)
                    .get(),
                builder: (_, snap) {
                  if (!snap.hasData) return const SizedBox.shrink();
                  final user = UserChat.fromDocument(snap.data!);
                  final isSelected = _selectedMembers.contains(friendId);
                  return CheckboxListTile(
                    value: isSelected,
                    onChanged: (v) => setState(() {
                      if (v == true) _selectedMembers.add(friendId);
                      else _selectedMembers.remove(friendId);
                    }),
                    title: Text(user.nickname,
                        style: const TextStyle(
                            color: ColorConstants.primaryColor,
                            fontWeight: FontWeight.w500)),
                    subtitle: user.aboutMe.isNotEmpty
                        ? Text(user.aboutMe,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: ColorConstants.greyColor, fontSize: 13))
                        : null,
                    secondary: ClipOval(
                      child: user.photoUrl.isNotEmpty
                          ? Image.network(user.photoUrl,
                          width: 48, height: 48, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                          const Icon(Icons.account_circle,
                              size: 48, color: ColorConstants.greyColor))
                          : const Icon(Icons.account_circle,
                          size: 48, color: ColorConstants.greyColor),
                    ),
                    activeColor: ColorConstants.primaryColor,
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Group',
            style: TextStyle(color: ColorConstants.primaryColor)),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _createGroup,
            child: const Text('CREATE',
                style: TextStyle(
                    color: ColorConstants.primaryColor,
                    fontWeight: FontWeight.bold)),
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
                // Group Icon placeholder
                Center(
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: ColorConstants.greyColor2,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.group,
                        size: 40, color: ColorConstants.greyColor),
                  ),
                ),
                const SizedBox(height: 20),
                // Group name
                const Text('Group Name *',
                    style: TextStyle(
                        color: ColorConstants.primaryColor,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: _groupNameController,
                  decoration: InputDecoration(
                    hintText: 'Enter group name',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
                const SizedBox(height: 16),
                // Description
                const Text('Description (optional)',
                    style: TextStyle(
                        color: ColorConstants.primaryColor,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: _descController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'What is this group about?',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
                const SizedBox(height: 24),
                // Members count indicator
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Select Members',
                        style: TextStyle(
                            color: ColorConstants.primaryColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
                    if (_selectedMembers.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: ColorConstants.primaryColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('${_selectedMembers.length} selected',
                            style: const TextStyle(color: Colors.white, fontSize: 12)),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildFriendsList(),
              ],
            ),
          ),
          if (_isLoading) LoadingView(),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    _descController.dispose();
    super.dispose();
  }
}