// lib/pages/group_info_page.dart
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_chat_demo/pages/pages.dart';
import 'package:flutter_chat_demo/providers/providers.dart';
import 'package:flutter_chat_demo/widgets/loading_view.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

class GroupInfoPage extends StatefulWidget {
  const GroupInfoPage({
    super.key,
    required this.group,
    required this.currentUserId,
    required this.memberNames,
  });

  final Group group;
  final String currentUserId;
  final Map<String, String> memberNames;

  @override
  State<GroupInfoPage> createState() => _GroupInfoPageState();
}

class _GroupInfoPageState extends State<GroupInfoPage> {
  late Group _group;
  bool _isLoading = false;
  bool _isAdmin = false;
  Map<String, UserChat> _memberData = {};

  @override
  void initState() {
    super.initState();
    _group = widget.group;
    _isAdmin = _group.adminId == widget.currentUserId;
    _loadMemberData();
  }

  Future<void> _loadMemberData() async {
    final data = <String, UserChat>{};
    for (final uid in _group.memberIds) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection(FirestoreConstants.pathUserCollection)
            .doc(uid)
            .get();
        if (doc.exists) data[uid] = UserChat.fromDocument(doc);
      } catch (_) {}
    }
    if (mounted) setState(() => _memberData = data);
  }

  Future<void> _changeGroupPhoto() async {
    if (!_isAdmin) return;
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;

    setState(() => _isLoading = true);
    try {
      final chatProvider = context.read<ChatProvider>();
      final file = File(picked.path);
      final fileName =
          'group_${_group.id}_${DateTime.now().millisecondsSinceEpoch}';
      final task = chatProvider.uploadFile(file, fileName);
      final snapshot = await task;
      final url = await snapshot.ref.getDownloadURL();

      await FirebaseFirestore.instance
          .collection(FirestoreConstants.pathGroupCollection)
          .doc(_group.id)
          .update({FirestoreConstants.groupPhotoUrl: url});

      setState(() {
        _group = Group(
          id: _group.id,
          groupName: _group.groupName,
          groupPhotoUrl: url,
          adminId: _group.adminId,
          memberIds: _group.memberIds,
          createdAt: _group.createdAt,
        );
      });
      Fluttertoast.showToast(msg: 'Group photo updated');
    } catch (e) {
      Fluttertoast.showToast(msg: 'Failed to update photo');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _editGroupName() async {
    if (!_isAdmin) return;
    final controller = TextEditingController(text: _group.groupName);
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit Group Name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Group name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (newName == null || newName.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance
          .collection(FirestoreConstants.pathGroupCollection)
          .doc(_group.id)
          .update({FirestoreConstants.groupName: newName});
      setState(() {
        _group = Group(
          id: _group.id,
          groupName: newName,
          groupPhotoUrl: _group.groupPhotoUrl,
          adminId: _group.adminId,
          memberIds: _group.memberIds,
          createdAt: _group.createdAt,
        );
      });
      Fluttertoast.showToast(msg: 'Group name updated');
    } catch (_) {
      Fluttertoast.showToast(msg: 'Failed to update name');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addMembers() async {
    if (!_isAdmin) return;
    // Show friend list to pick new members
    final friends = await _fetchFriends();
    if (!mounted) return;
    final existing = Set<String>.from(_group.memberIds);

    final selected = await showDialog<List<String>>(
      context: context,
      builder: (_) => _AddMembersDialog(
        friends: friends.where((f) => !existing.contains(f.id)).toList(),
      ),
    );

    if (selected == null || selected.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final newList = [..._group.memberIds, ...selected];
      await FirebaseFirestore.instance
          .collection(FirestoreConstants.pathGroupCollection)
          .doc(_group.id)
          .update({FirestoreConstants.memberIds: newList});
      await FirebaseFirestore.instance
          .collection(FirestoreConstants.pathConversationCollection)
          .doc(_group.id)
          .update({FirestoreConstants.participants: newList});

      setState(() {
        _group = Group(
          id: _group.id,
          groupName: _group.groupName,
          groupPhotoUrl: _group.groupPhotoUrl,
          adminId: _group.adminId,
          memberIds: newList,
          createdAt: _group.createdAt,
        );
      });
      await _loadMemberData();
      Fluttertoast.showToast(msg: 'Members added');
    } catch (_) {
      Fluttertoast.showToast(msg: 'Failed to add members');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<List<UserChat>> _fetchFriends() async {
    final result = <UserChat>[];
    try {
      final fs1 = await FirebaseFirestore.instance
          .collection(FirestoreConstants.pathFriendshipCollection)
          .where(FirestoreConstants.userId1, isEqualTo: widget.currentUserId)
          .get();
      final fs2 = await FirebaseFirestore.instance
          .collection(FirestoreConstants.pathFriendshipCollection)
          .where(FirestoreConstants.userId2, isEqualTo: widget.currentUserId)
          .get();

      final ids = <String>{};
      for (final d in fs1.docs) {
        ids.add(d.get(FirestoreConstants.userId2) as String);
      }
      for (final d in fs2.docs) {
        ids.add(d.get(FirestoreConstants.userId1) as String);
      }

      for (final id in ids) {
        final doc = await FirebaseFirestore.instance
            .collection(FirestoreConstants.pathUserCollection)
            .doc(id)
            .get();
        if (doc.exists) result.add(UserChat.fromDocument(doc));
      }
    } catch (_) {}
    return result;
  }

  Future<void> _removeMember(String userId) async {
    if (!_isAdmin || userId == widget.currentUserId) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove Member'),
        content:
            Text('Remove ${_memberData[userId]?.nickname ?? 'this member'}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      final newList = _group.memberIds.where((id) => id != userId).toList();
      await FirebaseFirestore.instance
          .collection(FirestoreConstants.pathGroupCollection)
          .doc(_group.id)
          .update({FirestoreConstants.memberIds: newList});
      setState(() {
        _group = Group(
          id: _group.id,
          groupName: _group.groupName,
          groupPhotoUrl: _group.groupPhotoUrl,
          adminId: _group.adminId,
          memberIds: newList,
          createdAt: _group.createdAt,
        );
        _memberData.remove(userId);
      });
      Fluttertoast.showToast(msg: 'Member removed');
    } catch (_) {
      Fluttertoast.showToast(msg: 'Failed to remove member');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _makeAdmin(String userId) async {
    if (!_isAdmin || userId == widget.currentUserId) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Make Admin'),
        content: Text(
            'Make ${_memberData[userId]?.nickname ?? 'this member'} admin?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm')),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance
          .collection(FirestoreConstants.pathGroupCollection)
          .doc(_group.id)
          .update({FirestoreConstants.adminId: userId});
      setState(() {
        _group = Group(
          id: _group.id,
          groupName: _group.groupName,
          groupPhotoUrl: _group.groupPhotoUrl,
          adminId: userId,
          memberIds: _group.memberIds,
          createdAt: _group.createdAt,
        );
        _isAdmin = userId == widget.currentUserId;
      });
      Fluttertoast.showToast(msg: 'Admin transferred');
    } catch (_) {
      Fluttertoast.showToast(msg: 'Failed to transfer admin');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Group Info',
            style: TextStyle(color: ColorConstants.primaryColor)),
        centerTitle: true,
        actions: [
          if (_isAdmin)
            TextButton(
              onPressed: _editGroupName,
              child: const Text('Edit',
                  style: TextStyle(color: ColorConstants.primaryColor)),
            ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 24),
                // Group avatar
                GestureDetector(
                  onTap: _isAdmin ? _changeGroupPhoto : null,
                  child: Stack(
                    children: [
                      Hero(
                        tag: 'group_avatar_${_group.id}',
                        child: CircleAvatar(
                          radius: 56,
                          backgroundImage: _group.groupPhotoUrl.isNotEmpty
                              ? NetworkImage(_group.groupPhotoUrl)
                              : null,
                          child: _group.groupPhotoUrl.isEmpty
                              ? const Icon(Icons.group,
                                  size: 56, color: Colors.white)
                              : null,
                          backgroundColor: ColorConstants.primaryColor,
                        ),
                      ),
                      if (_isAdmin)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                                color: ColorConstants.primaryColor,
                                shape: BoxShape.circle),
                            child: const Icon(Icons.camera_alt,
                                color: Colors.white, size: 18),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Group name
                GestureDetector(
                  onTap: _isAdmin ? _editGroupName : null,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_group.groupName,
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: ColorConstants.primaryColor)),
                      if (_isAdmin) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.edit,
                            size: 18, color: ColorConstants.greyColor),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text('Created ${_formatDate(_group.createdAt)}',
                    style: const TextStyle(
                        color: ColorConstants.greyColor, fontSize: 13)),
                const SizedBox(height: 24),
                // Media & Files shortcut
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Card(
                    elevation: 0,
                    color: ColorConstants.greyColor2.withOpacity(0.4),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      leading: const Icon(Icons.perm_media,
                          color: ColorConstants.primaryColor),
                      title: const Text('Media, Links & Docs'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => GroupMediaPage(
                            groupId: _group.id,
                            groupName: _group.groupName,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Members section
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${_group.memberIds.length} Members',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: ColorConstants.primaryColor)),
                      if (_isAdmin)
                        TextButton.icon(
                          onPressed: _addMembers,
                          icon: const Icon(Icons.person_add),
                          label: const Text('Add'),
                        ),
                    ],
                  ),
                ),
                ..._group.memberIds.map((uid) => _buildMemberTile(uid)),
                const SizedBox(height: 32),
              ],
            ),
          ),
          if (_isLoading) LoadingView(),
        ],
      ),
    );
  }

  Widget _buildMemberTile(String uid) {
    final user = _memberData[uid];
    final isThisAdmin = uid == _group.adminId;
    final isMe = uid == widget.currentUserId;

    return ListTile(
      leading: CircleAvatar(
        backgroundImage: user?.photoUrl.isNotEmpty == true
            ? NetworkImage(user!.photoUrl)
            : null,
        child: user?.photoUrl.isEmpty != false
            ? const Icon(Icons.person, color: Colors.white)
            : null,
        backgroundColor: ColorConstants.primaryColor.withOpacity(0.7),
      ),
      title: Row(
        children: [
          Text(user?.nickname ?? 'User',
              style: const TextStyle(fontWeight: FontWeight.w500)),
          if (isMe) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: const Text('You',
                  style: TextStyle(
                      fontSize: 11, color: ColorConstants.primaryColor)),
            ),
          ],
          if (isThisAdmin) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8)),
              child: const Text('Admin',
                  style: TextStyle(fontSize: 11, color: Colors.amber)),
            ),
          ],
        ],
      ),
      subtitle: user?.aboutMe.isNotEmpty == true
          ? Text(user!.aboutMe, maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      trailing: _isAdmin && !isMe
          ? PopupMenuButton<String>(
              onSelected: (val) {
                if (val == 'remove') _removeMember(uid);
                if (val == 'admin') _makeAdmin(uid);
                if (val == 'message') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatPage(
                        arguments: ChatPageArguments(
                          peerId: uid,
                          peerAvatar: user?.photoUrl ?? '',
                          peerNickname: user?.nickname ?? 'User',
                        ),
                      ),
                    ),
                  );
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'message', child: Text('Message')),
                if (!isThisAdmin)
                  const PopupMenuItem(
                      value: 'admin', child: Text('Make Admin')),
                const PopupMenuItem(
                    value: 'remove',
                    child: Text('Remove', style: TextStyle(color: Colors.red))),
              ],
            )
          : !isMe
              ? IconButton(
                  icon: const Icon(Icons.message,
                      color: ColorConstants.primaryColor),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatPage(
                        arguments: ChatPageArguments(
                          peerId: uid,
                          peerAvatar: user?.photoUrl ?? '',
                          peerNickname: user?.nickname ?? 'User',
                        ),
                      ),
                    ),
                  ),
                )
              : null,
    );
  }

  String _formatDate(String ts) {
    try {
      final dt = DateTime.fromMillisecondsSinceEpoch(int.parse(ts));
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return '';
    }
  }
}

