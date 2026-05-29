import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_chat_demo/pages/pages.dart';
import 'package:flutter_chat_demo/providers/providers.dart';
import 'package:flutter_chat_demo/widgets/widgets.dart';
import 'package:provider/provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FriendsPage
// ─────────────────────────────────────────────────────────────────────────────

class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key});

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage>
    with SingleTickerProviderStateMixin {
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? ColorConstants.backgroundDark : const Color(0xFFF5F7FF),
      body: NestedScrollView(
        headerSliverBuilder: (ctx, innerScrolled) => [
          SliverAppBar(
            expandedHeight: 130,
            pinned: true,
            floating: false,
            elevation: 0,
            backgroundColor: Colors.transparent,
            systemOverlayStyle:
                isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded,
                  color: isDark ? Colors.white70 : ColorConstants.primaryColor,
                  size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 60),
              title: Text(
                'Bạn bè',
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF1A1D2E),
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                  letterSpacing: -0.5,
                ),
              ),
              background: Container(
                color: isDark ? ColorConstants.surfaceDark : Colors.white,
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: Container(
                color: isDark ? ColorConstants.surfaceDark : Colors.white,
                child: TabBar(
                  controller: _tabController,
                  indicatorColor: ColorConstants.primaryColor,
                  indicatorWeight: 3,
                  indicatorSize: TabBarIndicatorSize.label,
                  labelColor: ColorConstants.primaryColor,
                  unselectedLabelColor: ColorConstants.greyColor,
                  labelStyle: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14),
                  unselectedLabelStyle: const TextStyle(
                      fontWeight: FontWeight.w400, fontSize: 14),
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
              isDark: isDark,
            ),
            _SuggestionsTab(
              currentUserId: _currentUserId,
              friendProvider: _friendProvider,
              firebaseFirestore: _firebaseFirestore,
              isDark: isDark,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// My Friends Tab
// ─────────────────────────────────────────────────────────────────────────────

class _MyFriendsTab extends StatelessWidget {
  final String currentUserId;
  final FriendProvider friendProvider;
  final FirebaseFirestore firebaseFirestore;
  final bool isDark;

  const _MyFriendsTab({
    required this.currentUserId,
    required this.friendProvider,
    required this.firebaseFirestore,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: friendProvider.getFriendsList(currentUserId),
      builder: (_, snap1) {
        return StreamBuilder<QuerySnapshot>(
          stream: friendProvider.getFriendsList2(currentUserId),
          builder: (_, snap2) {
            final isWaiting =
                snap1.connectionState == ConnectionState.waiting &&
                    snap2.connectionState == ConnectionState.waiting;

            if (isWaiting) {
              return const _FriendListSkeleton();
            }

            final all = [
              ...(snap1.data?.docs ?? []),
              ...(snap2.data?.docs ?? []),
            ];

            if (all.isEmpty) {
              return _EmptyFriendsState(isDark: isDark);
            }

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
                    if (!snap.hasData) {
                      return const _FriendTileSkeleton();
                    }
                    final user = UserChat.fromDocument(snap.data!);
                    return _FriendTile(
                        user: user,
                        isDark: isDark,
                        index: i,
                        currentUserId: currentUserId);
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class _FriendTile extends StatefulWidget {
  final UserChat user;
  final bool isDark;
  final int index;
  final String currentUserId;

  const _FriendTile({
    required this.user,
    required this.isDark,
    required this.index,
    required this.currentUserId,
  });

  @override
  State<_FriendTile> createState() => _FriendTileState();
}

class _FriendTileState extends State<_FriendTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 320 + widget.index * 50),
    );
    _slide = Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    Future.delayed(Duration(milliseconds: widget.index * 50),
        () => mounted ? _ctrl.forward() : null);
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
              onTap: () => Navigator.push(
                context,
                _slideRoute(UserProfilePage(userChat: u)),
              ),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color:
                      widget.isDark ? ColorConstants.surfaceDark : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: widget.isDark
                        ? Colors.white.withOpacity(0.07)
                        : Colors.black.withOpacity(0.05),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color:
                          Colors.black.withOpacity(widget.isDark ? 0.18 : 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    AvatarWithStatus(
                      userId: u.id,
                      photoUrl: u.photoUrl,
                      size: 54,
                      indicatorSize: 14,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            u.nickname,
                            style: TextStyle(
                              color: widget.isDark
                                  ? Colors.white
                                  : const Color(0xFF1A1D2E),
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            u.aboutMe.isNotEmpty
                                ? u.aboutMe
                                : 'Chưa có tiểu sử',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: widget.isDark
                                  ? Colors.white38
                                  : Colors.black45,
                              fontSize: 12,
                              fontStyle: u.aboutMe.isEmpty
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _IconActionBtn(
                      icon: Icons.message_rounded,
                      color: ColorConstants.primaryColor,
                      tooltip: 'Nhắn tin',
                      onTap: () => Navigator.push(
                        context,
                        _slideRoute(ChatPage(
                          arguments: ChatPageArguments(
                            peerId: u.id,
                            peerAvatar: u.photoUrl,
                            peerNickname: u.nickname,
                          ),
                        )),
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

// ─────────────────────────────────────────────────────────────────────────────
// Suggestions Tab
// ─────────────────────────────────────────────────────────────────────────────

class _SuggestionsTab extends StatefulWidget {
  final String currentUserId;
  final FriendProvider friendProvider;
  final FirebaseFirestore firebaseFirestore;
  final bool isDark;

  const _SuggestionsTab({
    required this.currentUserId,
    required this.friendProvider,
    required this.firebaseFirestore,
    required this.isDark,
  });

  @override
  State<_SuggestionsTab> createState() => _SuggestionsTabState();
}

class _SuggestionsTabState extends State<_SuggestionsTab> {
  List<String> _myFriendIds = [];
  Map<String, List<String>> _mutualFriendsMap = {};
  bool _isLoading = true;

  /// FIX: Tránh gọi setState() sau khi widget đã bị dispose (async gap).
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  @override
  void dispose() {
    _isDisposed = true; // PHẢI đặt TRƯỚC super.dispose()
    super.dispose();
  }

  /// Helper an toàn: chỉ gọi setState khi widget còn sống.
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
      for (var d in fs1.docs) {
        myFriends.add(Friendship.fromDocument(d).userId2);
      }
      for (var d in fs2.docs) {
        myFriends.add(Friendship.fromDocument(d).userId1);
      }
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
    if (_isLoading) return const _FriendListSkeleton();

    if (_mutualFriendsMap.isEmpty) {
      return _EmptySuggestionsState(isDark: widget.isDark);
    }

    final sorted = _mutualFriendsMap.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));

    return RefreshIndicator(
      onRefresh: _loadSuggestions,
      color: ColorConstants.primaryColor,
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
              if (!snap.hasData) return const _FriendTileSkeleton();
              final user = UserChat.fromDocument(snap.data!);
              return _SuggestionTile(
                user: user,
                mutualCount: mutualCount,
                isDark: widget.isDark,
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
  final int mutualCount;
  final bool isDark;
  final int index;
  final FriendProvider friendProvider;
  final String currentUserId;
  final VoidCallback onRefresh;

  const _SuggestionTile({
    required this.user,
    required this.mutualCount,
    required this.isDark,
    required this.index,
    required this.friendProvider,
    required this.currentUserId,
    required this.onRefresh,
  });

  @override
  State<_SuggestionTile> createState() => _SuggestionTileState();
}

class _SuggestionTileState extends State<_SuggestionTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;
  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 320 + widget.index * 50),
    );
    _slide = Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    Future.delayed(Duration(milliseconds: widget.index * 50),
        () => mounted ? _ctrl.forward() : null);
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
    final success = await widget.friendProvider
        .sendFriendRequest(widget.currentUserId, widget.user.id);
    if (!mounted) return;
    setState(() => _requesting = false);
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã gửi lời mời kết bạn tới ${widget.user.nickname}'),
          backgroundColor: Colors.green[700],
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      widget.onRefresh();
    }
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
              onTap: () => Navigator.push(
                  context, _slideRoute(UserProfilePage(userChat: u))),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color:
                      widget.isDark ? ColorConstants.surfaceDark : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: ColorConstants.primaryColor
                        .withOpacity(widget.isDark ? 0.18 : 0.1),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: ColorConstants.primaryColor
                          .withOpacity(widget.isDark ? 0.06 : 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    _SimpleAvatar(url: u.photoUrl, name: u.nickname, size: 54),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            u.nickname,
                            style: TextStyle(
                              color: widget.isDark
                                  ? Colors.white
                                  : const Color(0xFF1A1D2E),
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.people_rounded,
                                  size: 13, color: ColorConstants.primaryColor),
                              const SizedBox(width: 4),
                              Text(
                                '${widget.mutualCount} bạn chung',
                                style: TextStyle(
                                  color: ColorConstants.primaryColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          if (u.aboutMe.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              u.aboutMe,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: ColorConstants.greyColor,
                                  fontSize: 12),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _requesting
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: ColorConstants.primaryColor,
                            ),
                          )
                        : _IconActionBtn(
                            icon: Icons.person_add_rounded,
                            color: ColorConstants.primaryColor,
                            tooltip: 'Kết bạn',
                            onTap: _addFriend,
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

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers / sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SimpleAvatar extends StatelessWidget {
  final String url;
  final String name;
  final double size;

  const _SimpleAvatar(
      {required this.url, required this.name, required this.size});

  @override
  Widget build(BuildContext context) {
    final colorIndex = name.isEmpty
        ? 0
        : name.codeUnitAt(0) % ColorConstants.avatarColors.length;
    final color = ColorConstants.avatarColors[colorIndex];
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.12),
        border: Border.all(color: color.withOpacity(0.25), width: 1.5),
      ),
      child: ClipOval(
        child: url.isNotEmpty
            ? Image.network(url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _placeholder(color))
            : _placeholder(color),
      ),
    );
  }

  Widget _placeholder(Color color) {
    return Container(
      color: color.withOpacity(0.1),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
              color: color, fontWeight: FontWeight.w700, fontSize: size * 0.36),
        ),
      ),
    );
  }
}

class _IconActionBtn extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _IconActionBtn({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  State<_IconActionBtn> createState() => _IconActionBtnState();
}

class _IconActionBtnState extends State<_IconActionBtn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 80));
    _scale = Tween<double>(begin: 1.0, end: 0.84)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
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
              color: widget.color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: widget.color.withOpacity(0.25)),
            ),
            child: Icon(widget.icon, color: widget.color, size: 20),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty / Loading states
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyFriendsState extends StatelessWidget {
  final bool isDark;
  const _EmptyFriendsState({required this.isDark});

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
              color: ColorConstants.primaryColor.withOpacity(0.07),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.people_outline_rounded,
                size: 40, color: ColorConstants.primaryColor.withOpacity(0.4)),
          ),
          const SizedBox(height: 20),
          Text(
            'Chưa có bạn bè nào',
            style: TextStyle(
              color: isDark ? Colors.white54 : ColorConstants.greyColor,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Thêm bạn để bắt đầu trò chuyện',
            style: TextStyle(color: ColorConstants.greyColor, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _EmptySuggestionsState extends StatelessWidget {
  final bool isDark;
  const _EmptySuggestionsState({required this.isDark});

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
              color: ColorConstants.primaryColor.withOpacity(0.07),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.person_search_rounded,
                size: 40, color: ColorConstants.primaryColor.withOpacity(0.4)),
          ),
          const SizedBox(height: 20),
          Text(
            'Chưa có gợi ý nào',
            style: TextStyle(
              color: isDark ? Colors.white54 : ColorConstants.greyColor,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Thêm nhiều bạn hơn để nhận gợi ý',
            style: TextStyle(color: ColorConstants.greyColor, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _FriendListSkeleton extends StatefulWidget {
  const _FriendListSkeleton();

  @override
  State<_FriendListSkeleton> createState() => _FriendListSkeletonState();
}

class _FriendListSkeletonState extends State<_FriendListSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final c = isDark
            ? Color.lerp(ColorConstants.surfaceDark2, const Color(0xFF2E3448),
                _anim.value)!
            : Color.lerp(
                const Color(0xFFF0F2FF), const Color(0xFFE0E4F5), _anim.value)!;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            children: List.generate(
              7,
              (_) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: c, borderRadius: BorderRadius.circular(16)),
                child: Row(
                  children: [
                    CircleAvatar(
                        radius: 27, backgroundColor: c.withOpacity(0.5)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                              height: 13,
                              width: 130,
                              decoration: BoxDecoration(
                                  color: c.withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(6))),
                          const SizedBox(height: 8),
                          Container(
                              height: 10,
                              width: 180,
                              decoration: BoxDecoration(
                                  color: c.withOpacity(0.4),
                                  borderRadius: BorderRadius.circular(5))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FriendTileSkeleton extends StatelessWidget {
  const _FriendTileSkeleton();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? ColorConstants.surfaceDark2 : const Color(0xFFF0F2FF);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration:
          BoxDecoration(color: c, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        CircleAvatar(radius: 27, backgroundColor: c.withOpacity(0.5)),
        const SizedBox(width: 14),
        Expanded(
            child: Container(
                height: 12,
                width: 120,
                decoration: BoxDecoration(
                    color: c.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(6)))),
      ]),
    );
  }
}

PageRoute _slideRoute(Widget page) {
  return PageRouteBuilder(
    pageBuilder: (_, animation, __) => page,
    transitionsBuilder: (_, animation, __, child) => SlideTransition(
      position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
          .animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
    transitionDuration: const Duration(milliseconds: 280),
  );
}
