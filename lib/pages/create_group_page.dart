import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_chat_demo/providers/auth_provider.dart';
import 'package:flutter_chat_demo/providers/friend_provider.dart';
import 'package:flutter_chat_demo/providers/home_provider.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CreateGroupPage
// ─────────────────────────────────────────────────────────────────────────────

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
  int _step = 0; // 0 = details, 1 = members

  late AnimationController _fabAnimCtrl;
  late AnimationController _stepAnimCtrl;
  late Animation<double> _fabScale;
  late Animation<Offset> _stepSlide;

  late final String _currentUserId;
  late final FriendProvider _friendProvider;
  late final FirebaseFirestore _firebaseFirestore;

  // ── colour palette ──────────────────────────────────────────────────────────
  static const _bg = Color(0xFF0D0F14);
  static const _surface = Color(0xFF181B24);
  static const _surfaceHigh = Color(0xFF1E2233);
  static const _accent = Color(0xFF4F8EF7);
  static const _accentGlow = Color(0x334F8EF7);
  static const _textPrimary = Color(0xFFEEF2FF);
  static const _textSecondary = Color(0xFF8B93B0);
  static const _divider = Color(0xFF252A3A);

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

  // ── navigation between steps ──────────────────────────────────────────────

  void _goToStep(int step) {
    if (step == 1 && _groupNameController.text.trim().isEmpty) {
      _showToast('❗ Please enter a group name');
      return;
    }
    HapticFeedback.selectionClick();
    _stepAnimCtrl.reset();
    setState(() => _step = step);
    _stepAnimCtrl.forward();
  }

  // ── create ────────────────────────────────────────────────────────────────

  Future<void> _createGroup() async {
    if (_groupNameController.text.trim().isEmpty) {
      _showToast('❗ Please enter group name');
      return;
    }
    if (_selectedMembers.isEmpty) {
      _showToast('❗ Select at least one member');
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _isLoading = true);

    try {
      final memberIds = [_currentUserId, ..._selectedMembers];
      final now = DateTime.now().millisecondsSinceEpoch.toString();
      final groupName = _groupNameController.text.trim();
      final systemMsg = '$groupName group created';

      // Build initial roles map – creator is owner
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

      _showToast('🎉 Group created!', isSuccess: true);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showToast('❌ Failed to create group: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showToast(String msg, {bool isSuccess = false}) {
    Fluttertoast.showToast(
      msg: msg,
      backgroundColor:
          isSuccess ? const Color(0xFF1A3A2A) : const Color(0xFF3A1A1A),
      textColor: isSuccess ? Colors.greenAccent : Colors.redAccent,
    );
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark(),
      child: Scaffold(
        backgroundColor: _bg,
        body: Stack(
          children: [
            Column(
              children: [
                _buildHeader(),
                _buildStepIndicator(),
                Expanded(
                  child: SlideTransition(
                    position: _stepSlide,
                    child:
                        _step == 0 ? _buildDetailsStep() : _buildMembersStep(),
                  ),
                ),
              ],
            ),
            if (_isLoading) const _FullScreenLoader(),
          ],
        ),
        floatingActionButton: _step == 0
            ? null
            : ScaleTransition(
                scale: _fabScale,
                child: FloatingActionButton.extended(
                  onPressed: _selectedMembers.isNotEmpty ? _createGroup : null,
                  backgroundColor: _selectedMembers.isNotEmpty
                      ? _accent
                      : const Color(0xFF252A3A),
                  icon: const Icon(Icons.check_rounded),
                  label: Text(
                    'Create${_selectedMembers.isNotEmpty ? ' (${_selectedMembers.length})' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
      ),
    );
  }

  // ── header ────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      color: _bg,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: Icon(
                  _step == 0
                      ? Icons.close_rounded
                      : Icons.arrow_back_ios_new_rounded,
                  color: _textPrimary,
                ),
                onPressed: _step == 0
                    ? () => Navigator.pop(context)
                    : () => _goToStep(0),
              ),
              const SizedBox(width: 4),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _step == 0 ? 'New Group' : 'Add Members',
                    style: const TextStyle(
                        color: _textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.4),
                  ),
                  Text(
                    _step == 0
                        ? 'Step 1 of 2 — Group details'
                        : 'Step 2 of 2 — Select participants',
                    style:
                        const TextStyle(color: _textSecondary, fontSize: 12.5),
                  ),
                ],
              ),
              const Spacer(),
              if (_step == 0)
                _PrimarySmallBtn(
                  label: 'Next →',
                  onTap: () => _goToStep(1),
                  enabled: _groupNameController.text.trim().isNotEmpty,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _step == 0 ? 0.5 : 1.0,
                backgroundColor: _divider,
                valueColor: const AlwaysStoppedAnimation<Color>(_accent),
                minHeight: 3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── step 0: group details ─────────────────────────────────────────────────

  Widget _buildDetailsStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar placeholder
          Center(
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF4F8EF7), Color(0xFF6B4AE8)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _accent.withOpacity(.35),
                        blurRadius: 20,
                        spreadRadius: 2,
                      )
                    ],
                  ),
                  child: const Icon(Icons.group_rounded,
                      size: 44, color: Colors.white),
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: _accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: _bg, width: 2),
                  ),
                  child: const Icon(Icons.camera_alt_rounded,
                      size: 14, color: Colors.white),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          // Group name
          const _FieldLabel(label: 'Group Name', required: true),
          const SizedBox(height: 8),
          _DarkInput(
            controller: _groupNameController,
            hint: 'e.g.  🚀 Project Avengers',
            maxLength: 50,
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${_groupNameController.text.length}/50',
              style: const TextStyle(color: _textSecondary, fontSize: 11.5),
            ),
          ),
          const SizedBox(height: 20),
          // Description
          const _FieldLabel(label: 'Description', required: false),
          const SizedBox(height: 8),
          _DarkInput(
            controller: _descController,
            hint: 'What is this group about?',
            maxLines: 3,
            maxLength: 150,
          ),
          const SizedBox(height: 28),
          // Tips card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _accentGlow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _accent.withOpacity(.25), width: .8),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb_rounded,
                    color: Color(0xFFFFB84D), size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Give your group a clear name and description so members know what it\'s about.',
                    style: TextStyle(
                        color: _textSecondary, fontSize: 13, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          // Continue button
          SizedBox(
            width: double.infinity,
            child: _GradientBtn(
              label: 'Continue — Select Members',
              icon: Icons.people_rounded,
              onTap: () => _goToStep(1),
              enabled: _groupNameController.text.trim().isNotEmpty,
            ),
          ),
        ],
      ),
    );
  }

  // ── step 1: select members ────────────────────────────────────────────────

  Widget _buildMembersStep() {
    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Container(
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _divider, width: .8),
            ),
            child: TextField(
              style: const TextStyle(color: _textPrimary, fontSize: 15),
              decoration: const InputDecoration(
                hintText: 'Search friends...',
                hintStyle: TextStyle(color: _textSecondary),
                prefixIcon: Icon(Icons.search_rounded, color: _textSecondary),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 13),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
        ),
        // Selected chips
        if (_selectedMembers.isNotEmpty) _buildSelectedChips(),
        // Friend list
        Expanded(child: _buildFriendsList()),
      ],
    );
  }

  Widget _buildSelectedChips() {
    return SizedBox(
      height: 50,
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
                  height: 32,
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                );
              }
              final user = UserChat.fromDocument(snap.data!);
              return Container(
                margin: const EdgeInsets.only(right: 8),
                child: Chip(
                  backgroundColor: _accentGlow,
                  side: BorderSide(color: _accent.withOpacity(.4), width: .8),
                  labelPadding: const EdgeInsets.symmetric(horizontal: 2),
                  avatar: CircleAvatar(
                    backgroundImage: user.photoUrl.isNotEmpty
                        ? NetworkImage(user.photoUrl)
                        : null,
                    backgroundColor: _accent.withOpacity(.3),
                    child: user.photoUrl.isEmpty
                        ? Text(
                            user.nickname.substring(0, 1).toUpperCase(),
                            style: const TextStyle(
                                color: _accent,
                                fontSize: 11,
                                fontWeight: FontWeight.bold),
                          )
                        : null,
                  ),
                  label: Text(user.nickname,
                      style: const TextStyle(
                          color: _accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  deleteIcon:
                      const Icon(Icons.close_rounded, size: 14, color: _accent),
                  onDeleted: () => setState(() => _selectedMembers.remove(uid)),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildFriendsList() {
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
                      color: _surface,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.people_outline_rounded,
                        size: 44, color: _textSecondary),
                  ),
                  const SizedBox(height: 16),
                  const Text('No friends yet',
                      style: TextStyle(
                          color: _textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  const Text('Add friends to start a group',
                      style: TextStyle(color: _textSecondary, fontSize: 14)),
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
                        if (isSelected) {
                          _selectedMembers.remove(friendId);
                        } else {
                          _selectedMembers.add(friendId);
                        }
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? _accentGlow : _surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color:
                              isSelected ? _accent.withOpacity(.5) : _divider,
                          width: .8,
                        ),
                      ),
                      child: Row(
                        children: [
                          // Avatar
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundImage: user.photoUrl.isNotEmpty
                                    ? NetworkImage(user.photoUrl)
                                    : null,
                                backgroundColor: _accent.withOpacity(.2),
                                child: user.photoUrl.isEmpty
                                    ? Text(
                                        user.nickname
                                            .substring(0, 1)
                                            .toUpperCase(),
                                        style: const TextStyle(
                                            color: _accent,
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
                                    decoration: const BoxDecoration(
                                      color: _accent,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.check_rounded,
                                        color: Colors.white, size: 12),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(width: 14),
                          // Info
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user.nickname,
                                  style: TextStyle(
                                    color: isSelected ? _accent : _textPrimary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                                if (user.aboutMe.isNotEmpty)
                                  Text(
                                    user.aboutMe,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: _textSecondary, fontSize: 12.5),
                                  ),
                              ],
                            ),
                          ),
                          // Checkbox indicator
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSelected ? _accent : Colors.transparent,
                              border: Border.all(
                                color: isSelected ? _accent : _textSecondary,
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

// ─────────────────────────────────────────────────────────────────────────────
// Shared sub-widgets (local to this file)
// ─────────────────────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label, required this.required});
  final String label;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label,
            style: const TextStyle(
                color: Color(0xFF8B93B0),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: .4)),
        if (required)
          const Text(' *',
              style: TextStyle(
                  color: Color(0xFFFF5A5A),
                  fontSize: 13,
                  fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _DarkInput extends StatelessWidget {
  const _DarkInput({
    required this.controller,
    required this.hint,
    this.maxLines = 1,
    this.maxLength,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final int? maxLength;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF181B24),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF252A3A), width: .8),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        maxLength: maxLength,
        textCapitalization: textCapitalization,
        style: const TextStyle(color: Color(0xFFEEF2FF), fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF8B93B0)),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          counterStyle: const TextStyle(color: Color(0xFF8B93B0), fontSize: 11),
        ),
      ),
    );
  }
}

