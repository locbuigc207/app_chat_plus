import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_chat_demo/providers/auth_provider.dart';
import 'package:flutter_chat_demo/providers/friend_provider.dart';
import 'package:flutter_chat_demo/providers/home_provider.dart';
import 'package:flutter_chat_demo/providers/theme_provider.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';

class CreateGroupPage extends StatefulWidget {
  const CreateGroupPage({super.key});

  @override
  State<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<CreateGroupPage>
    with TickerProviderStateMixin {
  final _groupNameController = TextEditingController();
  final _descController = TextEditingController();
  final Set<String> _selectedMembers = {};
  bool _isLoading = false;
  String _searchQuery = '';
  int _step = 0;

  late AnimationController _fabAnimCtrl;
  late AnimationController _stepAnimCtrl;
  late Animation<double> _fabScale;
  late Animation<Offset> _stepSlide;

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

    _fabAnimCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _fabScale = CurvedAnimation(parent: _fabAnimCtrl, curve: Curves.elasticOut);

    _stepAnimCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _stepSlide = Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
        .animate(
            CurvedAnimation(parent: _stepAnimCtrl, curve: Curves.easeOutCubic));
    _stepAnimCtrl.forward();

    _groupNameController.addListener(_onNameChanged);
  }

  void _onNameChanged() {
    if (_groupNameController.text.trim().isNotEmpty) {
      _fabAnimCtrl.forward();
    } else {
      _fabAnimCtrl.reverse();
    }
    setState(() {});
  }

  @override
  void dispose() {
    _fabAnimCtrl.dispose();
    _stepAnimCtrl.dispose();
    _groupNameController
      ..removeListener(_onNameChanged)
      ..dispose();
    _descController.dispose();
    super.dispose();
  }

  void _goToStep(int step) {
    if (step == 1 && _groupNameController.text.trim().isEmpty) {
      _showToast('❗ Vui lòng nhập tên nhóm');
      return;
    }
    HapticFeedback.selectionClick();
    _stepAnimCtrl.reset();
    setState(() => _step = step);
    _stepAnimCtrl.forward();
  }

