import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_chat_demo/pages/pages.dart';
import 'package:flutter_chat_demo/providers/providers.dart';
import 'package:flutter_chat_demo/providers/theme_provider.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

class GroupInfoPage extends StatefulWidget {
  const GroupInfoPage({
    super.key,
    required this.group,
    required this.currentUserId,
    required this.memberNames
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

  late AnimationController _headerCtrl;
  late Animation<double> _headerFade;
  late Animation<Offset> _headerSlide;

  @override
  void initState() {
    super.initState();
    _group = widget.group;
    _checkRoles();
    _loadMemberData();

    _headerCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _headerFade = CurvedAnimation(parent: _headerCtrl, curve: Curves.easeOut);
    _headerSlide = Tween<Offset>(begin: const Offset(0, .12), end: Offset.zero)
        .animate(CurvedAnimation(parent: _headerCtrl, curve: Curves.easeOutCubic));
    _headerCtrl.forward();
  }

  @override
  void dispose() {
    _headerCtrl.dispose();
    super.dispose();
  }

  void _checkRoles() {
    String role = _group.roles[widget.currentUserId] ?? 'member';
    if (_group.adminId == widget.currentUserId && role == 'member') {
      role = 'owner';
    }
    _isOwner = role == 'owner';
    _isAdmin = role == 'admin' || _isOwner;
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
        if (doc.exists) {
          data[uid] = UserChat.fromDocument(doc);
        }
      } catch (_) {}
    }
    if (mounted) setState(() => _memberData = data);
  }

  Future<void> _changeGroupPhoto(ThemeProvider theme) async {
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
      _toast('✅ Đã cập nhật ảnh nhóm', isSuccess: true);
    } catch (e) {
      _toast('❌ Không thể cập nhật ảnh');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _editGroupName(ThemeProvider theme) async {
    if (!_isAdmin) return;
    HapticFeedback.selectionClick();
    final p = theme.palette;
    final ctrl = TextEditingController(text: _group.groupName);

    final newName = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: p.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Đổi tên nhóm', style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: p.textPrimary),
          decoration: InputDecoration(
            hintText: 'Tên nhóm...',
            hintStyle: TextStyle(color: p.textSecondary),
            filled: true,
            fillColor: p.surfaceVariant,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: theme.primaryColor, width: 1.5)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Hủy', style: TextStyle(color: p.textSecondary))
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: Text('Lưu', style: TextStyle(color: theme.primaryColor, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    ctrl.dispose();

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
      _toast('✅ Đã đổi tên nhóm', isSuccess: true);
    } catch (_) {
      _toast('❌ Không thể đổi tên nhóm');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addMembers(ThemeProvider theme) async {
    if (!_isAdmin) return;
    HapticFeedback.lightImpact();
    final friends = await _fetchFriends();

    if (!mounted) return;

    final existing = Set<String>.from(_group.memberIds);
    final selected = await showDialog<List<String>>(
      context: context,
      builder: (_) => _AddMembersDialog(
          friends: friends.where((f) => !existing.contains(f.id)).toList(),
          palette: theme.palette,
          primary: theme.primaryColor
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
        'roles': newRoles
      });

      await FirebaseFirestore.instance
          .collection(FirestoreConstants.pathConversationCollection)
          .doc(_group.id)
          .update({FirestoreConstants.participants: newList});

      setState(() {
        _group = _group.copyWith(memberIds: newList, roles: newRoles);
      });
      await _loadMemberData();
      _toast('✅ Đã thêm ${selected.length} thành viên', isSuccess: true);
    } catch (_) {
      _toast('❌ Không thể thêm thành viên');
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

  Future<void> _removeMember(String userId, ThemeProvider theme) async {
    if (!_isAdmin || userId == widget.currentUserId) return;

    final targetRole = _getUserRole(userId);
    if (!_isOwner && (targetRole == 'owner' || targetRole == 'admin')) {
      _toast('⛔ Không đủ quyền');
      return;
    }

    final p = theme.palette;
    final confirm = await _showConfirmDialog(
        'Xóa thành viên',
        'Bạn muốn xóa ${_memberData[userId]?.nickname ?? 'thành viên này'}?',
        'Xóa',
        p,
        theme
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
        'roles': newRoles
      });

      setState(() {
        _group = _group.copyWith(memberIds: newList, roles: newRoles);
        _memberData.remove(userId);
      });
      _toast('✅ Đã xóa thành viên', isSuccess: true);
    } catch (_) {
      _toast('❌ Không thể xóa thành viên');
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

      final label = newRole == 'admin' ? 'thăng Admin' : 'đặt về Member';
      _toast('✅ ${_memberData[userId]?.nickname ?? 'User'} đã được $label', isSuccess: true);
    } catch (_) {
      _toast('❌ Không thể thay đổi vai trò');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool?> _showConfirmDialog(String title, String message, String confirmLabel, ThemePalette p, ThemeProvider theme) =>
      showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: p.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(title, style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700)),
            content: Text(message, style: TextStyle(color: p.textSecondary)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text('Hủy', style: TextStyle(color: p.textSecondary))
              ),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(confirmLabel, style: TextStyle(color: p.dangerColor, fontWeight: FontWeight.w700))
              ),
            ],
          )
      );

