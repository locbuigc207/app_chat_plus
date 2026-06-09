import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';

import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_chat_demo/pages/pages.dart';
import 'package:flutter_chat_demo/providers/providers.dart';
import 'package:flutter_chat_demo/providers/theme_provider.dart';
import 'package:flutter_chat_demo/widgets/widgets.dart';

class UserProfilePage extends StatefulWidget {
  final UserChat userChat;
  const UserProfilePage({super.key, required this.userChat});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  bool _areFriends = false;
  String? _friendRequestStatus;
  late final String _currentUserId;
  late final FriendProvider _friendProvider;
  late AnimationController _fabCtrl;
  late Animation<double> _fabAnim;

  @override
  void initState() {
    super.initState();
    _currentUserId = context.read<AuthProvider>().userFirebaseId ?? '';
    _friendProvider = FriendProvider(
      firebaseFirestore: context.read<HomeProvider>().firebaseFirestore,
    );
    _fabCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _fabAnim = CurvedAnimation(parent: _fabCtrl, curve: Curves.easeOutBack);
    _checkFriendshipStatus();
  }

  @override
  void dispose() {
    _fabCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkFriendshipStatus() async {
    setState(() => _isLoading = true);
    final areFriends = await _friendProvider.areFriends(_currentUserId, widget.userChat.id);
    String? requestStatus;

    if (!areFriends) {
      requestStatus = await _friendProvider.checkFriendRequest(_currentUserId, widget.userChat.id);
    }

    if (mounted) {
      setState(() {
        _areFriends = areFriends;
        _friendRequestStatus = requestStatus;
        _isLoading = false;
      });
      _fabCtrl.forward();
    }
  }

  Future<void> _handleFriendAction() async {
    if (_areFriends) {
      await _friendProvider.getOrCreateConversation(_currentUserId, widget.userChat.id, false);
      if (mounted) {
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) => ChatPage(
                  arguments: ChatPageArguments(
                      peerId: widget.userChat.id,
                      peerAvatar: widget.userChat.photoUrl,
                      peerNickname: widget.userChat.nickname
                  ),
                )
            )
        );
      }
    } else if (_friendRequestStatus == 'sent') {
      _toast('Đã gửi lời mời kết bạn rồi');
    } else if (_friendRequestStatus != null && _friendRequestStatus != 'sent') {
      setState(() => _isLoading = true);
      final success = await _friendProvider.acceptFriendRequest(_friendRequestStatus!, _currentUserId, widget.userChat.id);
      if (success) {
        _toast('Đã chấp nhận lời mời!');
        _checkFriendshipStatus();
      } else {
        setState(() => _isLoading = false);
        _toast('Thất bại, thử lại sau');
      }
    } else {
      setState(() => _isLoading = true);
      final success = await _friendProvider.sendFriendRequest(_currentUserId, widget.userChat.id);
      if (success) {
        _toast('Đã gửi lời mời kết bạn!');
        _checkFriendshipStatus();
      } else {
        setState(() => _isLoading = false);
        _toast('Thất bại, thử lại sau');
      }
    }
  }

  void _toast(String msg) => Fluttertoast.showToast(msg: msg);

  void _openMemoryTimeline() {
    final peerId = widget.userChat.id;
    final conversationId = _currentUserId.compareTo(peerId) > 0
        ? '$_currentUserId-$peerId'
        : '$peerId-$_currentUserId';

    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => MemoryTimelinePage(
              peerId: peerId,
              peerNickname: widget.userChat.nickname,
              currentUserId: _currentUserId,
              conversationId: conversationId,
            )
        )
    );
  }

  String _getButtonLabel() {
    if (_areFriends) return 'Nhắn tin';
    if (_friendRequestStatus == 'sent') return 'Đã gửi lời mời';
    if (_friendRequestStatus != null && _friendRequestStatus != 'sent') return 'Chấp nhận';
    return 'Kết bạn';
  }

  IconData _getButtonIcon() {
    if (_areFriends) return Icons.chat_rounded;
    if (_friendRequestStatus == 'sent') return Icons.schedule_rounded;
    if (_friendRequestStatus != null && _friendRequestStatus != 'sent') return Icons.check_rounded;
    return Icons.person_add_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final p = theme.palette;
    final user = widget.userChat;

    return Theme(
      data: theme.isDark ? theme.darkTheme : theme.lightTheme,
      child: Scaffold(
        backgroundColor: p.background,
        body: Stack(
          children: [
            CustomScrollView(
              slivers: [
                SliverAppBar(
                  expandedHeight: 300,
                  pinned: true,
                  backgroundColor: p.appBarBackground,
                  surfaceTintColor: Colors.transparent,
                  elevation: 0,
                  leading: IconButton(
                    icon: Icon(Icons.arrow_back_ios_new_rounded, color: theme.primaryColor, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                  flexibleSpace: FlexibleSpaceBar(
                    background: _buildHeroBackground(p, theme, user),
                    collapseMode: CollapseMode.parallax,
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 140),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildInfoSection(p, theme, user),
                        const SizedBox(height: 16),
                        _buildStatsSection(p, theme),
                        const SizedBox(height: 16),
                        _buildActionsSection(p, theme),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            // FAB bottom button
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).padding.bottom + 16),
                decoration: BoxDecoration(
                  color: p.surface,
                  border: Border(top: BorderSide(color: p.divider, width: 0.5)),
                  boxShadow: [
                    BoxShadow(
                        color: p.shadow.withValues(alpha: 0.3),
                        blurRadius: 20,
                        offset: const Offset(0, -4)
                    )
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: ScaleTransition(
                    scale: _fabAnim,
                    child: _isLoading
                        ? const SizedBox.shrink()
                        : SizedBox(
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: _friendRequestStatus == 'sent' ? null : _handleFriendAction,
                        icon: Icon(_getButtonIcon(), size: 20),
                        label: Text(
                            _getButtonLabel(),
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.primaryColor,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          disabledBackgroundColor: p.surfaceVariant,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_isLoading) Positioned.fill(child: LoadingView()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroBackground(ThemePalette p, ThemeProvider theme, UserChat user) {
    final colorIdx = user.nickname.isEmpty
        ? 0
        : user.nickname.codeUnitAt(0) % ColorConstants.avatarColors.length;
    final avatarColor = ColorConstants.avatarColors[colorIdx];

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            theme.primaryColor.withValues(alpha: 0.15),
            p.background,
          ],
        ),
      ),
      child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 40),
            // Avatar
            Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: avatarColor.withValues(alpha: 0.12),
                      border: Border.all(color: theme.primaryColor, width: 3),
                      boxShadow: [
                        BoxShadow(
                            color: theme.primaryColor.withValues(alpha: 0.25),
                            blurRadius: 20,
                            spreadRadius: 2
                        )
                      ],
                    ),
                    child: ClipOval(
                        child: user.photoUrl.isNotEmpty
                            ? Image.network(
                            user.photoUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Center(
                                child: Text(
                                    user.nickname.isNotEmpty ? user.nickname[0].toUpperCase() : '?',
                                    style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: avatarColor)
                                )
                            )
                        )
                            : Center(
                            child: Text(
                                user.nickname.isNotEmpty ? user.nickname[0].toUpperCase() : '?',
                                style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: avatarColor)
                            )
                        )
                    ),
                  ),
                  if (_areFriends)
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.green.shade500,
                          border: Border.all(color: p.background, width: 2.5)
                      ),
                      child: const Icon(Icons.check_rounded, color: Colors.white, size: 15),
                    ),
                ]
            ),
            const SizedBox(height: 16),
            Text(
                user.nickname,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: p.textPrimary, letterSpacing: -0.5)
            ),
            if (user.aboutMe.isNotEmpty) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                    user.aboutMe,
                    style: TextStyle(fontSize: 13.5, color: p.textSecondary, height: 1.4),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis
                ),
              ),
            ],
            const SizedBox(height: 14),
            // Online indicator
            StreamBuilder<UserPresence>(
              stream: context.read<UserPresenceProvider>().getUserPresenceStream(user.id),
              builder: (_, snap) {
                final isOnline = snap.data?.isOnline == true;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color: (isOnline ? Colors.green : p.surfaceVariant).withValues(alpha: isOnline ? 0.12 : 1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: (isOnline ? Colors.green : p.divider).withValues(alpha: 0.4)),
                  ),
                  child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isOnline ? Colors.green.shade400 : p.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                            isOnline ? 'Đang hoạt động' : 'Ngoại tuyến',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isOnline ? Colors.green.shade600 : p.textSecondary,
                            )
                        ),
                      ]
                  ),
                );
              },
            ),
          ]
      ),
    );
  }

  Widget _buildInfoSection(ThemePalette p, ThemeProvider theme, UserChat user) {
    return _SectionCard(
      title: 'Thông tin',
      icon: Icons.person_outline_rounded,
      palette: p,
      primary: theme.primaryColor,
      children: [
        _ProfileRow(
            icon: Icons.badge_rounded,
            label: 'Tên hiển thị',
            value: user.nickname,
            palette: p,
            primary: theme.primaryColor
        ),
        if (user.aboutMe.isNotEmpty) ...[
          _Divider(palette: p),
          _ProfileRow(
              icon: Icons.info_outline_rounded,
              label: 'Giới thiệu',
              value: user.aboutMe,
              palette: p,
              primary: theme.primaryColor
          ),
        ],
        if (user.phoneNumber.isNotEmpty) ...[
          _Divider(palette: p),
          _ProfileRow(
              icon: Icons.phone_rounded,
              label: 'Số điện thoại',
              value: user.phoneNumber,
              palette: p,
              primary: theme.primaryColor
          ),
        ],
      ],
    );
  }

  Widget _buildStatsSection(ThemePalette p, ThemeProvider theme) {
    return Row(
        children: [
          Expanded(
              child: _StatCard(
                  emoji: '💬',
                  label: 'Trò chuyện',
                  value: _areFriends ? 'Đã kết bạn' : 'Chưa kết bạn',
                  color: theme.primaryColor,
                  palette: p
              )
          ),
          const SizedBox(width: 12),
          Expanded(
              child: _StatCard(
                  emoji: '🤝',
                  label: 'Quan hệ',
                  value: _areFriends ? 'Bạn bè' : 'Người lạ',
                  color: _areFriends ? Colors.green.shade600 : p.textSecondary,
                  palette: p
              )
          ),
        ]
    );
  }

  Widget _buildActionsSection(ThemePalette p, ThemeProvider theme) {
    return _SectionCard(
      title: 'Tính năng AI',
      icon: Icons.auto_awesome_rounded,
      palette: p,
      primary: theme.primaryColor,
      children: [
        _ActionItem(
          icon: Icons.psychology_rounded,
          iconColor: Colors.purple.shade400,
          label: 'Relationship Memory AI',
          subtitle: 'Phân tích mối quan hệ & timeline kỷ niệm',
          palette: p,
          onTap: _openMemoryTimeline,
        ),
      ],
    );
  }
}

