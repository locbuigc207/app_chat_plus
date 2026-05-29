import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_chat_demo/pages/pages.dart';
import 'package:flutter_chat_demo/providers/providers.dart';
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

class _GroupInfoPageState extends State<GroupInfoPage> with TickerProviderStateMixin {
  late Group _group;
  bool _isLoading = false;
  bool _isOwner = false;
  bool _isAdmin = false;
  Map<String, UserChat> _memberData = {};

  late AnimationController _headerAnimCtrl;
  late Animation<double> _headerFadeAnim;
  late Animation<Offset> _headerSlideAnim;

  
  static const _bg = Color(0xFF0D0F14);
  static const _surface = Color(0xFF181B24);
  static const _surfaceHigh = Color(0xFF1E2233);
  static const _accent = Color(0xFF4F8EF7);
  static const _accentGlow = Color(0x334F8EF7);
  static const _gold = Color(0xFFFFB84D);
  static const _danger = Color(0xFFFF5A5A);
  static const _textPrimary = Color(0xFFEEF2FF);
  static const _textSecondary = Color(0xFF8B93B0);
  static const _divider = Color(0xFF252A3A);

  @override
  void initState() {
    super.initState();
    _group = widget.group;
    _checkRoles();
    _loadMemberData();

    _headerAnimCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _headerFadeAnim = CurvedAnimation(parent: _headerAnimCtrl, curve: Curves.easeOut);
    _headerSlideAnim = Tween<Offset>(begin: const Offset(0, .15), end: Offset.zero)
        .animate(CurvedAnimation(parent: _headerAnimCtrl, curve: Curves.easeOutCubic));
    _headerAnimCtrl.forward();
  }

  @override
  void dispose() {
    _headerAnimCtrl.dispose();
    super.dispose();
  }

  

  void _checkRoles() {
    String myRole = _group.roles[widget.currentUserId] ?? 'member';
    if (_group.adminId == widget.currentUserId && myRole == 'member') {
      myRole = 'owner';
    }
    _isOwner = myRole == 'owner';
    _isAdmin = myRole == 'admin' || _isOwner;
  }

  String _getUserRole(String uid) {
    String role = _group.roles[uid] ?? 'member';
    if (_group.adminId == uid && role == 'member') return 'owner';
    return role;
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
    HapticFeedback.lightImpact();
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null || !mounted) return;