  void _toast(String msg, {bool isSuccess = false}) {
    Fluttertoast.showToast(
        msg: msg,
        backgroundColor: isSuccess ? Colors.green.shade700 : Colors.red.shade700,
        textColor: Colors.white,
        toastLength: Toast.LENGTH_SHORT
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final p = theme.palette;

    return Theme(
      data: theme.isDark ? theme.darkTheme : theme.lightTheme,
      child: Scaffold(
        backgroundColor: p.background,
        body: Stack(
            children: [
              CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  _buildSliverAppBar(p, theme),
                  SliverToBoxAdapter(child: _buildBody(p, theme)),
                ],
              ),
              if (_isLoading)
                Positioned.fill(
                    child: Container(
                        color: Colors.black26,
                        child: Center(
                            child: CircularProgressIndicator(color: theme.primaryColor, strokeWidth: 2.5)
                        )
                    )
                ),
            ]
        ),
      ),
    );
  }

  Widget _buildSliverAppBar(ThemePalette p, ThemeProvider theme) {
    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      stretch: true,
      backgroundColor: p.appBarBackground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: theme.primaryColor),
          onPressed: () => Navigator.pop(context)
      ),
      actions: [
        if (_isAdmin)
          TextButton.icon(
            onPressed: () => _editGroupName(theme),
            icon: Icon(Icons.edit_rounded, size: 15, color: theme.primaryColor),
            label: Text('Sửa', style: TextStyle(color: theme.primaryColor, fontWeight: FontWeight.w600)),
          ),
        const SizedBox(width: 8),
      ],
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.parallax,
        background: _buildHeroBackground(p, theme),
      ),
    );
  }

  Widget _buildHeroBackground(ThemePalette p, ThemeProvider theme) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [theme.primaryColor.withValues(alpha: 0.15), p.background]
        ),
      ),
      child: SlideTransition(
        position: _headerSlide,
        child: FadeTransition(
          opacity: _headerFade,
          child: SafeArea(
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: _isAdmin ? () => _changeGroupPhoto(theme) : null,
                    child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          Container(
                            width: 90,
                            height: 90,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(colors: [theme.primaryColor, theme.primaryLightColor]),
                              boxShadow: [
                                BoxShadow(
                                    color: theme.primaryColor.withValues(alpha: 0.35),
                                    blurRadius: 20,
                                    spreadRadius: 2
                                )
                              ],
                            ),
                            child: Hero(
                              tag: 'group_avatar_${_group.id}',
                              child: CircleAvatar(
                                radius: 44,
                                backgroundImage: _group.groupPhotoUrl.isNotEmpty ? NetworkImage(_group.groupPhotoUrl) : null,
                                backgroundColor: Colors.transparent,
                                child: _group.groupPhotoUrl.isEmpty
                                    ? const Icon(Icons.group_rounded, size: 44, color: Colors.white)
                                    : null,
                              ),
                            ),
                          ),
                          if (_isAdmin)
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                  color: theme.primaryColor,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: p.background, width: 2)
                              ),
                              child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 13),
                            ),
                        ]
                    ),
                  ),
                  const SizedBox(height: 14),
                  GestureDetector(
                    onTap: _isAdmin ? () => _editGroupName(theme) : null,
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                              child: Text(
                                  _group.groupName,
                                  style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      color: p.textPrimary,
                                      letterSpacing: -0.5
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis
                              )
                          ),
                          if (_isAdmin) ...[
                            const SizedBox(width: 6),
                            Icon(Icons.edit_rounded, size: 15, color: p.textSecondary)
                          ],
                        ]
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.schedule_rounded, size: 12, color: p.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                            'Tạo ${_formatDate(_group.createdAt)}',
                            style: TextStyle(color: p.textSecondary, fontSize: 12.5)
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                              color: theme.primaryColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20)
                          ),
                          child: Text(
                              '${_group.memberIds.length} thành viên',
                              style: TextStyle(color: theme.primaryColor, fontSize: 12, fontWeight: FontWeight.w600)
                          ),
                        ),
                      ]
                  ),
                ]
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ThemePalette p, ThemeProvider theme) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          _buildActionCards(p, theme),
          const SizedBox(height: 20),
          _buildMembersSection(p, theme),
          const SizedBox(height: 24),
          if (_isAdmin) _buildDangerZone(p, theme),
          const SizedBox(height: 48),
        ]
    );
  }

  Widget _buildActionCards(ThemePalette p, ThemeProvider theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
          children: [
            Expanded(
                child: _ActionCard(
                  icon: Icons.perm_media_rounded,
                  label: 'Media',
                  sublabel: 'Files & Links',
                  color: theme.primaryColor,
                  palette: p,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => GroupMediaPage(groupId: _group.id, groupName: _group.groupName))
                  ),
                )
            ),
            const SizedBox(width: 12),
            if (_isAdmin)
              Expanded(
                  child: _ActionCard(
                    icon: Icons.person_add_rounded,
                    label: 'Thêm',
                    sublabel: 'Mời thành viên',
                    color: Colors.teal.shade400,
                    palette: p,
                    onTap: () => _addMembers(theme),
                  )
              )
            else
              const Spacer(),
          ]
      ),
    );
  }

  Widget _buildMembersSection(ThemePalette p, ThemeProvider theme) {
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
                children: [
                  Text(
                      'Thành viên',
                      style: TextStyle(color: p.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                        color: p.surfaceVariant,
                        borderRadius: BorderRadius.circular(10)
                    ),
                    child: Text(
                        '${_group.memberIds.length}',
                        style: TextStyle(color: p.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)
                    ),
                  ),
                ]
            ),
          ),
          const SizedBox(height: 12),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: p.divider, width: 0.6)
            ),
            child: Column(
                children: sorted.asMap().entries.map((entry) {
                  final i = entry.key;
                  final uid = entry.value;
                  return Column(
                      children: [
                        if (i > 0) Divider(height: 1, color: p.divider, indent: 64),
                        _buildMemberTile(uid, p, theme),
                      ]
                  );
                }).toList()
            ),
          ),
        ]
    );
  }

  Widget _buildMemberTile(String uid, ThemePalette p, ThemeProvider theme) {
    final user = _memberData[uid];
    final isMe = uid == widget.currentUserId;
    final role = _getUserRole(uid);
    final photoUrl = user?.photoUrl ?? '';
    final colorIdx = (user?.nickname ?? '').isEmpty
        ? 0
        : (user?.nickname ?? '').codeUnitAt(0) % ColorConstants.avatarColors.length;
    final avatarColor = ColorConstants.avatarColors[colorIdx];

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
                radius: 22,
                backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                backgroundColor: avatarColor.withValues(alpha: 0.15),
                child: photoUrl.isEmpty
                    ? Text(
                    (user?.nickname ?? 'U').isNotEmpty ? (user?.nickname ?? 'U')[0].toUpperCase() : '?',
                    style: TextStyle(color: avatarColor, fontWeight: FontWeight.bold)
                )
                    : null
            ),
            if (role == 'owner')
              Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                          color: Color(0xFFFFB84D),
                          shape: BoxShape.circle
                      ),
                      child: const Icon(Icons.star_rounded, size: 10, color: Colors.black)
                  )
              ),
            if (role == 'admin')
              Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                          color: Colors.teal.shade400,
                          shape: BoxShape.circle
                      ),
                      child: const Icon(Icons.shield_rounded, size: 10, color: Colors.white)
                  )
              ),
          ]
      ),
      title: Row(
          children: [
            Flexible(
                child: Text(
                    user?.nickname ?? 'User',
                    style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w600, fontSize: 14.5),
                    overflow: TextOverflow.ellipsis
                )
            ),
            if (isMe) ...[
              const SizedBox(width: 6),
              _RoleBadge(label: 'Bạn', color: theme.primaryColor)
            ],
            if (role == 'owner') ...[
              const SizedBox(width: 6),
              _RoleBadge(label: 'Owner', color: const Color(0xFFFFB84D))
            ],
            if (role == 'admin') ...[
              const SizedBox(width: 6),
              _RoleBadge(label: 'Admin', color: Colors.teal.shade400)
            ],
          ]
      ),
      subtitle: user?.aboutMe.isNotEmpty == true
          ? Text(
          user!.aboutMe,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: p.textSecondary, fontSize: 12)
      )
          : null,
      trailing: isMe ? null : PopupMenuButton<String>(
        onSelected: (val) {
          if (val == 'message') {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ChatPage(
                        arguments: ChatPageArguments(
                            peerId: uid,
                            peerAvatar: user?.photoUrl ?? '',
                            peerNickname: user?.nickname ?? 'User'
                        )
                    )
                )
            );
          }
          if (val == 'promote') _changeRole(uid, 'admin');
          if (val == 'demote') _changeRole(uid, 'member');
          if (val == 'remove') _removeMember(uid, theme);
        },
        itemBuilder: (_) => [
          PopupMenuItem(
              value: 'message',
              child: _PopupItem(icon: Icons.chat_rounded, label: 'Nhắn tin', palette: p)
          ),
          if (_isOwner && role == 'member')
            PopupMenuItem(
                value: 'promote',
                child: _PopupItem(icon: Icons.trending_up_rounded, label: 'Thăng Admin', palette: p)
            ),
          if (_isOwner && role == 'admin')
            PopupMenuItem(
                value: 'demote',
                child: _PopupItem(icon: Icons.trending_down_rounded, label: 'Hạ Member', palette: p)
            ),
          if (_isAdmin && role == 'member') ...[
            const PopupMenuDivider(),
            PopupMenuItem(
                value: 'remove',
                child: _PopupItem(icon: Icons.person_remove_rounded, label: 'Xóa khỏi nhóm', palette: p, isDestructive: true)
            )
          ],
          if (_isOwner && role == 'admin') ...[
            const PopupMenuDivider(),
            PopupMenuItem(
                value: 'remove',
                child: _PopupItem(icon: Icons.person_remove_rounded, label: 'Xóa khỏi nhóm', palette: p, isDestructive: true)
            )
          ],
        ],
        color: p.surfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        icon: Icon(Icons.more_vert_rounded, color: p.textSecondary, size: 20),
      ),
    );
  }

  Widget _buildDangerZone(ThemePalette p, ThemeProvider theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                  'VÙNG NGUY HIỂM',
                  style: TextStyle(
                      color: p.dangerColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8
                  )
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: p.dangerColor.withValues(alpha: 0.3), width: 0.8),
              ),
              child: ListTile(
                leading: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                        color: p.dangerColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10)
                    ),
                    child: Icon(Icons.delete_forever_rounded, color: p.dangerColor, size: 20)
                ),
                title: Text(
                    'Giải tán nhóm',
                    style: TextStyle(color: p.dangerColor, fontWeight: FontWeight.w600)
                ),
                subtitle: Text(
                    'Hành động không thể hoàn tác',
                    style: TextStyle(color: p.textSecondary, fontSize: 12)
                ),
                onTap: () async {
                  final confirm = await _showConfirmDialog(
                      'Giải tán nhóm',
                      'Bạn chắc chắn muốn xóa nhóm "${_group.groupName}" vĩnh viễn?',
                      'Giải tán',
                      p,
                      theme
                  );
                  if (confirm == true && mounted) Navigator.pop(context);
                },
              ),
            ),
          ]
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

