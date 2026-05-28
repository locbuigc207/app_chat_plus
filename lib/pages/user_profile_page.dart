import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_chat_demo/pages/pages.dart';
import 'package:flutter_chat_demo/providers/providers.dart';
import 'package:flutter_chat_demo/widgets/widgets.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';

class UserProfilePage extends StatefulWidget {
  final UserChat userChat;
  const UserProfilePage({super.key, required this.userChat});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage>
    with SingleTickerProviderStateMixin {
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
    _fabCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _fabAnim = CurvedAnimation(parent: _fabCtrl, curve: Curves.easeOut);
    _checkFriendshipStatus();
  }

  @override
  void dispose() {
    _fabCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkFriendshipStatus() async {
    setState(() => _isLoading = true);
    final areFriends =
        await _friendProvider.areFriends(_currentUserId, widget.userChat.id);
    String? requestStatus;
    if (!areFriends) {
      requestStatus = await _friendProvider.checkFriendRequest(
          _currentUserId, widget.userChat.id);
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
      await _friendProvider.getOrCreateConversation(
          _currentUserId, widget.userChat.id, false);
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ChatPage(
              arguments: ChatPageArguments(
                peerId: widget.userChat.id,
                peerAvatar: widget.userChat.photoUrl,
                peerNickname: widget.userChat.nickname,
              ),
            ),
          ),
        );
      }
    } else if (_friendRequestStatus == 'sent') {
      _toast('Đã gửi lời mời kết bạn rồi');
    } else if (_friendRequestStatus != null && _friendRequestStatus != 'sent') {
      setState(() => _isLoading = true);
      final success = await _friendProvider.acceptFriendRequest(
          _friendRequestStatus!, _currentUserId, widget.userChat.id);
      if (success) {
        _toast('Đã chấp nhận lời mời!');
        _checkFriendshipStatus();
      } else {
        setState(() => _isLoading = false);
        _toast('Thất bại, thử lại sau');
      }
    } else {
      setState(() => _isLoading = true);
      final success = await _friendProvider.sendFriendRequest(
          _currentUserId, widget.userChat.id);
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
        ),
      ),
    );
  }

  String _getButtonLabel() {
    if (_areFriends) return 'Nhắn tin';
    if (_friendRequestStatus == 'sent') return 'Đã gửi lời mời';
    if (_friendRequestStatus != null && _friendRequestStatus != 'sent') {
      return 'Chấp nhận';
    }
    return 'Kết bạn';
  }

  IconData _getButtonIcon() {
    if (_areFriends) return Icons.chat_rounded;
    if (_friendRequestStatus == 'sent') return Icons.schedule_rounded;
    if (_friendRequestStatus != null && _friendRequestStatus != 'sent') {
      return Icons.check_rounded;
    }
    return Icons.person_add_rounded;
  }

  Color _getButtonColor() {
    if (_friendRequestStatus == 'sent') return Colors.grey.shade400;
    return ColorConstants.primaryColor;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = widget.userChat;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0D0D0D) : const Color(0xFFF6F6F9),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // ── Hero AppBar ──────────────────────────────────────
              SliverAppBar(
                expandedHeight: 280,
                pinned: true,
                backgroundColor:
                    isDark ? const Color(0xFF1C1C2E) : Colors.white,
                elevation: 0,
                leading: IconButton(
                  icon: Icon(Icons.arrow_back_ios_new_rounded,
                      color: isDark ? Colors.white : Colors.black87, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  background: _buildHeroBackground(isDark, user),
                ),
              ),

              // ── Content ──────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Info fields
                      _buildInfoSection(isDark, user),
                      const SizedBox(height: 20),
                      // Actions
                      _buildActionsSection(isDark),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // ── Floating Action Button ───────────────────────────────
          Positioned(
            bottom: 24,
            left: 24,
            right: 24,
            child: SafeArea(
              child: ScaleTransition(
                scale: _fabAnim,
                child: _isLoading
                    ? const SizedBox.shrink()
                    : SizedBox(
                        height: 54,
                        child: ElevatedButton.icon(
                          onPressed: _friendRequestStatus == 'sent'
                              ? null
                              : _handleFriendAction,
                          icon: Icon(_getButtonIcon(), size: 20),
                          label: Text(
                            _getButtonLabel(),
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _getButtonColor(),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            disabledBackgroundColor: Colors.grey.shade300,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ),
              ),
            ),
          ),

          // Loading overlay
          if (_isLoading) Positioned.fill(child: LoadingView()),
        ],
      ),
    );
  }

  Widget _buildHeroBackground(bool isDark, UserChat user) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? [const Color(0xFF1C1C2E), const Color(0xFF0D0D0D)]
              : [
                  ColorConstants.primaryColor.withOpacity(0.08),
                  const Color(0xFFF6F6F9)
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
                  border:
                      Border.all(color: ColorConstants.primaryColor, width: 3),
                ),
                child: ClipOval(
                  child: user.photoUrl.isNotEmpty
                      ? Image.network(
                          user.photoUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _avatarFallback(user),
                          loadingBuilder: (_, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Center(
                                child: CircularProgressIndicator(
                                    color: ColorConstants.primaryColor,
                                    strokeWidth: 2));
                          },
                        )
                      : _avatarFallback(user),
                ),
              ),
              if (_areFriends)
                Container(
                  width: 26,
                  height: 26,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.green,
                  ),
                  child: const Icon(Icons.check_rounded,
                      color: Colors.white, size: 14),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            user.nickname,
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black87),
          ),
          if (user.aboutMe.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              user.aboutMe,
              style: TextStyle(
                  fontSize: 13.5,
                  color: isDark ? Colors.white54 : Colors.grey.shade600),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _avatarFallback(UserChat user) {
    final initials = user.nickname.isNotEmpty
        ? user.nickname.substring(0, 1).toUpperCase()
        : '?';
    return Container(
      color: ColorConstants.primaryColor.withOpacity(0.2),
      child: Center(
        child: Text(initials,
            style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: ColorConstants.primaryColor)),
      ),
    );
  }

  Widget _buildInfoSection(bool isDark, UserChat user) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Thông tin', isDark),
        const SizedBox(height: 10),
        _InfoCard(
          isDark: isDark,
          children: [
            _InfoRow(
              icon: Icons.badge_rounded,
              label: 'Tên hiển thị',
              value: user.nickname,
              isDark: isDark,
            ),
            if (user.aboutMe.isNotEmpty) ...[
              _InfoDivider(isDark: isDark),
              _InfoRow(
                icon: Icons.info_outline_rounded,
                label: 'Giới thiệu',
                value: user.aboutMe,
                isDark: isDark,
              ),
            ],
            if (user.phoneNumber.isNotEmpty) ...[
              _InfoDivider(isDark: isDark),
              _InfoRow(
                icon: Icons.phone_rounded,
                label: 'Số điện thoại',
                value: user.phoneNumber,
                isDark: isDark,
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildActionsSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Tính năng', isDark),
        const SizedBox(height: 10),
        _InfoCard(
          isDark: isDark,
          children: [
            _ActionRow(
              icon: Icons.psychology_rounded,
              iconColor: const Color(0xFF9C27B0),
              label: 'Relationship Memory AI',
              subtitle: 'Health Score & Timeline kỷ niệm',
              isDark: isDark,
              onTap: _openMemoryTimeline,
            ),
          ],
        ),
      ],
    );
  }

  Widget _sectionLabel(String text, bool isDark) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
          color: isDark ? Colors.white38 : Colors.grey.shade500),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final bool isDark;
  final List<Widget> children;
  const _InfoCard({required this.isDark, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C2E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color:
                isDark ? Colors.white.withOpacity(0.07) : Colors.grey.shade200),
      ),
      child: Column(children: children),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isDark;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: ColorConstants.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: ColorConstants.primaryColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 11.5,
                        color: isDark ? Colors.white38 : Colors.grey.shade500)),
                const SizedBox(height: 3),
                Text(value,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white : Colors.black87)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String subtitle;
  final bool isDark;
  final VoidCallback onTap;

  const _ActionRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.subtitle,
    required this.isDark,
    required this.onTap,
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
                color: iconColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 12.5,
                          color:
                              isDark ? Colors.white38 : Colors.grey.shade500)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: isDark ? Colors.white24 : Colors.grey.shade400,
                size: 20),
          ],
        ),
      ),
    );
  }
}

class _InfoDivider extends StatelessWidget {
  final bool isDark;
  const _InfoDivider({required this.isDark});

  @override
  Widget build(BuildContext context) => Divider(
        height: 1,
        indent: 70,
        endIndent: 16,
        color: isDark ? Colors.white.withOpacity(0.07) : Colors.grey.shade100,
      );
}