    setState(() => _isLoading = true);
    try {
      final chatProvider = context.read<ChatProvider>();
      final file = File(picked.path);
      final fileName = 'group_${_group.id}_${DateTime.now().millisecondsSinceEpoch}';
      final task = chatProvider.uploadFile(file, fileName);
      final snapshot = await task;
      final url = await snapshot.ref.getDownloadURL();

      await FirebaseFirestore.instance
          .collection(FirestoreConstants.pathGroupCollection)
          .doc(_group.id)
          .update({FirestoreConstants.groupPhotoUrl: url});

      setState(() {
        _group = _group.copyWith(groupPhotoUrl: url);
      });
      _showToast('✅ Group photo updated', isSuccess: true);
    } catch (e) {
      _showToast('❌ Failed to update photo');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _editGroupName() async {
    if (!_isAdmin) return;
    HapticFeedback.selectionClick();
    final controller = TextEditingController(text: _group.groupName);
    final newName = await _showEditNameDialog(controller);
    controller.dispose();
    if (newName == null || newName.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance
          .collection(FirestoreConstants.pathGroupCollection)
          .doc(_group.id)
          .update({FirestoreConstants.groupName: newName});
      setState(() {
        _group = _group.copyWith(groupName: newName);
      });
      _showToast('✅ Group name updated', isSuccess: true);
    } catch (_) {
      _showToast('❌ Failed to update name');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<String?> _showEditNameDialog(TextEditingController ctrl) {
    return showDialog<String>(
      context: context,
      builder: (_) => _DarkDialog(
        title: 'Edit Group Name',
        icon: Icons.edit_rounded,
        content: _DarkTextField(
          controller: ctrl,
          hint: 'Group name...',
          autofocus: true,
        ),
        actions: [
          _DialogBtn(label: 'Cancel', onTap: () => Navigator.pop(context)),
          _DialogBtn(
            label: 'Save',
            isPrimary: true,
            onTap: () => Navigator.pop(context, ctrl.text.trim()),
          ),
        ],
      ),
    );
  }

  

  Future<void> _addMembers() async {
    if (!_isAdmin) return;
    HapticFeedback.lightImpact();
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
      final newRoles = Map<String, dynamic>.from(_group.roles);
      for (final id in selected) {
        newRoles[id] = 'member';
      }

      await FirebaseFirestore.instance
          .collection(FirestoreConstants.pathGroupCollection)
          .doc(_group.id)
          .update({
        FirestoreConstants.memberIds: newList,
        'roles': newRoles,
      });
      await FirebaseFirestore.instance
          .collection(FirestoreConstants.pathConversationCollection)
          .doc(_group.id)
          .update({FirestoreConstants.participants: newList});

      setState(() {
        _group = _group.copyWith(memberIds: newList, roles: newRoles);
      });
      await _loadMemberData();
      _showToast('✅ ${selected.length} member(s) added', isSuccess: true);
    } catch (_) {
      _showToast('❌ Failed to add members');
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

    final targetRole = _getUserRole(userId);
    if (!_isOwner && (targetRole == 'owner' || targetRole == 'admin')) {
      _showToast('⛔ Insufficient permissions');
      return;
    }

    final confirm = await _showConfirmDialog(
      title: 'Remove Member',
      message: 'Remove ${_memberData[userId]?.nickname ?? 'this member'} from the group?',
      confirmLabel: 'Remove',
      isDangerous: true,
    );
    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      final newList = _group.memberIds.where((id) => id != userId).toList();
      final newRoles = Map<String, dynamic>.from(_group.roles)..remove(userId);

      await FirebaseFirestore.instance
          .collection(FirestoreConstants.pathGroupCollection)
          .doc(_group.id)
          .update({
        FirestoreConstants.memberIds: newList,
        'roles': newRoles,
      });
      setState(() {
        _group = _group.copyWith(memberIds: newList, roles: newRoles);
        _memberData.remove(userId);
      });
      _showToast('✅ Member removed', isSuccess: true);
    } catch (_) {
      _showToast('❌ Failed to remove member');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _changeRole(String userId, String newRole) async {
    if (!_isOwner || userId == widget.currentUserId) return;
    HapticFeedback.mediumImpact();
    setState(() => _isLoading = true);
    try {
      final newRoles = Map<String, dynamic>.from(_group.roles);
      newRoles[userId] = newRole;

      await FirebaseFirestore.instance
          .collection(FirestoreConstants.pathGroupCollection)
          .doc(_group.id)
          .update({'roles': newRoles});

      setState(() {
        _group = _group.copyWith(roles: newRoles);
      });
      final label = newRole == 'admin' ? 'promoted to Admin' : 'set to Member';
      _showToast('✅ ${_memberData[userId]?.nickname ?? 'User'} $label', isSuccess: true);
    } catch (_) {
      _showToast('❌ Role update failed');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  

  Future<bool?> _showConfirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
    bool isDangerous = false,
  }) =>
      showDialog<bool>(
        context: context,
        builder: (_) => _DarkDialog(
          title: title,
          icon: isDangerous ? Icons.warning_rounded : Icons.help_outline_rounded,
          iconColor: isDangerous ? _danger : _accent,
          content: Text(message, style: const TextStyle(color: _textSecondary, fontSize: 14.5)),
          actions: [
            _DialogBtn(label: 'Cancel', onTap: () => Navigator.pop(context, false)),
            _DialogBtn(
              label: confirmLabel,
              isPrimary: true,
              isDanger: isDangerous,
              onTap: () => Navigator.pop(context, true),
            ),
          ],
        ),
      );

  void _showToast(String msg, {bool isSuccess = false}) {
    Fluttertoast.showToast(
      msg: msg,
      backgroundColor: isSuccess ? const Color(0xFF1A3A2A) : const Color(0xFF3A1A1A),
      textColor: isSuccess ? Colors.greenAccent : Colors.redAccent,
      toastLength: Toast.LENGTH_SHORT,
    );
  }

  

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark(),
      child: Scaffold(
        backgroundColor: _bg,
        body: Stack(
          children: [
            CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                _buildSliverAppBar(),
                SliverToBoxAdapter(child: _buildBody()),
              ],
            ),
            if (_isLoading) const _FullScreenLoader(),
          ],
        ),
      ),
    );
  }

  

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      stretch: true,
      backgroundColor: _bg,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _textPrimary),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        if (_isAdmin)
          TextButton.icon(
            onPressed: _editGroupName,
            icon: const Icon(Icons.edit_rounded, size: 16, color: _accent),
            label:
                const Text('Edit', style: TextStyle(color: _accent, fontWeight: FontWeight.w600)),
          ),
        const SizedBox(width: 8),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: _buildAppBarBackground(),
        collapseMode: CollapseMode.parallax,
      ),
    );
  }

  Widget _buildAppBarBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF131729), _bg],
        ),
      ),
      child: SlideTransition(
        position: _headerSlideAnim,
        child: FadeTransition(
          opacity: _headerFadeAnim,
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 16),
                
                GestureDetector(
                  onTap: _isAdmin ? _changeGroupPhoto : null,
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [_accent, Color(0xFF6B4AE8)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _accent.withValues(alpha: .45),
                              blurRadius: 24,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Hero(
                          tag: 'group_avatar_${_group.id}',
                          child: CircleAvatar(
                            radius: 46,
                            backgroundImage: _group.groupPhotoUrl.isNotEmpty
                                ? NetworkImage(_group.groupPhotoUrl)
                                : null,
                            backgroundColor: Colors.transparent,
                            child: _group.groupPhotoUrl.isEmpty
                                ? const Icon(Icons.group_rounded, size: 48, color: Colors.white)
                                : null,
                          ),
                        ),
                      ),
                      if (_isAdmin)
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: _accent,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: _accentGlow, blurRadius: 8, spreadRadius: 1)
                            ],
                          ),
                          child:
                              const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 14),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                
                GestureDetector(
                  onTap: _isAdmin ? _editGroupName : null,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          _group.groupName,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: _textPrimary,
                            letterSpacing: -.5,
                          ),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                      ),
                      if (_isAdmin) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.edit_rounded, size: 16, color: _textSecondary),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.schedule_rounded, size: 13, color: _textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      'Created ${_formatDate(_group.createdAt)}',
                      style: const TextStyle(color: _textSecondary, fontSize: 13),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _accentGlow,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_group.memberIds.length} members',
                        style: const TextStyle(
                            color: _accent, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  

  Widget _buildBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        _buildActionCards(),
        const SizedBox(height: 20),
        _buildMemberSection(),
        const SizedBox(height: 32),
        if (_isAdmin) _buildDangerZone(),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildActionCards() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _ActionCard(
              icon: Icons.perm_media_rounded,
              label: 'Media',
              sublabel: 'Files & Links',
              color: const Color(0xFF4F8EF7),
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
          const SizedBox(width: 12),
          if (_isAdmin)
            Expanded(
              child: _ActionCard(
                icon: Icons.person_add_rounded,
                label: 'Add',
                sublabel: 'Invite People',
                color: const Color(0xFF43C6AC),
                onTap: _addMembers,
              ),
            ),
          if (!_isAdmin) const Spacer(),
        ],
      ),
    );
  }

  Widget _buildMemberSection() {
    final owners = <String>[];
    final admins = <String>[];
    final members = <String>[];
    for (final uid in _group.memberIds) {
      final role = _getUserRole(uid);
      if (role == 'owner') {
        owners.add(uid);
      } else if (role == 'admin') {
        admins.add(uid);
      } else {
        members.add(uid);
      }
    }
    final sorted = [...owners, ...admins, ...members];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Members',
                  style: TextStyle(color: _textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
              Text('${_group.memberIds.length}',
                  style: const TextStyle(
                      color: _textSecondary, fontSize: 15, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _divider, width: .8),
          ),
          child: Column(
            children: sorted.asMap().entries.map((entry) {
              final i = entry.key;
              final uid = entry.value;
              return Column(
                children: [
                  if (i > 0) const Divider(height: 1, color: _divider, indent: 64),
                  _buildMemberTile(uid),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildMemberTile(String uid) {
    final user = _memberData[uid];
    final isMe = uid == widget.currentUserId;
    final targetRole = _getUserRole(uid);
    final photoUrl = user?.photoUrl ?? '';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
            backgroundColor: _accentGlow,
            child: photoUrl.isEmpty
                ? Text(
                    (user?.nickname ?? 'U').substring(0, 1).toUpperCase(),
                    style: const TextStyle(color: _accent, fontWeight: FontWeight.bold),
                  )
                : null,
          ),
          if (targetRole == 'owner')
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: 16,
                height: 16,
                decoration: const BoxDecoration(color: _gold, shape: BoxShape.circle),
                child: const Icon(Icons.star_rounded, size: 10, color: Colors.black),
              ),
            ),
          if (targetRole == 'admin')
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(color: const Color(0xFF4FD1C5), shape: BoxShape.circle),
                child: const Icon(Icons.shield_rounded, size: 10, color: Colors.black),
              ),
            ),
        ],
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              user?.nickname ?? 'User',
              style:
                  const TextStyle(color: _textPrimary, fontWeight: FontWeight.w600, fontSize: 15),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 6),
            _RoleBadge(label: 'You', color: _accent),
          ],
          if (targetRole == 'owner') ...[
            const SizedBox(width: 6),
            _RoleBadge(label: 'Owner', color: _gold),
          ],
          if (targetRole == 'admin') ...[
            const SizedBox(width: 6),
            _RoleBadge(label: 'Admin', color: const Color(0xFF4FD1C5)),
          ],
        ],
      ),
      subtitle: user?.aboutMe.isNotEmpty == true
          ? Text(
              user!.aboutMe,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _textSecondary, fontSize: 12.5),
            )
          : null,
      trailing: _buildTrailingMenu(uid, targetRole, isMe, user),
    );
  }

  Widget? _buildTrailingMenu(String uid, String targetRole, bool isMe, UserChat? user) {
    if (isMe) return null;

    final menuItems = <PopupMenuEntry<String>>[
      PopupMenuItem(
        value: 'message',
        child: _PopupItem(icon: Icons.chat_bubble_rounded, label: 'Send message'),
      ),
    ];

    if (_isOwner) {
      if (targetRole == 'member') {
        menuItems.add(PopupMenuItem(
          value: 'promote',
          child: _PopupItem(icon: Icons.trending_up_rounded, label: 'Promote to Admin'),
        ));
      } else if (targetRole == 'admin') {
        menuItems.add(PopupMenuItem(
          value: 'demote',
          child: _PopupItem(icon: Icons.trending_down_rounded, label: 'Demote to Member'),
        ));
      }
      menuItems.add(const PopupMenuDivider());
      menuItems.add(PopupMenuItem(
        value: 'remove',
        child: _PopupItem(
            icon: Icons.person_remove_rounded, label: 'Remove from group', isDestructive: true),
      ));
    } else if (_isAdmin && targetRole == 'member') {
      menuItems.add(const PopupMenuDivider());
      menuItems.add(PopupMenuItem(
        value: 'remove',
        child: _PopupItem(
            icon: Icons.person_remove_rounded, label: 'Remove from group', isDestructive: true),
      ));
    }

    return PopupMenuButton<String>(
      onSelected: (val) {
        if (val == 'remove') _removeMember(uid);
        if (val == 'promote') _changeRole(uid, 'admin');
        if (val == 'demote') _changeRole(uid, 'member');
        if (val == 'message') _navigateToPrivateChat(uid, user);
      },
      itemBuilder: (_) => menuItems,
      color: _surfaceHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      icon: const Icon(Icons.more_vert_rounded, color: _textSecondary, size: 20),
    );
  }

  Widget _buildDangerZone() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Danger Zone',
              style: TextStyle(
                  color: _danger, fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: .5)),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _danger.withValues(alpha: .25), width: .8),
            ),
            child: ListTile(
              leading: const Icon(Icons.delete_forever_rounded, color: _danger),
              title: const Text('Disband Group',
                  style: TextStyle(color: _danger, fontWeight: FontWeight.w600)),
              subtitle: const Text('This action cannot be undone',
                  style: TextStyle(color: _textSecondary, fontSize: 12)),
              onTap: () async {
                final confirm = await _showConfirmDialog(
                  title: 'Disband Group',
                  message: 'Are you sure you want to permanently delete "${_group.groupName}"?',
                  confirmLabel: 'Disband',
                  isDangerous: true,
                );
                if (confirm == true && mounted) Navigator.pop(context);
              },
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToPrivateChat(String uid, UserChat? user) {
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

  String _formatDate(String ts) {
    try {
      final dt = DateTime.fromMillisecondsSinceEpoch(int.parse(ts));
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return '';
    }
  }
}





class _AddMembersDialog extends StatefulWidget {
  const _AddMembersDialog({required this.friends});
  final List<UserChat> friends;

  @override
  State<_AddMembersDialog> createState() => _AddMembersDialogState();
}

class _AddMembersDialogState extends State<_AddMembersDialog> {
  final Set<String> _selected = {};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.friends
        .where((f) => f.nickname.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return Dialog(
      backgroundColor: const Color(0xFF181B24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            
            Row(
              children: [
                const Icon(Icons.person_add_rounded, color: Color(0xFF4F8EF7), size: 22),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Add Members',
                      style: TextStyle(
                          color: Color(0xFFEEF2FF), fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                if (_selected.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4F8EF7).withValues(alpha: .15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('${_selected.length} selected',
                        style: const TextStyle(color: Color(0xFF4F8EF7), fontSize: 12)),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0D0F14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                style: const TextStyle(color: Color(0xFFEEF2FF), fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Search friends...',
                  hintStyle: TextStyle(color: Color(0xFF8B93B0)),
                  prefixIcon: Icon(Icons.search_rounded, color: Color(0xFF8B93B0)),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const SizedBox(height: 12),
            
            SizedBox(
              height: 280,
              child: widget.friends.isEmpty
                  ? const Center(
                      child: Text('No friends to add', style: TextStyle(color: Color(0xFF8B93B0))))
                  : filtered.isEmpty
                      ? const Center(
                          child: Text('No results', style: TextStyle(color: Color(0xFF8B93B0))))
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final friend = filtered[i];
                            final isSelected = _selected.contains(friend.id);
                            return _FriendTile(
                              friend: friend,
                              isSelected: isSelected,
                              onToggle: () => setState(() {
                                if (isSelected) {
                                  _selected.remove(friend.id);
                                } else {
                                  _selected.add(friend.id);
                                }
                              }),
                            );
                          },
                        ),
            ),
            const SizedBox(height: 16),
            
            Row(
              children: [
                Expanded(
                  child: _OutlineBtn(
                    label: 'Cancel',
                    onTap: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _PrimaryBtn(
                    label: 'Add  (${_selected.length})',
                    enabled: _selected.isNotEmpty,
                    onTap: () => Navigator.pop(context, _selected.toList()),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}





class _FriendTile extends StatelessWidget {
  const _FriendTile({
    required this.friend,
    required this.isSelected,
    required this.onToggle,
  });

  final UserChat friend;
  final bool isSelected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF4F8EF7).withValues(alpha: .12) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF4F8EF7).withValues(alpha: .4) : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundImage: friend.photoUrl.isNotEmpty ? NetworkImage(friend.photoUrl) : null,
              backgroundColor: const Color(0xFF4F8EF7).withValues(alpha: .2),
              child: friend.photoUrl.isEmpty
                  ? Text(
                      friend.nickname.substring(0, 1).toUpperCase(),
                      style: const TextStyle(color: Color(0xFF4F8EF7), fontWeight: FontWeight.bold),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(friend.nickname,
                      style: const TextStyle(
                          color: Color(0xFFEEF2FF), fontWeight: FontWeight.w600, fontSize: 14.5)),
                  if (friend.aboutMe.isNotEmpty)
                    Text(friend.aboutMe,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFF8B93B0), fontSize: 12)),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? const Color(0xFF4F8EF7) : Colors.transparent,
                border: Border.all(
                  color: isSelected ? const Color(0xFF4F8EF7) : const Color(0xFF8B93B0),
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check_rounded, color: Colors.white, size: 14)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String sublabel;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          color: const Color(0xFF181B24),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: .25), width: .8),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: Color(0xFFEEF2FF), fontWeight: FontWeight.w700, fontSize: 14.5)),
                Text(sublabel, style: const TextStyle(color: Color(0xFF8B93B0), fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: .4)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, color: color, fontWeight: FontWeight.w700, letterSpacing: .3)),
    );
  }
}

class _PopupItem extends StatelessWidget {
  const _PopupItem({required this.icon, required this.label, this.isDestructive = false});
  final IconData icon;
  final String label;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? const Color(0xFFFF5A5A) : const Color(0xFFEEF2FF);
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: color, fontSize: 14)),
      ],
    );
  }
}

