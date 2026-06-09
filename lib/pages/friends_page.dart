import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_chat_demo/pages/pages.dart';
import 'package:flutter_chat_demo/providers/providers.dart';
import 'package:flutter_chat_demo/providers/theme_provider.dart';
import 'package:flutter_chat_demo/widgets/widgets.dart';

class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key});

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
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
    final theme = context.watch<ThemeProvider>();
    final p = theme.palette;

    return Theme(
      data: theme.isDark ? theme.darkTheme : theme.lightTheme,
      child: Scaffold(
        backgroundColor: p.background,
        body: NestedScrollView(
          headerSliverBuilder: (ctx, innerScrolled) => [
            SliverAppBar(
              expandedHeight: 120,
              pinned: true,
              floating: false,
              elevation: 0,
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              systemOverlayStyle: theme.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
              leading: IconButton(
                icon: Icon(Icons.arrow_back_ios_new_rounded, color: theme.primaryColor, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 56),
                title: Text(
                  'Bạn bè',
                  style: TextStyle(
                    color: p.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                    letterSpacing: -0.5,
                  ),
                ),
                background: Container(color: p.appBarBackground),
              ),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: Container(
                  color: p.appBarBackground,
                  child: TabBar(
                    controller: _tabController,
                    indicatorColor: theme.primaryColor,
                    indicatorWeight: 3,
                    indicatorSize: TabBarIndicatorSize.label,
                    labelColor: theme.primaryColor,
                    unselectedLabelColor: p.textSecondary,
                    labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w400, fontSize: 14),
                    tabs: const [
                      Tab(text: 'Bạn bè của tôi'),
                      Tab(text: 'Gợi ý'),
                    ],
                  ),
                ),
              ),
            ),
          ],
          body: TabBarView(
            controller: _tabController,
            children: [
              _MyFriendsTab(
                currentUserId: _currentUserId,
                friendProvider: _friendProvider,
                firebaseFirestore: _firebaseFirestore,
                palette: p,
                primary: theme.primaryColor,
              ),
              _SuggestionsTab(
                currentUserId: _currentUserId,
                friendProvider: _friendProvider,
                firebaseFirestore: _firebaseFirestore,
                palette: p,
                primary: theme.primaryColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── My Friends Tab ───────────────────────────────────────────────────────────

class _MyFriendsTab extends StatelessWidget {
  final String currentUserId;
  final FriendProvider friendProvider;
  final FirebaseFirestore firebaseFirestore;
  final ThemePalette palette;
  final Color primary;

  const _MyFriendsTab({
    required this.currentUserId,
    required this.friendProvider,
    required this.firebaseFirestore,
    required this.palette,
    required this.primary,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: friendProvider.getFriendsList(currentUserId),
      builder: (_, snap1) => StreamBuilder<QuerySnapshot>(
        stream: friendProvider.getFriendsList2(currentUserId),
        builder: (_, snap2) {
          final waiting = snap1.connectionState == ConnectionState.waiting &&
              snap2.connectionState == ConnectionState.waiting;

          if (waiting) return _FriendListSkeleton(palette: palette);

          final all = [...(snap1.data?.docs ?? []), ...(snap2.data?.docs ?? [])];

          if (all.isEmpty) return _EmptyFriendsState(palette: palette, primary: primary);

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            itemCount: all.length,
            itemBuilder: (_, i) {
              final friendship = Friendship.fromDocument(all[i]);
              final friendId = friendship.userId1 == currentUserId
                  ? friendship.userId2
                  : friendship.userId1;

              return FutureBuilder<DocumentSnapshot>(
                future: firebaseFirestore
                    .collection(FirestoreConstants.pathUserCollection)
                    .doc(friendId)
                    .get(),
                builder: (_, snap) {
                  if (!snap.hasData) return _FriendTileSkeleton(palette: palette);
                  final user = UserChat.fromDocument(snap.data!);
                  return _FriendTile(
                    user: user,
                    palette: palette,
                    primary: primary,
                    index: i,
                    currentUserId: currentUserId,
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

class _FriendTile extends StatefulWidget {
  final UserChat user;
  final ThemePalette palette;
  final Color primary;
  final int index;
  final String currentUserId;

  const _FriendTile({
    required this.user,
    required this.palette,
    required this.primary,
    required this.index,
    required this.currentUserId,
  });

  @override
  State<_FriendTile> createState() => _FriendTileState();
}

class _FriendTileState extends State<_FriendTile> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: Duration(milliseconds: 320 + widget.index * 50));
    _slide = Tween<Offset>(begin: const Offset(0, 0.14), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    Future.delayed(Duration(milliseconds: widget.index * 50), () => mounted ? _ctrl.forward() : null);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => Navigator.push(context, _slideRoute(UserProfilePage(userChat: u))),
              borderRadius: BorderRadius.circular(16),
              splashColor: widget.primary.withValues(alpha: 0.06),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: widget.palette.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: widget.palette.divider, width: 0.6),
                  boxShadow: [
                    BoxShadow(
                        color: widget.palette.shadow,
                        blurRadius: 10,
                        offset: const Offset(0, 3)
                    )
                  ],
                ),
                child: Row(
                  children: [
                    AvatarWithStatus(
                        userId: u.id,
                        photoUrl: u.photoUrl,
                        size: 52,
                        indicatorSize: 13
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              u.nickname,
                              style: TextStyle(
                                  color: widget.palette.textPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15
                              )
                          ),
                          const SizedBox(height: 3),
                          Text(
                            u.aboutMe.isNotEmpty ? u.aboutMe : 'Chưa có tiểu sử',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: widget.palette.textSecondary,
                              fontSize: 12,
                              fontStyle: u.aboutMe.isEmpty ? FontStyle.italic : FontStyle.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _IconActionBtn(
                      icon: Icons.message_rounded,
                      color: widget.primary,
                      tooltip: 'Nhắn tin',
                      onTap: () => Navigator.push(
                          context,
                          _slideRoute(ChatPage(
                            arguments: ChatPageArguments(
                                peerId: u.id,
                                peerAvatar: u.photoUrl,
                                peerNickname: u.nickname
                            ),
                          ))
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Suggestions Tab ──────────────────────────────────────────────────────────

class _SuggestionsTab extends StatefulWidget {
  final String currentUserId;
  final FriendProvider friendProvider;
  final FirebaseFirestore firebaseFirestore;
  final ThemePalette palette;
  final Color primary;

  const _SuggestionsTab({
    required this.currentUserId,
    required this.friendProvider,
    required this.firebaseFirestore,
    required this.palette,
    required this.primary,
  });

  @override
  State<_SuggestionsTab> createState() => _SuggestionsTabState();
}

class _SuggestionsTabState extends State<_SuggestionsTab> {
  List<String> _myFriendIds = [];
  Map<String, List<String>> _mutualFriendsMap = {};
  bool _isLoading = true;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) {
    if (!_isDisposed && mounted) setState(fn);
  }

  Future<void> _loadSuggestions() async {
    _safeSetState(() => _isLoading = true);

    try {
      final fs1 = await widget.firebaseFirestore
          .collection(FirestoreConstants.pathFriendshipCollection)
          .where(FirestoreConstants.userId1, isEqualTo: widget.currentUserId)
          .get();

      final fs2 = await widget.firebaseFirestore
          .collection(FirestoreConstants.pathFriendshipCollection)
          .where(FirestoreConstants.userId2, isEqualTo: widget.currentUserId)
          .get();

      final myFriends = <String>{};
      for (var d in fs1.docs) myFriends.add(Friendship.fromDocument(d).userId2);
      for (var d in fs2.docs) myFriends.add(Friendship.fromDocument(d).userId1);

      _myFriendIds = myFriends.toList();
      final mutualMap = <String, List<String>>{};

      for (var friendId in _myFriendIds) {
        final ff1 = await widget.firebaseFirestore
            .collection(FirestoreConstants.pathFriendshipCollection)
            .where(FirestoreConstants.userId1, isEqualTo: friendId)
            .get();

        final ff2 = await widget.firebaseFirestore
            .collection(FirestoreConstants.pathFriendshipCollection)
            .where(FirestoreConstants.userId2, isEqualTo: friendId)
            .get();

        for (var d in ff1.docs) {
          final uid = Friendship.fromDocument(d).userId2;
          if (uid != widget.currentUserId && !_myFriendIds.contains(uid)) {
            mutualMap.putIfAbsent(uid, () => []).add(friendId);
          }
        }
        for (var d in ff2.docs) {
          final uid = Friendship.fromDocument(d).userId1;
          if (uid != widget.currentUserId && !_myFriendIds.contains(uid)) {
            mutualMap.putIfAbsent(uid, () => []).add(friendId);
          }
        }
      }
      _safeSetState(() {
        _mutualFriendsMap = mutualMap;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading suggestions: $e');
      _safeSetState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return _FriendListSkeleton(palette: widget.palette);

    if (_mutualFriendsMap.isEmpty) {
      return _EmptySuggestionsState(palette: widget.palette, primary: widget.primary);
    }

    final sorted = _mutualFriendsMap.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));

    return RefreshIndicator(
      onRefresh: _loadSuggestions,
      color: widget.primary,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        itemCount: sorted.length,
        itemBuilder: (_, i) {
          final userId = sorted[i].key;
          final mutualCount = sorted[i].value.length;

          return FutureBuilder<DocumentSnapshot>(
            future: widget.firebaseFirestore
                .collection(FirestoreConstants.pathUserCollection)
                .doc(userId)
                .get(),
            builder: (_, snap) {
              if (!snap.hasData) return _FriendTileSkeleton(palette: widget.palette);
              final user = UserChat.fromDocument(snap.data!);
              return _SuggestionTile(
                user: user,
                mutualCount: mutualCount,
                palette: widget.palette,
                primary: widget.primary,
                index: i,
                friendProvider: widget.friendProvider,
                currentUserId: widget.currentUserId,
                onRefresh: _loadSuggestions,
              );
            },
          );
        },
      ),
    );
  }
}

class _SuggestionTile extends StatefulWidget {
  final UserChat user;
  final int mutualCount, index;
  final ThemePalette palette;
  final Color primary;
  final FriendProvider friendProvider;
  final String currentUserId;
  final VoidCallback onRefresh;

  const _SuggestionTile({
    required this.user,
    required this.mutualCount,
    required this.palette,
    required this.primary,
    required this.index,
    required this.friendProvider,
    required this.currentUserId,
    required this.onRefresh,
  });

  @override
  State<_SuggestionTile> createState() => _SuggestionTileState();
}

class _SuggestionTileState extends State<_SuggestionTile> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;
  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: Duration(milliseconds: 320 + widget.index * 50));
    _slide = Tween<Offset>(begin: const Offset(0, 0.14), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    Future.delayed(Duration(milliseconds: widget.index * 50), () => mounted ? _ctrl.forward() : null);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _addFriend() async {
    if (_requesting) return;
    setState(() => _requesting = true);
    HapticFeedback.lightImpact();

    final success = await widget.friendProvider.sendFriendRequest(widget.currentUserId, widget.user.id);
    if (!mounted) return;

    setState(() => _requesting = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã gửi lời mời kết bạn tới ${widget.user.nickname}'),
            backgroundColor: Colors.green[700],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          )
      );
      widget.onRefresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    final colorIdx = u.nickname.isEmpty ? 0 : u.nickname.codeUnitAt(0) % ColorConstants.avatarColors.length;
    final avatarColor = ColorConstants.avatarColors[colorIdx];

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => Navigator.push(context, _slideRoute(UserProfilePage(userChat: u))),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: widget.palette.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: widget.primary.withValues(alpha: 0.15), width: 0.8),
                  boxShadow: [
                    BoxShadow(
                        color: widget.palette.shadow,
                        blurRadius: 8,
                        offset: const Offset(0, 3)
                    )
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: avatarColor.withValues(alpha: 0.12),
                        border: Border.all(color: avatarColor.withValues(alpha: 0.25), width: 1.5),
                      ),
                      child: ClipOval(
                          child: u.photoUrl.isNotEmpty
                              ? Image.network(
                              u.photoUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Center(
                                  child: Text(
                                      u.nickname.isNotEmpty ? u.nickname[0].toUpperCase() : '?',
                                      style: TextStyle(color: avatarColor, fontWeight: FontWeight.w700, fontSize: 20)
                                  )
                              )
                          )
                              : Center(
                              child: Text(
                                  u.nickname.isNotEmpty ? u.nickname[0].toUpperCase() : '?',
                                  style: TextStyle(color: avatarColor, fontWeight: FontWeight.w700, fontSize: 20)
                              )
                          )
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              u.nickname,
                              style: TextStyle(
                                  color: widget.palette.textPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15
                              )
                          ),
                          const SizedBox(height: 4),
                          Row(
                              children: [
                                Icon(Icons.people_rounded, size: 13, color: widget.primary),
                                const SizedBox(width: 4),
                                Text(
                                    '${widget.mutualCount} bạn chung',
                                    style: TextStyle(color: widget.primary, fontSize: 12, fontWeight: FontWeight.w500)
                                ),
                              ]
                          ),
                          if (u.aboutMe.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                                u.aboutMe,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: widget.palette.textSecondary, fontSize: 12)
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _requesting
                        ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: widget.primary)
                    )
                        : _IconActionBtn(
                        icon: Icons.person_add_rounded,
                        color: widget.primary,
                        tooltip: 'Kết bạn',
                        onTap: _addFriend
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Shared Widgets ───────────────────────────────────────────────────────────

class _IconActionBtn extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _IconActionBtn({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap
  });

  @override
  State<_IconActionBtn> createState() => _IconActionBtnState();
}

class _IconActionBtnState extends State<_IconActionBtn> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 80));
    _scale = Tween<double>(begin: 1.0, end: 0.85).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: GestureDetector(
        onTapDown: (_) => _ctrl.forward(),
        onTapUp: (_) {
          _ctrl.reverse();
          widget.onTap();
        },
        onTapCancel: () => _ctrl.reverse(),
        child: ScaleTransition(
          scale: _scale,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: widget.color.withValues(alpha: 0.25)),
            ),
            child: Icon(widget.icon, color: widget.color, size: 20),
          ),
        ),
      ),
    );
  }
}

class _EmptyFriendsState extends StatelessWidget {
  final ThemePalette palette;
  final Color primary;

  const _EmptyFriendsState({required this.palette, required this.primary});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.07),
                  shape: BoxShape.circle
              ),
              child: Icon(Icons.people_outline_rounded, size: 40, color: primary.withValues(alpha: 0.4)),
            ),
            const SizedBox(height: 20),
            Text(
                'Chưa có bạn bè nào',
                style: TextStyle(color: palette.textSecondary, fontSize: 17, fontWeight: FontWeight.w600)
            ),
            const SizedBox(height: 8),
            Text(
                'Thêm bạn để bắt đầu trò chuyện',
                style: TextStyle(color: palette.textSecondary, fontSize: 13)
            ),
          ]
      ),
    );
  }
}

