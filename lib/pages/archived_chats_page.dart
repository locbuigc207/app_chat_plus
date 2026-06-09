import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../constants/constants.dart';
import '../models/models.dart';
import '../pages/pages.dart';
import '../providers/providers.dart';

class ArchivedChatsPage extends StatefulWidget {
  const ArchivedChatsPage({super.key});

  @override
  State<ArchivedChatsPage> createState() => _ArchivedChatsPageState();
}

class _ArchivedChatsPageState extends State<ArchivedChatsPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
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
    final theme = context.watch<ThemeProvider>();
    final p = theme.palette;
    final authProvider = context.read<AuthProvider>();
    final conversationProvider = context.read<ConversationProvider>();
    final currentUserId = authProvider.userFirebaseId ?? '';

    return Theme(
      data: theme.isDark ? theme.darkTheme : theme.lightTheme,
      child: Scaffold(
        backgroundColor: p.background,
        body: NestedScrollView(
          headerSliverBuilder: (ctx, innerScrolled) => [
            SliverAppBar(
              expandedHeight: 110,
              floating: false,
              pinned: true,
              elevation: 0,
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              systemOverlayStyle: theme.isDark
                  ? SystemUiOverlayStyle.light
                  : SystemUiOverlayStyle.dark,
              leading: IconButton(
                icon: Icon(Icons.arrow_back_ios_new_rounded,
                    color: theme.primaryColor, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                title: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const SizedBox(width: 40),
                    Container(
                      width: 34,
                      height: 34,
                      margin: const EdgeInsets.only(right: 10, bottom: 2),
                      decoration: BoxDecoration(
                        color: theme.primaryColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.archive_rounded,
                          color: theme.primaryColor, size: 18),
                    ),
                    Text(
                      'Đã lưu trữ',
                      style: TextStyle(
                        color: p.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
                background: Container(
                  decoration: BoxDecoration(
                    color: p.appBarBackground,
                    border: Border(
                        bottom: BorderSide(color: p.divider, width: 0.5)),
                  ),
                ),
              ),
            ),
          ],
          body: StreamBuilder<List<QueryDocumentSnapshot>>(
            stream:
                conversationProvider.getConversationsWithPinned(currentUserId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return _LoadingShimmer(palette: p);
              }

              if (snapshot.hasError) {
                return _ErrorState(error: '${snapshot.error}', palette: p);
              }

              final allDocs = snapshot.data ?? [];
              final archived = allDocs.where((doc) {
                final conv = Conversation.fromDocument(doc);
                return conv.archivedBy.contains(currentUserId);
              }).toList();

              if (archived.isEmpty) {
                return _EmptyArchiveState(
                    palette: p, primary: theme.primaryColor);
              }

              return FadeTransition(
                opacity: _fadeAnim,
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  itemCount: archived.length,
                  itemBuilder: (context, index) {
                    final conversation =
                        Conversation.fromDocument(archived[index]);

                    if (conversation.isGroup) {
                      return _GroupArchiveTile(
                        conversation: conversation,
                        currentUserId: currentUserId,
                        conversationProvider: conversationProvider,
                        palette: p,
                        primary: theme.primaryColor,
                        index: index,
                      );
                    }

                    return _DirectArchiveTile(
                      conversation: conversation,
                      currentUserId: currentUserId,
                      conversationProvider: conversationProvider,
                      palette: p,
                      primary: theme.primaryColor,
                      index: index,
                    );
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ─── Tiles ────────────────────────────────────────────────────────────────────

class _DirectArchiveTile extends StatelessWidget {
  final Conversation conversation;
  final String currentUserId;
  final ConversationProvider conversationProvider;
  final ThemePalette palette;
  final Color primary;
  final int index;

  const _DirectArchiveTile({
    required this.conversation,
    required this.currentUserId,
    required this.conversationProvider,
    required this.palette,
    required this.primary,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final otherUserId = conversation.participants
        .firstWhere((id) => id != currentUserId, orElse: () => '');

    if (otherUserId.isEmpty) return const SizedBox.shrink();

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection(FirestoreConstants.pathUserCollection)
          .doc(otherUserId)
          .get(),
      builder: (_, snapshot) {
        if (!snapshot.hasData) return _TileSkeleton(palette: palette);
        final user = UserChat.fromDocument(snapshot.data!);

        return _ArchiveTileCard(
          name: user.nickname,
          photoUrl: user.photoUrl,
          subtitle:
              user.aboutMe.isNotEmpty ? user.aboutMe : 'Nhắn tin trực tiếp',
          palette: palette,
          primary: primary,
          index: index,
          onTap: () => Navigator.push(
              context,
              _slideRoute(ChatPage(
                arguments: ChatPageArguments(
                    peerId: user.id,
                    peerAvatar: user.photoUrl,
                    peerNickname: user.nickname),
              ))),
          onUnarchive: () {
            HapticFeedback.lightImpact();
            conversationProvider.toggleArchiveConversation(
                conversation.id, currentUserId, false);
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
  final ThemePalette palette;
  final Color primary;
  final int index;

  const _GroupArchiveTile({
    required this.conversation,
    required this.currentUserId,
    required this.conversationProvider,
    required this.palette,
    required this.primary,
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
        if (!snapshot.hasData) return _TileSkeleton(palette: palette);
        final group = Group.fromDocument(snapshot.data!);

        return _ArchiveTileCard(
          name: group.groupName,
          photoUrl: group.groupPhotoUrl,
          subtitle: '${group.memberIds.length} thành viên',
          palette: palette,
          primary: primary,
          index: index,
          isGroup: true,
          onTap: () =>
              Navigator.push(context, _slideRoute(GroupChatPage(group: group))),
          onUnarchive: () {
            HapticFeedback.lightImpact();
            conversationProvider.toggleArchiveConversation(
                conversation.id, currentUserId, false);
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
  final ThemePalette palette;
  final Color primary;
  final int index;
  final bool isGroup;
  final VoidCallback onTap;
  final VoidCallback onUnarchive;

  const _ArchiveTileCard({
    required this.name,
    required this.photoUrl,
    required this.subtitle,
    required this.palette,
    required this.primary,
    required this.index,
    required this.onTap,
    required this.onUnarchive,
    this.isGroup = false,
  });

  @override
  State<_ArchiveTileCard> createState() => _ArchiveTileCardState();
}

class _ArchiveTileCardState extends State<_ArchiveTileCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: Duration(milliseconds: 350 + widget.index * 60));
    _slide = Tween<Offset>(begin: const Offset(0, 0.16), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    Future.delayed(Duration(milliseconds: widget.index * 55),
        () => mounted ? _ctrl.forward() : null);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorIndex = widget.name.isEmpty
        ? 0
        : widget.name.codeUnitAt(0) % ColorConstants.avatarColors.length;
    final avatarColor = ColorConstants.avatarColors[colorIndex];

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
                        offset: const Offset(0, 3)),
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
                        border: Border.all(
                            color: avatarColor.withValues(alpha: 0.25),
                            width: 1.5),
                      ),
                      child: ClipOval(
                        child: widget.photoUrl.isNotEmpty
                            ? Image.network(widget.photoUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    _AvatarPlaceholder(
                                        name: widget.name,
                                        color: avatarColor,
                                        isGroup: widget.isGroup))
                            : _AvatarPlaceholder(
                                name: widget.name,
                                color: avatarColor,
                                isGroup: widget.isGroup),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: widget.palette.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'Đã lưu trữ',
                                  style: TextStyle(
                                      color: Colors.orange,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  widget.subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: widget.palette.textSecondary,
                                      fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    _UnarchiveButton(onTap: widget.onUnarchive),
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

class _AvatarPlaceholder extends StatelessWidget {
  final String name;
  final Color color;
  final bool isGroup;

  const _AvatarPlaceholder({
    required this.name,
    required this.color,
    this.isGroup = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color.withValues(alpha: 0.1),
      child: isGroup
          ? Icon(Icons.group_rounded, color: color, size: 26)
          : Center(
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w700, fontSize: 20),
              ),
            ),
    );
  }
}

class _UnarchiveButton extends StatefulWidget {
  final VoidCallback onTap;

  const _UnarchiveButton({required this.onTap});

  @override
  State<_UnarchiveButton> createState() => _UnarchiveButtonState();
}

class _UnarchiveButtonState extends State<_UnarchiveButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 80));
    _scale = Tween<double>(begin: 1.0, end: 0.85)
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
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
            ),
            child: const Icon(Icons.unarchive_rounded,
                color: Colors.orange, size: 20),
          ),
        ),
      ),
    );
  }
}

// ─── Empty / Error / Loading ──────────────────────────────────────────────────

class _EmptyArchiveState extends StatelessWidget {
  final ThemePalette palette;
  final Color primary;

  const _EmptyArchiveState({required this.palette, required this.primary});

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
                color: primary.withValues(alpha: 0.07), shape: BoxShape.circle),
            child: Icon(Icons.archive_outlined,
                size: 40, color: primary.withValues(alpha: 0.4)),
          ),
          const SizedBox(height: 20),
          Text(
            'Không có cuộc trò chuyện\nđã lưu trữ',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: palette.textSecondary,
                fontSize: 16,
                fontWeight: FontWeight.w500,
                height: 1.5),
          ),
          const SizedBox(height: 10),
          Text(
            'Nhấn giữ cuộc trò chuyện để lưu trữ',
            style: TextStyle(color: palette.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _LoadingShimmer extends StatefulWidget {
  final ThemePalette palette;

  const _LoadingShimmer({required this.palette});

  @override
  State<_LoadingShimmer> createState() => _LoadingShimmerState();
}

class _LoadingShimmerState extends State<_LoadingShimmer>
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
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final c = Color.lerp(widget.palette.surface,
            widget.palette.surfaceVariant, _anim.value)!;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            children: List.generate(
                6,
                (_) => Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: c, borderRadius: BorderRadius.circular(16)),
                      child: Row(
                        children: [
                          CircleAvatar(
                              radius: 26,
                              backgroundColor: widget.palette.divider),
                          const SizedBox(width: 14),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Container(
                                    height: 13,
                                    width: 120,
                                    decoration: BoxDecoration(
                                        color: widget.palette.divider,
                                        borderRadius:
                                            BorderRadius.circular(6))),
                                const SizedBox(height: 8),
                                Container(
                                    height: 10,
                                    width: 180,
                                    decoration: BoxDecoration(
                                        color: widget.palette.divider
                                            .withValues(alpha: 0.6),
                                        borderRadius:
                                            BorderRadius.circular(5))),
                              ])),
                        ],
                      ),
                    )),
          ),
        );
      },
    );
  }
}

class _TileSkeleton extends StatelessWidget {
  final ThemePalette palette;

  const _TileSkeleton({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: palette.surface, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          CircleAvatar(radius: 26, backgroundColor: palette.divider),
          const SizedBox(width: 14),
          Expanded(
              child: Container(
                  height: 12,
                  width: 100,
                  decoration: BoxDecoration(
                      color: palette.divider,
                      borderRadius: BorderRadius.circular(6)))),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  final ThemePalette palette;

  const _ErrorState({required this.error, required this.palette});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.cloud_off_rounded, size: 48, color: palette.textSecondary),
          const SizedBox(height: 16),
          Text(
            'Không thể tải dữ liệu',
            style: TextStyle(
                color: palette.textSecondary,
                fontSize: 15,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(error,
              style: TextStyle(color: palette.textSecondary, fontSize: 12),
              textAlign: TextAlign.center),
        ]),
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