  Future<void> _createGroup() async {
    if (_groupNameController.text.trim().isEmpty) {
      _showToast('❗ Vui lòng nhập tên nhóm');
      return;
    }
    if (_selectedMembers.isEmpty) {
      _showToast('❗ Chọn ít nhất một thành viên');
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _isLoading = true);

    try {
      final memberIds = [_currentUserId, ..._selectedMembers];
      final now = DateTime.now().millisecondsSinceEpoch.toString();
      final groupName = _groupNameController.text.trim();
      final systemMsg = 'Nhóm $groupName đã được tạo';

      final roles = <String, dynamic>{
        _currentUserId: 'owner',
        for (final id in _selectedMembers) id: 'member',
      };

      final groupDoc = await _firebaseFirestore
          .collection(FirestoreConstants.pathGroupCollection)
          .add({
        FirestoreConstants.groupName: groupName,
        FirestoreConstants.groupPhotoUrl: '',
        FirestoreConstants.adminId: _currentUserId,
        FirestoreConstants.memberIds: memberIds,
        FirestoreConstants.createdAt: now,
        'description': _descController.text.trim(),
        'roles': roles,
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

      _showToast('🎉 Tạo nhóm thành công!', isSuccess: true);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showToast('❌ Không thể tạo nhóm: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showToast(String msg, {bool isSuccess = false}) {
    Fluttertoast.showToast(
      msg: msg,
      backgroundColor: isSuccess ? Colors.green.shade700 : Colors.red.shade700,
      textColor: Colors.white,
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
            Column(
              children: [
                _buildHeader(p, theme),
                _buildStepIndicator(p, theme),
                Expanded(
                  child: SlideTransition(
                    position: _stepSlide,
                    child: _step == 0
                        ? _buildDetailsStep(p, theme)
                        : _buildMembersStep(p, theme),
                  ),
                ),
              ],
            ),
            if (_isLoading) _LoadingOverlay(primary: theme.primaryColor),
          ],
        ),
        floatingActionButton: _step == 0
            ? null
            : ScaleTransition(
                scale: _fabScale,
                child: FloatingActionButton.extended(
                  onPressed: _selectedMembers.isNotEmpty ? _createGroup : null,
                  backgroundColor: _selectedMembers.isNotEmpty
                      ? theme.primaryColor
                      : p.surfaceVariant,
                  icon: Icon(Icons.check_rounded,
                      color: _selectedMembers.isNotEmpty
                          ? Colors.white
                          : p.textSecondary),
                  label: Text(
                    'Tạo nhóm${_selectedMembers.isNotEmpty ? ' (${_selectedMembers.length})' : ''}',
                    style: TextStyle(
                      color: _selectedMembers.isNotEmpty
                          ? Colors.white
                          : p.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildHeader(ThemePalette p, ThemeProvider theme) {
    return Container(
      color: p.appBarBackground,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              IconButton(
                icon: Icon(
                  _step == 0
                      ? Icons.close_rounded
                      : Icons.arrow_back_ios_new_rounded,
                  color: p.textPrimary,
                  size: 20,
                ),
                onPressed: _step == 0
                    ? () => Navigator.pop(context)
                    : () => _goToStep(0),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _step == 0 ? 'Nhóm mới' : 'Thêm thành viên',
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.4,
                      ),
                    ),
                    Text(
                      _step == 0
                          ? 'Bước 1/2 — Thông tin nhóm'
                          : 'Bước 2/2 — Chọn thành viên',
                      style: TextStyle(color: p.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (_step == 0)
                AnimatedOpacity(
                  opacity:
                      _groupNameController.text.trim().isNotEmpty ? 1.0 : 0.4,
                  duration: const Duration(milliseconds: 200),
                  child: GestureDetector(
                    onTap: () => _goToStep(1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [
                          theme.primaryColor,
                          theme.primaryLightColor
                        ]),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Tiếp →',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator(ThemePalette p, ThemeProvider theme) {
    return Container(
      color: p.appBarBackground,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _step == 0 ? 0.5 : 1.0,
              backgroundColor: p.divider,
              valueColor: AlwaysStoppedAnimation<Color>(theme.primaryColor),
              minHeight: 3,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _StepDot(
                  active: true,
                  done: _step > 0,
                  label: 'Chi tiết',
                  primary: theme.primaryColor,
                  palette: p),
              Expanded(
                  child: Divider(
                      color: _step > 0 ? theme.primaryColor : p.divider,
                      thickness: 1.5)),
              _StepDot(
                  active: _step >= 1,
                  done: false,
                  label: 'Thành viên',
                  primary: theme.primaryColor,
                  palette: p),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsStep(ThemePalette p, ThemeProvider theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 60),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [theme.primaryColor, theme.primaryLightColor],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                          color: theme.primaryColor.withValues(alpha: .3),
                          blurRadius: 20,
                          spreadRadius: 2)
                    ],
                  ),
                  child: const Icon(Icons.group_rounded,
                      size: 44, color: Colors.white),
                ),
                GestureDetector(
                  onTap: () {},
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: theme.primaryColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: p.background, width: 2),
                    ),
                    child: const Icon(Icons.camera_alt_rounded,
                        size: 14, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          _FieldLabel(label: 'Tên nhóm *', palette: p),
          const SizedBox(height: 8),
          _ThemedInput(
            controller: _groupNameController,
            hint: 'vd: 🚀 Nhóm dự án Avengers',
            maxLength: 50,
            textCapitalization: TextCapitalization.words,
            palette: p,
            primary: theme.primaryColor,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${_groupNameController.text.length}/50',
                  style: TextStyle(color: p.textSecondary, fontSize: 11.5)),
            ),
          ),
          const SizedBox(height: 20),
          _FieldLabel(label: 'Mô tả (tuỳ chọn)', palette: p),
          const SizedBox(height: 8),
          _ThemedInput(
            controller: _descController,
            hint: 'Nhóm này về chủ đề gì?',
            maxLines: 3,
            maxLength: 150,
            palette: p,
            primary: theme.primaryColor,
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.primaryColor.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: theme.primaryColor.withValues(alpha: .18)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb_outline_rounded,
                    color: Colors.amber.shade600, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Đặt tên rõ ràng giúp các thành viên hiểu mục đích nhóm hơn.',
                    style: TextStyle(
                        color: p.textSecondary, fontSize: 13, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _groupNameController.text.trim().isNotEmpty
                  ? () => _goToStep(1)
                  : null,
              icon: const Icon(Icons.people_rounded, size: 20),
              label: const Text('Tiếp — Chọn thành viên',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primaryColor,
                foregroundColor: Colors.white,
                elevation: 0,
                disabledBackgroundColor: p.surfaceVariant,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMembersStep(ThemePalette p, ThemeProvider theme) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Container(
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: p.divider),
            ),
            child: TextField(
              style: TextStyle(color: p.textPrimary, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Tìm bạn bè...',
                hintStyle: TextStyle(color: p.textSecondary),
                prefixIcon: Icon(Icons.search_rounded, color: p.textSecondary),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 13),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
        ),
        if (_selectedMembers.isNotEmpty) _buildSelectedChips(p, theme),
        Expanded(child: _buildFriendsList(p, theme)),
      ],
    );
  }

  Widget _buildSelectedChips(ThemePalette p, ThemeProvider theme) {
    return SizedBox(
      height: 52,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        itemCount: _selectedMembers.length,
        itemBuilder: (_, i) {
          final uid = _selectedMembers.elementAt(i);
          return FutureBuilder<DocumentSnapshot>(
            future: _firebaseFirestore
                .collection(FirestoreConstants.pathUserCollection)
                .doc(uid)
                .get(),
            builder: (_, snap) {
              if (!snap.hasData) {
                return Container(
                  margin: const EdgeInsets.only(right: 8),
                  width: 80,
                  height: 36,
                  decoration: BoxDecoration(
                      color: p.surface,
                      borderRadius: BorderRadius.circular(20)),
                );
              }
              final user = UserChat.fromDocument(snap.data!);
              return Container(
                margin: const EdgeInsets.only(right: 8),
                child: Chip(
                  backgroundColor: theme.primaryColor.withValues(alpha: 0.1),
                  side: BorderSide(
                      color: theme.primaryColor.withValues(alpha: .3)),
                  avatar: CircleAvatar(
                    backgroundImage: user.photoUrl.isNotEmpty
                        ? NetworkImage(user.photoUrl)
                        : null,
                    backgroundColor: theme.primaryColor.withValues(alpha: .25),
                    child: user.photoUrl.isEmpty
                        ? Text(
                            user.nickname.isNotEmpty
                                ? user.nickname[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                                color: theme.primaryColor,
                                fontSize: 11,
                                fontWeight: FontWeight.bold))
                        : null,
                  ),
                  label: Text(user.nickname,
                      style: TextStyle(
                          color: theme.primaryColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  deleteIcon: Icon(Icons.close_rounded,
                      size: 14, color: theme.primaryColor),
                  onDeleted: () => setState(() => _selectedMembers.remove(uid)),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildFriendsList(ThemePalette p, ThemeProvider theme) {
    return StreamBuilder<QuerySnapshot>(
      stream: _friendProvider.getFriendsList(_currentUserId),
      builder: (_, snap1) => StreamBuilder<QuerySnapshot>(
        stream: _friendProvider.getFriendsList2(_currentUserId),
        builder: (_, snap2) {
          final all = [
            ...(snap1.data?.docs ?? []),
            ...(snap2.data?.docs ?? [])
          ];
          if (all.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                        color: p.surfaceVariant, shape: BoxShape.circle),
                    child: Icon(Icons.people_outline_rounded,
                        size: 44, color: p.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  Text('Chưa có bạn bè',
                      style: TextStyle(
                          color: p.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text('Thêm bạn bè để tạo nhóm',
                      style: TextStyle(color: p.textSecondary, fontSize: 14)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
            physics: const BouncingScrollPhysics(),
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
                  if (_searchQuery.isNotEmpty &&
                      !user.nickname
                          .toLowerCase()
                          .contains(_searchQuery.toLowerCase())) {
                    return const SizedBox.shrink();
                  }
                  final isSelected = _selectedMembers.contains(friendId);
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        if (isSelected)
                          _selectedMembers.remove(friendId);
                        else
                          _selectedMembers.add(friendId);
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? theme.primaryColor.withValues(alpha: 0.08)
                            : p.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected
                              ? theme.primaryColor.withValues(alpha: .4)
                              : p.divider,
                          width: isSelected ? 1.5 : 0.8,
                        ),
                      ),
                      child: Row(
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundImage: user.photoUrl.isNotEmpty
                                    ? NetworkImage(user.photoUrl)
                                    : null,
                                backgroundColor:
                                    theme.primaryColor.withValues(alpha: .15),
                                child: user.photoUrl.isEmpty
                                    ? Text(
                                        user.nickname.isNotEmpty
                                            ? user.nickname[0].toUpperCase()
                                            : '?',
                                        style: TextStyle(
                                            color: theme.primaryColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15),
                                      )
                                    : null,
                              ),
                              if (isSelected)
                                Positioned(
                                  right: -4,
                                  bottom: -4,
                                  child: Container(
                                    width: 18,
                                    height: 18,
                                    decoration: BoxDecoration(
                                        color: theme.primaryColor,
                                        shape: BoxShape.circle),
                                    child: const Icon(Icons.check_rounded,
                                        color: Colors.white, size: 12),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(user.nickname,
                                    style: TextStyle(
                                      color: isSelected
                                          ? theme.primaryColor
                                          : p.textPrimary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    )),
                                if (user.aboutMe.isNotEmpty)
                                  Text(user.aboutMe,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: p.textSecondary,
                                          fontSize: 12.5)),
                              ],
                            ),
                          ),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSelected
                                  ? theme.primaryColor
                                  : Colors.transparent,
                              border: Border.all(
                                color: isSelected
                                    ? theme.primaryColor
                                    : p.textSecondary,
                                width: 2,
                              ),
                            ),
                            child: isSelected
                                ? const Icon(Icons.check_rounded,
                                    color: Colors.white, size: 14)
                                : null,
                          ),
                        ],
                      ),
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

// ── Supporting widgets ─────────────────────────────────────────────────────

class _StepDot extends StatelessWidget {
  final bool active;
  final bool done;
  final String label;
  final Color primary;
  final ThemePalette palette;

  const _StepDot({
    required this.active,
    required this.done,
    required this.label,
    required this.primary,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? primary : palette.surfaceVariant,
            border: Border.all(
                color: active ? primary : palette.divider, width: 1.5),
          ),
          child: Center(
            child: done
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 14)
                : Text('${active ? '●' : '○'}',
                    style: TextStyle(
                      color: active ? Colors.white : palette.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    )),
          ),
        ),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(
              fontSize: 10,
              color: active ? primary : palette.textSecondary,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            )),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  final ThemePalette palette;

  const _FieldLabel({required this.label, required this.palette});

  @override
  Widget build(BuildContext context) {
    return Text(label,
        style: TextStyle(
            color: palette.textSecondary,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            letterSpacing: .3));
  }
}

class _ThemedInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final int? maxLength;
  final TextCapitalization textCapitalization;
  final ThemePalette palette;
  final Color primary;

  const _ThemedInput({
    required this.controller,
    required this.hint,
    required this.palette,
    required this.primary,
    this.maxLines = 1,
    this.maxLength,
    this.textCapitalization = TextCapitalization.none,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.divider),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        maxLength: maxLength,
        textCapitalization: textCapitalization,
        style: TextStyle(color: palette.textPrimary, fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: palette.textSecondary),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          counterStyle: TextStyle(color: palette.textSecondary, fontSize: 11),
        ),
      ),
    );
  }
}

class _LoadingOverlay extends StatelessWidget {
  final Color primary;
  const _LoadingOverlay({required this.primary});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black45,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: primary, strokeWidth: 2.5),
            const SizedBox(height: 14),
            const Text('Đang tạo nhóm...',
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