// ─── Shared Widgets ───────────────────────────────────────────────────────────

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label, sublabel;
  final Color color;
  final ThemePalette palette;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.color,
    required this.palette,
    required this.onTap
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.2), width: 0.8),
          boxShadow: [
            BoxShadow(color: palette.shadow, blurRadius: 8)
          ],
        ),
        child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10)
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        label,
                        style: TextStyle(
                            color: palette.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 14
                        )
                    ),
                    Text(
                        sublabel,
                        style: TextStyle(color: palette.textSecondary, fontSize: 11.5)
                    ),
                  ]
              ),
            ]
        ),
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _RoleBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: color.withValues(alpha: 0.35))
      ),
      child: Text(
          label,
          style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2
          )
      ),
    );
  }
}

class _PopupItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final ThemePalette palette;
  final bool isDestructive;

  const _PopupItem({
    required this.icon,
    required this.label,
    required this.palette,
    this.isDestructive = false
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? const Color(0xFFFF5A5A) : palette.textPrimary;
    return Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(color: color, fontSize: 14))
        ]
    );
  }
}

class _AddMembersDialog extends StatefulWidget {
  final List<UserChat> friends;
  final ThemePalette palette;
  final Color primary;

  const _AddMembersDialog({
    required this.friends,
    required this.palette,
    required this.primary
  });