class _DarkDialog extends StatelessWidget {
  const _DarkDialog({
    required this.title,
    required this.icon,
    required this.content,
    required this.actions,
    this.iconColor = const Color(0xFF4F8EF7),
  });

  final String title;
  final IconData icon;
  final Color iconColor;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF181B24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          color: Color(0xFFEEF2FF), fontSize: 18, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            content,
            const SizedBox(height: 20),
            Row(
              children: actions
                  .map((a) => Expanded(child: a))
                  .toList()
                  .expand((w) => [w, const SizedBox(width: 10)])
                  .toList()
                ..removeLast(),
            ),
          ],
        ),
      ),
    );
  }
}

class _DarkTextField extends StatelessWidget {
  const _DarkTextField({required this.controller, required this.hint, this.autofocus = false});
  final TextEditingController controller;
  final String hint;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D0F14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        style: const TextStyle(color: Color(0xFFEEF2FF), fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF8B93B0)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    );
  }
}

class _DialogBtn extends StatelessWidget {
  const _DialogBtn({
    required this.label,
    required this.onTap,
    this.isPrimary = false,
    this.isDanger = false,
  });
  final String label;
  final VoidCallback onTap;
  final bool isPrimary;
  final bool isDanger;

  @override
  Widget build(BuildContext context) {
    Color bg = const Color(0xFF252A3A);
    Color fg = const Color(0xFFEEF2FF);
    if (isPrimary && !isDanger) {
      bg = const Color(0xFF4F8EF7);
      fg = Colors.white;
    } else if (isDanger) {
      bg = const Color(0xFFFF5A5A).withValues(alpha: .15);
      fg = const Color(0xFFFF5A5A);
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        alignment: Alignment.center,
        child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 14)),
      ),
    );
  }
}