// ─── Shared Widgets ───────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final ThemePalette palette;
  final Color primary;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.palette,
    required this.primary,
    required this.children
  });

  @override
  Widget build(BuildContext context) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 10),
            child: Row(
                children: [
                  Icon(icon, size: 13, color: primary.withValues(alpha: 0.7)),
                  const SizedBox(width: 6),
                  Text(
                      title.toUpperCase(),
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: palette.textSecondary,
                          letterSpacing: 1
                      )
                  ),
                ]
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: palette.divider, width: 0.6),
              boxShadow: [
                BoxShadow(
                    color: palette.shadow,
                    blurRadius: 8,
                    offset: const Offset(0, 2)
                )
              ],
            ),
            child: Column(children: children),
          ),
        ]
    );
  }
}

class _ProfileRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final ThemePalette palette;
  final Color primary;

  const _ProfileRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.palette,
    required this.primary
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10)
              ),
              child: Icon(icon, color: primary, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          label,
                          style: TextStyle(
                              fontSize: 11,
                              color: palette.textSecondary,
                              fontWeight: FontWeight.w500
                          )
                      ),
                      const SizedBox(height: 3),
                      Text(
                          value,
                          style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w500,
                              color: palette.textPrimary
                          )
                      ),
                    ]
                )
            ),
          ]
      ),
    );
  }
}

class _ActionItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label, subtitle;
  final ThemePalette palette;
  final VoidCallback onTap;

  const _ActionItem({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.subtitle,
    required this.palette,
    required this.onTap
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12)
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            label,
                            style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: palette.textPrimary
                            )
                        ),
                        const SizedBox(height: 2),
                        Text(
                            subtitle,
                            style: TextStyle(fontSize: 12, color: palette.textSecondary)
                        ),
                      ]
                  )
              ),
              Icon(Icons.chevron_right_rounded, color: palette.textSecondary, size: 20),
            ]
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String emoji, label, value;
  final Color color;
  final ThemePalette palette;

  const _StatCard({
    required this.emoji,
    required this.label,
    required this.value,
    required this.color,
    required this.palette
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.divider, width: 0.6),
        boxShadow: [
          BoxShadow(color: palette.shadow, blurRadius: 8)
        ],
      ),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 26)),
            const SizedBox(height: 8),
            Text(
                value,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: color),
                textAlign: TextAlign.center
            ),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, color: palette.textSecondary)),
          ]
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  final ThemePalette palette;

  const _Divider({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Divider(
        height: 1,
        indent: 68,
        endIndent: 16,
        color: palette.divider
    );
  }
}