  @override
  State<_AddMembersDialog> createState() => _AddMembersDialogState();
}

class _AddMembersDialogState extends State<_AddMembersDialog> {
  final Set<String> _selected = {};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.friends.where((f) => f.nickname.toLowerCase().contains(_query.toLowerCase())).toList();

    return Dialog(
      backgroundColor: widget.palette.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                  children: [
                    Icon(Icons.person_add_rounded, color: widget.primary, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(
                            'Thêm thành viên',
                            style: TextStyle(
                                color: widget.palette.textPrimary,
                                fontSize: 17,
                                fontWeight: FontWeight.w700
                            )
                        )
                    ),
                    if (_selected.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                            color: widget.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20)
                        ),
                        child: Text(
                            '${_selected.length} đã chọn',
                            style: TextStyle(color: widget.primary, fontSize: 12)
                        ),
                      ),
                  ]
              ),
              const SizedBox(height: 14),
              TextField(
                style: TextStyle(color: widget.palette.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Tìm bạn bè...',
                  hintStyle: TextStyle(color: widget.palette.textSecondary),
                  prefixIcon: Icon(Icons.search_rounded, color: widget.palette.textSecondary),
                  filled: true,
                  fillColor: widget.palette.surfaceVariant,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(vertical: 11),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 270,
                child: widget.friends.isEmpty
                    ? Center(child: Text('Không có bạn bè để thêm', style: TextStyle(color: widget.palette.textSecondary)))
                    : filtered.isEmpty
                    ? Center(child: Text('Không tìm thấy', style: TextStyle(color: widget.palette.textSecondary)))
                    : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final f = filtered[i];
                    final isSelected = _selected.contains(f.id);
                    return GestureDetector(
                      onTap: () => setState(() {
                        if (isSelected) {
                          _selected.remove(f.id);
                        } else {
                          _selected.add(f.id);
                        }
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected ? widget.primary.withValues(alpha: 0.1) : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: isSelected ? widget.primary.withValues(alpha: 0.35) : Colors.transparent
                          ),
                        ),
                        child: Row(
                            children: [
                              CircleAvatar(
                                  radius: 20,
                                  backgroundImage: f.photoUrl.isNotEmpty ? NetworkImage(f.photoUrl) : null,
                                  backgroundColor: widget.primary.withValues(alpha: 0.2),
                                  child: f.photoUrl.isEmpty
                                      ? Text(
                                      f.nickname.isNotEmpty ? f.nickname[0].toUpperCase() : '?',
                                      style: TextStyle(color: widget.primary, fontWeight: FontWeight.bold)
                                  )
                                      : null
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            f.nickname,
                                            style: TextStyle(
                                                color: widget.palette.textPrimary,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14.5
                                            )
                                        ),
                                        if (f.aboutMe.isNotEmpty)
                                          Text(
                                              f.aboutMe,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(color: widget.palette.textSecondary, fontSize: 12)
                                          ),
                                      ]
                                  )
                              ),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isSelected ? widget.primary : Colors.transparent,
                                  border: Border.all(
                                      color: isSelected ? widget.primary : widget.palette.textSecondary,
                                      width: 2
                                  ),
                                ),
                                child: isSelected
                                    ? const Icon(Icons.check_rounded, color: Colors.white, size: 13)
                                    : null,
                              ),
                            ]
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              Row(
                  children: [
                    Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                              foregroundColor: widget.palette.textSecondary,
                              side: BorderSide(color: widget.palette.divider),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 12)
                          ),
                          child: const Text('Hủy'),
                        )
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                        child: ElevatedButton(
                          onPressed: _selected.isNotEmpty
                              ? () => Navigator.pop(context, _selected.toList())
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: widget.primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            disabledBackgroundColor: widget.palette.surfaceVariant,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: Text(
                              'Thêm (${_selected.length})',
                              style: const TextStyle(fontWeight: FontWeight.w700)
                          ),
                        )
                    ),
                  ]
              ),
            ]
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
    String? createdAt
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