// Add members dialog
class _AddMembersDialog extends StatefulWidget {
  const _AddMembersDialog({required this.friends});
  final List<UserChat> friends;

  @override
  State<_AddMembersDialog> createState() => _AddMembersDialogState();
}

class _AddMembersDialogState extends State<_AddMembersDialog> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Members'),
      content: SizedBox(
        width: double.maxFinite,
        height: 300,
        child: widget.friends.isEmpty
            ? const Center(child: Text('No friends to add'))
            : ListView.builder(
                itemCount: widget.friends.length,
                itemBuilder: (_, i) {
                  final friend = widget.friends[i];
                  final selected = _selected.contains(friend.id);
                  return CheckboxListTile(
                    value: selected,
                    onChanged: (v) {
                      setState(() {
                        if (v == true)
                          _selected.add(friend.id);
                        else
                          _selected.remove(friend.id);
                      });
                    },
                    title: Text(friend.nickname),
                    secondary: CircleAvatar(
                      backgroundImage: friend.photoUrl.isNotEmpty
                          ? NetworkImage(friend.photoUrl)
                          : null,
                      child: friend.photoUrl.isEmpty
                          ? const Icon(Icons.person, color: Colors.white)
                          : null,
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(context, _selected.toList()),
          child: Text('Add (${_selected.length})'),
        ),
      ],
    );
  }
}