class _OutlineBtn extends StatelessWidget {
  const _OutlineBtn({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF252A3A)),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: const Text('Cancel',
            style: TextStyle(color: Color(0xFF8B93B0), fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _PrimaryBtn extends StatelessWidget {
  const _PrimaryBtn({required this.label, required this.onTap, this.enabled = true});
  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          gradient:
              enabled ? const LinearGradient(colors: [Color(0xFF4F8EF7), Color(0xFF6B4AE8)]) : null,
          color: enabled ? null : const Color(0xFF252A3A),
          borderRadius: BorderRadius.circular(12),
          boxShadow: enabled
              ? [
                  BoxShadow(
                      color: const Color(0xFF4F8EF7).withValues(alpha: .35),
                      blurRadius: 12,
                      offset: const Offset(0, 4))
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: TextStyle(
                color: enabled ? Colors.white : const Color(0xFF8B93B0),
                fontWeight: FontWeight.w700,
                fontSize: 14)),
      ),
    );
  }
}

class _FullScreenLoader extends StatelessWidget {
  const _FullScreenLoader();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black38,
      child: const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF4F8EF7),
          strokeWidth: 2.5,
        ),
      ),
    );
  }
}


extension GroupCopy on Group {
  Group copyWith({
    String? id,
    String? groupName,
    String? groupPhotoUrl,
    String? adminId,
    List<String>? memberIds,
    Map<String, dynamic>? roles,
    String? createdAt,
  }) {
    return Group(
      id: id ?? this.id,
      groupName: groupName ?? this.groupName,
      groupPhotoUrl: groupPhotoUrl ?? this.groupPhotoUrl,
      adminId: adminId ?? this.adminId,
      memberIds: memberIds ?? this.memberIds,
      roles: roles ?? this.roles,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