class _EmptySuggestionsState extends StatelessWidget {
  final ThemePalette palette;
  final Color primary;

  const _EmptySuggestionsState({required this.palette, required this.primary});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.07),
                  shape: BoxShape.circle
              ),
              child: Icon(Icons.person_search_rounded, size: 40, color: primary.withValues(alpha: 0.4)),
            ),
            const SizedBox(height: 20),
            Text(
                'Chưa có gợi ý nào',
                style: TextStyle(color: palette.textSecondary, fontSize: 17, fontWeight: FontWeight.w600)
            ),
            const SizedBox(height: 8),
            Text(
                'Thêm nhiều bạn hơn để nhận gợi ý',
                style: TextStyle(color: palette.textSecondary, fontSize: 13)
            ),
          ]
      ),
    );
  }
}

class _FriendListSkeleton extends StatefulWidget {
  final ThemePalette palette;

  const _FriendListSkeleton({required this.palette});

  @override
  State<_FriendListSkeleton> createState() => _FriendListSkeletonState();
}

class _FriendListSkeletonState extends State<_FriendListSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final c = Color.lerp(widget.palette.surface, widget.palette.surfaceVariant, _anim.value)!;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            children: List.generate(
                7,
                    (_) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(16)),
                  child: Row(
                      children: [
                        CircleAvatar(radius: 26, backgroundColor: widget.palette.divider),
                        const SizedBox(width: 14),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                      height: 13,
                                      width: 130,
                                      decoration: BoxDecoration(
                                          color: widget.palette.divider,
                                          borderRadius: BorderRadius.circular(6)
                                      )
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                      height: 10,
                                      width: 180,
                                      decoration: BoxDecoration(
                                          color: widget.palette.divider.withValues(alpha: 0.6),
                                          borderRadius: BorderRadius.circular(5)
                                      )
                                  ),
                                ]
                            )
                        ),
                      ]
                  ),
                )
            ),
          ),
        );
      },
    );
  }
}

class _FriendTileSkeleton extends StatelessWidget {
  final ThemePalette palette;

  const _FriendTileSkeleton({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(16)),
      child: Row(
          children: [
            CircleAvatar(radius: 26, backgroundColor: palette.divider),
            const SizedBox(width: 14),
            Expanded(
                child: Container(
                    height: 12,
                    width: 120,
                    decoration: BoxDecoration(
                        color: palette.divider,
                        borderRadius: BorderRadius.circular(6)
                    )
                )
            ),
          ]
      ),
    );
  }
}

PageRoute _slideRoute(Widget page) => PageRouteBuilder(
  pageBuilder: (_, a, __) => page,
  transitionsBuilder: (_, a, __, child) => SlideTransition(
    position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
        .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
    child: child,
  ),
  transitionDuration: const Duration(milliseconds: 280),
);