class _GradientBtn extends StatelessWidget {
  const _GradientBtn({
    required this.label,
    required this.icon,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 52,
        decoration: BoxDecoration(
          gradient: enabled
              ? const LinearGradient(
                  colors: [Color(0xFF4F8EF7), Color(0xFF6B4AE8)])
              : null,
          color: enabled ? null : const Color(0xFF252A3A),
          borderRadius: BorderRadius.circular(16),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: const Color(0xFF4F8EF7).withOpacity(.35),
                    blurRadius: 16,
                    offset: const Offset(0, 5),
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                color: enabled ? Colors.white : const Color(0xFF8B93B0),
                size: 20),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: enabled ? Colors.white : const Color(0xFF8B93B0),
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrimarySmallBtn extends StatelessWidget {
  const _PrimarySmallBtn(
      {required this.label, required this.onTap, this.enabled = true});
  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: enabled
              ? const LinearGradient(
                  colors: [Color(0xFF4F8EF7), Color(0xFF6B4AE8)])
              : null,
          color: enabled ? null : const Color(0xFF252A3A),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: enabled ? Colors.white : const Color(0xFF8B93B0),
            fontWeight: FontWeight.w700,
            fontSize: 13.5,
          ),
        ),
      ),
    );
  }
}

class _FullScreenLoader extends StatelessWidget {
  const _FullScreenLoader();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black45,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              color: Color(0xFF4F8EF7),
              strokeWidth: 2.5,
            ),
            SizedBox(height: 16),
            Text(
              'Creating group...',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
