import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

import '../constants/constants.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import 'chat_page.dart';
import 'group_chat_page.dart';

class ArchivedChatsPage extends StatefulWidget {
  const ArchivedChatsPage({super.key});

  @override
  State<ArchivedChatsPage> createState() => _ArchivedChatsPageState();
}

class _ArchivedChatsPageState extends State<ArchivedChatsPage> with SingleTickerProviderStateMixin {
  late final AnimationController _entryCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _entryCtrl.forward();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.read<AuthProvider>();
    final conversationProvider = context.read<ConversationProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentUserId = authProvider.userFirebaseId ?? '';

    return Scaffold(
      backgroundColor: isDark ? ColorConstants.backgroundDark : const Color(0xFFF5F7FF),
      body: NestedScrollView(
        headerSliverBuilder: (ctx, innerScrolled) => [
          SliverAppBar(
            expandedHeight: 120,
            floating: false,
            pinned: true,
            elevation: 0,
            backgroundColor: Colors.transparent,
            systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
            leading: IconButton(
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: isDark ? Colors.white70 : ColorConstants.primaryColor,
                size: 20,
              ),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              title: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const SizedBox(width: 40),
                  Container(
                    width: 36,
                    height: 36,
                    margin: const EdgeInsets.only(right: 12, bottom: 2),
                    decoration: BoxDecoration(
                      color: ColorConstants.primaryColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child:
                        Icon(Icons.archive_rounded, color: ColorConstants.primaryColor, size: 18),
                  ),
                  Text(
                    'Đã lưu trữ',
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF1A1D2E),
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              background: Container(
                decoration: BoxDecoration(
                  color: isDark ? ColorConstants.surfaceDark : Colors.white,
                  border: Border(
                    bottom: BorderSide(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.black.withValues(alpha: 0.06),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
        body: StreamBuilder<List<QueryDocumentSnapshot>>(
          stream: conversationProvider.getConversationsWithPinned(currentUserId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _LoadingShimmer();
            }

            if (snapshot.hasError) {
              return _ErrorState(error: '${snapshot.error}');
            }

            final allDocs = snapshot.data ?? [];
            final archived = allDocs.where((doc) {
              final conv = Conversation.fromDocument(doc);
              return conv.archivedBy.contains(currentUserId);
            }).toList();

            if (archived.isEmpty) {
              return const _EmptyArchiveState();
            }

            return FadeTransition(
              opacity: _fadeAnim,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                itemCount: archived.length,
                itemBuilder: (context, index) {
                  final conversation = Conversation.fromDocument(archived[index]);

                  if (conversation.isGroup) {
                    return _GroupArchiveTile(
                      conversation: conversation,
                      currentUserId: currentUserId,
                      conversationProvider: conversationProvider,
                      isDark: isDark,
                      index: index,
                    );
                  }

                  return _DirectArchiveTile(
                    conversation: conversation,
                    currentUserId: currentUserId,
                    conversationProvider: conversationProvider,
                    isDark: isDark,
                    index: index,
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DirectArchiveTile extends StatelessWidget {
  final Conversation conversation;
  final String currentUserId;
  final ConversationProvider conversationProvider;
  final bool isDark;
  final int index;

  const _DirectArchiveTile({
    required this.conversation,
    required this.currentUserId,
    required this.conversationProvider,
    required this.isDark,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final otherUserId =
        conversation.participants.firstWhere((id) => id != currentUserId, orElse: () => '');
    if (otherUserId.isEmpty) return const SizedBox.shrink();

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection(FirestoreConstants.pathUserCollection)
          .doc(otherUserId)
          .get(),
      builder: (_, snapshot) {
        if (!snapshot.hasData) return _TileSkeleton(isDark: isDark);
        final user = UserChat.fromDocument(snapshot.data!);

        return _ArchiveTileCard(
          name: user.nickname,
          photoUrl: user.photoUrl,
          subtitle: user.aboutMe.isNotEmpty ? user.aboutMe : 'Nhắn tin trực tiếp',
          isDark: isDark,
          index: index,
          onTap: () => Navigator.push(
            context,
            _slideRoute(ChatPage(
              arguments: ChatPageArguments(
                peerId: user.id,
                peerAvatar: user.photoUrl,
                peerNickname: user.nickname,
              ),
            )),
          ),
          onUnarchive: () {
            HapticFeedback.lightImpact();
            conversationProvider.toggleArchiveConversation(
              conversation.id,
              currentUserId,
              false,
            );
          },
        );
      },
    );
  }
}

class _GroupArchiveTile extends StatelessWidget {
  final Conversation conversation;
  final String currentUserId;
  final ConversationProvider conversationProvider;
  final bool isDark;
  final int index;

  const _GroupArchiveTile({
    required this.conversation,
    required this.currentUserId,
    required this.conversationProvider,
    required this.isDark,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection(FirestoreConstants.pathGroupCollection)
          .doc(conversation.id)
          .get(),
      builder: (_, snapshot) {
        if (!snapshot.hasData) return _TileSkeleton(isDark: isDark);
        final group = Group.fromDocument(snapshot.data!);

        return _ArchiveTileCard(
          name: group.groupName,
          photoUrl: group.groupPhotoUrl,
          subtitle: '${group.memberIds.length} thành viên',
          isDark: isDark,
          index: index,
          isGroup: true,
          onTap: () => Navigator.push(
            context,
            _slideRoute(GroupChatPage(group: group)),
          ),
          onUnarchive: () {
            HapticFeedback.lightImpact();
            conversationProvider.toggleArchiveConversation(
              conversation.id,
              currentUserId,
              false,
            );
          },
        );
      },
    );
  }
}

class _ArchiveTileCard extends StatefulWidget {
  final String name;
  final String photoUrl;
  final String subtitle;
  final bool isDark;
  final int index;
  final bool isGroup;
  final VoidCallback onTap;
  final VoidCallback onUnarchive;

  const _ArchiveTileCard({
    required this.name,
    required this.photoUrl,
    required this.subtitle,
    required this.isDark,
    required this.index,
    required this.onTap,
    required this.onUnarchive,
    this.isGroup = false,
  });

  @override
  State<_ArchiveTileCard> createState() => _ArchiveTileCardState();
}

class _ArchiveTileCardState extends State<_ArchiveTileCard> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 350 + widget.index * 60),
    );
    _slide = Tween<Offset>(begin: const Offset(0, 0.18), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    Future.delayed(
        Duration(milliseconds: widget.index * 60), () => mounted ? _ctrl.forward() : null);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(16),
              splashColor: ColorConstants.primaryColor.withValues(alpha: 0.06),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: widget.isDark ? ColorConstants.surfaceDark : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: widget.isDark
                        ? Colors.white.withValues(alpha: 0.07)
                        : Colors.black.withValues(alpha: 0.05),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: widget.isDark ? 0.2 : 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    _ArchiveAvatar(
                      url: widget.photoUrl,
                      name: widget.name,
                      isGroup: widget.isGroup,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.name,
                            style: TextStyle(
                              color: widget.isDark ? Colors.white : const Color(0xFF1A1D2E),
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              letterSpacing: -0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'Đã lưu trữ',
                                  style: TextStyle(
                                    color: Colors.orange,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  widget.subtitle,
                                  style: TextStyle(
                                    color: widget.isDark ? Colors.white38 : Colors.black45,
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    _UnarchiveBtn(onTap: widget.onUnarchive),
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

class _ArchiveAvatar extends StatelessWidget {
  final String url;
  final String name;
  final bool isGroup;

  const _ArchiveAvatar({required this.url, required this.name, this.isGroup = false});

  @override
  Widget build(BuildContext context) {
    final colorIndex = name.isEmpty ? 0 : name.codeUnitAt(0) % ColorConstants.avatarColors.length;
    final avatarColor = ColorConstants.avatarColors[colorIndex];

    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: avatarColor.withValues(alpha: 0.12),
        border: Border.all(color: avatarColor.withValues(alpha: 0.25), width: 1.5),
      ),
      child: ClipOval(
        child: url.isNotEmpty
            ? Image.network(url,
                fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder(avatarColor))
            : _placeholder(avatarColor),
      ),
    );
  }

  Widget _placeholder(Color color) {
    if (isGroup) {
      return Container(
        color: color.withValues(alpha: 0.1),
        child: Icon(Icons.group_rounded, color: color, size: 26),
      );
    }
    return Container(
      color: color.withValues(alpha: 0.1),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
      ),
    );
  }
}

class _UnarchiveBtn extends StatefulWidget {
  final VoidCallback onTap;
  const _UnarchiveBtn({required this.onTap});

  @override
  State<_UnarchiveBtn> createState() => _UnarchiveBtnState();
}

class _UnarchiveBtnState extends State<_UnarchiveBtn> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 80));
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
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Tooltip(
          message: 'Bỏ lưu trữ',
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
            ),
            child: const Icon(Icons.unarchive_rounded, color: Colors.orange, size: 20),
          ),
        ),
      ),
    );
  }
}

class _EmptyArchiveState extends StatelessWidget {
  const _EmptyArchiveState();

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
              color: ColorConstants.primaryColor.withValues(alpha: 0.06),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.archive_outlined,
                size: 40, color: ColorConstants.primaryColor.withValues(alpha: 0.4)),
          ),
          const SizedBox(height: 20),
          const Text(
            'Không có cuộc trò chuyện\nđã lưu trữ',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: ColorConstants.greyColor,
              fontSize: 16,
              fontWeight: FontWeight.w500,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Nhấn giữ cuộc trò chuyện để lưu trữ',
            style: TextStyle(color: ColorConstants.greyColor, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _LoadingShimmer extends StatefulWidget {
  const _LoadingShimmer();

  @override
  State<_LoadingShimmer> createState() => _LoadingShimmerState();
}

class _LoadingShimmerState extends State<_LoadingShimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
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
            ? Color.lerp(ColorConstants.surfaceDark2, const Color(0xFF2E3448), _anim.value)!
            : Color.lerp(const Color(0xFFF0F2FF), const Color(0xFFE0E4F5), _anim.value)!;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            children: List.generate(
              6,
              (i) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: c,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    CircleAvatar(radius: 27, backgroundColor: c.withValues(alpha: 0.5)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                              height: 13,
                              width: 120,
                              decoration: BoxDecoration(
                                  color: c.withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(6))),
                          const SizedBox(height: 8),
                          Container(
                              height: 10,
                              width: 180,
                              decoration: BoxDecoration(
                                  color: c.withValues(alpha: 0.4),
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

class _TileSkeleton extends StatelessWidget {
  final bool isDark;
  const _TileSkeleton({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final c = isDark ? ColorConstants.surfaceDark2 : const Color(0xFFF0F2FF);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          CircleAvatar(radius: 27, backgroundColor: c.withValues(alpha: 0.5)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                    height: 12,
                    width: 100,
                    decoration: BoxDecoration(
                        color: c.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(6))),
                const SizedBox(height: 8),
                Container(
                    height: 10,
                    width: 160,
                    decoration: BoxDecoration(
                        color: c.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(5))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  const _ErrorState({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 48, color: ColorConstants.greyColor),
            const SizedBox(height: 16),
            const Text('Không thể tải dữ liệu',
                style: TextStyle(
                    color: ColorConstants.greyColor, fontSize: 15, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Text(error,
                style: const TextStyle(color: ColorConstants.greyColor, fontSize: 12),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

PageRoute _slideRoute(Widget page) {
  return PageRouteBuilder(
    pageBuilder: (_, animation, __) => page,
    transitionsBuilder: (_, animation, __, child) {
      return SlideTransition(
        position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
        child: child,
      );
    },
    transitionDuration: const Duration(milliseconds: 280),
  );
}
